# Speicher- und Laufzeitmessung
# Ausführen:  mix run bench/bench.exs

defmodule Bench do
  import PrologEx

  def main do
    [h, t, r, l, rt, n, m, acc, acc1] = Enum.map(~w(H T R L RT N M A A1), &v/1)

    db =
      consult([
        # Endrekursive Schleife ohne Datenstrukturen
        rule(s("count", [0]), [a("!")]),
        rule(s("count", [n]), [s("is", [m, s("-", [n, 1])]), s("count", [m])]),

        # Endrekursion über eine große Liste
        fact(s("len", [list([]), acc, acc])),
        rule(s("len", [list([v("_")], t), acc, n]), [
          s("is", [acc1, s("+", [acc, 1])]),
          s("len", [t, acc1, n])
        ]),

        # Liste in Prolog aufbauen: numlist(N, L) mit L = [N, ..., 1]
        rule(s("numlist", [0, list([])]), [a("!")]),
        rule(s("numlist", [n, list([n], t)]), [
          s("is", [m, s("-", [n, 1])]),
          s("numlist", [m, t])
        ]),

        # Klassischer nrev-Benchmark: nrev einer 30er-Liste = 496 logische Inferenzen
        fact(s("app", [list([]), l, l])),
        rule(s("app", [list([h], t), l, list([h], r)]), [s("app", [t, l, r])]),
        fact(s("nrev", [list([]), list([])])),
        rule(s("nrev", [list([h], t), r]), [
          s("nrev", [t, rt]),
          s("app", [rt, list([h]), r])
        ]),
        rule(s("bench", [0]), [a("!")]),
        rule(s("bench", [n]), [
          s("nrev", [list(Enum.to_list(1..30)), v("_")]),
          s("is", [m, s("-", [n, 1])]),
          s("bench", [m])
        ])
      ])

    IO.puts("Speicher (Spitze während des Laufs) und Zeit:")

    for k <- [100_000, 1_000_000] do
      measure("count(#{k})", fn -> first_with_stats(db, s("count", [k])) end)
    end

    measure("len(<1 Mio. Elemente>)", fn ->
      first_with_stats(db, s("len", [list(Enum.to_list(1..1_000_000)), 0, n]))
    end)

    measure("numlist + len (1 Mio.)", fn ->
      first_with_stats(
        db,
        s(",", [s("numlist", [1_000_000, l]), s("len", [l, 0, n])])
      )
    end)

    iters = 10_000
    us = measure("nrev30 × #{iters}", fn -> first_with_stats(db, s("bench", [iters])) end)
    lips = (496 + 3) * iters / (us / 1_000_000)
    IO.puts("   -> #{Float.round(lips / 1_000_000, 2)} Mio. LIPS")
  end

  # Spitzen-Speicher des ausführenden Prozesses, von außen alle 5 ms abgefragt
  defp measure(label, fun) do
    parent = self()

    pid =
      spawn(fn ->
        {us, res} = :timer.tc(fun)
        send(parent, {:done, self(), res, us})
      end)

    {res, us, peak} = poll(pid, 0)
    {:ok, stats} = res

    IO.puts(
      "   #{String.pad_trailing(label, 24)} Spitze #{String.pad_leading(Float.to_string(Float.round(peak / 1_048_576, 1)), 6)} MB, " <>
        "#{String.pad_leading(Integer.to_string(div(us, 1000)), 6)} ms  " <>
        "(am Ende #{stats.bindings} Bindungen, #{stats.choicepoints} Choice Points)"
    )

    us
  end

  defp poll(pid, peak) do
    receive do
      {:done, ^pid, res, us} -> {res, us, peak}
    after
      5 ->
        peak =
          case Process.info(pid, :memory) do
            {:memory, m} -> max(m, peak)
            nil -> peak
          end

        poll(pid, peak)
    end
  end
end

Bench.main()
