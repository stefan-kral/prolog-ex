defmodule PrologEx.ClpzGoldenTest do
  # 400 zufällige clpz-Anfragen gegen die Antworten der ursprünglichen
  # Prolog-Fassung (Scryer b7066b4), aufgezeichnet mit
  # test/fixtures/clpz/gen_golden.exs. Jeder Schritt nach Elixir muss
  # dieselben Antworten liefern (samt Restzielen und Fehlern). Dieselben
  # Anfragen geben in Scryer dieselben Ergebnisse (Vergleich mit
  # test/fixtures/clpz/harness.pl, siehe gen_golden.exs; abweichend nur die
  # Reihenfolge der Variablen in Summen und zusammengefasste freeze-Ziele).
  # Restziele in Scryers Form (Flag clpz_residuals = scryer).
  use ExUnit.Case, async: true
  alias PrologEx.Reader

  @golden Path.expand("fixtures/clpz/golden.txt", __DIR__)
  @external_resource @golden

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, ":- use_module(library(clpz)).\n"))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  defp norm(s), do: Regex.replace(~r/_\d+/, s, "_")

  defp answer(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      c.db
      |> PrologEx.query(g)
      |> Enum.take(4)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
      |> case do
        [] -> "false"
        as -> Enum.join(as, " ; ")
      end
    rescue
      e in PrologEx.Error ->
        "error: " <> PrologEx.Writer.format(PrologEx.unmark(e.term), quoted: true)
    end
  end

  test "400 Anfragen wie die Prolog-Fassung", c do
    Reader.put_current(c.reader)
    Process.put(:prolog_ex_ops, c.ops)
    PrologEx.put_db(c.db)
    # Restziele genau wie Scryer (Standard ist die lesbare Form)
    PrologEx.Flags.set("clpz_residuals", PrologEx.a("scryer"))

    diffs =
      for line <- @golden |> File.read!() |> String.split("\n", trim: true),
          [q, expected] = String.split(line, "\t"),
          actual = answer(c, q),
          norm(actual) != norm(expected),
          do: "#{q}\n  erwartet: #{expected}\n  erhalten: #{actual}"

    assert diffs == [],
           "#{length(diffs)} Abweichungen:\n" <> Enum.join(Enum.take(diffs, 10), "\n")
  end
end
