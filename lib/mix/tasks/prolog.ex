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
  zeilenweise von stdin, etwa unter rlwrap (`./start_ex`); am Terminal
  bricht dann SIGTERM die laufende Anfrage ab (`rlwrap -I` schickt es bei
  Ctrl-C).
  """

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("compile")

    # start_ex aus einem anderen Verzeichnis: mix läuft im Projekt, Prolog
    # im Aufrufverzeichnis (Dateien auf der Kommandozeile, consult/1,
    # working_directory/2 relativ dazu). Danach gelöscht, damit von hier
    # gestartete Programme sie nicht erben
    case System.get_env("PROLOG_EX_CWD") do
      dir when dir in [nil, ""] ->
        :ok

      dir ->
        System.delete_env("PROLOG_EX_CWD")

        case File.cd(dir) do
          :ok ->
            :ok

          {:error, _} ->
            IO.puts(:stderr, "% Verzeichnis #{dir} nicht erreichbar, bleibe im Projekt")
        end
    end

    code = PrologEx.Toplevel.main(args)
    if code != 0, do: exit({:shutdown, code})
  end
end
