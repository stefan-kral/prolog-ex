defmodule Mix.Tasks.Prolog.BuildReader do
  @shortdoc "Übersetzt den gprolog-Term-Reader (priv/gprolog/reader)"

  @moduledoc """
  Übersetzt `priv/gprolog/reader.pl` mit `gplc` zu einem eigenständigen
  Programm `priv/gprolog/reader`.

      mix prolog.build_reader

  `gplc` wird im `PATH` gesucht; ein anderer Pfad lässt sich über die
  Umgebungsvariable `GPLC` setzen, z. B. `GPLC=/opt/homebrew/bin/gplc`.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    case build() do
      {:ok, path} -> Mix.shell().info("Reader übersetzt: #{path}")
      {:error, msg} -> Mix.raise(msg)
    end
  end

  @doc false
  def build do
    src = Path.join(["priv", "gprolog", "reader.pl"])
    out = Path.join(["priv", "gprolog", "reader"])

    with {:ok, gplc} <- find_gplc() do
      case System.cmd(gplc, ["--no-top-level", "-o", out, src], stderr_to_stdout: true) do
        {_, 0} -> {:ok, out}
        {output, code} -> {:error, "gplc ist mit Status #{code} gescheitert:\n#{output}"}
      end
    end
  end

  defp find_gplc do
    case System.get_env("GPLC") || System.find_executable("gplc") do
      nil ->
        {:error,
         "gplc nicht gefunden. GNU Prolog installieren (z. B. `brew install gnu-prolog`) " <>
           "oder GPLC=/pfad/zu/gplc setzen."}

      path ->
        {:ok, path}
    end
  end
end
