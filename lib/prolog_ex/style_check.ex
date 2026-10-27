defmodule PrologEx.StyleCheck do
  @moduledoc """
  Welche Warnungen `consult` ausgibt (`style_check/1` wie SWI):
  `singleton` und `discontiguous`, beide anfangs an. Gehört der Sitzung
  (Prozess-Dictionary).
  """

  @key :prolog_ex_style_check
  @kinds [:singleton, :discontiguous]

  def kinds, do: @kinds

  def on?(kind), do: not MapSet.member?(Process.get(@key, MapSet.new()), kind)

  def set(kind, on?) do
    off = Process.get(@key, MapSet.new())
    Process.put(@key, if(on?, do: MapSet.delete(off, kind), else: MapSet.put(off, kind)))
    :ok
  end
end
