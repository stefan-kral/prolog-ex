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

  test "Regel mit Join", %{db: db} do
    assert answers(db, s("grandparent", [a("tom"), @z])) == ["Z = ann", "Z = pat"]
  end

  test "Backtracking über alle Zerlegungen von append", %{db: db} do
    assert answers(db, s("append", [@x, @y, list([1, 2, 3])])) == [
             "X = [], Y = [1, 2, 3]",
             "X = [1], Y = [2, 3]",
             "X = [1, 2], Y = [3]",
             "X = [1, 2, 3], Y = []"
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

  test "deterministische Schleife hinterlässt keine Choice Points und wenig Bindungen",
       %{db: db} do
    assert {:ok, %{choicepoints: 0, bindings: b}} = first_with_stats(db, s("count", [100_000]))
    assert b < 10_000
  end
end
