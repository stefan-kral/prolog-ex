defmodule PrologEx.Effects do
  @moduledoc """
  Äußere Wirkungen (Prozesse starten, Umgebung ändern, Shell): der
  Toplevel rechnet die nächste Antwort probeweise in einem eigenen Prozess
  voraus (siehe `PrologEx.Toplevel`) und verwirft sie bei Seiteneffekten.
  Wirkungen außerhalb des Interpreters ließen sich aber nicht mehr
  zurücknehmen – darum bricht `external!/0` das Vorausrechnen ab, bevor
  sie passieren; die Antwort kommt dann erst nach `;`.

  Außerhalb des Vorausrechnens vermerkt `external!/0` die Wirkung im
  Zustand des Interpreters (ein Zähler im Prozess-Wörterbuch). So sieht
  sie auch das Memo des Toplevels („seit der letzten Antwort ein
  Seiteneffekt?“, `PrologEx.Toplevel.state_snapshot/0`), das sonst nur
  Änderungen am Interpreter und Ausgaben bemerkt – eine Shell schreibt
  an ihm vorbei.
  """

  # (nicht prolog_ex_...: gehört nicht zum verglichenen Zustand)
  @key :speculative_lookahead

  @counter :prolog_ex_external_effects

  @doc """
  Vor einer äußeren Wirkung: im Vorausrechnen abbrechen (der Toplevel
  fragt dann nach `;`), sonst die Wirkung vermerken
  """
  def external! do
    if Process.get(@key),
      do: throw(:prolog_ex_speculative_abort),
      else: Process.put(@counter, Process.get(@counter, 0) + 1)

    :ok
  end

  @doc false
  def speculative!, do: Process.put(@key, true)

  # --- call_with_no_side_effects/1 (library(iso_ext)) ---------------------------
  #
  # Der Bereich ist ein Zähler in der Substitution (wie die Ebene von
  # call_with_depth_limit/3): '$nse_enter' erhöht ihn, '$nse_exit' senkt
  # ihn. Backtracking in den Bereich hinein stellt ihn mit der Substitution
  # wieder her, Scheitern und Ausnahmen den Stand davor – der Bereich ist
  # für Nichtdeterminismus durchsichtig. Unter-Maschinen (findall, \+, ...)
  # teilen die Substitution und damit den Bereich.
  #
  # Prüfpunkte: Builtins mit Wirkung sind in PrologEx.Builtins markiert
  # ({:fx, Art, Kategorie}); die Maschine prüft vor dem Aufruf. Dazu time/1
  # (gibt aus) und das Einwickeln von Code, der im Bereich registriert wird
  # und später laufen kann (Cleanup von setup_call_cleanup/3, freeze/2,
  # when/2): er läuft im Bereich ('$nse_call'/1).

  @nse :"$nse"

  @doc "Schlüssel des Bereichs in der Substitution"
  def nse_key, do: @nse

  @doc "Ist in dieser Substitution ein Bereich ohne Seiteneffekte offen?"
  def nse?(subst), do: is_map_key(subst, @nse)

  @doc """
  Vor einer Wirkung der Kategorie `cat` (database, state, io, external,
  random, memo, tabling) im Bereich: `permission_error(perform,
  side_effect, Ziel)` mit `context(Name/Stelligkeit, Kategorie)`. `goal`
  ist eine Funktion, die das Ziel (aufgelöst) liefert – erst im Fehlerfall
  gerechnet.
  """
  def nse_check!(subst, cat, name, arity, goal) do
    if is_map_key(subst, @nse) do
      import PrologEx, only: [mk: 2, a: 1]

      PrologEx.Error.throw!(
        mk("error", [
          mk("permission_error", [a("perform"), a("side_effect"), goal.()]),
          mk("context", [mk("/", [a(name), arity]), a(cat)])
        ])
      )
    end

    :ok
  end

  @doc "Code, der im Bereich registriert wird, im Bereich laufen lassen"
  def nse_wrap(goal, subst) do
    if is_map_key(subst, @nse) do
      import PrologEx, only: [mk: 2, a: 1]
      mk(":", [a("system"), mk("$nse_call", [goal])])
    else
      goal
    end
  end
end
