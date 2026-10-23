defmodule PrologEx.DbIndexTest do
  # Der beim assert ERWEITERTE Index muss exakt dem neu gebauten entsprechen
  use ExUnit.Case, async: true
  import PrologEx

  @runs 500

  defp gen_entry do
    first =
      case :rand.uniform(6) do
        1 -> v("X")
        2 -> a(Enum.random(["a", "b"]))
        3 -> s("f", [v("Y")])
        4 -> [1]
        _ -> :rand.uniform(3)
      end

    entry({s("p", [first, :rand.uniform(100)]), a("true")})
  end

  test "materialize nach asserta/assertz == Neubau aus den Einträgen" do
    :rand.seed(:exsss, {7, 8, 9})

    for _ <- 1..@runs do
      start = for _ <- 1..(:rand.uniform(6) - 1), do: gen_entry()

      Enum.reduce(1..:rand.uniform(25), pred_from_entries(start), fn _, pred ->
        pred =
          case :rand.uniform(4) do
            1 -> assert_entry(pred, gen_entry(), :a)
            4 -> materialize(pred)
            _ -> assert_entry(pred, gen_entry(), :z)
          end

        m = materialize(pred)
        assert m == pred_from_entries(pred_entries(pred))
        # zufällig mit oder ohne Materialisieren weiter
        if :rand.uniform(2) == 1, do: m, else: pred
      end)
    end
  end

  test "Erweitern erhält die Reihenfolge je Schlüssel" do
    p = pred_from_entries(for i <- 1..10, do: entry({s("p", [1, i]), a("true")}))

    p =
      p
      |> assert_entry(entry({s("p", [1, 11]), a("true")}), :z)
      |> assert_entry(entry({s("p", [1, 12]), a("true")}), :z)
      |> assert_entry(entry({s("p", [v("X"), 0]), a("true")}), :a)

    m = materialize(p)
    seconds = fn cls -> Enum.map(cls, fn c -> elem(c, 1) end) end
    {:pred, _, by_key, _, _} = m
    assert length(by_key[1]) == 13
    assert m == pred_from_entries(pred_entries(p))
    assert seconds.(elem(m, 1)) |> hd() == :any
  end
end
