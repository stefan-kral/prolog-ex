defmodule PrologEx.SoftCutTest do
  @moduledoc "Soft cut: (C *-> T ; E), (C *-> T), if/3 (SICStus)"
  use ExUnit.Case, async: false
  alias PrologEx.{Consult, Reader}

  @moduletag :gprolog

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = PrologEx.use_library(%{}, "lists", "user")

    {db, []} =
      Consult.load(
        db,
        Reader.read_terms(r, """
        cut_t(X) :- ( member(X, [1, 2, 3]) *-> ! ; true ).
        cut_t(4).
        cut_e(X) :- ( fail *-> true ; !, X = e ).
        cut_e(f).
        if_t(X) :- if(member(X, [1, 2, 3]), !, true).
        if_t(4).
        cc(X) :- ( member(X, [1, 2]), ! *-> true ; true ).
        cc(9).
        ce(X) :- ( member(X, [1, 2]), ! *-> true ).
        ce(9).
        goal_expansion(alt, neu).
        neu.
        exp1 :- ( alt *-> alt ; alt ).
        exp2 :- if(alt, alt, alt).
        """)
      )

    {:ok, reader: r, db: db}
  end

  defp ask(c, q, n \\ 10) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      c.db
      |> PrologEx.query(g)
      |> Enum.take(n)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    rescue
      e in PrologEx.Error -> {:error, Exception.message(e)}
    end
  end

  test "alle Lösungen der Bedingung, Else nur ohne Lösung", c do
    assert ask(c, "( member(X, [1, 2, 3]) *-> Y = X ; Y = none )") ==
             ["X = 1, Y = 1", "X = 2, Y = 2", "X = 3, Y = 3"]

    assert ask(c, "( fail *-> Y = a ; Y = b )") == ["Y = b"]
    # Then scheitert für manche Lösungen: Else läuft trotzdem nicht
    assert ask(c, "( member(X, [1, 2, 3]) *-> X > 1 ; X = none )") == ["X = 2", "X = 3"]
    assert ask(c, "( member(X, [1, 2]) *-> X > 5 ; X = none )") == []
    # die übrigen Alternativen der Bedingung scheitern: Else bleibt aus
    assert ask(c, "( member(X, [1, 2]), X < 2 *-> true ; X = none )") == ["X = 1"]
    assert ask(c, "if((member(X, [1, 2, 3]), X < 2), true, X = none)") == ["X = 1"]
    # zum Vergleich: -> nimmt nur die erste Lösung
    assert ask(c, "( member(X, [1, 2, 3]) -> Y = X ; Y = none )") == ["X = 1, Y = 1"]
  end

  test "ohne Else: wie (C, T)", c do
    assert ask(c, "( member(X, [1, 2]) *-> Y = X )") == ["X = 1, Y = 1", "X = 2, Y = 2"]
    assert ask(c, "( fail *-> true )") == []
  end

  test "if/3 wie SICStus", c do
    assert ask(c, "if(member(X, [1, 2, 3]), Y = X, Y = none)") ==
             ["X = 1, Y = 1", "X = 2, Y = 2", "X = 3, Y = 3"]

    assert ask(c, "if(fail, Y = a, Y = b)") == ["Y = b"]
    assert ask(c, "if(member(X, [1, 2]), X > 5, X = none)") == []
    assert ask(c, "G = (member(X, [1, 2]), Y = X), if(G, true, true)") |> length() == 2
  end

  test "Cut: in der Bedingung lokal, in Then/Else wie bei ;", c do
    assert ask(c, "( member(X, [1, 2, 3]), X >= 2, ! *-> true ; X = none )") == ["X = 2"]

    assert ask(c, "( member(X, [1, 2, 3]), ! *-> Y = a ; Y = b ), member(Z, [p, q])") ==
             ["X = 1, Y = a, Z = p", "X = 1, Y = a, Z = q"]

    # Cut in Then schneidet die Klausel (auch die Alternativen der Bedingung)
    assert ask(c, "cut_t(X)") == ["X = 1"]
    assert ask(c, "cut_e(X)") == ["X = e"]
    assert ask(c, "if_t(X)") == ["X = 1"]
    # Cut in der Bedingung schneidet nicht die Klausel
    assert ask(c, "cc(X)") == ["X = 1", "X = 9"]
    assert ask(c, "ce(X)") == ["X = 1", "X = 9"]
  end

  test "deterministische Bedingung hinterlässt keinen Choice Point", c do
    for q <- ["( true *-> true ; true )", "if(true, true, true)", "( X = 1 *-> true ; true )"] do
      [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")
      assert [{_, false}] = c.db |> PrologEx.solutions(g) |> Enum.take(1), q
    end

    # mit Alternativen in der Bedingung: weitere Lösungen möglich
    [{:term, g, _}] = Reader.read_terms(c.reader, "( member(X, [1, 2]) *-> true ; true ).")
    assert [{_, true}] = c.db |> PrologEx.solutions(g) |> Enum.take(1)
  end

  test "geschachtelt, in findall, mit Ausnahmen", c do
    assert ask(c, "findall(X-Y, ( member(X, [1, 2]) *-> member(Y, [a, b]) ; Y = n ), L)") ==
             ["L = [1-a, 1-b, 2-a, 2-b]"]

    assert ask(
             c,
             "findall(X-Y, ( member(X, [1, 2]) *-> ( member(Y, [a]), X > 1 *-> true ; Y = n ) ; true ), L)"
           ) == ["L = [1-n, 2-a]"]

    assert ask(c, "catch(( throw(x) *-> true ; true ), x, R = gefangen)") == ["R = gefangen"]

    assert ask(c, "( X = 1 ; X = 2 ), ( member(Y, [X, 3]) *-> true ; Y = none )") ==
             ["X = 1, Y = 1", "X = 1, Y = 3", "X = 2, Y = 2", "X = 2, Y = 3"]
  end

  test "Schreiben, Expansion, Schutz", c do
    assert ExUnit.CaptureIO.capture_io(fn -> ask(c, "writeq((a *-> b ; c)), nl") end) ==
             "a*->b;c\n"

    assert ask(c, "clause(exp1, B)") == ["B = (neu*->neu;neu)"]
    assert ask(c, "clause(exp2, B)") == ["B = if(neu, neu, neu)"]
    assert ask(c, "catch(assertz(if(a, b, c)), error(E, _), true)") |> hd() =~ "permission_error"
  end
end
