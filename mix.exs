defmodule PrologEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :prolog_ex,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      # nach Elixir: der gprolog-Reader (Mix.Tasks.Compile.PrologReader unten)
      compilers: Mix.compilers() ++ [:prolog_reader],
      aliases: [
        # alles neu, wie make clean && make all
        rebuild: ["clean", "compile --force"]
      ],
      # Hilfsdateien der Tests (z. B. der frühere Writer als Referenz)
      test_ignore_filters: [~r"^test/fixtures/"],
      deps: []
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end
end

defmodule Mix.Tasks.Compile.PrologReader do
  @shortdoc "Übersetzt den gprolog-Reader, wenn reader.pl neuer ist"

  @moduledoc """
  Compiler-Schritt nach dem Elixir-Compiler: `mix compile` – und damit
  `mix test`, `mix run`, `mix prolog` – übersetzt `priv/gprolog/reader.pl`
  mit `gplc` zu `priv/gprolog/reader`, wenn das Programm fehlt oder älter
  ist als die Quelle. `mix compile --force` übersetzt immer, `mix clean`
  löscht das Programm.

  Steht hier in `mix.exs` (nicht in `lib/`), damit er immer geladen ist –
  auch bei `mix clean` und vor dem ersten Übersetzen.

  `gplc` wird im `PATH` gesucht, sonst über die Umgebungsvariable `GPLC`
  (z. B. `GPLC=/opt/homebrew/bin/gplc`). Fehlt es, gibt es nur eine
  Warnung: ohne Reader laufen die Teile weiter, die keinen gprolog
  brauchen (die Tests dafür sind mit `:gprolog` markiert).
  """

  use Mix.Task.Compiler

  @src "priv/gprolog/reader.pl"
  @out "priv/gprolog/reader"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])

    if opts[:force] || stale?() do
      case build() do
        {:ok, path} ->
          Mix.shell().info("Reader übersetzt: #{path}")
          {:ok, []}

        {:error, msg} ->
          Mix.shell().error("Warnung: Reader nicht übersetzt – #{msg}")
          {:ok, [diagnostic(msg)]}
      end
    else
      {:noop, []}
    end
  end

  @impl true
  def clean do
    File.rm(@out)
    :ok
  end

  @doc "Fehlt das Programm oder ist es älter als reader.pl?"
  def stale? do
    case {File.stat(@out), File.stat(@src)} do
      {{:ok, %{mtime: bin}}, {:ok, %{mtime: pl}}} -> pl > bin
      {{:error, _}, _} -> true
      _ -> false
    end
  end

  @doc "reader.pl übersetzen: {:ok, pfad} | {:error, meldung}"
  def build do
    with {:ok, gplc} <- find_gplc() do
      case System.cmd(gplc, ["--no-top-level", "-o", @out, @src], stderr_to_stdout: true) do
        {_, 0} -> {:ok, @out}
        {output, code} -> {:error, "gplc ist mit Status #{code} gescheitert:\n#{output}"}
      end
    end
  end

  defp find_gplc do
    gplc =
      case System.get_env("GPLC") do
        nil -> System.find_executable("gplc")
        "" -> System.find_executable("gplc")
        path -> if File.exists?(path), do: path
      end

    if gplc,
      do: {:ok, gplc},
      else:
        {:error,
         "gplc nicht gefunden. GNU Prolog installieren (z. B. `brew install gnu-prolog`) " <>
           "oder GPLC=/pfad/zu/gplc setzen."}
  end

  defp diagnostic(msg) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "prolog_reader",
      file: Path.expand(@src),
      message: msg,
      position: 0,
      severity: :warning
    }
  end
end
