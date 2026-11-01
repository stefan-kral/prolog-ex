defmodule PrologEx.MixProject do
  use Mix.Project

  # Erlang/OTP 28 oder neuer (z. B. PCRE2 in :re für library(pcre))
  @min_otp 28

  def project do
    if String.to_integer(System.otp_release()) < @min_otp,
      do: Mix.raise("PrologEx braucht Erlang/OTP #{@min_otp} oder neuer")

    [
      app: :prolog_ex,
      version: "0.1.0",
      # die ersten Fassungen mit Unterstützung für OTP 28
      elixir: "~> 1.18.4 or ~> 1.19",
      start_permanent: Mix.env() == :prod,
      aliases: [
        # alles neu, wie make clean && make all
        rebuild: ["clean", "compile --force"]
      ],
      # Hilfsdateien der Tests (z. B. der frühere Writer als Referenz)
      test_ignore_filters: [~r"^test/fixtures/"],
      # library(http/...): ssl und inets erst beim ersten Aufruf starten
      # (als Abhängigkeit kosteten sie jeden Start ~60 ms). Dafür dürfen
      # sie nicht als fehlend gemeldet werden, und Mix darf sie nicht aus
      # dem Suchpfad nehmen.
      elixirc_options: [no_warn_undefined: [:ssl, :public_key, :httpc, :inets]],
      prune_code_paths: false,
      deps: []
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end
end
