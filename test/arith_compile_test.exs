defmodule PrologEx.ArithCompileTest do
  @moduledoc """
  Übersetzte Arithmetik (is/2 und Vergleiche im Klauselrumpf, siehe
  PrologEx.Compiler) gegen die interpretierte (dasselbe Ziel über call/1):
  gleiche Werte, gleiche Fehler – auf zufälligen Ausdrücken und Belegungen.
  """
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @ops2 ~w(+ - * / // mod rem div min max ** ^ >> << /\\ \\/ xor atan2 copysign gcd log)
  @ops1 ~w(- abs sign sqrt sin exp log float integer truncate round floor ceiling \\ msb succ)
  @leaves [
    "A",
    "B",
    "0",
    "1",
    "2",
    "3",
    "-1",
    "7",
    "2.5",
    "0.0",
    "-0.5",
    "pi",
    "e",
    "foo",
    "[3]",
    "foo(1)",
    "100000000000000000000"
  ]
  @values ["0", "3", "-2", "2.5", "(1+2)", "foo", "_", "1.0e308", "[5]", "f(x)"]
  @cmps ~w(=:= =\\= < > =< >=)

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r}
  end

  defp expr(0), do: Enum.random(@leaves)

  defp expr(d) do
    case :rand.uniform(4) do
      1 -> expr(0)
      2 -> "#{Enum.random(@ops1)}(#{expr(d - 1)})"
      _ -> "(#{expr(d - 1)}) #{op2()} (#{expr(d - 1)})"
    end
  end

  # Operatoren als Funktor schreiben, wenn sie keine Operatoren sind
  defp op2, do: Enum.random(@ops2)

  defp wrap(e) do
    # atan2/copysign/gcd/log sind keine Operatoren: als Funktor
    Regex.replace(~r/\(([^()]*)\) (atan2|copysign|gcd|log) \(([^()]*)\)/, e, "\\2(\\1, \\3)")
  end

  defp run(c, db, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      db
      |> PrologEx.query(g)
      |> Enum.take(2)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    rescue
      e in PrologEx.Error -> {:error, Exception.message(e)}
    end
  end

  test "is/2: übersetzt = interpretiert", c do
    :rand.seed(:exsss, {1, 2, 3})

    exprs =
      for _ <- 1..250 do
        e = expr(3) |> wrap()
        # nur Ausdrücke, die der Reader liest
        case Reader.read_terms(c.reader, "t(X) :- X is #{e}.") do
          [{:term, _, _}] -> e
          _ -> nil
        end
      end
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    assert length(exprs) > 100

    src =
      exprs
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {e, i} -> "c#{i}(A, B, X) :- X is #{e}." end)

    # nicht jeder Ausdruck braucht A und B
    PrologEx.StyleCheck.set(:singleton, false)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))

    checked =
      for {e, i} <- Enum.with_index(exprs),
          a <- Enum.take_random(@values, 4),
          b <- Enum.take_random(@values, 3) do
        compiled = run(c, db, "A = #{a}, B = #{b}, c#{i}(A, B, X)")
        interpreted = run(c, db, "A = #{a}, B = #{b}, call((X is #{e}))")

        assert compiled == interpreted,
               "#{e} mit A = #{a}, B = #{b}: #{inspect(compiled)} / #{inspect(interpreted)}"

        compiled
      end

    # die Stichprobe enthält Werte und Fehler
    assert Enum.count(checked, &is_list/1) > 100
    assert Enum.count(checked, &match?({:error, _}, &1)) > 100
  end

  test "Vergleiche: übersetzt = interpretiert", c do
    :rand.seed(:exsss, {4, 5, 6})

    cases =
      for _ <- 1..120 do
        {wrap(expr(2)), Enum.random(@cmps), wrap(expr(2))}
      end
      |> Enum.filter(fn {l, op, r} ->
        match?([{:term, _, _}], Reader.read_terms(c.reader, "t :- #{l} #{op} #{r}."))
      end)

    src =
      cases
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {{l, op, r}, i} -> "k#{i}(A, B) :- (#{l}) #{op} (#{r})." end)

    # nicht jeder Ausdruck braucht A und B
    PrologEx.StyleCheck.set(:singleton, false)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))

    for {{l, op, r}, i} <- Enum.with_index(cases),
        a <- Enum.take_random(@values, 3),
        b <- Enum.take_random(@values, 3) do
      compiled = run(c, db, "A = #{a}, B = #{b}, k#{i}(A, B)")
      interpreted = run(c, db, "A = #{a}, B = #{b}, call(((#{l}) #{op} (#{r})))")

      assert compiled == interpreted,
             "(#{l}) #{op} (#{r}) mit A = #{a}, B = #{b}: #{inspect(compiled)} / #{inspect(interpreted)}"
    end
  end

  test "Konstanten werden gefaltet, Fehler bleiben zur Laufzeit", c do
    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(c.reader, """
        k1(X) :- X is 2 * 3 + 1.
        k2(X) :- X is 1 / 0.
        k3(X) :- fail, X is 1 / 0.
        k4(X) :- X is random(10) * 0 + 1.
        k5(X) :- X is foo + 1.
        k6(X, Y) :- X is Y * 2 + pi.
        k7 :- 3 * 2 > 5.
        k8(N) :- N - 1 >= 0.
        """)
      )

    assert run(c, db, "k1(X)") == ["X = 7"]
    assert run(c, db, "k2(X)") == {:error, "evaluation_error(zero_divisor)"}
    assert run(c, db, "k3(X)") == []
    assert run(c, db, "k4(X)") == ["X = 1"]
    assert run(c, db, "k5(X)") == {:error, "type_error(evaluable,foo/0)"}
    assert run(c, db, "k6(X, 1)") == ["X = #{2 + :math.pi()}"]
    assert run(c, db, "k6(X, Y)") == {:error, "instantiation_error"}
    assert run(c, db, "k7") == ["true"]
    assert run(c, db, "k8(1)") == ["true"]
    assert run(c, db, "k8(0)") == []

    # clause/2 und listing zeigen den Quelltext, nicht die Übersetzung
    assert run(c, db, "clause(k1(X), B)") == ["B = (X is 2*3+1)"]
  end

  test "assertz-Klauseln (markierte Teilterme) werden auch übersetzt", c do
    assert run(c, %{}, "assertz((d(X, Y) :- Y is X * 2 + 1)), d(4, Y)") == ["Y = 9"]
    assert run(c, %{}, "assertz((d2(Y) :- Y is 2 * 3 + 1)), d2(Y)") == ["Y = 7"]
  end

  test "teure Konstanten werden nicht beim Laden ausgerechnet", c do
    {t, {_db, []}} =
      :timer.tc(fn ->
        PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, "big(X) :- X is 7 ^ 10000000."))
      end)

    assert t < 1_000_000
  end
end
