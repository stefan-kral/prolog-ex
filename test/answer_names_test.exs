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
    assert ask(c, "copy_term(f(A, B, A), C).") == ["C = f(_A, _B, _A)"]
    assert ask(c, "copy_term(f(Q)-g(Q), X-Y).") == ["X = f(_A), Y = g(_A)"]
    assert ask(c, "length(L, 2), dif(L, [a, b]).") == ["L = [_A,_B], dif(f(_A, _B), f(a, b))"]

    assert ask(c, "length(L, 2), L = [_, Y], freeze(Y, true).") == [
             "L = [_A,Y], freeze(Y, true)"
           ]
  end

  test "Anfragevariablen behalten ihren Namen, ihre Namen werden übersprungen", c do
    assert ask(c, "X = f(_, Y, _).") == ["X = f(_A, Y, _B)"]
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
end
