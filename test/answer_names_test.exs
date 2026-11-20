defmodule PrologEx.AnswerNamesTest do
  # Frische Variablen in Antworten heißen _A, _B, ..., _Z, _AA, ... (wie
  # SICStus), je Antwort neu, in Reihenfolge des Auftretens; Namen der
  # Anfrage werden übersprungen
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = Enum.reduce(["lists"], %{}, &PrologEx.use_library(&2, &1, "user"))
    {:ok, reader: r, db: db}
  end

  defp ask(c, text, n \\ 4) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)

    c.db
    |> PrologEx.query(g)
    |> Enum.take(n)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "je Antwort neu ab _A", c do
    assert ask(c, "length(As, N).") ==
             [
               "As = [], N = 0",
               "As = [_A], N = 1",
               "As = [_A,_B], N = 2",
               "As = [_A,_B,_C], N = 3"
             ]
  end

  test "dieselbe Variable, derselbe Name – auch über Bindungen und Restziele hinweg", c do
    assert ask(c, "copy_term(f(A, B, A), C).") == ["C = f(_A,_B,_A)"]
    assert ask(c, "copy_term(f(Q)-g(Q), X-Y).") == ["X = f(_A), Y = g(_A)"]
    assert ask(c, "length(L, 2), dif(L, [a, b]).") == ["L = [_A,_B], dif(f(_A,_B),f(a,b))"]

    assert ask(c, "length(L, 2), L = [_, Y], freeze(Y, true).") == [
             "L = [_A,Y], freeze(Y,true)"
           ]
  end

  test "Anfragevariablen behalten ihren Namen, ihre Namen werden übersprungen", c do
    assert ask(c, "X = f(_, Y, _).") == ["X = f(_A,Y,_B)"]
    # _A steht in der Anfrage: frische beginnen bei _B
    assert ask(c, "length(L, 3), L = [_A|_].") == ["L = [_A,_B,_C]"]
    assert ask(c, "length(L, 3), L = [_, _B|_].") == ["L = [_A,_B,_C]"]
    assert ask(c, "length(L, 2), L = [_, _A].") == ["L = [_B,_A]"]
  end

  test "nach _Z: _AA, _AB, ...", c do
    [answer] = ask(c, "length(L, 30).")
    assert answer =~ ",_Y,_Z,_AA,_AB,_AC,_AD]"

    [answer] = ask(c, "length(L, 703).")
    assert answer =~ ",_ZY,_ZZ,_AAA]"
  end

  # Antworten auflösen: Listen als Schleife, unveränderte Abschnitte und
  # Strukturen ohne Kopie – gebundene Stellen mitten in Abschnitten, Rest
  # als gebundene Variable, Teillisten, attributierte Elemente, Zyklen,
  # geteilte Teilterme (erwartet: wie vor der Umstellung)
  test "Listen in Antworten: Bindungen mitten drin, offene und zyklische Reste", c do
    for {q, a} <- [
          {"numlist(1, 5, L0), append(L0, [X|T], L), X = f(Y), T = [a, Z|R], Y = 9.",
           "L = [1,2,3,4,5,f(9),a,Z|R], L0 = [1,2,3,4,5], T = [a,Z|R], X = f(9), Y = 9"},
          {"length(L, 3), L = [A|_], A = g(B), last(L, B).", "A = g(B), L = [g(B),_A,B]"},
          {"L = [a, b|T], T = [c|L].", "L = [a,b,c|L], T = [c|L]"},
          {"X = f(X, Y), Y = [1,2|X].", "X = f(X,[1,2|X]), Y = [1,2|X]"},
          {"L = [1, 2, X], freeze(X, true).", "L = [1,2,X], freeze(X,true)"},
          {"length(L, 4), L = [_, X|_], dif(X, a), L = [_, _, b|_].",
           "L = [_A,X,b,_B], dif(X,a)"},
          {"A = [1,2,3|B], B = [4|C], C = [].", "A = [1,2,3,4], B = [4], C = []"},
          {"A = [p(X), q(Y)|_], X = Y, Y = 1.", "A = [p(1),q(1)|_A], X = 1, Y = 1"},
          {"length(L, 3), copy_term(L, L2), L2 = [Z|_], Z = q.",
           "L = [_A,_B,_C], L2 = [q,_D,_E], Z = q"},
          {"findall(A-B, (member(A, [1,2,3]), B = f(A, _)), L).",
           "L = [1-f(1,_A),2-f(2,_B),3-f(3,_C)]"},
          {"T0 = [x], T1 = [T0|T0], T2 = [T1|T1], L = f(T2, T2).",
           ~s{L = f([["x",x],"x",x],[["x",x],"x",x]), T0 = "x", T1 = ["x",x], T2 = [["x",x],"x",x]}}
        ] do
      assert ask(c, q, 1) == [a], q
    end

    # lang: ungebundene Variablen bleiben, gebundene Stellen erscheinen
    [a] = ask(c, "length(L, 100000), nth1(50000, L, m), last(L, e), L = [s|_].", 1)
    assert a =~ ~r/^L = \[s,_A,_B,/
    assert a =~ ~r/,m,_[A-Z]+,/
    assert a =~ ~r/,e\]$/
  end
end
