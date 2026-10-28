defmodule PrologEx.Effects do
  @moduledoc """
  Äußere Wirkungen (Prozesse starten, Umgebung ändern, Shell): der
  Toplevel rechnet die nächste Antwort probeweise in einem eigenen Prozess
  voraus (siehe `PrologEx.Toplevel`) und verwirft sie bei Seiteneffekten.
  Wirkungen außerhalb des Interpreters ließen sich aber nicht mehr
  zurücknehmen – darum bricht `external!/0` das Vorausrechnen ab, bevor
  sie passieren; die Antwort kommt dann erst nach `;`.

  Außerhalb des Vorausrechnens vermerkt `external!/0` die Wirkung im
  Zustand des Interpreters (ein Zähler im Prozess-Wörterbuch). So sieht
  sie auch das Memo des Toplevels („seit der letzten Antwort ein
  Seiteneffekt?“, `PrologEx.Toplevel.state_snapshot/0`), das sonst nur
  Änderungen am Interpreter und Ausgaben bemerkt – eine Shell schreibt
  an ihm vorbei.
  """

  # (nicht prolog_ex_...: gehört nicht zum verglichenen Zustand)
  @key :speculative_lookahead

  @counter :prolog_ex_external_effects

  @doc """
  Vor einer äußeren Wirkung: im Vorausrechnen abbrechen (der Toplevel
  fragt dann nach `;`), sonst die Wirkung vermerken
  """
  def external! do
    if Process.get(@key),
      do: throw(:prolog_ex_speculative_abort),
      else: Process.put(@counter, Process.get(@counter, 0) + 1)

    :ok
  end

  @doc false
  def speculative!, do: Process.put(@key, true)
end
