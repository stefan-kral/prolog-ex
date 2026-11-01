defmodule PrologEx.Builtins.ScryerPrims do
  @moduledoc """
  Hilfsprädikate der Scryer-Maschine, die `library(time)` (aus Scryer,
  priv/library/time.pl) braucht: `'$cpu_now'/1`, `'$inference_count'/1`,
  `'$current_time'/1`, `'$ceil_scaled'/3`.
  """
  use PrologEx.Builtin

  # CPU-Zeit der VM in Sekunden (Gleitkommazahl, wie Scryer)
  defbuiltin "$cpu_now", [t] do
    {:unify, [{t, elem(:erlang.statistics(:runtime), 0) / 1000}]}
  end

  defbuiltin "$inference_count", [n] do
    {:unify, [{n, PrologEx.inferences()}]}
  end

  # Zeitstempel jetzt, in Ortszeit (wie die Zeiten in library(files))
  defbuiltin "$current_time", [t] do
    {:unify, [{t, PrologEx.Builtins.Files.timestamp(System.os_time(:second))}]}
  end

  # '$ceil_scaled'(X, Scale, N): N = ceiling(X * Scale), X eine nicht
  # negative Zahl. Floats gelten als die Dezimalzahl, die sie zeigen
  # (kürzeste Darstellung): 1.1 * 1000 ist 1100, nicht 1101 (binär ist 1.1
  # etwas größer). Für sleep/1, sleep_ms/1 und die Zeitgrenzen.
  defbuiltin "$ceil_scaled", [x, scale, n] do
    {:unify, [{n, ceil_scaled(deref(x), deref(scale))}]}
  end

  @doc false
  def ceil_scaled(x, scale) when is_integer(x), do: x * scale

  def ceil_scaled(x, scale) when is_float(x) do
    {int, frac, exp} =
      case Regex.run(~r/^(\d+)\.(\d+)(?:e(-?\d+))?$/, Float.to_string(x)) do
        [_, int, frac] -> {int, frac, ""}
        [_, int, frac, exp] -> {int, frac, exp}
      end

    # x = int.frac * 10^exp = digits / 10^(len(frac) - exp)
    digits = String.to_integer(int <> frac)
    shift = String.length(frac) - if(exp == "", do: 0, else: String.to_integer(exp))

    if shift <= 0,
      do: digits * 10 ** -shift * scale,
      else: div(digits * scale + 10 ** shift - 1, 10 ** shift)
  end
end
