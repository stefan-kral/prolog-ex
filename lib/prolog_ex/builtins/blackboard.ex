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

  Dazu wie Scryers `library(iso_ext)`:

    * `bb_b_put(:Key, +Term)`        backtrackbar und ohne Kopie (wie
                                     SWIs `b_setval/2`): Backtracking
                                     stellt den vorigen Stand her

  Solche Werte stehen in der Substitution unter `#{inspect(:"$bb_b")}`
  (eine Map Schlüssel → Term); Backtracking nimmt sie wie Bindungen
  zurück, die Kompaktierung hält sie (und ihre Variablen) am Leben.
  `bb_get/2` liefert sie ohne Kopie, dieselben Variablen; `bb_put/2`
  entfernt sie.
  """
  use PrologEx.Builtin, module: "blackboard"
  require PrologEx
  alias PrologEx.Error

  defbuiltin "bb_put", [key, t] do
    put(key, t, context_module(), subst())
  end

  @b_key :"$bb_b"

  @doc "Schlüssel der backtrackbaren Werte in der Substitution"
  def b_key, do: @b_key

  defbuiltin "bb_b_put", [key, t] do
    s = subst()
    k = key!(key, context_module(), s)
    {:subst, Map.update(s, @b_key, %{k => t}, &Map.put(&1, k, t))}
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

    case s do
      %{@b_key => %{^k => _} = m} -> {:subst, Map.put(s, @b_key, Map.delete(m, k))}
      _ -> :ok
    end
  end

  @doc """
  bb_get/2 in Modul `mod`. Ist das Ziel eine gewöhnliche ungebundene
  Variable, wird sie direkt gebunden: die Kopie hat nur frische Variablen,
  ein Occurs-Check ist nie nötig (attributierte: Unifikation, die weckt).
  """
  def get(key, t, mod, s) do
    k = key!(key, mod, s)

    case s do
      %{@b_key => %{^k => v}} -> {:unify, [{t, v}]}
      _ -> get_global(k, t, s)
    end
  end

  defp get_global(k, t, s) do
    case fetch(k) do
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

  @doc false
  # für Bibliotheken in Elixir (clpb): b_getval/2 bzw. b_setval/2 im
  # Modul mod (Schlüssel ein Atomname)
  def b_value(mod, name, s) do
    k = {mod, {:atom, name}}

    case s do
      %{@b_key => %{^k => v}} -> {:ok, v}
      _ -> with {:ok, v} <- fetch(k), do: {:ok, value_copy(v, %{})}
    end
  end

  @doc false
  def b_put(s, mod, name, v) do
    k = {mod, {:atom, name}}
    Map.update(s, @b_key, %{k => v}, &Map.put(&1, k, v))
  end

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
