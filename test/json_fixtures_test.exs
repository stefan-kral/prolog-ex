defmodule PrologEx.JsonFixturesTest do
  # library(http/json) gegen SWI-Prolog 9.0.4: zufällig erzeugte (auch
  # kaputte) JSON-Texte zum Lesen und Terme mit Optionen zum Schreiben
  # (test/fixtures/json/*.pl); die Erwartung (*.out) ist SWIs Ausgabe für
  # dieselben Programme. Ohne Tabs (SWI zählt die Spalte bis zum nächsten
  # Tabstopp, PrologEx ein Zeichen) und ohne UTF-16-Ersatzpaare (die
  # PrologEx zu einem Zeichen verbindet)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @dir Path.join(__DIR__, "fixtures/json")

  setup do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r}
  end

  for name <- ["read", "write"] do
    test "#{name}: wie SWI", c do
      text = File.read!(Path.join(@dir, unquote(name) <> ".pl"))
      {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, text))
      {out, result} = TableCase.run(c.reader, db, "go")
      assert result == {:answers, ["true"]}, inspect(result)
      exp = File.read!(Path.join(@dir, unquote(name) <> ".out"))

      for {x, y, i} <-
            Enum.zip([
              String.split(out, "\n"),
              String.split(exp, "\n"),
              Stream.iterate(1, &(&1 + 1))
            ]) do
        assert x == y, "Zeile #{i}:\n PrologEx: #{x}\n SWI:      #{y}"
      end

      assert length(String.split(out, "\n")) == length(String.split(exp, "\n"))
    end
  end
end
