defmodule PrologEx.TreallaTest do
  # Tests aus Trealla Prolog (test/fixtures/trealla, MIT, siehe LICENSE
  # dort): je Programm NAME.pl die erwartete Ausgabe NAME.expected, wie
  # Trealla sie prüft (laden, initialization(main), stdout vergleichen).
  # Davor prelude.pl mit den Bibliotheken, die Trealla ohne use_module
  # kennt. Übernommen sind die Programme, die PrologEx so besteht und die
  # keine Dateien, Zeiten oder Zufall brauchen (Auswahl:
  # conformance/trealla/run.sh, Liste in PASSING); der ganze Lauf mit
  # Abweichungen steht unter conformance/trealla.
  use ExUnit.Case, async: true
  alias PrologEx.Reader

  @dir "test/fixtures/trealla"
  @prelude Path.join(@dir, "prelude.pl")
  @names @dir |> Path.join("PASSING") |> File.read!() |> String.split("\n", trim: true)
  @external_resource Path.join(@dir, "PASSING")

  for n <- @names do
    test n do
      {:ok, r} = Reader.start_link()
      Reader.put_current(r)
      PrologEx.put_db(%{})
      src = Path.join(@dir, unquote(n))

      out =
        ExUnit.CaptureIO.capture_io(fn ->
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            {:ok, _} = PrologEx.Consult.load_file(@prelude)

            # halt/0,1 im Programm beendet es (wie bei Trealla)
            try do
              {:ok, _} = PrologEx.Consult.load_file(src)
            catch
              :throw, {:prolog_halt, _} -> :ok
            end
          end)
        end)

      assert out == File.read!(Path.rootname(src) <> ".expected")
    end
  end
end
