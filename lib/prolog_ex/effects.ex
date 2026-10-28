defmodule PrologEx.Effects do
  @moduledoc """
  Äußere Wirkungen (Prozesse starten, Umgebung ändern, Shell): der
  Toplevel rechnet die nächste Antwort probeweise in einem eigenen Prozess
  voraus (siehe `PrologEx.Toplevel`) und verwirft sie bei Seiteneffekten.
  Wirkungen außerhalb des Interpreters ließen sich aber nicht mehr
  zurücknehmen – darum bricht `external!/0` das Vorausrechnen ab, bevor
  sie passieren; die Antwort kommt dann erst nach `;`.
  """

  # (nicht prolog_ex_...: gehört nicht zum verglichenen Zustand)
  @key :speculative_lookahead

  @doc "Im Vorausrechnen: abbrechen (der Toplevel fragt dann nach `;`)"
  def external! do
    if Process.get(@key), do: throw(:prolog_ex_speculative_abort), else: :ok
  end

  @doc false
  def speculative!, do: Process.put(@key, true)
end
