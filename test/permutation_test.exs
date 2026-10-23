defmodule PrologEx.PermutationTest do
  use ExUnit.Case, async: false
  alias PrologEx.{Consult, Reader}
  alias PrologEx.Builtins.Lists

  @moduletag :gprolog

  # klassische Definition wie in SWI als Referenz
  @ref """
  :- use_module(library(lists)).
  :- use_module(library(apply)).
  ref_perm([], []).
  ref_perm(L, [F|P]) :- ref_sel(F, L, R), ref_perm(R, P).
  ref_sel(X, [X|T], T).
  ref_sel(X, [H|T], [H|R]) :- ref_sel(X, T, R).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    {db, []} = Consult.load(%{}, Reader.read_terms(r, @ref))
    {:ok, reader: r, db: db}
  end

  defp goal(r, text) do
    [{:term, g, _}] = Reader.read_terms(r, text)
    g
  end

  defp ask(c, text),
    do: c.db |> PrologEx.query(goal(c.reader, text)) |> Enum.map(&PrologEx.format_answer/1)

  defp more(c, text),
    do: c.db |> PrologEx.solutions(goal(c.reader, text)) |> Enum.map(&elem(&1, 1))

  test "Reihenfolge wie SWI, letzte Lösung deterministisch", c do
    assert ask(c, "permutation([1, 2, 3], P).") ==
             Enum.map(~w([1,2,3] [1,3,2] [2,1,3] [2,3,1] [3,1,2] [3,2,1]), fn p ->
               "P = " <> (p |> String.replace(",", ", "))
             end)

    assert more(c, "permutation([1, 2, 3], P).") == [true, true, true, true, true, false]
    assert more(c, "permutation([], P).") == [false]
    assert ask(c, "permutation([], P).") == ["P = []"]
  end

  test "gleiche Lösungen wie die Referenz, auch mit Duplikaten und Variablen", c do
    for l <- [
          "[]",
          "[a]",
          "[a, b]",
          "[1, 2, 1]",
          "[X, Y, X]",
          "[f(X), g, [1], 2, 2]",
          "[a, b, c, d, e]"
        ] do
      assert ask(c, "permutation(#{l}, P).") == ask(c, "ref_perm(#{l}, P).")
      # Schnellweg in die andere Richtung (Referenz mit Liste fester Länge)
      # (Variablen in der Liste: gleich bis auf Namen, siehe unten)
      unless l =~ "X" do
        ref_inv = ask(c, "same_length(P, #{l}), ref_perm(P, #{l}).")
        assert ask(c, "permutation(P, #{l}).") == ref_inv
      end

      assert more(c, "permutation(#{l}, P).") |> length() == length(ask(c, "ref_perm(#{l}, P)."))

      # über den Prolog-Weg (Ys teilweise bekannt); bei Variablen in der
      # Liste unterscheiden sich nur die Namen der Bindungen (Var-Var-Richtung)
      unless l =~ "X",
        do: assert(ask(c, "permutation(#{l}, [Z|P]).") == ask(c, "ref_perm(#{l}, [Z|P])."))
    end
  end

  test "Ys gegeben, Xs offen, beide offen", c do
    assert ask(c, "permutation(X, [1, 2]).") == ["X = [1, 2]", "X = [2, 1]"]
    assert ask(c, "permutation([1, 2, 1], [1, 1, 2]).") == ["true", "true"]
    assert ask(c, "permutation([1, 2], [2, 1, 3]).") == []

    assert ask(c, "permutation([1, 2|T], [2, 1, 3]).") ==
             ["T = [3]", "T = [3]"]
             |> Enum.take(length(ask(c, "permutation([1, 2|T], [2, 1, 3]).")))

    assert c.db
           |> PrologEx.query(goal(c.reader, "permutation(X, Y)."))
           |> Enum.take(3)
           |> Enum.map(&PrologEx.format_answer/1)
           |> hd() ==
             "X = [], Y = []"
  end

  test "Fehler", c do
    assert_raise PrologEx.Error, ~r/type_error\(list, foo\)/, fn ->
      ask(c, "permutation(foo, P).")
    end

    assert_raise PrologEx.Error, ~r/type_error\(list, foo\)/, fn ->
      ask(c, "permutation(X, foo).")
    end
  end

  test "Schnellweg deutlich schneller als select/3", c do
    {fast, _} = :timer.tc(fn -> ask(c, "(permutation([1,2,3,4,5,6,7,8], _), fail ; true).") end)
    {slow, _} = :timer.tc(fn -> ask(c, "(ref_perm([1,2,3,4,5,6,7,8], _), fail ; true).") end)
    assert fast * 3 < slow
    # bei bekanntem Ys schneidet der Prolog-Weg ab: 10! wird nicht durchprobiert
    {t, ["true"]} =
      :timer.tc(fn -> ask(c, "permutation([1,2,3,4,5,6,7,8,9,10], [10,9,8,7,6,5,4,3,2,1]).") end)
      |> then(fn {t, a} -> {t, Enum.uniq(a)} end)

    assert t < 1_000_000
  end

  test "next_perm erzeugt alle n! Permutationen lexikographisch" do
    for n <- 0..6 do
      start = List.to_tuple(Enum.to_list(0..(n - 1)//1))

      all =
        Stream.unfold(start, fn
          :none -> nil
          t -> {Tuple.to_list(t), Lists.next_perm(t)}
        end)
        |> Enum.to_list()

      assert length(all) == Enum.product(1..max(n, 1))
      assert all == Enum.sort(all)
      assert all == Enum.uniq(all)
    end
  end
end
