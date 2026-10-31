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
    ] ++ lazy_otp_apps()
  end

  # library(http/...): ssl und inets erst beim ersten Aufruf starten (als
  # Abhängigkeit kosteten sie jeden Start ~60 ms). Dafür dürfen sie nicht
  # als fehlend gemeldet werden, und Mix (ab 1.15) darf sie nicht aus dem
  # Suchpfad nehmen; Elixir 1.14 kennt dafür nur xref.
  @lazy [:ssl, :public_key, :httpc, :inets]

  defp lazy_otp_apps do
    if Version.match?(System.version(), ">= 1.15.0"),
      do: [elixirc_options: [no_warn_undefined: @lazy], prune_code_paths: false],
      else: [xref: [exclude: @lazy]]
  end

  def application do
    [extra_applications: [:logger]]
  end
end
