defmodule PrologEx.RetractIndexTest do
  # retract/1 und retractall/1 prüfen nur die Klauseln, die zum ersten
  # Argument passen können (Index wie beim Aufruf) – mit denselben
  # Ergebnissen in derselben Reihenfolge
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @src """
  :- dynamic(r/2).
  r(1, a).
  r(X, b) :- X > 0.
  r(1, c).
  r(2, d).
  r(f(x), e).
  r([], f).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    libs = Enum.reduce(["lists", "between", "iso_ext"], %{}, &PrologEx.use_library(&2, &1))
    {db, []} = PrologEx.Consult.load(libs, Reader.read_terms(c.reader, @src))
    PrologEx.put_db(db)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(10)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp rest(c), do: ask(c, "findall(K-V, clause(r(K, V), _), L)")

  test "retract/1: Reihenfolge, Klausel mit Variable vorn an ihrer Stelle", c do
    # Liste aus Zeichen: als "…" (double_quotes=chars)
    assert ask(c, "findall(Y, retract((r(1, Y) :- _)), L)") == [~s(L = "abc")]
    assert rest(c) == ["L = [2-d,f(x)-e,[]-f]"]
  end

  test "retract/1: erster Treffer, Rest beim Backtracking", c do
    assert ask(c, "retract(r(1, Y))") == ["Y = a", "Y = c"]
    # r(X, b) hat einen Rumpf: retract(r(1, Y)) meint (r(1, Y) :- true)
    assert rest(c) == ["L = [_A-b,2-d,f(x)-e,[]-f]"]
  end

  test "retract/1: Struktur, Liste, offen", c do
    assert ask(c, "retract((r(f(x), Y) :- true))") == ["Y = e"]
    assert ask(c, "retract((r([], Y) :- true))") == ["Y = f"]
    assert ask(c, "retract((r(K, d) :- true))") == ["K = 2"]
    assert ask(c, "retract((r(9, Y) :- B))") == ["B = (9>0), Y = b"]
    assert rest(c) == ["L = [1-a,1-c]"]
  end

  test "retractall/1: passende samt Klausel mit Variable vorn; ohne Treffer unverändert", c do
    # r(X, b) passt zu r(7, _) (der Rumpf zählt nicht, ISO 8.9.5)
    assert ask(c, "retractall(r(7, _))") == ["true"]
    assert rest(c) == ["L = [1-a,1-c,2-d,f(x)-e,[]-f]"]

    # kein Treffer (auch die Klausel mit Variable vorn passt nicht)
    assert ask(c, "retractall(r(g(y), zz))") == ["true"]
    assert rest(c) == ["L = [1-a,1-c,2-d,f(x)-e,[]-f]"]

    assert ask(c, "retractall(r(1, _))") == ["true"]
    assert rest(c) == ["L = [2-d,f(x)-e,[]-f]"]

    assert ask(c, "retractall(r(_, _))") == ["true"]
    assert rest(c) == ["L = []"]
  end

  test "retractall/1 ohne Treffer: danach weiter aufrufbar, assert wirkt", c do
    assert ask(c, "retractall(r(g(y), zz)), r(7, V)") == ["V = b"]
    assert ask(c, "retractall(r(g(y), zz)), assertz(r(7, g)), r(7, V)") == ["V = b", "V = g"]
  end

  # nach assertz hinten Angehängtes ist aufgeschoben ({:cat, ...}); alles,
  # was die ganze Liste braucht, sieht sie in der richtigen Reihenfolge
  test "assertz/asserta im Wechsel mit Aufrufen: Reihenfolge stimmt überall", c do
    q = """
    retractall(r(_, _)),
    assertz(r(1, a)), r(1, _), assertz(r(2, b)), r(2, _), asserta(r(0, z)),
    assertz(r(X0, v)), r(1, _), assertz(r(1, c)),
    findall(K-V, r(K, V), L1),
    findall(V, r(1, V), L2),
    findall(K-V, clause(r(K, V), true), L3),
    predicate_property(r(_, _), number_of_clauses(N)),
    retract(r(2, b)), findall(K-V, r(K, V), L4),
    X0 = x
    """

    assert [a] = ask(c, q)
    assert a =~ "L1 = [0-z,1-a,2-b,_A-v,1-c]"
    assert a =~ ~s(L2 = "avc")
    assert a =~ "L3 = [0-z,1-a,2-b,_B-v,1-c]"
    assert a =~ "N = 5"
    assert a =~ "L4 = [0-z,1-a,_C-v,1-c]"
  end

  test "offenes erstes Argument nach vielen assertz: alle Lösungen in Reihenfolge", c do
    [a] =
      ask(c, """
      retractall(r(_, _)),
      forall(between(1, 50, I), (assertz(r(I, w)), r(I, _))),
      findall(K, r(K, _), L), length(L, N), L = [F|_], last(L, La)
      """)

    for part <- ["F = 1", "La = 50", "N = 50"], do: assert(a =~ part)
    assert a =~ "L = [1,2,3,"
  end

  test "Aufruf mit offenem erstem Argument macht flach und schreibt zurück", c do
    all = fn -> PrologEx.current_db() |> Map.fetch!({"user", "r", 2}) |> elem(1) end
    # (ist r/2 übersetzt – der JIT nimmt auch dynamische –, baut das erste
    # assertz einmal schlicht neu: materialize/1; danach aufgeschoben)
    ask(c, "assertz(r(7, x)), r(7, _)")
    # gebundenes erstes Argument: bleibt aufgeschoben
    ask(c, "assertz(r(9, z)), r(9, _)")
    assert {:cat, _, _} = all.()
    # offen: einmal flach, zurückgeschrieben
    ask(c, "once(r(_, _))")
    assert is_list(all.())
    # nullstellig bzw. offen über call/N ebenso
    ask(c, "assertz(r(8, y)), r(8, _), once(call(r, _, _))")
    assert is_list(all.())

    # nullstellig: braucht immer alle Klauseln
    ask(c, "assertz(n0), n0, assertz(n0), n0")
    assert is_list(PrologEx.current_db() |> Map.fetch!({"user", "n0", 0}) |> elem(1))
  end

  # Schlüsselindex der Einträge (retract/1, retractall/1): nachgeführt nur,
  # wenn ein retract genau einen Eintrag vorn entfernt. Fällt es auf die
  # flache Form zurück (hier: Klausel mit Variable an erster Stelle), kommt
  # hinten Angehängtes nach vorn – mit dem alten Index daran fehlte
  # retractall/1 danach eine passende Klausel (gefunden mit einem
  # Vergleich zufälliger Operationsfolgen gegen den vorigen Stand)
  test "retract mit Rückfall auf die flache Form: Index bleibt vollständig", c do
    ask(c, "retractall(r(_, _)), assertz(r(1, a)), assertz(r(2, b)), r(1, _)")
    # hinten: eine Klausel mit Variable im Quelltext-Kopf (übersetzt mit
    # Schlüssel 7) und eine mit Variable an erster Stelle
    ask(c, "assertz((r(X, c) :- X = 7)), assertz(r(_, d)), r(1, _)")
    # vorn entfernen (Index entsteht), dann die Klausel mit Variable vorn
    assert ask(c, "retract(r(1, a))") == ["true"]
    assert ask(c, "retract(r(_, d))") == ["true"]
    assert ask(c, "retractall(r(7, _)), findall(K-V, r(K, V), L)") == ["L = [2-b]"]
  end

  # Warteschlange aus Fakten: vorn retract, hinten assertz – dieselben
  # Lösungen in derselben Reihenfolge wie SWI. Mit once/1 eine
  # Warteschlange; ohne setzt findall/3 auch in retract/1 zurück, das dann
  # den ganzen Schnappschuss (5 Fakten) zurückzieht: 12 × 5
  test "Warteschlange aus Fakten mit und ohne gebundenes erstes Argument", c do
    for {fill, re, as, rest} <- [
          {"assertz(r(q, I))", "once(retract(r(q, X)))", "assertz(r(q, Y))",
           "findall(V, r(q, V), Rest)"},
          {"assertz(r(I, x))", "once(retract(r(X, _)))", "assertz(r(Y, x))",
           "findall(K, r(K, _), Rest)"}
        ] do
      a =
        ask(c, """
        retractall(r(_, _)), forall(between(1, 5, I), #{fill}),
        findall(X, (between(1, 12, _), #{re}, Y is X + 5, #{as}), Xs), #{rest}
        """)

      assert a == ["Rest = [13,14,15,16,17], Xs = [1,2,3,4,5,6,7,8,9,10,11,12]"]
    end

    [b] =
      ask(c, """
      retractall(r(_, _)), forall(between(1, 5, I), assertz(r(q, I))),
      findall(X, (between(1, 12, _), retract(r(q, X)), Y is X + 5, assertz(r(q, Y))), Xs),
      length(Xs, N), last(Xs, La), findall(V, r(q, V), Rest)
      """)

    assert b =~ "N = 60"
    assert b =~ "La = 60"
    assert b =~ "Rest = [61,62,63,64,65]"
  end
end
