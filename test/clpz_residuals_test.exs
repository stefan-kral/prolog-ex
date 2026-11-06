defmodule PrologEx.ClpzResidualsTest do
  # Restziele von library(clpz): standardmäßig lesbar (Flag clpz_residuals =
  # compact) – halboffene Domänen als #>/#>=/#</#=<, X #=< Y + C als #< oder
  # #=< mit der betragsmäßig kleineren Konstante; lineare Summen ebenso,
  # eine allein stehende Zahl rechts; mit clpz_residuals = scryer genau wie
  # Scryer
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}

  # Restziele einer Bedingung C (ohne Domänen gepostet) an frischen
  # Variablen wieder posten: in der Box -3..3 dieselben Lösungen wie C
  @program """
  same(C, Vs, Gs, N) :-
      copy_term(C-Vs, C1-Vs1), call(C1), copy_term(Vs1, Ws, Gs),
      findall(Vs, (call(C), Vs ins -3..3, label(Vs)), A),
      findall(Ws, (call(Gs), Ws ins -3..3, label(Ws)), B),
      A == B, length(A, N).

  % ... und in den Restzielen keine Hilfsvariablen mehr
  same_noaux(C, Vs, Gs, N) :-
      same(C, Vs, Gs, N),
      copy_term(C-Vs, C1-Vs1), call(C1), copy_term(Vs1, Ws, Gs1),
      term_variables(Gs1, GVs),
      \\+ ( member(V, GVs), \\+ ( member(W, Ws), W == V ) ).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ["clpz", "lists"])
    PrologEx.put_db(db)
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @program))
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

  test "lineare Summen: Zahl allein rechts, kleinste Konstante", c do
    for {q, want} <- [
          {"2*X+Y #=< 5", "2*X+Y#=<5"},
          {"2*X+Y #< 5", "2*X+Y#=<4"},
          {"2*X+3*Y #> 5", "2*X+3*Y#>5"},
          {"2*X+3*Y #>= 5", "2*X+3*Y#>4"},
          {"2*X+Y #>= -3", "2*X+Y#>= -3"},
          {"2*X+Y #>= 0", "2*X+Y#>=0"},
          {"2*X+Y #< 0", "2*X+Y#<0"},
          {"2*X+Y #< -5", "2*X+Y#< -5"},
          {"2*X #< 3*Y", "2*X#<3*Y"},
          {"2*X #=< 3*Y", "2*X#=<3*Y"},
          {"X+Y #< Z", "X+Y#<Z"},
          {"X - 2*Y #< -4", "X+4#<2*Y"},
          {"X+Y+Z #< W+2", "X+Y+Z#=<W+1"},
          {"X+Y+Z+3 #< W", "X+Y+Z+3#<W"}
        ] do
      assert res(c, q) == want, q
    end
  end

  test "wieder gepostet: dieselben Lösungen", c do
    for q <- [
          "X #> 1",
          "X #> -2",
          "X #< 1",
          "X #< -1",
          "X #=< Y - 2",
          "X #< Y + 2",
          "2*X+3*Y #> 1",
          "2*X+Y #>= -3",
          "2*X+Y #< -1",
          "2*X #< 3*Y",
          "X - 2*Y #< -4",
          "X+Y+Z #< W+2",
          "X+Y #< Z - 1",
          "X+Y+Z+1 #< W"
        ] do
      assert {:answers, [ans]} =
               run(c, "C = (#{q}), term_variables(C, Vs), same(C, Vs, Gs, N)"),
             q

      assert ans =~ ~r/N = [1-9]/, q
      refute ans =~ ~r/ in |\+ -/, q <> ": " <> ans
    end
  end

  test "Hilfsvariablen eingesetzt, Reifikation lesbar", c do
    for {q, want} <- [
          {"X #< Y #<==> B", "B in 0..1, X#<Y#<==>B"},
          {"X #> 3 #<==> B", "B in 0..1, X#>3#<==>B"},
          {"X in 0..3, B #<==> (0 #>= X)", "B in 0..1, X#=<0#<==>B, X in 0..3"},
          {"X #> Y + 2 #<==> B", "B in 0..1, X#>Y+2#<==>B"},
          {"X #\\= 3 #==> X #> Y", "X#\\=3#==>Y#<X"},
          {"X #= 1 #\\/ Y #= 2", "X#=1#\\/Y#=2"},
          {"#\\ (X #= 1 #/\\ Y #= 2)", "#\\ (X#=1#/\\Y#=2)"},
          {"X #< Y #<==> (Z #> 0)", "Z#>0#<==>X#<Y"},
          {"X #= Y*Z - 1", "X#=Y*Z-1"},
          {"X #= abs(Y) - 2", "X#>= -2, X#=abs(Y)-2"},
          {"X #= Y*Z", "Y*Z#=X"},
          {"X #= Y*Z + 2", "X#=Y*Z+2"},
          {"X #= abs(Y - Z) + 1", "X#>0, X#=abs(Y-Z)+1"},
          {"X #= (Y - Z) * W", "X#=(Y-Z)*W"},
          {"X #= Y mod 3 + 1", "X in 1..3, X#=Y mod 3+1"},
          {"X #= max(Y, Z) - 1", "Z#=<X+1, Y#=<X+1, X#=max(Y,Z)-1"}
        ] do
      assert res(c, q) == want, q
    end
  end

  test "Hilfsvariablen: wieder gepostet dieselben Lösungen, keine übrig", c do
    for q <- [
          "X #< Y #<==> B",
          "X #> Y + 2 #<==> B",
          "X #\\= 1 #==> X #> Y",
          "X #= 1 #\\/ Y #= 2",
          "#\\ (X #= 1 #/\\ Y #= 2)",
          "X #< Y #<==> (Z #> 0)",
          "X #= Y*Z - 1",
          "X #= abs(Y) - 2",
          "X #= Y*Z + 2",
          "X #= abs(Y - Z) + 1",
          "X #= max(Y, Z) - 1",
          "X #= (Y - Z) * W",
          "X #= Y mod 3 + 1",
          "X #= Y*Z - W*V",
          "X #< Y #<==> B, Y #> Z #<==> B"
        ] do
      assert {:answers, [ans]} =
               run(c, "C = (#{q}), term_variables(C, Vs), same_noaux(C, Vs, Gs, N)"),
             q

      assert ans =~ ~r/N = [1-9]/, q
    end
  end

  test "sichtbar bleibt, was in der Anfrage bzw. im kopierten Term steht", c do
    # copy_term/3: Y und Z nicht im kopierten Term, aber ohne Definition
    assert res(c, "X #= Y*Z - 1, copy_term(X, X1, Gs)") =~ "Gs = clpz:(X1#=_A*_B-1)"
    # alle im Term: dieselbe Form wie im Toplevel
    assert res(c, "X #= Y*Z - 1, copy_term([X,Y,Z], [A,B,C], Gs), Y = Y, Z = Z") =~
             "Gs = clpz:(A#=B*C-1)"

    # library(iso_ext): Liste
    assert {:answers, [ans]} =
             run(c, "use_module(library(iso_ext)), X #< Y #<==> B, copy_term([X,Y,B], V, Gs)")

    assert ans =~ "Gs = [clpz:(_A#<_B#<==>_C),clpz:(_C in 0..1)], V = [_A,_B,_C]", ans
  end

  test "Nachlauf: Kreise und fremde Vorkommen", c do
    # A #= B+1 und B #= A*2: nur eine der beiden wird eingesetzt
    assert res(c, "clpz:'$post_residuals'([], [clpz:(A #= B+1), clpz:(B #= A*2)], Gs)") =~
             ~r/^Gs = \[clpz:\(\w+#=\(\w+\+1\)\*2\)\]$/

    # A auch in einem Ziel eines anderen Moduls: bleibt
    assert res(
             c,
             "clpz:'$post_residuals'([X], [clpz:(X+1 #= A), clpz:(A #= Y*Z), freeze(A, true)], Gs), " <>
               "length(Gs, N)"
           ) =~ "N = 3"

    # nur eine Definition je Ziel (A #= B ist nicht zugleich die von B)
    assert res(
             c,
             "clpz:'$post_residuals'([X,Y], [clpz:(A #= B), clpz:(A #> X), clpz:(B #< Y)], Gs)"
           ) == "Gs = [clpz:(B#>X),clpz:(B#<Y)]"

    # A in der eigenen Definition: bleibt
    assert res(
             c,
             "clpz:'$post_residuals'([X,Y], [clpz:(A*X #= A), clpz:(A #\\= Y)], Gs), length(Gs, N)"
           ) =~
             "N = 2"

    # mehrere Verwendungen nur für einfache Ausdrücke (V oder V + C)
    assert res(
             c,
             "clpz:'$post_residuals'([X,Y,Z,W], [clpz:(Y*Z #= A), clpz:(A #\\= X), clpz:(A #\\= W)], Gs), length(Gs, N)"
           ) =~ "N = 3"

    assert res(
             c,
             "clpz:'$post_residuals'([X,Y,W], [clpz:(Y+1 #= A), clpz:(A #\\= X), clpz:(A #\\= W)], Gs)"
           ) == "Gs = [clpz:(Y+1#\\=X),clpz:(Y+1#\\=W)]"

    # Wahrheitswert: nur als Operand von Verknüpfungen, Domäne genau 0..1
    assert res(
             c,
             "clpz:'$post_residuals'([X,Y,Z,C], [clpz:(X #< Y #<==> A), clpz:(A + Z #= 1 #==> C)], Gs), length(Gs, N)"
           ) =~ "N = 2"

    assert res(
             c,
             "clpz:'$post_residuals'([X,Y,C], [clpz:(X #< Y #<==> A), clpz:(A in 0..2), clpz:(A #==> C)], Gs), length(Gs, N)"
           ) =~ "N = 3"

    # Domäne als Vergleich: verschoben (X + 1 #< 3 heißt X #=< 1)
    assert res(
             c,
             "clpz:'$post_residuals'([X,Y], [clpz:(X+1 #= A), clpz:(A #< 3), clpz:(A #\\= Y)], Gs)"
           ) ==
             "Gs = [clpz:(X#=<1),clpz:(X+1#\\=Y)]"

    # Konstanten auf beiden Seiten zusammengefasst
    assert res(c, "clpz:'$post_residuals'([X,Y,Z], [clpz:(X+1 #= A), clpz:(Y*Z+3 #= A)], Gs)") ==
             "Gs = [clpz:(X#=Y*Z+2)]"

    # Duplikate weg, auch mehrfache
    assert res(c, "clpz:'$post_residuals'([], [x, y, x, x], Gs)") == "Gs = [x,y]"

    # sichtbar: bleibt
    assert res(
             c,
             "clpz:'$post_residuals'([X,A], [clpz:(X+1 #= A), clpz:(A #= Y*Z)], Gs), length(Gs, N)"
           ) =~
             "N = 2"
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
    assert res(c, "2*X+3*Y #> 5") == "6#=<2*X+3*Y"
    assert res(c, "X+Y #< Z") == "X+Y+1#=<Z"
    assert res(c, "X #= Y*Z - 1") =~ "_A"
    assert res(c, "X #> 3 #<==> B") =~ "X#>=4#<==>B"
  end

  test "Flag: Voreinstellung compact, andere Werte abgelehnt", c do
    assert res(c, "current_prolog_flag(clpz_residuals, F)") == "F = compact"

    assert res(c, "catch(set_prolog_flag(clpz_residuals, x), error(E, _), true)") ==
             "E = domain_error(flag_value,clpz_residuals+x)"
  end
end
