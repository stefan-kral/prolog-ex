defmodule PrologEx.ProgramBatteryTest do
  # Programm-Batterie: test/programs/NAME.pl (Programm unverändert aus der
  # Quelle) mit NAME.checks.pl (Erwartungen, siehe runner.pl). Die
  # Erwartungen stammen aus unabhängigen Quellen (etwa OEIS) oder aus SWI
  # und Scryer und werden mit test/programs/cross.sh dort gegengeprüft.
  use ExUnit.Case, async: true
  alias PrologEx.Reader

  @dir Path.expand("programs", __DIR__)
  @runner Path.join(@dir, "runner.pl")
  @external_resource @runner
  @names (for f <- Path.wildcard(Path.join(@dir, "*.checks.pl")) do
            Path.basename(f, ".checks.pl")
          end)
  for n <- @names do
    @external_resource Path.join(@dir, n <> ".pl")
    @external_resource Path.join(@dir, n <> ".checks.pl")
  end

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  for n <- @names do
    test n, c do
      Reader.put_current(c.reader)

      src =
        Enum.map_join(
          [
            @runner,
            Path.join(@dir, unquote(n) <> ".pl"),
            Path.join(@dir, unquote(n) <> ".checks.pl")
          ],
          "\n",
          &File.read!/1
        )

      {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
      [{:term, g, _}] = Reader.read_terms(c.reader, "failures(Fs).")
      PrologEx.put_db(db)

      [out] =
        PrologEx.query(db, g)
        |> Enum.take(1)
        |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))

      assert out == "Fs = []", "#{unquote(n)}: #{out}"
    end
  end
end
