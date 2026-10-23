defmodule PrologEx.OrderTest do
  use ExUnit.Case, async: true
  import PrologEx
  alias PrologEx.Order

  @x v("X")
  @y v("Y")
  @z v("Z")
  @l v("L")
  @o v("O")

  defp db, do: consult([fact(s("p", [1]))])
  defp all(goal), do: db() |> query(goal) |> Enum.take(20) |> Enum.map(&format_answer/1)
  defp ok?(goal), do: all(goal) != []

  defp error(goal) do
    assert_raise RuntimeError, fn -> Enum.take(query(db(), goal), 1) end
  end

  describe "Gleichheit ist strikt" do
    test "1 und 1.0 sind verschiedene Terme" do
      assert all(s("=", [1, 1.0])) == []
      assert all(s("=", [s("f", [1]), s("f", [1.0])])) == []
      assert all(s("==", [1, 1.0])) == []
      assert all(s("\\==", [1, 1.0])) == ["true"]
      assert all(s("=", [1.0, 1.0])) == ["true"]
    end
  end

  describe "Standardordnung" do
    # [1] ist '.'(1, []): Stelligkeit 2 wie f(a, a), und '.' < f
    test "Var < Zahl < Atom < zusammengesetzt" do
      chain = [
        @x,
        1.0,
        1,
        2,
        a("[]"),
        a("a"),
        a("b"),
        s("f", [@y]),
        list([1]),
        s("f", [a("a"), a("a")])
      ]

      for {a, i} <- Enum.with_index(chain), {b, j} <- Enum.with_index(chain) do
        expected =
          cond do
            i < j -> "<"
            i > j -> ">"
            true -> "="
          end

        assert all(s("compare", [@o, a, b])) == ["O = #{expected}"],
               "compare(#{format(a)}, #{format(b)})"
      end
    end

    test "zusammengesetzt: Stelligkeit, dann Name, dann Argumente" do
      assert all(s("@<", [s("z", [1]), s("a", [1, 1])])) == ["true"]
      assert all(s("@<", [s("a", [2]), s("b", [1])])) == ["true"]
      assert all(s("@<", [s("f", [1, 2]), s("f", [1, 3])])) == ["true"]
      assert all(s("@<", [list([1, 2]), list([1, 3])])) == ["true"]
      # '.'/2 gegen g/2: Name entscheidet ('.' < g)
      assert all(s("@<", [list([9]), s("g", [1, 1])])) == ["true"]
    end

    test "@-Vergleiche" do
      assert all(s("@<", [1, 2])) == ["true"]
      assert all(s("@>", [a("b"), a("a")])) == ["true"]
      assert all(s("@=<", [a("a"), a("a")])) == ["true"]
      assert all(s("@>=", [a("a"), a("b")])) == []
      assert all(s("==", [s("f", [@x]), s("f", [@x])])) == ["true"]
      assert all(s("==", [@x, @y])) == []
    end

    test "gebundene Variablen werden verfolgt" do
      goal = s(",", [s("=", [@x, 5]), s("compare", [@o, @x, 3])])
      assert all(goal) == ["O = >, X = 5"]
    end

    test "compare/3: Fehler und Prüfung" do
      assert all(s("compare", [a("<"), 1, 2])) == ["true"]
      assert all(s("compare", [a("="), 1, 2])) == []
      error(s("compare", [a("foo"), 1, 2]))
      error(s("compare", [1, 1, 2]))
    end
  end

  describe "sort/2, msort/2, keysort/2" do
    test "sort sortiert und entfernt Duplikate" do
      assert all(s("sort", [list([a("c"), a("b"), a("a"), a("b"), 2, 1, 1.0]), @l])) ==
               ["L = [1.0, 1, 2, a, b, c]"]

      assert all(s("sort", [list([]), @l])) == ["L = []"]
      assert all(s("sort", [list([@y, @x, @y]), @l])) |> hd() =~ ~r/^L = \[[XY], [XY]\]$/
    end

    test "msort behält Duplikate" do
      assert all(s("msort", [list([a("b"), a("a"), a("b")]), @l])) == ["L = [a, b, b]"]
    end

    test "keysort ist stabil" do
      pairs =
        list([s("-", [a("b"), 1]), s("-", [a("a"), 2]), s("-", [a("b"), 0]), s("-", [a("a"), 1])])

      assert all(s("keysort", [pairs, @l])) == ["L = [-(a, 2), -(a, 1), -(b, 1), -(b, 0)]"]
    end

    test "Fehler" do
      error(s("sort", [a("foo"), @l]))
      error(s("sort", [list([1], @x), @l]))
      error(s("sort", [list([1]), a("foo")]))
      error(s("keysort", [list([s("-", [a("a"), 1]), a("x")]), @l]))
      error(s("keysort", [list([@x]), @l]))
    end
  end

  describe "term_variables/2" do
    test "Reihenfolge des ersten Auftretens, ohne Wiederholung" do
      t = s("f", [@x, s("g", [@y, @x]), list([@z], v("_"))])
      [ans] = db() |> query(s("term_variables", [t, @l])) |> Enum.take(1)
      assert [@x, @y, @z, {:var, _}] = ans["L"]
      assert all(s("term_variables", [s("f", [a("a"), list([1, 2])]), @l])) == ["L = []"]
    end

    test "gebundene Variablen zählen nicht" do
      goal = s(",", [s("=", [@x, s("h", [@y])]), s("term_variables", [s("f", [@x, @z]), @l])])
      assert all(goal) == ["L = [Y, Z], X = h(Y)"]
    end
  end

  describe "subsumes_term/2 (ISO-Beispiele)" do
    test "Beispiele" do
      assert ok?(s("subsumes_term", [a("a"), a("a")]))
      assert all(s("subsumes_term", [s("f", [v("_A"), v("_B")]), s("f", [@z, @z])])) == ["true"]
      assert all(s("subsumes_term", [s("f", [@z, @z]), s("f", [v("_A"), v("_B")])])) == []
      assert all(s("subsumes_term", [s("g", [@x]), s("g", [s("f", [@x])])])) == []
      assert all(s("subsumes_term", [@x, s("f", [@x])])) == []

      assert all(s(",", [s("subsumes_term", [@x, @y]), s("subsumes_term", [@y, s("f", [@x])])])) ==
               ["true"]
    end

    test "bindet nichts" do
      assert all(s(",", [s("subsumes_term", [s("f", [@x]), s("f", [1])]), s("var", [@x])])) ==
               ["true"]
    end
  end

  describe "Eigenschaften der Ordnung" do
    defp gen(depth) do
      case :rand.uniform(if depth <= 0, do: 5, else: 9) do
        1 -> Enum.random([@x, @y])
        2 -> Enum.random([0, 1, 2])
        3 -> Enum.random([1.0, 2.5])
        4 -> Enum.random([a("a"), a("b"), list([])])
        5 -> Enum.random([a("a"), 1])
        6 -> s(Enum.random(["f", "g"]), [gen(depth - 1)])
        7 -> s("f", [gen(depth - 1), gen(depth - 1)])
        8 -> list([gen(depth - 1)], gen(depth - 1))
        9 -> list([gen(depth - 1), gen(depth - 1)])
      end
    end

    defp flip(:lt), do: :gt
    defp flip(:gt), do: :lt
    defp flip(:eq), do: :eq

    test "antisymmetrisch, transitiv, unabhängig von Markierungen" do
      :rand.seed(:exsss, {2, 7, 1})

      for _ <- 1..2000 do
        [a, b, c] = [gen(3), gen(3), gen(3)]
        ab = Order.compare(a, b, %{})
        assert Order.compare(b, a, %{}) == flip(ab)
        assert Order.compare(a, unmark(a), %{}) == :eq
        assert Order.compare(unmark(a), b, %{}) == ab

        if ab != :gt and Order.compare(b, c, %{}) != :gt,
          do: assert(Order.compare(a, c, %{}) != :gt, "nicht transitiv")
      end
    end

    test "== genau dann, wenn identisch (strikt)" do
      :rand.seed(:exsss, {8, 2, 8})

      for _ <- 1..2000 do
        [a, b] = [gen(3), gen(3)]
        assert Order.compare(a, b, %{}) == :eq == (unmark(a) === unmark(b))
      end
    end
  end
end
