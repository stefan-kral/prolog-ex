defmodule PrologEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :prolog_ex,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
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
