defmodule PrologEx.SgmlFixturesTest do
  # library(sgml) gegen die Vorbilder: zufällig erzeugte (oft kaputte)
  # XML-Texte für load_xml/3 mit Scryer Prologs Ausgabe als Erwartung
  # (xml_read), zufällige DOMs mit Optionen für xml_write/3 und
  # html_write/3 mit SWI-Prologs Ausgabe (xml_write)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @dir Path.join(__DIR__, "fixtures/sgml")

  setup do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r}
  end

  for name <- ["xml_read", "xml_write"] do
    test "#{name}: wie das Vorbild", c do
      text = File.read!(Path.join(@dir, unquote(name) <> ".pl"))
      {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, text))
      {out, result} = TableCase.run(c.reader, db, "go")
      assert result == {:answers, ["true"]}, inspect(result)
      exp = File.read!(Path.join(@dir, unquote(name) <> ".out"))
      a = String.split(out, "\n")
      b = String.split(exp, "\n")

      for {x, y, i} <- Enum.zip([a, b, Stream.iterate(1, &(&1 + 1))]) do
        assert x == y, "Zeile #{i}:\n PrologEx: #{x}\n Vorbild:  #{y}"
      end

      assert length(a) == length(b)
    end
  end
end
