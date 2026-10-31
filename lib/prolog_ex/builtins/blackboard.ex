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
  require PrologEx
  alias PrologEx.Error

  defbuiltin "bb_put", [key, t] do
    put(key, t, context_module(), subst())
  end

  defbuiltin "bb_get", [key, t] do
    get(key, t, context_module(), subst())
  end

  @doc """
  bb_put/2 in Modul `mod` (auch für die Maschine, die es direkt ausführt).
  Atomares und markiert Ground wird nicht kopiert.
  """
  def put(key, t, mod, s) do
    k = key!(key, mod, s)
    put(k, value_copy(PrologEx.walk(t, s), s))
    :ok
  end

  @doc """
  bb_get/2 in Modul `mod`. Ist das Ziel eine gewöhnliche ungebundene
  Variable, wird sie direkt gebunden: die Kopie hat nur frische Variablen,
  ein Occurs-Check ist nie nötig (attributierte: Unifikation, die weckt).
  """
  def get(key, t, mod, s) do
    case fetch(key!(key, mod, s)) do
      {:ok, v} ->
        v = value_copy(v, %{})

        case PrologEx.walk(t, s) do
          {:var, id} = var when not (is_tuple(id) and elem(id, 0) == :attv) ->
            {:subst, Map.put(s, var, v)}

          _ ->
            {:unify, [{t, v}]}
        end

      :error ->
        :fail
    end
  end

  # gespeichert und gelesen wird eine Kopie; atomare und markierte
  # (variablenfreie) Werte sind ihre eigene Kopie
  defp value_copy(v, s) do
    if PrologEx.is_known_ground(v), do: v, else: PrologEx.copy_fresh(v, s)
  end

  defbuiltin "bb_delete", [key, t] do
    k = key!(key, context_module(), subst())

    case fetch(k) do
      {:ok, v} ->
        s = subst()

        case PrologEx.unify(t, value_copy(v, %{}), s) do
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

        case PrologEx.unify(old, value_copy(v, %{}), s) do
          {:ok, s} ->
            put(k, value_copy(PrologEx.walk(new, s), s))
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
