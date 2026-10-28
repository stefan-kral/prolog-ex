defmodule PrologEx.RandomTest do
  use ExUnit.Case, async: false
  alias PrologEx.{Consult, Reader}

  @prog """
  :- use_module(library(random)).
  :- use_module(library(lists)).
  :- use_module(library(apply)).
  ist_perm(L, P) :- msort(L, S), msort(P, S).
  teilfolge([], _).
  teilfolge([X|Xs], [X|Ys]) :- !, teilfolge(Xs, Ys).
  teilfolge(Xs, [_|Ys]) :- teilfolge(Xs, Ys).
  zwischen(L, H, X) :- integer(X), X >= L, X =< H.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    {db, []} = Consult.load(%{}, Reader.read_terms(r, @prog))
    {:ok, reader: r, db: db}
  end

  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    c.db |> PrologEx.query(g) |> Enum.take(5) |> Enum.map(&PrologEx.format_answer/1)
  end

  defp ok?(c, text), do: ask(c, text) != []

  defp err(c, text) do
    Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end))
  end

  test "nur nach use_module(library(random)) sichtbar", c do
    [{:term, g, _}] = Reader.read_terms(c.reader, "random(X).")

    assert_raise PrologEx.Error, ~r/existence_error/, fn ->
      PrologEx.query(%{}, g) |> Enum.take(1)
    end
  end

  test "reproduzierbar mit set_random/1 und getrand/setrand", c do
    assert ok?(
             c,
             "set_random(seed(7)), randseq(20, 20, A), set_random(seed(7)), randseq(20, 20, B), A == B."
           )

    assert ok?(
             c,
             "set_random(seed(7)), randseq(20, 20, A), set_random(seed(8)), randseq(20, 20, B), A \\== B."
           )

    assert ok?(c, "getrand(S), random(A), random(_), setrand(S), random(B), A == B.")
    assert ask(c, "getrand(S), S = rand(A, B), integer(A), integer(B).") |> length() == 1
    assert err(c, "setrand(foo).") =~ "domain_error(random_state"
  end

  test "maybe/0: etwa jedes zweite Mal, deterministisch, reproduzierbar", c do
    [ans] = ask(c, "findall(x, (between(1, 4000, _), maybe), L), length(L, N).")
    [_, n] = Regex.run(~r/N = (\d+)/, ans)
    assert String.to_integer(n) in 1800..2200

    assert ask(
             c,
             "set_random(seed(3)), findall(B, (between(1, 30, _), (maybe -> B = 1 ; B = 0)), L1), " <>
               "set_random(seed(3)), findall(B, (between(1, 30, _), (maybe -> B = 1 ; B = 0)), L2), " <>
               "L1 == L2, sort(L1, [0, 1])."
           )
           |> length() == 1

    # kein Choice Point: höchstens eine Lösung
    assert ask(c, "between(1, 50, _), maybe, !.") |> length() == 1
    assert ask(c, "findall(x, maybe, L), length(L, N), N =< 1.") |> length() == 1
  end

  test "randseq/3 und randset/3", c do
    assert ok?(c, "randseq(50, 50, L), numlist(1, 50, N), ist_perm(L, N).")

    assert ok?(
             c,
             "randseq(10, 1000, L), length(L, 10), sort(L, S), length(S, 10), maplist(zwischen(1, 1000), L)."
           )

    assert ok?(c, "randset(10, 1000, L), length(L, 10), sort(L, L).")
    assert ok?(c, "randseq(300, 400, L), sort(L, S), length(S, 300).")
    assert ask(c, "randseq(0, 5, L).") == ["L = []"]
    assert err(c, "randseq(6, 5, L).") =~ "domain_error"
    assert err(c, "randseq(K, 5, L).") =~ "instantiation_error"
    assert err(c, "randseq(a, 5, L).") =~ "type_error(integer, a)"
  end

  test "random/1, random/3, random_between/3: Grenzen", c do
    assert ok?(c, "random(X), float(X), X >= 0.0, X < 1.0.")

    assert ok?(
             c,
             "findall(X, (between(1, 300, _), random(1, 4, X)), L), msort(L, S), sort(S, [1, 2, 3])."
           )

    assert ok?(
             c,
             "findall(X, (between(1, 300, _), random_between(1, 3, X)), L), sort(L, [1, 2, 3])."
           )

    assert ok?(c, "random(1.5, 2, X), float(X), X >= 1.5, X < 2.")
    assert ask(c, "random(3, 3, X).") == []
    assert ask(c, "random_between(3, 2, X).") == []
    assert ok?(c, "random_between(5, 5, X), X == 5.")
    assert err(c, "random(a, 2, X).") =~ "type_error(number, a)"
    assert err(c, "random_between(1, 2.5, X).") =~ "type_error(integer, 2.5)"
  end

  test "random_member/2, random_select/3, random_subseq/3", c do
    assert ok?(c, "random_member(X, [a, b, c]), memberchk(X, [a, b, c]).")
    assert ask(c, "random_member(X, []).") == []
    assert err(c, "random_member(X, [a|_]).") =~ "instantiation_error"

    assert ok?(c, "random_select(X, [a, b, c], R), length(R, 2), msort([X|R], [a, b, c]).")
    assert ask(c, "random_select(X, [], R).") == []
    # umgekehrt: einfügen
    assert ok?(c, "random_select(x, L, [a, b, c]), length(L, 4), select(x, L, [a, b, c]).")

    assert ok?(
             c,
             "numlist(1, 20, L), random_subseq(L, S, C), teilfolge(S, L), teilfolge(C, L), append(S, C, A), msort(A, L)."
           )
  end

  test "random_permutation/2 in beide Richtungen, etwa gleichverteilt", c do
    assert ok?(c, "random_permutation([a, b, c, d], P), ist_perm([a, b, c, d], P).")
    assert ok?(c, "random_permutation(P, [a, b, c, d]), ist_perm([a, b, c, d], P).")
    assert ask(c, "random_permutation([], P).") == ["P = []"]
    assert err(c, "random_permutation(X, Y).") =~ "instantiation_error"

    # 6000 Mischungen von [1, 2, 3]: jede der 6 Permutationen etwa 1000-mal
    counts =
      for p <- ~w([1,2,3] [1,3,2] [2,1,3] [2,3,1] [3,1,2] [3,2,1]) do
        [n] =
          ask(
            c,
            "findall(x, (between(1, 6000, _), random_permutation([1, 2, 3], P), P == #{p}), L), length(L, N)."
          )

        n |> String.split("N = ") |> List.last() |> String.to_integer()
      end

    for n <- counts, do: assert(n in 800..1200, "Verteilung: #{inspect(counts)}")
  end
end
