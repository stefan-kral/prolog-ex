defmodule PrologEx.FindallFlagsTest do
  use ExUnit.Case, async: true
  import PrologEx
  import ExUnit.CaptureIO

  @x v("X")
  @y v("Y")
  @i v("I")
  @l v("L")
  @a v("A")
  @n v("N")
  @c v("C")

  defp db do
    consult([
      fact(s("p", [1])),
      fact(s("p", [2])),
      fact(s("p", [3])),
      fact(s("q", [s("f", [@x, @x])]))
    ])
  end

  defp all(goal, opts \\ []),
    do: db() |> query(goal, opts) |> Enum.take(20) |> Enum.map(&format_answer/1)

  defp more(goal), do: db() |> solutions(goal) |> Enum.take(20) |> Enum.map(&elem(&1, 1))
  defp error(goal), do: assert_raise(PrologEx.Error, fn -> Enum.take(query(db(), goal), 1) end)
  defp first(goal), do: db() |> query(goal) |> Enum.take(1) |> hd()

  describe "findall/3,4" do
    test "sammelt alle Lösungen" do
      assert all(s("findall", [@x, s("p", [@x]), @l])) == ["L = [1, 2, 3]"]
      assert all(s("findall", [@x, a("fail"), @l])) == ["L = []"]

      assert all(s("findall", [s("-", [@x, @x]), s("p", [@x]), @l])) == [
               "L = [1-1, 2-2, 3-3]"
             ]

      assert more(s("findall", [@x, s("p", [@x]), @l])) == [false]
    end

    test "findall/4 mit Rest" do
      assert all(s("findall", [@x, s("p", [@x]), @l, list([9])])) == ["L = [1, 2, 3, 9]"]
    end

    test "Ergebnisse sind Kopien mit frischen Variablen" do
      ans = first(s("findall", [s("-", [@x, @y]), s("p", [@x]), @l]))
      [{:struct, "-", [1, v1]}, {:struct, "-", [2, v2]}, _] = ans["L"]
      assert match?({:var, _}, v1) and v1 != v2 and v1 != @y
      # Sharing innerhalb eines Ergebnisses bleibt erhalten
      ans = first(s("findall", [@a, s("q", [@a]), @l]))
      [{:struct, "f", [u, w]}] = ans["L"]
      assert u == w
    end

    test "Cut im Ziel ist lokal, Bindungen bleiben draußen" do
      assert all(s("findall", [@x, s(",", [s("p", [@x]), a("!")]), @l])) == ["L = [1]"]

      assert all(s(",", [s("findall", [@x, s("p", [@x]), @l]), s("var", [@x])])) == [
               "L = [1, 2, 3]"
             ]
    end

    test "verschachtelt und mit Kompaktierung bei jedem Schritt" do
      inner = s("findall", [@y, s("p", [@y]), @l])
      goal = s("findall", [s("-", [@x, @l]), s(",", [s("p", [@x]), inner]), @a])

      for opts <- [[], [compact_threshold: 1]] do
        assert all(goal, opts) ==
                 ["A = [1-[1, 2, 3], 2-[1, 2, 3], 3-[1, 2, 3]]"]
      end
    end

    test "Fehler im Ziel kommen durch" do
      error(s("findall", [@x, s("gibtsnicht", [@x]), @l]))
    end
  end

  describe "findnsols/4,5" do
    test "SWI-Beispiele" do
      assert all(s("findnsols", [5, @i, s("between", [1, 12, @i]), @l])) ==
               ["L = [1, 2, 3, 4, 5]", "L = [6, 7, 8, 9, 10]", "L = [11, 12]"]

      assert all(s("findnsols", [4, @i, s("between", [1, 8, @i]), @l])) ==
               ["L = [1, 2, 3, 4]", "L = [5, 6, 7, 8]", "L = []"]
    end

    test "letzter, kürzerer Teil deterministisch" do
      assert more(s("findnsols", [5, @i, s("between", [1, 12, @i]), @l])) == [true, true, false]
      assert more(s("findnsols", [5, @i, s("between", [1, 3, @i]), @l])) == [false]
    end

    test "unendliches Ziel: nur so viel wie nötig" do
      ans = first(s("findnsols", [3, @i, s("between", [1, a("inf"), @i]), @l]))
      assert ans["L"] == [1, 2, 3]
    end

    test "findnsols/5 und Fehler" do
      assert all(s("findnsols", [2, @x, s("p", [@x]), @l, list([0])]), []) |> hd() ==
               "L = [1, 2, 0]"

      error(s("findnsols", [0, @x, s("p", [@x]), @l]))
      error(s("findnsols", [@n, @x, s("p", [@x]), @l]))
    end
  end

  describe "arg/3" do
    test "Modi" do
      assert all(s("arg", [2, s("f", [a("a"), a("b")]), @a])) == ["A = b"]
      assert all(s("arg", [3, s("f", [a("a"), a("b")]), @a])) == []
      assert all(s("arg", [0, s("f", [a("a")]), @a])) == []
      # ISO 8.5.2.3: offenes N ist ein Fehler (kein Aufzählen wie in SWI)
      error(s("arg", [@n, s("f", [a("a"), a("b")]), @a]))
      assert all(s("arg", [1, list([a("x")], a("y")), @a])) == ["A = x"]
      assert all(s("arg", [2, list([a("x")], a("y")), @a])) == ["A = y"]
      # Argument eines ground Terms ist wieder markiert (geteilt)
      assert all(s("arg", [1, s("f", [list([1, 2])]), list([1, 2])])) == ["true"]
    end

    test "Fehler" do
      error(s("arg", [1, a("foo"), @a]))
      error(s("arg", [1, @x, @a]))
      error(s("arg", [a("a"), s("f", [1]), @a]))
      error(s("arg", [-1, s("f", [1]), @a]))
    end
  end

  describe "copy_term/2" do
    test "frische Variablen, Sharing bleibt" do
      ans = first(s("copy_term", [s("f", [@x, @y, @x, s("g", [1])]), @c]))
      {:struct, "f", [v1, v2, v3, g]} = ans["C"]
      assert v1 == v3 and v1 != v2 and v1 != @x
      assert g == {:struct, "g", [1]}
    end

    test "gebundene Variablen werden eingesetzt, ground Teile geteilt" do
      goal = s(",", [s("=", [@x, list([1, 2])]), s("copy_term", [s("h", [@x, @y]), @c])])
      ans = first(goal)
      {:struct, "h", [l, _]} = ans["C"]
      assert l == [1, 2]
      # intern: die markierte Liste wird nicht kopiert
      assert copy_fresh(list([1, 2]), %{}) === list([1, 2])
    end
  end

  describe "Prolog-Flags" do
    test "current_prolog_flag/2" do
      assert all(s("current_prolog_flag", [a("bounded"), @x])) == ["X = false"]
      assert all(s("current_prolog_flag", [a("double_quotes"), @x])) == ["X = chars"]
      assert length(all(s("current_prolog_flag", [@n, @x]))) >= 8
      error(s("current_prolog_flag", [a("gibtsnicht"), @x]))
    end

    test "set_prolog_flag/2: setzen, lesen, Fehler" do
      goal =
        s(",", [
          s("set_prolog_flag", [a("unknown"), a("fail")]),
          s("current_prolog_flag", [a("unknown"), @x])
        ])

      assert all(goal) == ["X = fail"]
      error(s("set_prolog_flag", [a("bounded"), a("true")]))
      error(s("set_prolog_flag", [a("unknown"), a("vielleicht")]))
      error(s("set_prolog_flag", [a("gibtsnicht"), 1]))
      error(s("set_prolog_flag", [@x, 1]))
    end

    test "Flags überstehen Backtracking" do
      goal =
        s(",", [
          s(";", [s(",", [s("set_prolog_flag", [a("debug"), a("on")]), a("fail")]), a("true")]),
          s("current_prolog_flag", [a("debug"), @x])
        ])

      assert all(goal) == ["X = on"]
    end

    # ISO 7.11.2
    test "debug und char_conversion mit on/off, max_arity unbounded (nur lesbar)" do
      assert all(s("current_prolog_flag", [a("debug"), @x])) == ["X = off"]
      assert all(s("current_prolog_flag", [a("char_conversion"), @x])) == ["X = off"]
      assert all(s("current_prolog_flag", [a("max_arity"), @x])) == ["X = unbounded"]
      error(s("set_prolog_flag", [a("max_arity"), 40]))
      error(s("set_prolog_flag", [a("debug"), a("trace")]))
      error(s("set_prolog_flag", [a("debug"), a("true")]))
    end

    test "unknown: error, fail, warning" do
      error(s("gibtsnicht", [1]))

      assert all(s(",", [s("set_prolog_flag", [a("unknown"), a("fail")]), s("gibtsnicht", [1])])) ==
               []

      err =
        capture_io(:stderr, fn ->
          goal =
            s(",", [s("set_prolog_flag", [a("unknown"), a("warning")]), s("gibtsnicht", [1])])

          assert all(goal) == []
        end)

      assert err =~ "gibtsnicht/1"
    end
  end
end
