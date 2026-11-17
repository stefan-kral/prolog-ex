defmodule PrologEx.ClpzPuzzlesTest do
  # library(clpz) an Rätseln mit unabhängig bekanntem Ergebnis
  # (test/fixtures/clpz_puzzles):
  #   * Sudokus mit 17 Vorgaben aus Gordon Royles Sammlung (49151, jedes
  #     eindeutig lösbar; CC BY 2.5): clpz muss genau eine Lösung finden,
  #     die ohne clpz geprüft wird (Vorgaben, Zeilen, Spalten, Blöcke)
  #   * Golomb-Lineale: kürzeste Länge für N Marken (OEIS A003022);
  #     labeling([min(L)]) muss sie treffen, die Abstände prüft Prolog
  #     ohne clpz
  # Alle 49151 Sudokus und mehr Marken: conformance/clpz_puzzles/run.sh.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @dir "test/fixtures/clpz_puzzles"

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})

    for f <- ~w(sudoku.pl sudoku17.pl golomb.pl),
        do: {:ok, _} = PrologEx.Consult.load_file(Path.join(@dir, f))

    {:ok, reader: r, db: PrologEx.current_db()}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  @names for [_, n] <-
               Regex.scan(~r/^puzzle\('([^']+)'/m, File.read!(Path.join(@dir, "sudoku17.pl"))),
             do: n

  defp bad(c, goal, names) do
    for n <- names,
        r = TableCase.run(c.reader, c.db, "#{goal}(#{n}, V)"),
        r != {"", {:answers, ["V = ok"]}},
        do: {n, r}
  end

  test "Sudokus mit 17 Vorgaben (100): genau eine Lösung, und sie stimmt", c do
    assert bad(c, "verdict", Enum.map(@names, &"'#{&1}'")) == []
  end

  test "Golomb-Lineale mit 1 bis 7 Marken: kürzeste Länge wie bekannt", c do
    assert bad(c, "g_verdict", Enum.map(1..7, &to_string/1)) == []
  end

  @tag :slow
  test "Golomb-Lineal mit 8 Marken (Länge 34)", c do
    assert bad(c, "g_verdict", ["8"]) == []
  end
end
