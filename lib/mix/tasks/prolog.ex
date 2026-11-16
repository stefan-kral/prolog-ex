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

  Am Terminal liest der Zeileneditor der BEAM (Pfeiltasten, Verlauf,
  TAB-Completion von Prädikaten, Bibliotheken und Dateinamen). Ctrl-C
  bricht die laufende Anfrage ab, wenn die BEAM mit `+Bc` läuft:
  `bin/prolog` (wie `mix prolog`, mit `+Bc`). `--no-edit` liest wie früher
  zeilenweise von stdin, etwa für `rlwrap mix prolog --no-edit`; dann
  beendet Ctrl-D die Eingabe, Ctrl-C bricht aber nichts ab.
  """

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("compile")

    # bin/prolog wechselt ins Projekt; Dateien gelten relativ zum Aufrufer
    case System.get_env("PROLOG_EX_CWD") do
      nil -> :ok
      dir -> File.cd!(dir)
    end

    code = PrologEx.Toplevel.main(args)
    if code != 0, do: exit({:shutdown, code})
  end
end
