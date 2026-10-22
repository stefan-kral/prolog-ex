# Speicher- und Laufzeitmessung
# Ausführen:  mix run bench/bench.exs

defmodule Bench do
  import PrologEx

  def main do
    [x, y, z, h, t, r, n, m, acc, acc1] =
      Enum.map(~w(X Y Z H T R N M A A1), &v/1)

    _ = {x, y, z, h, r}

    db =
      consult([
        # Familie
        fact(s("parent", [a("tom"), a("bob")])),
        fact(s("parent", [a("tom"), a("liz")])),
        fact(s("parent", [a("bob"), a("ann")])),
        fact(s("parent", [a("bob"), a("pat")])),
        rule(s("grandparent", [x, z]), [s("parent", [x, y]), s("parent", [y, z])]),

        # append/3
        fact(s("append", [a("[]"), x, x])),
        rule(s("append", [list([h], t), y, list([h], r)]), [s("append", [t, y, r])]),

        # max/3 mit Cut
        rule(s("max", [x, y, x]), [s(">=", [x, y]), a("!")]),
        fact(s("max", [v("_"), y, y])),

        # member/2 und Negation
        fact(s("member", [x, list([x], v("_"))])),
        rule(s("member", [x, list([v("_")], t)]), [s("member", [x, t])]),
        rule(s("not_member", [x, y]), [s("\\+", [s("member", [x, y])])]),

        # Unendlicher Generator
        fact(s("nat", [0])),
        rule(s("nat", [n]), [s("nat", [m]), s("is", [n, s("+", [m, 1])])]),

        # Endrekursive Schleifen für den Speichertest
        rule(s("count", [0]), [a("!")]),
        rule(s("count", [n]), [s("is", [m, s("-", [n, 1])]), s("count", [m])]),

        fact(s("len", [a("[]"), acc, acc])),
        rule(s("len", [list([v("_")], t), acc, n]), [
          s("is", [acc1, s("+", [acc, 1])]),
          s("len", [t, acc1, n])
        ])
      ])

    IO.puts("Speichertest:")

    for k <- [100_000, 1_000_000, 10_000_000] do
      measure("count(#{k})", fn -> first_with_stats(db, s("count", [k])) end)
    end

    measure("len(<Liste mit 1 Mio.>, 0, N)", fn ->
      first_with_stats(db, s("len", [list(Enum.to_list(1..1_000_000)), 0, n]))
    end)
  end

  # Spitzen-Speicher des ausführenden Prozesses, von außen alle 20 ms abgefragt
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
      "   #{String.pad_trailing(label, 28)} Spitze #{Float.round(peak / 1_048_576, 1)} MB, " <>
        "am Ende #{stats.bindings} Bindungen / #{stats.choicepoints} Choice Points, " <>
        "#{div(us, 1000)} ms"
    )
  end

  defp poll(pid, peak) do
    receive do
      {:done, ^pid, res, us} -> {res, us, peak}
    after
      20 ->
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
