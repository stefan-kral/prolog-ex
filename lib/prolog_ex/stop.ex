defmodule PrologEx.Stop do
  @moduledoc """
  Abbruchpunkte in langen eingebauten Schleifen (BDDs von clpb, …): Die
  Maschine prüft Zeitgrenzen und Ctrl-C nur zwischen gezählten Schritten;
  ein einzelnes Builtin kann aber lange rechnen. Läuft eine Grenze oder
  Ctrl-C (`arm/2`, von der Maschine vor jedem Builtin, nur wenn eine aktiv
  ist), sieht `tick!/0` alle #{4096} Aufrufe auf die Uhr bzw. das Flag und
  bricht das Builtin dann mit `PrologEx.Stop` ab; die Maschine entscheidet
  wie an ihren Prüfpunkten (time_limit_exceeded, '$aborted', set_timer/1).
  Ohne aktive Grenze kostet `tick!/0` ein Process.get.
  """

  defexception message: "Abbruchpunkt"

  @key :"$px_stop"
  @every 4096

  @doc false
  def arm(nil, nil), do: Process.delete(@key)
  def arm(deadline, ref), do: Process.put(@key, {deadline, ref, @every})

  @doc false
  def disarm, do: Process.delete(@key)

  @doc "in langen Schleifen aufrufen"
  def tick! do
    case Process.get(@key) do
      nil -> :ok
      {d, ref, n} when n > 0 -> Process.put(@key, {d, ref, n - 1})
      {d, ref, _} -> check!(d, ref)
    end
  end

  defp check!(d, ref) do
    if (d != nil and System.monotonic_time(:microsecond) >= d) or
         (ref != nil and :atomics.get(ref, 1) != 0) do
      raise __MODULE__
    else
      Process.put(@key, {d, ref, @every})
    end
  end
end
