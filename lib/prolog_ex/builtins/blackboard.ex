defmodule PrologEx.Builtins.Blackboard do
  @moduledoc """
  `library(blackboard)`: globale Werte je Modul, wie SICStus
  (`bb_put/2` & Co. sind dort eingebaut).

    * `bb_put(:Key, +Term)`          speichert eine Kopie von Term
    * `bb_get(:Key, ?Term)`          Kopie des Werts; scheitert ohne Wert
    * `bb_delete(:Key, ?Term)`       wie bb_get, entfernt den Wert dann
    * `bb_update(:Key, ?Old, ?New)`  Old mit dem Wert unifizieren, dann New
                                     (als Kopie) speichern

  Key ist ein Atom oder eine Ganzzahl, optional `M:Key`; ohne Modul gilt
  das Kontextmodul, so stören sich gleichnamige Schlüssel verschiedener
  Module nicht. Die Werte überstehen Backtracking (wie assert); gespeichert
  wird eine Kopie mit frischen Variablen, ohne Attribute.
  """
  use PrologEx.Builtin, module: "blackboard"
  alias PrologEx.Error

  defbuiltin "bb_put", [key, t] do
    k = key!(key, context_module(), subst())
    put(k, PrologEx.copy_fresh(t, subst()))
    :ok
  end

  defbuiltin "bb_get", [key, t] do
    case fetch(key!(key, context_module(), subst())) do
      {:ok, v} -> {:unify, [{t, PrologEx.copy_fresh(v, %{})}]}
      :error -> :fail
    end
  end

  defbuiltin "bb_delete", [key, t] do
    k = key!(key, context_module(), subst())

    case fetch(k) do
      {:ok, v} ->
        s = subst()

        case PrologEx.unify(t, PrologEx.copy_fresh(v, %{}), s) do
          {:ok, s} ->
            PrologEx.update_db(&Map.update!(&1, :blackboard, fn bb -> Map.delete(bb, k) end))
            {:subst, s}

          _ ->
            :fail
        end

      :error ->
        :fail
    end
  end

  defbuiltin "bb_update", [key, old, new] do
    k = key!(key, context_module(), subst())

    case fetch(k) do
      {:ok, v} ->
        s = subst()

        case PrologEx.unify(old, PrologEx.copy_fresh(v, %{}), s) do
          {:ok, s} ->
            put(k, PrologEx.copy_fresh(new, s))
            {:subst, s}

          _ ->
            :fail
        end

      :error ->
        :fail
    end
  end

  # ---------------------------------------------------------------------

  defp fetch(k), do: PrologEx.current_db() |> Map.get(:blackboard, %{}) |> Map.fetch(k)

  defp put(k, v),
    do:
      PrologEx.update_db(&Map.update(&1, :blackboard, %{k => v}, fn bb -> Map.put(bb, k, v) end))

  # {Modul, Schlüssel}; M:K auch geschachtelt
  defp key!(key, mod, s) do
    case PrologEx.unmark_top(PrologEx.walk(key, s)) do
      {:struct, ":", [m, k]} ->
        case PrologEx.walk(m, s) do
          {:atom, m} -> key!(k, m, s)
          {:var, _} -> Error.instantiation!()
          other -> Error.type!("atom", PrologEx.resolve(other, s))
        end

      {:atom, name} ->
        {mod, {:atom, name}}

      [] ->
        {mod, []}

      n when is_integer(n) ->
        {mod, n}

      {:var, _} ->
        Error.instantiation!()

      other ->
        Error.type!("atomic", PrologEx.resolve(other, s))
    end
  end
end
