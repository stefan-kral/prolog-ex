defmodule PrologEx.Tools.Gprolog do
  @moduledoc """
  Lädt das gprolog-Orakel (nur für Vergleiche, nicht Teil von PrologEx):
  `PrologEx.GprologReader` samt Hilfsmodulen aus `tools/gprolog/`.
  """

  @dir __DIR__

  def ensure_loaded do
    unless Code.ensure_loaded?(PrologEx.GprologReader) do
      for f <- ~w(canonical.ex number_syntax.ex gprolog_reader.ex),
          do: Code.require_file(Path.join(@dir, f))
    end

    PrologEx.GprologReader
  end
end
