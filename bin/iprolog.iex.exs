# von bin/iprolog geladen. (repl() direkt hier aufzurufen ginge, aber dann
# unterbricht Ctrl-C nicht – die iex-Shell läuft da noch nicht.)
import PrologEx.Toplevel, only: [repl: 0, repl: 1, reset_session: 0]
IO.puts("PrologEx: `repl` startet den Prolog-Toplevel (Ctrl-C: zurück zu iex, `repl` macht weiter)")
