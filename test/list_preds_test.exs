defmodule PrologEx.ListPredsTest do
  use ExUnit.Case, async: true
  import PrologEx.TestLibs
  import PrologEx

  @x v("X")
  @y v("Y")
  @i v("I")
  @e v("E")
  @l v("L")
  @r v("R")
  @n v("N")
  @t v("T")

  # klassische Referenzdefinitionen (nur für die Vergleiche)
  defp db do
    [h, t, e, i, i0, r, ri] = Enum.map(~w(H T E I I0 R RI), &v/1)

    consult([
      fact(s("p", [1])),
      fact(s("p", [2])),
      fact(s("p", [3])),
      fact(s("nth0_c", [0, [e | v("_")], e])),
      rule(s("nth0_c", [i, [v("_") | t], e]), [
        s("nth0_c", [i0, t, e]),
        s("is", [i, s("+", [i0, 1])])
      ]),
      fact(s("nth0_c", [0, [e | t], e, t])),
      rule(s("nth0_c", [i, [h | t], e, [h | ri]]), [
        s("nth0_c", [i0, t, e, ri]),
        s("is", [i, s("+", [i0, 1])])
      ]),
      fact(s("sel_c", [e, [e | t], t])),
      rule(s("sel_c", [e, [h | t], [h | r]]), [s("sel_c", [e, t, r])]),
      fact(s("dummy", [r]))
    ])
    |> libs()
  end

  defp all(goal, n \\ 20), do: db() |> query(goal) |> Enum.take(n) |> Enum.map(&format_answer/1)
  defp more(goal), do: db() |> solutions(goal) |> Enum.take(20) |> Enum.map(&elem(&1, 1))

  defp error(goal), do: assert_raise(PrologEx.Error, fn -> Enum.take(query(db(), goal), 1) end)

  # Antworten als Varianten vergleichen
  defp norm(answers) do
    Enum.map(answers, fn ans ->
      {terms, _} = ans |> Enum.sort() |> Enum.map(&elem(&1, 1)) |> renumber(%{})
      terms
    end)
  end

  defp renumber({:var, _} = x, m) do
    case Map.fetch(m, x) do
      {:ok, i} -> {{:v, i}, m}
      :error -> {{:v, map_size(m)}, Map.put(m, x, map_size(m))}
    end
  end

  defp renumber({:struct, f, args}, m) do
    {args, m} = renumber(args, m)
    {{:struct, f, args}, m}
  end

  defp renumber([h | t], m) do
    {h, m} = renumber(h, m)
    {t, m} = renumber(t, m)
    {[h | t], m}
  end

  defp renumber(t, m), do: {t, m}

  defp same(goal_a, goal_b, n \\ 8) do
    norm(db() |> query(goal_a) |> Enum.take(n)) == norm(db() |> query(goal_b) |> Enum.take(n))
  end

  defp gen_list(open?) do
    items =
      for _ <- 1..:rand.uniform(4)//1, do: Enum.random([1, 2, a("a"), v("A"), s("f", [v("B")])])

    items = Enum.drop(items, 1)
    if open?, do: list(items, v("T")), else: list(items)
  end

  describe "succ/2" do
    test "beide Richtungen und Fehler" do
      assert all(s("succ", [3, @y])) == ["Y = 4"]
      assert all(s("succ", [@x, 4])) == ["X = 3"]
      assert all(s("succ", [0, @y])) == ["Y = 1"]
      assert all(s("succ", [@x, 0])) == []
      assert all(s("succ", [2, 3])) == ["true"]
      error(s("succ", [@x, @y]))
      error(s("succ", [-1, @y]))
      error(s("succ", [a("a"), @y]))
    end
  end

  describe "call_nth/2" do
    test "nummeriert Lösungen" do
      assert all(s("call_nth", [s("p", [@x]), @n])) == [
               "N = 1, X = 1",
               "N = 2, X = 2",
               "N = 3, X = 3"
             ]

      assert more(s("call_nth", [s("p", [@x]), @n])) == [true, true, false]
    end

    test "N-te Lösung, deterministisch" do
      assert all(s("call_nth", [s("p", [@x]), 2])) == ["X = 2"]
      assert more(s("call_nth", [s("p", [@x]), 2])) == [false]
      assert all(s("call_nth", [s("p", [@x]), 4])) == []
    end

    test "deterministisches Ziel: kein Choice Point" do
      assert more(s("call_nth", [a("true"), @n])) == [false]
    end

    test "Cut im Ziel ist lokal" do
      assert all(s("call_nth", [s(",", [s("p", [@x]), a("!")]), @n])) == ["N = 1, X = 1"]
    end

    test "Fehler" do
      error(s("call_nth", [a("true"), 0]))
      error(s("call_nth", [a("true"), a("a")]))
    end

    test "countall über call_nth (Anzahl = Nummer der angehängten Alternative - 1)" do
      done = v("Done")
      m = v("M")

      goal =
        s(",", [
          s("call_nth", [s(";", [s("p", [@x]), s("=", [done, a("true")])]), m]),
          s(",", [s("==", [done, a("true")]), s(",", [a("!"), s("is", [@n, s("-", [m, 1])])])])
        ])

      [ans] = db() |> query(goal) |> Enum.take(1)
      assert ans["N"] == 3
    end
  end

  describe "select/3" do
    test "Modi" do
      assert all(s("select", [@x, list([a("a"), a("b"), a("c")]), @r])) ==
               ["R = \"bc\", X = a", "R = \"ac\", X = b", "R = \"ab\", X = c"]

      assert more(s("select", [@x, list([a("a"), a("b")]), @r])) == [true, false]
      assert more(s("select", [a("b"), list([a("a"), a("b")]), @r])) == [false]

      assert all(s("select", [a("x"), @l, list([a("a"), a("b")])])) ==
               ["L = \"xab\"", "L = \"axb\"", "L = \"abx\""]
    end

    test "gleich wie klassisch" do
      :rand.seed(:exsss, {9, 1, 9})

      for _ <- 1..500 do
        l = gen_list(:rand.uniform(4) == 1)
        x = Enum.random([@x, 1, a("a"), s("f", [2])])
        r = Enum.random([@r, @r, gen_list(false)])

        assert same(s("select", [x, l, r]), s("sel_c", [x, l, r])),
               "select(#{format(x)}, #{format(l)}, #{format(r)})"
      end
    end
  end

  describe "same_length/2" do
    test "Modi" do
      assert all(s("same_length", [list([1, 2]), list([a("a"), a("b")])])) == ["true"]
      assert all(s("same_length", [list([1, 2]), list([a("a")])])) == []
      assert all(s("same_length", [list([1, 2]), @l])) |> hd() =~ ~r/^L = \[_A, _B\]$/

      assert all(s("same_length", [list([a("a")], @t), list([1, 2, 3])])) |> hd() =~
               ~r/^T = \[_A, _B\]$/

      assert more(s("same_length", [list([1, 2]), @l])) == [false]

      assert all(s("same_length", [list([1, 2, 3]), list([a("a")], @t)])) |> hd() =~
               ~r/^T = \[_A, _B\]$/

      assert length(all(s("same_length", [@l, @r]), 3)) == 3
    end
  end

  describe "nth0/nth1" do
    test "Modi" do
      abc = list([a("a"), a("b"), a("c")])
      assert all(s("nth0", [1, abc, @e])) == ["E = b"]
      assert all(s("nth1", [1, abc, @e])) == ["E = a"]
      assert all(s("nth0", [5, abc, @e])) == []
      assert all(s("nth1", [0, abc, @e])) == []
      assert all(s("nth1", [@i, abc, @e])) == ["E = a, I = 1", "E = b, I = 2", "E = c, I = 3"]
      assert more(s("nth0", [@i, abc, @e])) == [true, true, false]
      assert more(s("nth0", [1, abc, @e])) == [false]
      assert all(s("nth0", [1, abc, @e, @r])) == ["E = b, R = \"ac\""]
      assert more(s("nth1", [@i, abc, @e, @r])) == [true, true, false]
      assert all(s("nth0", [1, @l, a("x"), list([a("a"), a("b")])])) == ["L = \"axb\""]

      assert all(s("nth0", [@i, @l, a("x"), list([a("a"), a("b")])])) ==
               ["I = 0, L = \"xab\"", "I = 1, L = \"axb\"", "I = 2, L = \"abx\""]

      assert all(s("nth0", [3, list([a("a")], @t), a("x")])) |> hd() =~
               ~r/^T = \[_A, _B, x\|_C\]$/

      error(s("nth0", [a("a"), abc, @e]))
    end

    test "gleich wie klassisch (echte Listen)" do
      :rand.seed(:exsss, {4, 4, 4})

      for _ <- 1..400 do
        l = gen_list(false)
        i = Enum.random([@i, 0, 1, 2, 5])
        e = Enum.random([@e, 1, a("a")])

        assert same(s("nth0", [i, l, e]), s("nth0_c", [i, l, e])),
               "nth0(#{format(i)}, #{format(l)})"

        assert same(s("nth0", [i, l, e, @r]), s("nth0_c", [i, l, e, @r])),
               "nth0/4(#{format(i)}, #{format(l)})"
      end
    end
  end

  describe "maplist/2..8" do
    test "Modi" do
      assert all(s("maplist", [a("succ"), list([1, 2, 3]), @l])) == ["L = [2, 3, 4]"]
      assert all(s("maplist", [a("atom"), list([a("a"), a("b")])])) == ["true"]
      assert all(s("maplist", [a("atom"), list([a("a"), 1])])) == []

      assert all(s("maplist", [s("nth1", [2]), list([list([1, 2]), list([3, 4])]), @l])) == [
               "L = [2, 4]"
             ]

      assert more(s("maplist", [a("succ"), list([1, 2, 3]), @l])) == [false]
    end

    test "maplist/8 ruft call/8" do
      db = consult([fact(s("seven", Enum.map(1..7, fn k -> v("A#{k}") end)))]) |> libs()
      ls = for k <- 1..7, do: list([k, k])
      assert db |> query(s("maplist", [a("seven") | ls])) |> Enum.take(1) == [%{}]
    end
  end
end
