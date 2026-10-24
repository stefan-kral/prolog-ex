defmodule PrologEx.Builtins.Statistics do
  @moduledoc """
  `statistics(?Key, ?Wert)` wie SICStus, für Zeitmessungen:

    * `runtime`, `total_runtime`, `process_cputime`: `[T, D]` – CPU-Zeit
      in Millisekunden seit Start der VM und seit dem letzten Aufruf mit
      demselben Schlüssel. Es ist die CPU-Zeit der ganzen Erlang-VM (alle
      Scheduler); solange nur die Prolog-Sitzung rechnet, ist das ihre.
    * `walltime`: `[T, D]` – vergangene Zeit in Millisekunden seit Start
      der VM bzw. seit dem letzten Aufruf.
    * `real_time`: `[S, D]` – Sekunden seit 1970 bzw. seit dem letzten
      Aufruf.

  "Seit dem letzten Aufruf" zählt je Schlüssel und Sitzung (Prozess), wie
  SICStus; der erste Aufruf misst ab Start. Unbekannter Schlüssel:
  domain_error(statistics_key, Key).

      ?- statistics(runtime, [T0|_]), ..., statistics(runtime, [T1|_]),
         T is T1 - T0.
  """
  use PrologEx.Builtin
  alias PrologEx.Error

  @keys ~w(runtime total_runtime process_cputime walltime real_time)

  defbuiltin "statistics", [key, value] do
    case deref(key) do
      {:var, _} ->
        Error.instantiation!()

      {:atom, k} when k in @keys ->
        now = current(k)
        last = Process.get({:prolog_ex_stat, k}, start(k, now))
        Process.put({:prolog_ex_stat, k}, now)
        {:unify, [{value, list([now, now - last])}]}

      {:atom, _} = k ->
        Error.domain!("statistics_key", k)

      other ->
        Error.type!("atom", resolve(other))
    end
  end

  defp current(k) when k in ~w(runtime total_runtime process_cputime),
    do: elem(:erlang.statistics(:runtime), 0)

  defp current("walltime"), do: elem(:erlang.statistics(:wall_clock), 0)
  defp current("real_time"), do: System.os_time(:second)

  # Bezugspunkt für den ersten Aufruf
  defp start("real_time", now), do: now
  defp start(_, _now), do: 0
end
