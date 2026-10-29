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
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, @src))
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
end
