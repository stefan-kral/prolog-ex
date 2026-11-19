defmodule PrologEx.ProgramBatteryTest do
  # Programm-Batterie: test/programs/NAME.pl (Programm unverändert aus der
  # Quelle) mit NAME.checks.pl (Erwartungen, siehe runner.pl). Die
  # Erwartungen stammen aus unabhängigen Quellen (etwa OEIS) oder aus SWI
  # und Scryer und werden mit test/programs/cross.sh dort gegengeprüft.
  #
  # Nicht parallel zu anderen Tests: Laden muss ohne Meldungen gehen, und
  # capture_io(:stderr) fängt die Meldungen aller Prozesse – auch die
  # parallel laufender Tests (etwa die Warnungen beim Laden des Vorspanns
  # der Trealla-Tests), die hier dann als Fehlschlag galten. Allein läuft
  # die Batterie in rund 7 s.
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  # die großen CLP-Programme brauchen auf einem langsamen Rechner mehr als
  # die 60 s, die ExUnit vorgibt
  @moduletag timeout: 300_000

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
    # als Datei geladen (abschnittsweise wie consult/1): Operatoren aus
    # Bibliotheken (clpz: ins, #=) gelten ab der Direktive
    @tag :tmp_dir
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

      file = Path.join(c.tmp_dir, unquote(n) <> ".pl")
      File.write!(file, src)
      PrologEx.put_db(%{})

      msgs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          {:ok, _} = PrologEx.Consult.load_file(file)
        end)

      # Singleton-Warnungen stören nicht: die Programme sind übernommen
      # (chat_parser von 1989) und bleiben unverändert
      msgs =
        msgs
        |> String.split("\n", trim: true)
        |> Enum.reject(&(&1 =~ "Warnung (Zeile" and &1 =~ "Singleton-Variablen"))
        |> Enum.join("\n")

      assert msgs == "", "#{unquote(n)}: #{msgs}"
      db = PrologEx.current_db()
      [{:term, g, _}] = Reader.read_terms(c.reader, "failures(Fs).")

      [out] =
        PrologEx.query(db, g)
        |> Enum.take(1)
        |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))

      assert out == "Fs = []", "#{unquote(n)}: #{out}"
    end
  end
end
