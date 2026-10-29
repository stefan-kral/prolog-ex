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
end
