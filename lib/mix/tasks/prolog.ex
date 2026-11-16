defmodule Mix.Tasks.Prolog do
  @shortdoc "Startet den PrologEx-Toplevel"

  @moduledoc """
  Startet den Prolog-Toplevel.

      mix prolog                      interaktiv
      mix prolog app.pl               app.pl laden, dann interaktiv
      mix prolog app.pl -g main -q    laden, main ausführen, beenden
      mix prolog - < app.pl           Programm von stdin laden (ohne Toplevel)
      cat app.pl | mix prolog - -g main

  Im Toplevel lädt `[user].` Klauseln von der Tastatur (Ende mit
  `end_of_file.` oder Ctrl-D), `[datei].` lädt eine Datei.

  Am Terminal liest ein eigener Zeileneditor (Pfeiltasten, Verlauf,
  TAB-Completion von Prädikaten, Bibliotheken und Dateinamen; Ctrl-D auf
  leerer Zeile beendet `[user]` bzw. die Sitzung). Ctrl-C bricht die
  laufende Anfrage ab, wenn die BEAM mit `+Bc` läuft:
  `elixir --erl "+Bc" -S mix prolog`. `--no-edit` liest wie früher
  zeilenweise von stdin, etwa unter rlwrap (`./start_ex`).
  """

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("compile")

    code = PrologEx.Toplevel.main(args)
    if code != 0, do: exit({:shutdown, code})
  end
end
