defmodule PrologEx.SkipListTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :gprolog
  @moduletag timeout: 20_000

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    PrologEx.put_db(PrologEx.use_library(%{}, "lists", "user"))
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "'$skip_list'/3: echte, offene, keine Listen", c do
    assert ask(c, "'$skip_list'(N, [a, b, c], R)") == ["N = 3, R = []"]
    assert ask(c, "'$skip_list'(N, [a, b|T], R), R == T") == ["N = 2, T = R"]
    assert ask(c, "'$skip_list'(N, [a|foo], R)") == ["N = 1, R = foo"]
    assert ask(c, "'$skip_list'(N, foo, R)") == ["N = 0, R = foo"]
    assert ask(c, "'$skip_list'(N, L, R), R == L") == ["L = R, N = 0"]
    assert ask(c, "'$skip_list'(2, [a, b], [])") == ["true"]
    assert ask(c, "'$skip_list'(3, [a, b], [])") == []
    # über Variablen gebundene Zellen und markierte (ground) Listen
    assert ask(c, "L = [a|T], T = [b|U], U = [c], '$skip_list'(N, L, R)") |> hd() =~
             "N = 3, R = []"

    assert ask(c, "numlist(1, 1000, L), '$skip_list'(N, [x|L], R)") |> hd() =~
             "N = 1001, R = []"
  end

  # (zyklische Terme nur hinter \+ \+: Antworten mit ihnen ließen sich nicht schreiben)
  test "'$skip_list'/3: zyklische Listen terminieren, Rest ist eine Zelle im Zyklus", c do
    assert ask(c, "\\+ \\+ (X = [a|X], '$skip_list'(_, X, R), R = [H|_], H == a)") == ["true"]

    for q <- [
          "X = [a|X]",
          "X = [a, b, c|X]",
          "X = [1, 2|Y], Y = [3, 4, 5, 6, 7|Y]",
          "numlist(1, 50, L), append(L, X0, X0), X = [x|X0]",
          # Zyklus über mehrere Variablen
          "X = [1|B], B = [2|C], C = [3|D], D = [4|E], E = [5|X]"
        ] do
      assert ask(c, "\\+ \\+ (#{q}, '$skip_list'(N, X, R), R = [_|_], integer(N))") ==
               ["true"],
             q
    end
  end
end
