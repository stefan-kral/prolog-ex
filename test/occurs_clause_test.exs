defmodule PrologEx.OccursClauseTest do
  use ExUnit.Case, async: true
  import PrologEx.TestLibs
  import PrologEx

  @x v("X")
  @y v("Y")
  @z v("Z")
  @b v("B")
  @h v("H")
  @n v("N")
  @a v("A")
  @p v("P")

  defp db do
    [h, t, l, r] = Enum.map(~w(H T L R), &v/1)

    consult([
      fact(s("app", [[], l, l])),
      rule(s("app", [[h | t], l, [h | r]]), [s("app", [t, l, r])]),
      fact(s("f", [1])),
      fact(s("f", [2])),
      fact(s("pair", [@x, s("g", [@x])]))
    ])
    |> PrologEx.declare({"leer", 2})
  end

  defp all(goal, opts \\ []),
    do: db() |> query(goal, opts) |> Enum.take(20) |> Enum.map(&format_answer/1)

  defp error(goal, db \\ db()),
    do: assert_raise(PrologEx.Error, fn -> Enum.take(query(db, goal), 1) end)

  defp oc(mode, goal), do: s(",", [s("set_prolog_flag", [a("occurs_check"), a(mode)]), goal])

  # Gelingt das Ziel? Ohne Aufbereiten der Antwort – entstünde (fälschlich)
  # ein zyklischer Term, endet der Test trotzdem.
  defp ok?(db \\ nil, goal), do: first_with_stats(db || db(), goal) != false

  describe "unify_with_occurs_check/2" do
    test "verhindert zyklische Terme, bindet sonst normal" do
      refute ok?(s("unify_with_occurs_check", [@x, s("f", [@x])]))
      refute ok?(s("unify_with_occurs_check", [@x, list([a("a")], @x)]))

      assert all(s("unify_with_occurs_check", [s("f", [@x, @y]), s("f", [@y, s("g", [1])])])) ==
               ["X = g(1), Y = g(1)"]

      assert all(s("unify_with_occurs_check", [@x, @x])) == ["true"]
    end

    test "unabhängig vom Flag" do
      goal = oc("error", s("unify_with_occurs_check", [@x, s("f", [@x])]))
      refute ok?(goal)
    end
  end

  describe "Flag occurs_check" do
    test "true: Unifikation scheitert statt Zyklus" do
      refute ok?(oc("true", s("=", [@x, s("f", [@x])])))
      refute ok?(oc("true", s("=", [s("f", [@x, @y]), s("f", [@y, s("h", [@x])])])))
      # Zyklus über den Listenrest
      refute ok?(oc("true", s("=", [@x, list([a("a")], @x)])))
      refute ok?(oc("true", s("=", [@x, list([a("a"), a("b")], s("f", [@x]))])))
      assert all(oc("true", s("=", [@x, s("f", [@y])]))) == ["X = f(Y)"]
    end

    test "true: auch im Klauselkopf (Write-Modus und zweites Vorkommen)" do
      # pair(X, g(X)) gegen pair(Y, Y): Y = g(Y) im Write-Modus
      refute ok?(oc("true", s("pair", [@y, @y])))
      # app([X], [], [f(X)]): X = f(X) über zweites Vorkommen von H
      refute ok?(oc("true", s("app", [list([@x]), list([]), list([s("f", [@x])])])))
      # Write-Modus mit Slot im Listenrest: tl([a|L], [b|L]) gegen tl(Y, [b|Y])
      l = v("L")
      db = consult([fact(s("tl", [list([a("a")], l), list([a("b")], l)]))])
      refute ok?(db, oc("true", s("tl", [@y, list([a("b")], @y)])))
      # Write-Modus: wr(X, f(X)) – zweites Argument wird gebaut, enthält Slot
      db = consult([fact(s("wr", [@x, s("f", [list([1], @x)])]))])
      refute ok?(db, oc("true", s("wr", [@y, @y])))
      assert all(oc("true", s("app", [list([1]), list([2]), @z]))) == ["Z = [1,2]"]
    end

    test "error: wirft occurs_check-Fehler" do
      error(oc("error", s("=", [@x, s("f", [@x])])))
    end

    test "false: wieder ohne Prüfung (Standard)" do
      reset =
        s(",", [
          s("set_prolog_flag", [a("occurs_check"), a("true")]),
          s("set_prolog_flag", [a("occurs_check"), a("false")])
        ])

      # ohne Check entsteht der zyklische Term X = f(X). Die Antwort wird
      # nicht aufbereitet (resolve liefe bei einem Zyklus endlos)
      assert {:ok, _} = first_with_stats(db(), s(",", [reset, s("=", [@x, s("f", [@x])])]))
    end

    test "ground Terme werden nicht durchsucht" do
      big = list(Enum.to_list(1..200_000))
      goal = oc("true", s(",", [s("=", [@x, s("h", [big, @y])]), s("=", [@y, big])]))
      {us, {:ok, _}} = :timer.tc(fn -> first_with_stats(db(), goal) end)
      assert us < 200_000, "#{us} µs"
    end
  end

  describe "Eigenschaft: Occurs-Check = Referenz" do
    defp gen(vars, d) do
      case :rand.uniform(if d <= 0, do: 4, else: 8) do
        1 -> Enum.random(vars)
        2 -> Enum.random(vars)
        3 -> Enum.random([a("a"), 1, list([])])
        4 -> Enum.random([a("b"), 2])
        5 -> s("f", [gen(vars, d - 1)])
        6 -> s("g", [gen(vars, d - 1), gen(vars, d - 1)])
        7 -> list([gen(vars, d - 1)], gen(vars, d - 1))
        8 -> list([gen(vars, d - 1), gen(vars, d - 1)])
      end
    end

    # Referenz: naive Unifikation mit Occurs-Check
    defp rw({:var, _} = x, s), do: if(Map.has_key?(s, x), do: rw(s[x], s), else: x)
    defp rw(t, _), do: t

    defp ru(x, y, s) do
      x = rw(x, s)
      y = rw(y, s)

      cond do
        x == y -> {:ok, s}
        match?({:var, _}, x) -> if rocc(x, y, s), do: :error, else: {:ok, Map.put(s, x, y)}
        match?({:var, _}, y) -> if rocc(y, x, s), do: :error, else: {:ok, Map.put(s, y, x)}
        true -> rargs(rparts(x), rparts(y), s)
      end
    end

    defp rocc(v, t, s) do
      case rw(t, s) do
        ^v -> true
        {:struct, _, args} -> Enum.any?(args, &rocc(v, &1, s))
        [h | tl] -> rocc(v, h, s) or rocc(v, tl, s)
        _ -> false
      end
    end

    defp rparts({:struct, f, a}), do: {f, a}
    defp rparts([h | t]), do: {".", [h, t]}
    defp rparts(t), do: {:atomic, t}

    defp rargs({f, xs}, {f, ys}, s) when length(xs) == length(ys) do
      Enum.zip(xs, ys)
      |> Enum.reduce_while({:ok, s}, fn {x, y}, {:ok, s} ->
        case ru(x, y, s) do
          {:ok, s} -> {:cont, {:ok, s}}
          :error -> {:halt, :error}
        end
      end)
    end

    defp rargs(_, _, _), do: :error

    # Zyklen gezielt herbeiführen: V = T bzw. Kopf p(A, T) gegen p(Y, Y),
    # wobei V/A in T an zufälliger Stelle steckt (auch im Listenrest)
    defp plant(v, d) do
      case :rand.uniform(if d <= 0, do: 1, else: 5) do
        1 -> v
        2 -> s("f", [plant(v, d - 1)])
        3 -> s("g", [gen([@z], 1), plant(v, d - 1)])
        4 -> list([gen([@z], 1)], plant(v, d - 1))
        5 -> list([plant(v, d - 1), gen([@z], 1)])
      end
    end

    test "gezielt erzeugte Zyklen werden erkannt" do
      :rand.seed(:exsss, {1, 4, 1})

      for _ <- 1..1000 do
        t = plant(@x, 4)
        cyclic = t != @x
        assert ok?(oc("true", s("=", [@x, t]))) == not cyclic, "X = #{format(t)}"

        th = plant(v("A"), 4)
        db = consult([fact(s("p", [v("A"), th]))])
        assert ok?(db, oc("true", s("p", [@y, @y]))) == (th == v("A")), "p(A, #{format(th)})"
      end
    end

    test "=/2 und Klauselkopf mit occurs_check = true" do
      :rand.seed(:exsss, {3, 3, 3})
      vars = [@x, @y, @z]

      for _ <- 1..3000 do
        g = gen(vars, 3)
        h = gen([v("A"), v("B")], 3)
        db = consult([fact(s("p", [h]))])
        expected = ru(unmark(g), unmark(h), %{}) != :error

        for goal <- [s("=", [g, h]), s("p", [g])] do
          # first_with_stats bereitet keine Antwort auf – bei einem (falschen)
          # zyklischen Ergebnis endet der Test also trotzdem
          got = first_with_stats(db, oc("true", goal)) != false
          assert got == expected, "#{format(goal)} mit Kopf p(#{format(h)}): erwartet #{expected}"
        end
      end
    end
  end

  describe "clause/2" do
    test "Benutzerprädikate" do
      assert all(s("clause", [s("f", [@x]), @b])) == ["B = true, X = 1", "B = true, X = 2"]
      [a1, a2] = db() |> query(s("clause", [s("app", [@x, @y, @z]), @b])) |> Enum.take(2)
      assert a1["B"] == a("true") and a1["Y"] == a1["Z"]
      assert {:struct, "app", [_, _, _]} = a2["B"]
      assert all(s("clause", [s("leer", [@x, @y]), @b])) == []
      assert all(s("clause", [s("gibtsnicht", [@x]), @b])) == []
    end

    test "frische Variablen je Lösung, Sharing bleibt" do
      [ans] = db() |> query(s("clause", [s("pair", [@x, @y]), @b])) |> Enum.take(1)
      assert ans["Y"] == {:struct, "g", [ans["X"]]}
    end

    test "Bibliotheksprädikate in Prolog: ja; Elixir, Steuerkonstrukte, $-Prädikate: nein" do
      # nur nach use_module(library(lists)) sichtbar
      assert [] = db() |> query(s("clause", [s("numlist", [@n, @a]), @b])) |> Enum.take(1)

      assert [_] =
               db() |> libs() |> query(s("clause", [s("numlist", [@n, @a]), @b])) |> Enum.take(1)

      error(s("clause", [s("append", [@x, @y, @z]), @b]), libs(db()))
      error(s("clause", [s("call", [@x]), @b]))
      error(s("clause", [s(":", [a("lists"), s("$select3", [@x, @y, @z, @a])]), @b]))
    end

    test "Fehler" do
      error(s("clause", [@h, a("true")]))
      error(s("clause", [3, @b]))
      error(s("clause", [s("f", [@x]), 4]))
    end
  end

  describe "current_predicate/1" do
    test "Aufzählen und Prüfen" do
      assert all(s("current_predicate", [@p])) ==
               ["P = app/3", "P = f/1", "P = leer/2", "P = pair/2"]

      assert all(s("current_predicate", [s("/", [a("app"), @a])])) == ["A = 3"]
      assert all(s("current_predicate", [s("/", [@n, 2])])) == ["N = leer", "N = pair"]
      assert all(s("current_predicate", [s("/", [a("append"), 3])])) == []
    end

    test "Fehler" do
      error(s("current_predicate", [a("foo")]))
      error(s("current_predicate", [s("/", [1, 2])]))
      error(s("current_predicate", [s("/", [a("f"), a("x")])]))
    end
  end
end
