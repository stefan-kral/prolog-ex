defmodule PrologEx.TestVectorsTest do
  # Kleinere Sammlungen mit unabhängigem Orakel (test/fixtures/test_vectors,
  # Herkunft in SOURCES.md; Runner vectors.pl):
  #   * RFC 4648, Abschnitt 10: Base64 und Base16 (library(bytes),
  #     chars_base64/3)
  #   * Markus Kuhns UTF-8-Stresstest (272 Zeilen, 68 ungültig): je Zeile
  #     die Codes nach Python – streng (bytes_utf8/2, Dateien mit
  #     encoding(utf8)) und mit U+FFFD je größtem ungültigem Teilstück
  #     (chars_utf8bytes/2)
  #   * csv-spectrum: 11 CSV-Dateien mit den erwarteten Zeilen
  #   * Unicode 17.0: char_type(C, upper(U)) und lower(L) für alle 3037
  #     Zeichen, deren Groß- oder Kleinschreibung nicht sie selbst ist; die
  #     Klassen (alphabetic, lower, upper, numeric, control, whitespace) an
  #     jedem 331. Zeichen und an Zeichen, die in 17.0 neu sind
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @dir "test/fixtures/test_vectors"

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    tmp = Path.join(System.tmp_dir!(), "px_vectors_#{System.unique_integer([:positive])}.tmp")
    PrologEx.put_db(%{})

    for f <- ~w(vectors.pl utf8_kuhn.pl csv_spectrum.pl case_ucd17.pl classes_ucd17.pl),
        do: {:ok, _} = PrologEx.Consult.load_file(Path.join(@dir, f))

    extra = "csv_dir('#{@dir}/csv/'). tmp_path('#{tmp}')."
    {db, []} = PrologEx.Consult.load(PrologEx.current_db(), Reader.read_terms(r, extra))
    on_exit(fn -> File.rm(tmp) end)
    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  # alle Namen N mit V \== ok
  defp bad(c, check, gen) do
    q = "findall(N-V, (#{gen}, #{check}(N, V), V \\== ok), L)"
    {"", {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    a
  end

  test "RFC 4648: Base64 und Base16 in beide Richtungen", c do
    assert bad(c, "v_rfc4648", "rfc4648(N, _, _)") == "L = []"
  end

  test "UTF-8 streng (bytes_utf8/2): jede Zeile wie Python, ungültige als Fehler", c do
    assert bad(c, "v_utf8_bytes", "line(N, _, _, _)") == "L = []"
  end

  test "UTF-8 streng aus Dateien (encoding(utf8))", c do
    assert bad(c, "v_utf8_stream", "line(N, _, _, _)") == "L = []"
  end

  # (Scryers DCG nahm überlange Formen an – C0 AF war „/“ – und warf bei
  # Ersatzpaaren einen Fehler: 37 Zeilen wichen ab)
  test "UTF-8 mit Ersatzzeichen (chars_utf8bytes/2): U+FFFD je größtem ungültigem Teilstück",
       c do
    assert bad(c, "v_utf8_chars", "line(N, _, _, _)") == "L = []"
  end

  test "csv-spectrum: csv_read_file/3 liest jede Datei wie erwartet", c do
    assert bad(c, "v_csv", "spectrum(N, _)") == "L = []"
  end

  test "Unicode 17.0: upper/lower von char_type/2 wie UnicodeData und SpecialCasing", c do
    assert bad(c, "v_case", "case(N, _, _)") == "L = []"
  end

  test "Unicode 17.0: Klassen von char_type/2 wie die allgemeine Kategorie", c do
    assert bad(c, "v_class", "uc(N, _, _)") == "L = []"
  end

  test "Unicode 17.0 auch im Leser und Schreiber (U+088F ist ein Buchstabe)", c do
    q =
      "atom_codes(A, [0x88F, 0x61]), read_from_chars([x, =, '\\x88F\\', '.'], T), " <>
        "write_term_to_chars(A, [quoted(true)], Cs)"

    assert {"", {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    assert a =~ "T = (x=\u088F)"
    # ohne Hochkommas geschrieben: ein Name aus Buchstaben
    assert a =~ "A = \u088Fa, Cs = [\u088F,a]"
  end
end
