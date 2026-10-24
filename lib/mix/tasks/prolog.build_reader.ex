defmodule Mix.Tasks.Prolog.BuildReader do
  @shortdoc "Übersetzt den gprolog-Term-Reader (priv/gprolog/reader)"

  @moduledoc """
  Übersetzt `priv/gprolog/reader.pl` mit `gplc` zu einem eigenständigen
  Programm `priv/gprolog/reader` – immer, auch wenn es aktuell ist.

      mix prolog.build_reader

  Normalerweise nicht nötig: `mix compile` erledigt das, sobald
  `reader.pl` neuer ist (Compiler-Schritt `Mix.Tasks.Compile.PrologReader`
  in `mix.exs`). `gplc` wird im `PATH` gesucht oder über `GPLC` gesetzt.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    case Mix.Tasks.Compile.PrologReader.build() do
      {:ok, path} -> Mix.shell().info("Reader übersetzt: #{path}")
      {:error, msg} -> Mix.raise(msg)
    end
  end
end
