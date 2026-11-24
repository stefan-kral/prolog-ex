defmodule PrologEx.Builtins.SideEffects do
  @moduledoc """
  `call_with_no_side_effects(:G)` (`library(iso_ext)`): G wie `call/1`, aber
  jede Wirkung – auf die Datenbank, den Zustand des Interpreters, Streams
  oder nach außen – ist vorher ein Fehler
  `permission_error(perform, side_effect, Ziel)` mit `context(N/A,
  Kategorie)`. Super-strikt: auch Lesen aus Streams, Speicher-Streams
  (`with_output_to/2`, `format/3`), Zufall, `b_setval/2`, Memo und Tabling.
  Lesen von Zustand, das ihn nicht ändert, ist erlaubt.

  Der Bereich ist für Nichtdeterminismus durchsichtig (ein Zähler in der
  Substitution, siehe `PrologEx.Effects`). Code, der im Bereich registriert
  wird und später laufen kann (Cleanup von `setup_call_cleanup/3`,
  `freeze/2`, `when/2`), läuft im Bereich (`'$nse_call'/1`).
  """
  use PrologEx.Builtin
  alias PrologEx.Effects
  alias PrologEx.Store

  defbuiltin "$nse_enter", [] do
    s = subst()
    {:subst, Store.put(s, Effects.nse_key(), Store.get(s, Effects.nse_key(), 0) + 1)}
  end

  defbuiltin "$nse_exit", [] do
    s = subst()
    k = Effects.nse_key()

    case Store.get(s, k, 0) do
      n when n > 1 -> {:subst, Store.put(s, k, n - 1)}
      _ -> {:subst, Map.delete(s, k)}
    end
  end

  # '$nse_at'(D, G): G auf Tiefe D (der des Bereichs, in dem G registriert
  # wurde: PrologEx.Effects.nse_wrap/2), danach die Tiefe davor
  defbuiltin "$nse_depth", [d] do
    {:unify, [{d, Store.get(subst(), Effects.nse_key(), 0)}]}
  end

  defbuiltin "$nse_put", [d] do
    s = subst()
    k = Effects.nse_key()

    case PrologEx.Store.walk(d, s) do
      n when is_integer(n) and n > 0 -> {:subst, Store.put(s, k, n)}
      _ -> {:subst, Map.delete(s, k)}
    end
  end

  def meta,
    do: [
      {"system", "$nse_call", [0]},
      {"system", "$nse_at", ["?", 0]},
      {"iso_ext", "call_with_no_side_effects", [0]}
    ]

  def library do
    import PrologEx, only: [s: 2, v: 1, rule: 2]
    g = v("G")
    body = [s("$nse_enter", []), s("call", [g]), s("$nse_exit", [])]

    [d, o] = [v("D"), v("O")]

    at = [s("$nse_depth", [o]), s("$nse_put", [d]), s("call", [g]), s("$nse_put", [o])]

    %{
      "system" => [rule(s("$nse_call", [g]), body), rule(s("$nse_at", [d, g]), at)],
      "iso_ext" => [rule(s("call_with_no_side_effects", [g]), body)]
    }
  end
end
