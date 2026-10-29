defmodule PrologExTest do
  use ExUnit.Case, async: true
  import PrologEx

  @x v("X")
  @y v("Y")
  @z v("Z")
  @h v("H")
  @t v("T")
  @r v("R")
  @n v("N")
  @m v("M")
  @acc v("A")
  @acc1 v("A1")

  setup_all do
    db =
      consult([
        fact(s("parent", [a("tom"), a("bob")])),
        fact(s("parent", [a("tom"), a("liz")])),
        fact(s("parent", [a("bob"), a("ann")])),
        fact(s("parent", [a("bob"), a("pat")])),
        rule(s("grandparent", [@x, @z]), [s("parent", [@x, @y]), s("parent", [@y, @z])]),
        fact(s("append", [a("[]"), @x, @x])),
        rule(s("append", [list([@h], @t), @y, list([@h], @r)]), [s("append", [@t, @y, @r])]),
        rule(s("max", [@x, @y, @x]), [s(">=", [@x, @y]), a("!")]),
        fact(s("max", [v("_"), @y, @y])),
        fact(s("member", [@x, list([@x], v("_"))])),
        rule(s("member", [@x, list([v("_")], @t)]), [s("member", [@x, @t])]),
        rule(s("not_member", [@x, @y]), [s("\\+", [s("member", [@x, @y])])]),
        fact(s("nat", [0])),
        rule(s("nat", [@n]), [s("nat", [@m]), s("is", [@n, s("+", [@m, 1])])]),
        rule(s("count", [0]), [a("!")]),
        rule(s("count", [@n]), [s("is", [@m, s("-", [@n, 1])]), s("count", [@m])]),
        fact(s("len", [a("[]"), @acc, @acc])),
        rule(s("len", [list([v("_")], @t), @acc, @n]), [
          s("is", [@acc1, s("+", [@acc, 1])]),
          s("len", [@t, @acc1, @n])
        ])
      ])

    {:ok, db: db}
  end

  defp answers(db, goal, limit \\ 100) do
    db |> query(goal) |> Enum.take(limit) |> Enum.map(&format_answer/1)
  end

  test "mark/1 markiert einen ground Term vollständig, unmark/1 entfernt alles" do
    # roh gebaut (mk/2 würde schon beim Bauen markieren)
    t = {:struct, "f", [{:struct, "g", [{:atom, "a"}]}, [1, {:struct, "h", [2]}]]}

    m = PrologEx.mark(t)
    assert {:gstruct, "f", [{:gstruct, "g", _}, {:glist, [1, {:gstruct, "h", [2]}]}]} = m

    assert PrologEx.unmark(m) ==
             {:struct, "f", [{:struct, "g", [{:atom, "a"}]}, [1, {:struct, "h", [2]}]]}
  end

  test "Regel mit Join", %{db: db} do
    assert answers(db, s("grandparent", [a("tom"), @z])) == ["Z = ann", "Z = pat"]
  end

  test "Backtracking über alle Zerlegungen von append", %{db: db} do
    assert answers(db, s("append", [@x, @y, list([1, 2, 3])])) == [
             "X = [], Y = [1,2,3]",
             "X = [1], Y = [2,3]",
             "X = [1,2], Y = [3]",
             "X = [1,2,3], Y = []"
           ]
  end

  test "Cut schneidet die zweite Klausel ab", %{db: db} do
    assert answers(db, s("max", [3, 7, @m])) == ["M = 7"]
    assert answers(db, s("max", [9, 4, @m])) == ["M = 9"]
  end

  test "Negation als Fehlschlag", %{db: db} do
    assert answers(db, s("not_member", [a("d"), list([a("a"), a("b")])])) == ["true"]
    assert answers(db, s("not_member", [a("a"), list([a("a"), a("b")])])) == []
  end

  test "Disjunktion", %{db: db} do
    assert answers(db, s(";", [s("=", [@x, 1]), s("=", [@x, 2])])) == ["X = 1", "X = 2"]
  end

  test "Lösungen sind lazy", %{db: db} do
    assert answers(db, s("nat", [@n]), 5) == Enum.map(0..4, &"N = #{&1}")
  end

  test "Endrekursion mit Akkumulator", %{db: db} do
    assert answers(db, s("len", [list(Enum.to_list(1..10_000)), 0, @n]), 1) == ["N = 10000"]
  end

  describe "Listen als native Cons-Zellen" do
    test "kanonische Form: '.'/2 ist immer Cons, '[]' immer []" do
      assert a("[]") == []
      assert s(".", [@x, a("[]")]) == [@x]
      assert s(".", [@x, 2]) == [@x | 2]
      assert list([1, 2], @t) == [1, 2 | @t]
      assert s("foo", []) == a("foo")
    end

    test "variablenfreie Terme werden beim Bauen markiert" do
      assert s(".", [1, a("[]")]) == {:glist, [1]}
      assert s(".", [1, 2]) == {:glist, [1 | 2]}
      assert list([1, 2, 3]) == {:glist, [1, 2, 3]}
      assert s("f", [1, a("b")]) == {:gstruct, "f", [1, {:atom, "b"}]}
      assert s("f", [@x]) == {:struct, "f", [@x]}
      # ground Kopf vor markierter Liste: O(1), bleibt markiert
      assert cons(0, list([1, 2])) == {:glist, [0, 1, 2]}
      # nicht-ground Kopf vor markierter Liste: rohe Zelle, Rest bleibt markiert
      assert cons(@x, list([1, 2])) == [@x | {:glist, [1, 2]}]
      assert unmark(cons(@x, list([1, 2]))) == [@x, 1, 2]
      assert uncons(list([1, 2])) == {:cons, 1, {:glist, [2]}}
      assert uncons(list([1])) == {:cons, 1, []}
    end

    test "uncons/cons" do
      assert uncons([1, 2]) == {:cons, 1, [2]}
      assert uncons([]) == :empty
      assert uncons(a("x")) == :other
      assert cons(1, [2]) == [1, 2]
    end

    test "Liste mit offenem Rest wird gebunden", %{db: db} do
      goal = s("=", [list([1, 2], @t), list([1, 2, 3, 4])])
      assert answers(db, goal) == ["T = [3,4]"]
    end

    test "unvollständige Liste wird mit | ausgegeben", %{db: db} do
      assert answers(db, s("=", [@x, list([1, 2], @t)])) == ["X = [1,2|T]"]
      assert answers(db, s("=", [@x, s(".", [1, 2])])) == ["X = [1|2]"]
    end

    test "Liste und '.'-Struktur sind derselbe Term", %{db: db} do
      goal = s("=", [s(".", [@h, @t]), list([a("a"), a("b")])])
      assert answers(db, goal) == ["H = a, T = \"b\""]
    end

    test "Liste unifiziert nicht mit anderer Struktur oder Atom", %{db: db} do
      assert answers(db, s("=", [list([1]), s("f", [1, a("[]")])])) == []
      assert answers(db, s("=", [list([]), a("nil")])) == []
    end

    test "Unifikation sehr langer Listen ohne Rekursionstiefe", %{db: db} do
      n = 200_000
      xs = Enum.to_list(1..n)
      open = Enum.map(1..n, fn i -> v("V#{i}") end) |> list(@t)
      goal = s(",", [s("=", [open, list(xs ++ [0])]), s("len", [@t, 0, @n])])
      [ans] = db |> query(goal) |> Enum.take(1)
      assert ans["T"] == [0]
      assert ans["N"] == 1
    end
  end

  test "frische Rumpfvariablen sind bei jedem Aufruf verschieden" do
    db =
      consult([
        rule(s("mk", [0, list([])]), [a("!")]),
        rule(s("mk", [@n, list([@x], @t)]), [s("is", [@m, s("-", [@n, 1])]), s("mk", [@m, @t])]),
        rule(s("fresh", [list([])]), []),
        rule(s("fresh", [list([@x], @t)]), [s("=", [@y, @x]), s("fresh", [@t])])
      ])

    goal = s(",", [s("mk", [3, @x]), s("=", [@x, list([a("a"), a("b"), a("c")])])])
    assert answers(db, goal) == ["X = \"abc\""]

    goal = s(",", [s("fresh", [list([@x, @y])]), s("=", [list([@x, @y]), list([1, 2])])])
    assert answers(db, goal) == ["X = 1, Y = 2"]
  end

  test "deterministische Schleife hinterlässt keine Choice Points und wenig Bindungen",
       %{db: db} do
    assert {:ok, %{choicepoints: 0, bindings: b}} = first_with_stats(db, s("count", [100_000]))
    assert b < 10_000
  end
end
