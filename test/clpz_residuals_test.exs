defmodule PrologEx.ClpzResidualsTest do
  # Restziele von library(clpz): standardmäßig lesbar (Flag clpz_residuals =
  # compact) – halboffene Domänen als #>/#>=/#</#=<, X #=< Y + C als #< oder
  # #=< mit der betragsmäßig kleineren Konstante; mit clpz_residuals =
  # scryer genau wie Scryer
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ["clpz", "lists"])
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.put(:prolog_ex_ops, c.ops)
    PrologEx.put_db(c.db)
    PrologEx.Flags.reset()
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  defp run(c, q), do: c.reader |> TableCase.run(c.db, q) |> elem(1)

  defp res(c, q) do
    assert {:answers, [ans]} = run(c, q), q
    ans
  end

  test "Standard: lesbare Form mit kleinster Konstante", c do
    for {q, want} <- [
          {"X #> 1", "X#>1"},
          {"X #>= 1", "X#>0"},
          {"X #> -5", "X#>= -4"},
          {"X #>= 0", "X#>=0"},
          {"X #< 3", "X#=<2"},
          {"X #=< -1", "X#<0"},
          {"X #< -3", "X#< -3"},
          {"X #=< 0", "X#=<0"},
          {"X #=< Y - 3", "X#<Y-2"},
          {"X #=< Y - 1", "X#<Y"},
          {"X #=< Y + 2", "X#=<Y+2"},
          {"X #=< Y", "Y#>=X"},
          {"X in 1..3", "X in 1..3"},
          {"X in 1..3 \\/ 7..sup", "X in 1..3\\/7..sup"}
        ] do
      assert res(c, q) == want, q
    end
  end

  test "mit clpz:monotonic bleibt in/2 (wie Scryer)", c do
    assert res(c, "assertz(clpz:monotonic), #X #> 1") == "X in 2..sup"
  end

  test "Beispiel: A #> 1, A #< B, C #< 3", c do
    ans = res(c, "A #> 1, A #< B, C #< 3")
    assert ans =~ "A#>1"
    assert ans =~ "A#<B"
    assert ans =~ "C#=<2" or ans =~ "C#<3"
    refute ans =~ " in "
    refute ans =~ "+ -1"
  end

  test "Restziele wieder gepostet: dieselbe Bedeutung", c do
    # copy_term/3 holt die Restziele (als Konjunktion); nach dem Posten an
    # den frischen Variablen dieselben Domänen
    q =
      "X #> -5, X #=< Y - 3, Y #< 10, copy_term([X,Y], [X1,Y1], Gs), " <>
        "call(Gs), fd_dom(X, DX), fd_dom(X1, DX1), fd_dom(Y, DY), fd_dom(Y1, DY1), " <>
        "DX == DX1, DY == DY1"

    assert {:answers, [_]} = run(c, q)
  end

  test "Flag scryer: genau Scryers Form", c do
    PrologEx.Flags.set("clpz_residuals", PrologEx.a("scryer"))
    assert res(c, "X #> 1") =~ "X in 2..sup"
    assert res(c, "X #< 3") =~ "X in inf..2"
    assert res(c, "X #< Y") =~ "X#=<Y+ -1"
  end

  test "Flag: Voreinstellung compact, andere Werte abgelehnt", c do
    assert res(c, "current_prolog_flag(clpz_residuals, F)") == "F = compact"

    assert res(c, "catch(set_prolog_flag(clpz_residuals, x), error(E, _), true)") ==
             "E = domain_error(flag_value,clpz_residuals+x)"
  end
end
