defmodule PrologEx.Builtins.Statistics do
  @moduledoc """
  `statistics(?Key, ?Wert)` und `statistics/0`.

  Zeit, wie SICStus – `[T, D]`: Stand und Abstand zum letzten Aufruf mit
  demselben Schlüssel (je Sitzung; der erste Aufruf misst ab Start):

    * `runtime`, `total_runtime`, `process_cputime`: CPU-Zeit in ms. Es ist
      die CPU-Zeit der ganzen Erlang-VM (alle Scheduler); solange nur die
      Prolog-Sitzung rechnet, ist das ihre.
    * `walltime`: vergangene Zeit in ms seit Start der VM.
    * `real_time`: Sekunden seit 1970.

  Rechenarbeit:

    * `inferences`: Anzahl der Prädikataufrufe der Sitzung (eine Zahl, wie
      SWI) – auch eingebaute wie `=/2`, `is/2`; nicht Steuerkonstrukte
      (`,` `;` `->` `!`) und `call/N` selbst.
    * `reductions`: `[R, D]` – Reduktionen des Sitzungsprozesses, das
      prozessgenaue Arbeitsmaß der BEAM.

  Speicher (Bytes):

    * `memory`: `[Belegt, 0]` wie SICStus – der Sitzungsprozess (Heap,
      Stack: bei uns vor allem Substitution, Ziele, Choice Points); große
      Binaries (auch Atomnamen) liegen außerhalb und zählen nicht.
    * `process_memory`: dieselbe Zahl, ohne Liste.
    * `vm_memory`: die ganze VM (`:erlang.memory(:total)`).
    * `garbage_collection`: `[Anzahl, Bytes freigegeben, 0]` wie SICStus,
      für die ganze VM seit Start; die GC-Zeit misst die BEAM nicht.

  System:

    * `schedulers`: Anzahl der aktiven Scheduler (≈ CPU-Kerne).
    * `process_count`: Anzahl der Erlang-Prozesse.

  `statistics/0` gibt eine Übersicht davon aus, ohne die Abstände von
  `statistics/2` zurückzusetzen.

  Unbekannter Schlüssel: domain_error(statistics_key, Key).
  """
  use PrologEx.Builtin
  alias PrologEx.Error

  # [T, D] mit Bezug auf den letzten Aufruf
  @deltas ~w(runtime total_runtime process_cputime walltime real_time reductions)
  @keys @deltas ++
          ~w(inferences memory process_memory vm_memory garbage_collection schedulers process_count)

  defbuiltin "statistics", [key, value] do
    case deref(key) do
      {:var, _} ->
        Error.instantiation!()

      {:atom, k} when k in @deltas ->
        now = current(k)
        last = Process.get({:prolog_ex_stat, k}, start(k, now))
        Process.put({:prolog_ex_stat, k}, now)
        {:unify, [{value, list([now, now - last])}]}

      {:atom, k} when k in @keys ->
        {:unify, [{value, other(k)}]}

      {:atom, _} = k ->
        Error.domain!("statistics_key", k)

      other ->
        Error.type!("atom", resolve(other))
    end
  end

  defbuiltin "statistics", [] do
    IO.write(summary())
    :ok
  end

  @doc "Text von statistics/0"
  def summary do
    {gcs, words, _} = :erlang.statistics(:garbage_collection)

    rows = [
      {"CPU-Zeit (VM)", "#{secs(current("runtime"))} s"},
      {"Laufzeit (Uhr)", "#{secs(current("walltime"))} s seit Start der VM"},
      {"Inferenzen", group(PrologEx.inferences())},
      {"Reduktionen", "#{group(current("reductions"))} (Sitzungsprozess)"},
      {"Speicher Sitzung", bytes(process_memory())},
      {"Speicher VM", bytes(:erlang.memory(:total))},
      {"GC (VM)",
       "#{group(gcs)} Läufe, #{bytes(words * :erlang.system_info(:wordsize))} freigegeben"},
      {"Scheduler",
       "#{:erlang.system_info(:schedulers_online)}, " <>
         "#{:erlang.system_info(:process_count)} Prozesse"},
      {"System", "Erlang/OTP #{:erlang.system_info(:otp_release)}, Elixir #{System.version()}"}
    ]

    width = rows |> Enum.map(&String.length(elem(&1, 0))) |> Enum.max()

    Enum.map_join(rows, "", fn {k, v} ->
      "% #{String.pad_trailing(k <> ":", width + 1)} #{v}\n"
    end)
  end

  # ---------------------------------------------------------------------

  defp current(k) when k in ~w(runtime total_runtime process_cputime),
    do: elem(:erlang.statistics(:runtime), 0)

  defp current("walltime"), do: elem(:erlang.statistics(:wall_clock), 0)
  defp current("real_time"), do: System.os_time(:second)
  defp current("reductions"), do: elem(Process.info(self(), :reductions), 1)

  # Bezugspunkt für den ersten Aufruf
  defp start("real_time", now), do: now
  defp start(_, _now), do: 0

  defp other("inferences"), do: PrologEx.inferences()
  defp other("memory"), do: list([process_memory(), 0])
  defp other("process_memory"), do: process_memory()
  defp other("vm_memory"), do: :erlang.memory(:total)

  defp other("garbage_collection") do
    {n, words, _} = :erlang.statistics(:garbage_collection)
    list([n, words * :erlang.system_info(:wordsize), 0])
  end

  defp other("schedulers"), do: :erlang.system_info(:schedulers_online)
  defp other("process_count"), do: :erlang.system_info(:process_count)

  defp process_memory, do: elem(Process.info(self(), :memory), 1)

  defp secs(ms), do: :erlang.float_to_binary(ms / 1000, decimals: 3)

  defp bytes(b) when b >= 1_048_576,
    do: "#{:erlang.float_to_binary(b / 1_048_576, decimals: 1)} MB"

  defp bytes(b) when b >= 1024, do: "#{:erlang.float_to_binary(b / 1024, decimals: 1)} KB"
  defp bytes(b), do: "#{b} Bytes"

  # 1234567 -> "1 234 567"
  defp group(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
    |> String.reverse()
  end
end
