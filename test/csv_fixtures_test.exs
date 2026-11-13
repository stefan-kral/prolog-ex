defmodule PrologEx.CsvFixturesTest do
  # library(csv): SWIs Schnittstelle (csv//1,2, csv_read_file/2,3, …) und
  # Scryers (parse_csv//1,2, write_csv/2,3). Die Programme in
  # test/fixtures/csv liefen auch in SWI-Prolog 9.0.4 bzw. Scryer Prolog;
  # deren Ausgaben (*.out) sind die Erwartung
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @dir Path.join(__DIR__, "fixtures/csv")

  setup do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    tmp = Path.join(System.tmp_dir!(), "prolog_ex_csv_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, reader: r, tmp: tmp}
  end

  defp run_fixture(c, name, goal \\ "go") do
    text = File.read!(Path.join(@dir, name <> ".pl")) |> String.replace("@DIR@", c.tmp)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, text))
    {out, result} = TableCase.run(c.reader, db, goal)
    assert result == {:answers, ["true"]}, inspect(result)
    out
  end

  defp expected(name), do: File.read!(Path.join(@dir, name <> ".out"))

  test "csv//2 lesen wie SWI (Optionen, Zahlen, Anführungszeichen, Fehler)", c do
    assert_same(run_fixture(c, "swi_parse"), expected("swi_parse"))
  end

  test "faule Listen (phrase_from_file), Dateien, Zeilen, Schreiben wie SWI", c do
    assert_same(run_fixture(c, "swi_files"), expected("swi_files"))
  end

  test "parse_csv//2 und write_csv/3 wie Scryer", c do
    # wie bei Scryer liest phrase_from_file/2 Zeichen (double_quotes=chars)
    out = run_fixture(c, "scryer", "set_prolog_flag(double_quotes, chars), once(go)")
    assert_same(out, expected("scryer"))
  end

  defp assert_same(out, exp) do
    a = String.split(out, "\n")
    b = String.split(exp, "\n")

    for {x, y, i} <- Enum.zip([a, b, Stream.iterate(1, &(&1 + 1))]) do
      assert x == y, "Zeile #{i}:\n PrologEx: #{x}\n Vorlage:  #{y}"
    end

    assert length(a) == length(b)
  end
end
