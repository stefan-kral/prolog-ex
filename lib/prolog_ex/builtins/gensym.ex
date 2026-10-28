defmodule PrologEx.Builtins.Gensym do
  @moduledoc """
  `library(gensym)` wie Scryer und SWI: eindeutige Atome je Basis.

    * `gensym(+Base, -Unique)`  Unique = Base gefolgt vom nächsten Zähler
                                (`a1`, `a2`, ...)
    * `reset_gensym(+Base)`     Zähler von Base zurücksetzen
    * `reset_gensym`            alle Zähler zurücksetzen (SWI)
    * `current_gensym_base(?Base)` zählt die Basen mit laufendem Zähler
                                in Standardordnung auf – **Erweiterung**,
                                weder in Scryer noch in SWI; nach
                                `reset_gensym/1` ist die Basis weg. Die
                                Liste wird beim Aufruf festgehalten
                                (`gensym/2` beim Backtracking ändert sie nicht).

  Die Zähler liegen (erst ab dem ersten `gensym/2`) unter dem Schlüssel
  `:gensym` in der Datenbank und überstehen Backtracking wie `assert`.
  Erzeugte Atome sind Binaries, keine BEAM-Atome: sie belasten die
  Atomtabelle der VM nicht.

  Fehler: Base Variable → `instantiation_error`, kein Atom →
  `type_error(atom, Base)` (Scryers `atom_si/1` scheitert dort nur);
  Unique gebunden → `uninstantiation_error(Unique)` wie Scryers
  `must_be(var, Unique)`.
  """
  use PrologEx.Builtin, module: "gensym"
  alias PrologEx.Error

  defbuiltin "gensym", [base, unique] do
    case deref(unique) do
      {:var, _} -> :ok
      _ -> Error.uninstantiation!(resolve(unique))
    end

    b = base!(base, subst())
    n = Map.get(counters(), b, 0) + 1
    PrologEx.update_db(&Map.update(&1, :gensym, %{b => n}, fn m -> Map.put(m, b, n) end))
    {:unify, [{unique, {:atom, b <> Integer.to_string(n)}}]}
  end

  defbuiltin "reset_gensym", [base] do
    b = base!(base, subst())

    if Map.has_key?(counters(), b),
      do: PrologEx.update_db(&Map.update!(&1, :gensym, fn m -> Map.delete(m, b) end))

    :ok
  end

  defbuiltin "reset_gensym", [] do
    PrologEx.update_db(&Map.delete(&1, :gensym))
    :ok
  end

  defbuiltin "current_gensym_base", [base], nondet: true do
    case PrologEx.unmark_top(deref(base)) do
      {:var, _} ->
        for b <- Enum.sort(Map.keys(counters())), do: {:unify, [{base, base_term(b)}]}

      {:atom, b} ->
        if Map.has_key?(counters(), b), do: [:ok], else: []

      [] ->
        if Map.has_key?(counters(), "[]"), do: [:ok], else: []

      _ ->
        Error.type!("atom", resolve(base))
    end
  end

  defp base_term("[]"), do: []
  defp base_term(b), do: {:atom, b}

  defp counters, do: Map.get(PrologEx.current_db(), :gensym, %{})

  defp base!(base, s) do
    case PrologEx.unmark_top(PrologEx.walk(base, s)) do
      {:var, _} -> Error.instantiation!()
      {:atom, b} -> b
      [] -> "[]"
      _ -> Error.type!("atom", PrologEx.resolve(base, s))
    end
  end
end
