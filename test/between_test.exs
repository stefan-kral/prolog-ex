defmodule PrologEx.BetweenTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: PrologEx.use_library(%{}, "between", "user")}
  end

  defp ask(c, q, n \\ 10, db \\ nil) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      (db || c.db)
      |> PrologEx.query(g)
      |> Enum.take(n)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    rescue
      e in PrologEx.Error -> {:error, Exception.message(e)}
    end
  end

  test "gen_nat/1", c do
    assert ask(c, "gen_nat(N)", 5) == ["N = 0", "N = 1", "N = 2", "N = 3", "N = 4"]
    assert ask(c, "gen_nat(5)") == ["true"]
    assert ask(c, "gen_nat(0)") == ["true"]
    assert ask(c, "gen_nat(-1)") == []
    assert ask(c, "gen_nat(a)") == {:error, "type_error(integer,a)"}
    assert ask(c, "gen_nat(1.0)") == {:error, "type_error(integer,1.0)"}
    # konstanter Speicher: weit zählen, ohne Liste
    assert ask(c, "gen_nat(N), N >= 100000, !") == ["N = 100000"]
  end

  test "gen_int/1", c do
    assert ask(c, "gen_int(I)", 7) == [
             "I = 0",
             "I = 1",
             "I = -1",
             "I = 2",
             "I = -2",
             "I = 3",
             "I = -3"
           ]

    assert ask(c, "gen_int(-7)") == ["true"]
    assert ask(c, "gen_int(f(x))") == {:error, "type_error(integer,f(x))"}
    assert ask(c, "gen_int(I), I < -50, !") == ["I = -51"]
  end

  test "numlist/5", c do
    # Beispiel aus der SICStus-Doku
    assert ask(c, "numlist(L, 2, U, N, [1, X, Y, Z])") ==
             ["L = 1, N = 4, U = 7, X = 3, Y = 5, Z = 7"]

    assert ask(c, "numlist(1, 3, 10, N, L)") == ["L = [1,4,7,10], N = 4"]
    assert ask(c, "numlist(10, -3, 1, N, L)") == ["L = [10,7,4,1], N = 4"]
    assert ask(c, "numlist(5, 7, 5, N, L)") == ["L = [5], N = 1"]
    assert ask(c, "numlist(1, 3, 9, N, L)") == []
    assert ask(c, "numlist(5, 1, 1, N, L)") == []
    assert ask(c, "numlist(0, 5, U, 3, L)") == ["L = [0,5,10], U = 10"]
    assert ask(c, "numlist(L, S, U, 3, [2, 5, X])") == ["L = 2, S = 3, U = 8, X = 8"]
    assert ask(c, "numlist(1, 2, 7, 4, [1, 3, 5, 7])") == ["true"]
    assert ask(c, "numlist(1, 2, 7, 4, [1, 3, 6, 7])") == []
    assert ask(c, "numlist(1, 2, 7, 3, L)") == []
    assert ask(c, "numlist(L, S, U, N, [a, b])") == []
    # einelementig: Step bleibt offen
    assert ask(c, "numlist(L, S, U, N, [4])") == ["L = 4, N = 1, U = 4"]
    assert ask(c, "numlist(1, 1, 3, 0, L)") == []
    assert ask(c, "numlist(1, 1, 3, N, [1|T])") == ["N = 3, T = [2,3]"]
    # zu wenig bekannt
    assert ask(c, "numlist(L, S, U, N, Xs)") == {:error, "instantiation_error"}
    assert ask(c, "numlist(L, 2, 7, N, Xs)") == {:error, "instantiation_error"}
    assert ask(c, "numlist(L, S, U, N, [X, Y])") == {:error, "instantiation_error"}
    assert ask(c, "numlist(1, 0, 1, N, L)") == {:error, "instantiation_error"}
    assert ask(c, "numlist(1, 0, 1, 3, L)") == ["L = [1,1,1]"]
    assert ask(c, "numlist(a, 1, 3, N, L)") == {:error, "type_error(integer,a)"}
  end

  test "between/3, repeat/1, numlist/2,3 kommen mit (wie SICStus)", c do
    db = PrologEx.use_library(%{}, "between", "user")
    assert ask(c, "numlist(3, L)", 10, db) == ["L = [1,2,3]"]
    assert ask(c, "numlist(2, 4, L)", 10, db) == ["L = [2,3,4]"]
    assert ask(c, "findall(x, repeat(3), L)", 10, db) == ["L = \"xxx\""]
    assert ask(c, "between(1, 3, X)", 10, db) == ["X = 1", "X = 2", "X = 3"]

    # Import-Liste mit eingebautem between/3, lists dazu ohne Konflikt
    assert ask(c, "use_module(library(between), [between/3, gen_nat/1]), gen_nat(0)", 10, %{}) ==
             ["true"]

    assert ask(
             c,
             "use_module(library(lists)), use_module(library(between)), numlist(2, L)",
             10,
             %{}
           ) ==
             ["L = [1,2]"]
  end

  test "nur nach use_module sichtbar", c do
    assert ask(c, "gen_nat(0)", 1, %{}) == {:error, "existence_error(procedure,gen_nat/1)"}
  end
end
