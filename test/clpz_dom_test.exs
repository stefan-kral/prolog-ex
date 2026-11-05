defmodule PrologEx.ClpzDomTest do
  # PrologEx.Builtins.ClpzDom (Domänen als kanonische Intervalllisten) gegen
  # ein Mengenorakel: eine Domäne ist die Menge ihrer Elemente im Fenster
  # -W..W, dazu zwei Bits "alles unter -W" und "alles über W" (die
  # Unendlichkeiten). Alle Mengenoperationen müssen damit übereinstimmen;
  # jedes Ergebnis muss kanonisch sein.
  use ExUnit.Case, async: true
  alias PrologEx.Builtins.ClpzDom, as: D

  @w 12

  # --- Orakel: {MapSet im Fenster, unten offen?, oben offen?} ---------------

  defp oracle(d) do
    set =
      for {l, u} <- d, x <- -@w..@w, D.leq(l, x) and D.leq(x, u), into: MapSet.new(), do: x

    {set, match?([{:inf, _} | _], d), d != [] and match?({_, :sup}, List.last(d))}
  end

  defp o_inter({s1, lo1, hi1}, {s2, lo2, hi2}),
    do: {MapSet.intersection(s1, s2), lo1 and lo2, hi1 and hi2}

  defp o_union({s1, lo1, hi1}, {s2, lo2, hi2}), do: {MapSet.union(s1, s2), lo1 or lo2, hi1 or hi2}

  defp o_compl({s, lo, hi}),
    do: {MapSet.difference(MapSet.new(-@w..@w), s), not lo, not hi}

  defp o_subset?({s1, lo1, hi1}, {s2, lo2, hi2}),
    do: MapSet.subset?(s1, s2) and (not lo1 or lo2) and (not hi1 or hi2)

  # --- Zufallsdomänen --------------------------------------------------------

  defp rand_bound_pair do
    a = Enum.random(-@w..@w)
    b = Enum.random(-@w..@w)
    {min(a, b), max(a, b)}
  end

  defp rand_dom do
    ivs = for _ <- 1..Enum.random(0..4)//1, do: rand_bound_pair()

    ivs =
      case :rand.uniform(5) do
        1 -> [{:inf, Enum.random(-@w..@w)} | ivs]
        2 -> [{Enum.random(-@w..@w), :sup} | ivs]
        3 -> [{:inf, Enum.random(-@w..@w)}, {Enum.random(-@w..@w), :sup} | ivs]
        _ -> ivs
      end

    if :rand.uniform(20) == 1, do: D.all(), else: D.from_intervals(ivs)
  end

  # kanonisch, und das Orakel stimmt (Elemente im Fenster – alle Schranken
  # liegen im Fenster, also sieht das Orakel die ganze Domäne)
  defp check(d, expected, what) do
    assert D.valid?(d), "#{what}: nicht kanonisch: #{inspect(d)}"
    assert oracle(d) == expected, "#{what}: #{inspect(d)}"
  end

  setup do
    :rand.seed(:exsss, {2026, 11, 5})
    :ok
  end

  test "from_intervals: kanonisch, Menge erhalten" do
    for _ <- 1..500 do
      ivs = for _ <- 1..Enum.random(0..6)//1, do: rand_bound_pair()
      d = D.from_intervals(ivs)
      assert D.valid?(d), inspect(ivs)
      s = for {l, u} <- ivs, x <- l..u, into: MapSet.new(), do: x
      assert oracle(d) == {s, false, false}, inspect(ivs)
      # idempotent
      assert D.from_intervals(d) == d
    end

    assert D.from_intervals([{3, 1}, {:sup, 2}, {5, :inf}]) == []
    assert D.from_intervals([{1, 3}, {4, 4}, {6, 7}]) == [{1, 4}, {6, 7}]
    assert D.from_intervals([{:inf, 3}, {2, 5}, {9, :sup}]) == [{:inf, 5}, {9, :sup}]
    assert D.from_list([5, 3, 4, 9, 3]) == [{3, 5}, {9, 9}]
    assert D.interval(:inf, :sup) == D.all()
    assert D.interval(:sup, :sup) == [] and D.interval(:inf, :inf) == []
  end

  test "Mengenoperationen wie das Orakel" do
    for _ <- 1..1500 do
      d1 = rand_dom()
      d2 = rand_dom()
      o1 = oracle(d1)
      o2 = oracle(d2)
      x = Enum.random(-@w..@w)

      check(D.intersection(d1, d2), o_inter(o1, o2), "intersection #{inspect({d1, d2})}")
      check(D.union(d1, d2), o_union(o1, o2), "union #{inspect({d1, d2})}")
      check(D.complement(d1), o_compl(o1), "complement #{inspect(d1)}")
      check(D.subtract(d1, d2), o_inter(o1, o_compl(o2)), "subtract #{inspect({d1, d2})}")

      {s1, lo1, hi1} = o1
      check(D.remove(d1, x), {MapSet.delete(s1, x), lo1, hi1}, "remove #{inspect({d1, x})}")

      check(
        D.remove_greater_than(d1, x),
        {MapSet.filter(s1, &(&1 <= x)), lo1, false},
        "remove_greater_than #{inspect({d1, x})}"
      )

      check(
        D.remove_smaller_than(d1, x),
        {MapSet.filter(s1, &(&1 >= x)), false, hi1},
        "remove_smaller_than #{inspect({d1, x})}"
      )

      assert D.contains?(d1, x) == MapSet.member?(s1, x), inspect({d1, x})

      # Teilmenge (für d1 = [] falsch, wie das Original)
      assert D.subdomain?(d1, d2) == (d1 != [] and o_subset?(o2, o1)), inspect({d1, d2})
      assert D.subdomain?(d1, d1) == (d1 != [])
      assert D.subdomain?(d1, []) == (d1 != [])
    end
  end

  test "Schranken, Anzahl, Liste, Punkt" do
    for _ <- 1..500 do
      d = rand_dom()
      {s, lo, hi} = oracle(d)

      case d do
        [] ->
          assert D.infimum(d) == nil and D.supremum(d) == nil
          assert D.num_elements(d) == 0
          assert D.to_list(d) == {:ok, []}

        _ ->
          assert D.infimum(d) == if(lo, do: :inf, else: Enum.min(s))
          assert D.supremum(d) == if(hi, do: :sup, else: Enum.max(s))

          if lo or hi do
            assert D.num_elements(d) == :sup
            assert D.to_list(d) == :error
          else
            assert D.num_elements(d) == MapSet.size(s)
            assert D.to_list(d) == {:ok, Enum.sort(s)}
          end
      end

      case D.singleton(d) do
        {:ok, x} -> assert MapSet.size(s) == 1 and not lo and not hi and MapSet.member?(s, x)
        :error -> assert MapSet.size(s) != 1 or lo or hi
      end
    end
  end

  test "smallest_finite, largest_finite, spread wie das Original" do
    # die kleinste endliche Schranke ist die untere des ersten Intervalls,
    # oder dessen obere, wenn die untere inf ist (für inf..sup also sup)
    assert D.smallest_finite([{:inf, 3}, {7, 9}]) == 3
    assert D.smallest_finite([{2, 3}, {7, :sup}]) == 2
    assert D.smallest_finite([{:inf, :sup}]) == :sup
    assert D.largest_finite([{:inf, 3}, {7, :sup}]) == 7
    assert D.largest_finite([{2, 3}, {7, 9}]) == 9
    assert D.largest_finite([{:inf, :sup}]) == :inf
    assert D.spread([{:inf, 3}, {7, 9}]) == 6
    assert D.spread([{2, 2}]) == 0
    assert D.spread([{:inf, :sup}]) == :inf
    assert D.spread([]) == nil
  end

  test "shift, negate: Mengenbilder" do
    for _ <- 1..300 do
      d = rand_dom()
      {s, lo, hi} = oracle(d)
      o = Enum.random(-3..3)
      sh = D.shift(d, o)
      assert D.valid?(sh)
      # Elemente im kleineren Fenster vergleichen (Verschiebung bleibt drin)
      inner = fn set -> MapSet.filter(set, &(abs(&1) <= @w - 3)) end
      {ss, _, _} = oracle(sh)
      assert inner.(ss) == inner.(MapSet.new(s, &(&1 + o))), inspect({d, o})
      assert oracle(D.negate(d)) == {MapSet.new(s, &(-&1)), hi, lo}, inspect(d)
      assert D.valid?(D.negate(d))
    end
  end

  test "expand, expand_more, contract, contract_less: intervallweise wie das Original" do
    # expand: l..u -> l·m..u·m (Obermenge der Vielfachen)
    assert D.expand([{1, 3}, {5, 5}], 2) == [{2, 6}, {10, 10}]
    assert D.expand([{1, 3}], -2) == [{-6, -2}]
    assert D.expand([{:inf, 3}, {5, :sup}], 3) == [{:inf, 9}, {15, :sup}]
    assert D.expand([{1, 3}], 1) == [{1, 3}]
    # expand_more: alle x mit x // m in l..u
    assert D.expand_more([{1, 2}], 3) == [{3, 8}]
    assert D.expand_more([{-2, -1}], 3) == [{-8, -3}]
    assert D.expand_more([{0, 0}], 3) == [{-2, 2}]
    assert D.expand_more([{:inf, -1}, {1, :sup}], 2) == [{:inf, -2}, {2, :sup}]
    # contract: die x, deren m-faches in l..u liegt
    assert D.contract([{3, 8}], 3) == [{1, 2}]
    assert D.contract([{-8, -3}], 3) == [{-2, -1}]
    assert D.contract([{4, 5}], 3) == []
    assert D.contract([{-2, 2}], 3) == [{0, 0}]
    assert D.contract([{:inf, 8}], 3) == [{:inf, 2}]
    # contract_less: l//m..u//m
    assert D.contract_less([{4, 11}], 3) == [{1, 3}]
    assert D.contract_less([{-11, -4}], 3) == [{-3, -1}]
    assert D.contract_less([{-2, 2}], 3) == [{0, 0}]

    for _ <- 1..300 do
      d = rand_dom()
      m = Enum.random([-3, -2, -1, 1, 2, 3, 5])

      for f <- [&D.expand/2, &D.expand_more/2, &D.contract/2, &D.contract_less/2] do
        assert D.valid?(f.(d, m)), inspect({d, m})
      end

      # contract(expand(d)) enthält d; contract_less(expand(d)) ebenso
      {s, _, _} = oracle(d)
      {se, _, _} = oracle(D.contract(D.expand(d, m), m))
      assert MapSet.subset?(MapSet.filter(s, &(abs(&1 * m) <= @w)), se), inspect({d, m})
    end
  end

  test "Prolog-Term hin und zurück" do
    for _ <- 1..300 do
      d = rand_dom()
      t = D.to_term(d)
      assert D.from_term(t) == {:ok, d}, inspect(d)
    end

    assert D.to_term([{:inf, 3}, {5, 5}, {9, 13}, {16, :sup}]) == [
             PrologEx.mk("..", [PrologEx.a("inf"), 3]),
             5,
             PrologEx.mk("..", [9, 13]),
             PrologEx.mk("..", [16, PrologEx.a("sup")])
           ]

    # nicht kanonisch: keine Domäne
    assert D.from_term([PrologEx.mk("..", [1, 3]), PrologEx.mk("..", [4, 6])]) == :error
    assert D.from_term([PrologEx.mk("..", [3, 3])]) == :error
    assert D.from_term([5, 3]) == :error
    assert D.from_term([PrologEx.a("inf")]) == :error
    assert D.from_term(PrologEx.a("empty")) == :error
  end
end
