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
  def nse_check!(subst, cat, name, arity, goal, args \\ nil) do
    if is_map_key(subst, @nse) and not allowed?(cat, name, arity, args, subst) do
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

  # --- Ausnahmen: Wirkungen, die den Bereich nicht verlassen ---------------
  #
  # io: Schreiben in einen Speicher-Stream, den der Bereich selbst geöffnet
  # hat und wieder schließt (with_output_to/2, format/3 in eine Senke) –
  # nur auf derselben Tiefe, ein innerer Bereich darf nicht nach außen
  # schreiben.
  # random: in einem Kind von library(concurrent) gehört der Generator dem
  # Kind (eigener Startwert, verschwindet mit ihm) – auf der Tiefe des
  # Kinds (1).

  @child :prolog_ex_conc_child

  @doc "Den Prozess als Kind von library(concurrent) markieren"
  def mark_child!, do: Process.put(@child, true)

  @doc "Tiefe des Bereichs (0: keiner)"
  def nse_depth(subst), do: Map.get(subst, @nse, 0)

  @doc "Darf hier Zufall gezogen werden (der Generator ändert sich)?"
  def random_ok?(subst),
    do: not is_map_key(subst, @nse) or (Process.get(@child) == true and nse_depth(subst) == 1)

  # Ausgabe auf den aktuellen Ausgabestream
  @out_current MapSet.new(
                 ~w(write/1 print/1 writeln/1 writeq/1 write_canonical/1 write_term/2 nl/0
                    put_char/1 put_code/1 tab/1 format/1 format/2 flush_output/0)
               )
  # Ausgabe auf einen Stream im ersten Argument
  @out_stream MapSet.new(~w(write/2 print/2 writeln/2 writeq/2 write_canonical/2 write_term/3 nl/1
                   put_char/2 put_code/2 tab/2 format/3 flush_output/1))
  # with_output_to/2 (öffnet und schließt seinen Speicher-Stream selbst)
  @wot MapSet.new(~w($wot_sink/1 $wot_open/2 $wot_restore/2 $wot_close/3))

  defp allowed?("random", _name, _arity, _args, subst), do: random_ok?(subst)

  defp allowed?("io", name, arity, args, subst) do
    pi = "#{name}/#{arity}"

    cond do
      MapSet.member?(@wot, pi) -> true
      MapSet.member?(@out_current, pi) -> local?(PrologEx.Stream.current_output(), subst)
      MapSet.member?(@out_stream, pi) and is_list(args) -> local_target?(hd(args), pi, subst)
      true -> false
    end
  end

  defp allowed?(_cat, _name, _arity, _args, _subst), do: false

  defp local?(id, subst), do: PrologEx.Stream.nse_depth(id) == nse_depth(subst)

  defp local_target?(t, pi, subst) do
    case PrologEx.unmark_top(PrologEx.Store.walk(t, subst)) do
      {:struct, "$stream", [id]} when is_integer(id) -> local?(id, subst)
      # format/3 in eine Senke (atom(A), chars(Cs), ...): eigener Stream
      other -> pi == "format/3" and PrologEx.Builtins.Swi.sink?(other)
    end
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
