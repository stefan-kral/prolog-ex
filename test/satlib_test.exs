defmodule PrologEx.SatlibTest do
  # library(clpb) an Formeln aus SATLIB (www.cs.ubc.ca/~hoos/SATLIB) mit
  # bekanntem Ergebnis (test/fixtures/satlib, Runner sat.pl):
  #   * uf20-91 (50 von 1000): zufällige 3-SAT-Formeln, 20 Variablen, erfüllbar;
  #     die Modelle hat Python durch Durchprobieren aller 2^20 Belegungen
  #     gezählt (conformance/satlib/count.py) – unabhängig von clpb
  #   * aim-50 (erfüllbar oder nicht, steht im Namen), dubois, hole7
  #     (Schubfach: 8 Tauben, 7 Löcher): strukturiert, unerfüllbar
  # Größere zufällige Formeln (uf50) sind für BDDs zu groß – in SWI wie
  # hier; an uf50-01 prüfen wir, dass Zeitgrenze und Ctrl-C mitten in
  # clpb greifen. Alle Formeln: conformance/satlib/run.sh.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @dir "test/fixtures/satlib"

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    dbs =
      for f <- ~w(uf20 structured hard), into: %{} do
        PrologEx.put_db(%{})
        {:ok, _} = PrologEx.Consult.load_file(Path.join(@dir, "sat.pl"))
        {:ok, _} = PrologEx.Consult.load_file(Path.join(@dir, f <> ".pl"))
        {f, PrologEx.current_db()}
      end

    {:ok, reader: r, dbs: dbs}
  end

  setup c do
    Reader.put_current(c.reader)
    on_exit(fn -> PrologEx.disarm_interrupt() end)
    :ok
  end

  defp names(file) do
    for [_, n] <-
          Regex.scan(~r/^expected\('([^']+)'/m, File.read!(Path.join(@dir, file <> ".pl"))),
        do: n
  end

  defp bad(c, file, names) do
    for n <- names,
        r = TableCase.run(c.reader, c.dbs[file], "verdict('#{n}', V)"),
        r != {"", {:answers, ["V = ok"]}},
        do: {n, r}
  end

  test "uf20-91 (die ersten 10): erfüllbar, Belegung stimmt, sat_count wie Durchprobieren", c do
    assert bad(c, "uf20", Enum.take(names("uf20"), 10)) == []
  end

  @tag :slow
  test "uf20-91: alle 50", c do
    assert bad(c, "uf20", Enum.drop(names("uf20"), 10)) == []
  end

  test "aim-50 (24 Formeln) und dubois20/21: erfüllbar bzw. unerfüllbar wie bekannt", c do
    assert bad(c, "structured", names("structured") -- ["hole7"]) == []
  end

  @tag :slow
  test "hole7 (Schubfach, 56 Variablen): unerfüllbar", c do
    assert bad(c, "structured", ["hole7"]) == []
  end

  @q "cnf('uf50-01', N, Cls), catch(call_with_time_limit(1, solve(N, Cls, _)), E, true)"

  test "Zeitgrenze greift mitten in clpb (uf50-01 braucht viel länger)", c do
    t0 = System.monotonic_time(:millisecond)

    assert {"", {:answers, [a]}} =
             TableCase.run(c.reader, c.dbs["hard"], "use_module(library(time)), " <> @q)

    assert a =~ "E = time_limit_exceeded"
    assert System.monotonic_time(:millisecond) - t0 < 10_000
  end

  test "Ctrl-C greift mitten in clpb", c do
    ref = :atomics.new(1, [])
    PrologEx.arm_interrupt(ref)
    spawn(fn -> Process.sleep(500) && :atomics.put(ref, 1, 1) end)
    t0 = System.monotonic_time(:millisecond)
    q = "cnf('uf50-01', N, Cls), solve(N, Cls, _)"
    assert inspect(TableCase.run(c.reader, c.dbs["hard"], q)) =~ "$aborted"
    assert System.monotonic_time(:millisecond) - t0 < 10_000
  end
end
