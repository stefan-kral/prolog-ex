defmodule PrologEx.ClauseIndexTest do
  # clause/2 wählt die Klauseln wie ein Aufruf (Index aufs erste Argument):
  # dieselben Lösungen in derselben Reihenfolge, aber ohne die
  # unpassenden zu kopieren, und deterministisch bei genau einer
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @src """
  :- dynamic(d/1).
  p(1, a).
  p(X, b) :- X > 0.
  p(1, c).
  p(2, d).
  p(f(x), e).
  p([h|t], f).
  p([], g).
  q(1, eins).
  q(2, zwei).
  q(3, drei).
  nullstellig :- q(1, _).
  nullstellig.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @src))
    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    PrologEx.put_db(c.db)
    # Antworten: Listen aus Zeichen erscheinen als "…" (double_quotes=chars)
    :ok
  end

  defp goal(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")
    g
  end

  defp ask(c, q) do
    g = goal(c, q)

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(10)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  # je Lösung: bleibt danach noch ein Choice Point?
  defp more(c, q),
    do: PrologEx.current_db() |> PrologEx.solutions(goal(c, q)) |> Enum.map(&elem(&1, 1))

  test "Reihenfolge: Klauseln mit Variable vorn bleiben an ihrer Stelle", c do
    assert ask(c, "clause(p(1, Y), _)") == ["Y = a", "Y = b", "Y = c"]
    assert ask(c, "clause(p(2, Y), _)") == ["Y = b", "Y = d"]
    assert ask(c, "clause(p(f(x), Y), _)") == ["Y = b", "Y = e"]
    assert ask(c, "clause(p(f(y), Y), _)") == ["Y = b"]
    assert ask(c, "clause(p([h|t], Y), _)") == ["Y = b", "Y = f"]
    # gleicher Schlüssel ('.'/2), aber der Kopf passt nicht
    assert ask(c, "clause(p([a], Y), _)") == ["Y = b"]
    assert ask(c, "clause(p([], Y), _)") == ["Y = b", "Y = g"]
    # offen: alle, wie bisher
    assert ask(c, "findall(Y, clause(p(_, Y), _), L)") == [~s(L = "abcdefg")]
    # attributierte Variable an erster Stelle: offen, also alle
    assert ask(c, "freeze(A, true), findall(Y, clause(p(A, Y), _), L)") |> hd() =~
             ~s(L = "abcdefg")
  end

  test "nullstellig: alle Klauseln", c do
    assert ask(c, "clause(nullstellig, B)") == ["B = q(1,_A)", "B = true"]
  end

  test "Rümpfe und Köpfe wie gespeichert", c do
    assert ask(c, "clause(p(5, Y), B)") == ["B = (5>0), Y = b"]
    assert ask(c, "clause(p(X, b), B)") == ["B = (X>0)"]
  end

  test "deterministisch, wenn genau eine Klausel passt", c do
    assert more(c, "clause(q(2, Y), true)") == [false]
    assert more(c, "clause(q(9, Y), true)") == []
    assert more(c, "clause(q(Y, _), true)") == [true, true, false]
    assert more(c, "clause(p(1, Y), _)") == [true, true, false]
  end

  test "dynamisch: nach assert, Schnappschuss während retract", c do
    assert ask(
             c,
             "assertz(d(1)), assertz(d(2)), asserta(d(0)), findall(X, clause(d(X), true), L)"
           ) ==
             ["L = [0,1,2]"]

    PrologEx.put_db(c.db)
    assert more(c, "assertz(d(1)), assertz(d(2)), clause(d(2), B)") == [false]

    # Schnappschuss: während der Aufzählung zurückgezogene Klauseln bleiben sichtbar
    PrologEx.put_db(c.db)

    assert ask(c, "assertz(d(1)), assertz(d(1)), findall(x, (clause(d(1), _), retract(d(1))), L)") ==
             [~s(L = "xx")]
  end
end
