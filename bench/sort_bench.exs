# Messung sort/2, msort/2, keysort/2
# Ausführen:  mix run bench/sort_bench.exs
import PrologEx

defmodule SortBench do
  import PrologEx

  # Nur das Builtin: first_with_stats löst die Antwort nicht auf
  def time(db, goal) do
    for _ <- 1..3 do
      {us, {:ok, _}} = :timer.tc(fn -> first_with_stats(db, goal) end)
      us
    end
    |> Enum.min()
  end

  def run(cases) do
    :rand.seed(:exsss, {1, 2, 3})
    db = consult([])

    for {label, pred, build} <- cases do
      {list_term, extra_goal} = build.()
      goal = s(",", [extra_goal, s(pred, [list_term, v("S")])])
      ms = time(db, goal) / 1000

      IO.puts(
        "  #{String.pad_trailing(label, 44)} #{:erlang.float_to_binary(ms, decimals: 1) |> String.pad_leading(8)} ms"
      )
    end
  end
end

n = 200_000
shuffled = fn items -> {list(Enum.shuffle(items)), a("true")} end

SortBench.run([
  {"sort: #{n} Zahlen, gemischt", "sort", fn -> shuffled.(Enum.to_list(1..n)) end},
  {"sort: #{n} Zahlen, vorsortiert", "sort", fn -> {list(Enum.to_list(1..n)), a("true")} end},
  {"sort: #{n} Zahlen, viele Duplikate", "sort", fn -> shuffled.(for i <- 1..n, do: rem(i, 1000)) end},
  {"sort: 50.000 Atome, gemischt", "sort", fn -> shuffled.(for i <- 1..50_000, do: a("atom#{i}")) end},
  {"sort: 50.000 Terme f(N, a), gemischt", "sort",
   fn -> shuffled.(for i <- 1..50_000, do: s("f", [i, a("a")])) end},
  {"sort: 50.000 Listen [N, N], gemischt", "sort", fn -> shuffled.(for i <- 1..50_000, do: list([i, i])) end},
  {"sort: 50.000 Variablen", "sort", fn -> {list(for i <- 1..50_000, do: v("V#{i}")), a("true")} end},
  {"sort: 20.000 gebundene Variablen", "sort",
   fn ->
     vars = for i <- 1..20_000, do: v("V#{i}")
     binds = Enum.zip(vars, Enum.shuffle(1..20_000)) |> Enum.map(fn {x, k} -> s("=", [x, k]) end)
     {list(vars), conj(binds)}
   end},
  {"msort: #{n} Zahlen, gemischt", "msort", fn -> shuffled.(Enum.to_list(1..n)) end},
  {"keysort: 100.000 Paare K-V, gemischt", "keysort",
   fn -> shuffled.(for i <- 1..100_000, do: s("-", [rem(i, 5000), i])) end}
])
