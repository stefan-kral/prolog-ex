defmodule PrologEx.Builtins.ScryerPrims do
  @moduledoc """
  Hilfsprädikate der Scryer-Maschine, die `library(time)` (aus Scryer,
  priv/library/time.pl) braucht: `'$cpu_now'/1`, `'$inference_count'/1`,
  `'$current_time'/1`, `'$sleep'/1`.
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

  # schlafen; T ist eine Zahl ≥ 0 (geprüft in time.pl)
  defbuiltin "$sleep", [t] do
    Process.sleep(round(deref(t) * 1000))
    :ok
  end
end
