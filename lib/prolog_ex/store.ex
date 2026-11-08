defmodule PrologEx.Store do
  @moduledoc """
  Der Bindungsspeicher: alle Zugriffe auf die Substitution laufen über
  dieses Modul. Die Maschine, die Builtins und die Kompaktierung kennen
  nur diese Schnittstelle, nicht die Darstellung.

  Darstellung (zurzeit): eine persistente Map, die als Wert durchgereicht
  wird. Einträge:

    * `{:var, id} => Term` – Bindung einer Variablen,
    * `{:attrs, id} => %{Modul => Term}` – Attribute der attributierten
      Variablen `{:var, {:attv, id}}`,
    * `:wake => [Var]` – seit dem letzten Wecken gebundene attributierte
      Variablen (neueste vorn), siehe `bind/3` und `take_wake/1`,
    * weitere Schlüssel der Maschine und einzelner Builtins (Ebene von
      call_with_depth_limit/3, backtrackbares Blackboard), siehe `get/3`,
      `put/3`, `update/4`.

  Choice Points merken sich den Zustand mit `snapshot/1` und stellen ihn
  mit `restore/1` wieder her – für die persistente Map beides die
  Identität. Ein veränderlicher Speicher mit Trail hätte hier eine Marke
  und das Zurückspulen; die Aufrufer änderten sich nicht.
  """

  @type t :: map()

  @doc "Leerer Speicher"
  @spec new() :: t
  def new, do: %{}

  @doc "Anzahl der Einträge (Statistik)"
  def size(s), do: map_size(s)

  # ---------------------------------------------------------------------
  # Bindungen
  # ---------------------------------------------------------------------

  @doc "Variable bis zu einer freien Variablen oder einem Nicht-Variablen-Term verfolgen"
  def walk({:var, _} = var, s) do
    case s do
      %{^var => t} -> walk(t, s)
      _ -> var
    end
  end

  def walk(t, _s), do: t

  @doc "Direkte Bindung einer Variablen (ein Schritt), falls gebunden"
  @spec binding(t, term) :: {:ok, term} | :error
  def binding(s, {:var, _} = var), do: Map.fetch(s, var)

  @doc """
  Einzige Stelle, an der Variablen gebunden werden. Eine attributierte
  Variable wird zusätzlich unter `:wake` vermerkt; die Maschine weckt
  danach ihre Ziele. Für normale Variablen kostet das nichts.
  """
  def bind({:var, {:attv, _}} = var, t, s),
    do: s |> Map.put(var, t) |> Map.update(:wake, [var], &[var | &1])

  def bind({:var, _} = var, t, s), do: Map.put(s, var, t)

  @doc """
  Bindung setzen, ohne zu wecken (für Variablen, deren Wecken der Aufrufer
  selbst übernimmt oder die er gerade entbunden hatte; für normale
  Variablen dasselbe wie `bind/3`).
  """
  def put_binding(s, {:var, _} = var, t), do: Map.put(s, var, t)

  @doc "Bindung wieder lösen (vorübergehend, etwa während verify_attributes/3 läuft)"
  def unbind(s, {:var, _} = var), do: Map.delete(s, var)

  # ---------------------------------------------------------------------
  # Wecken
  # ---------------------------------------------------------------------

  @doc "Sind seit dem letzten Wecken attributierte Variablen gebunden worden?"
  def wake?(s), do: is_map_key(s, :wake)

  @doc """
  Die seit dem letzten Wecken gebundenen attributierten Variablen (neueste
  vorn) entnehmen: `{vars, s}` oder `:none`.
  """
  def take_wake(s) do
    case s do
      %{wake: ws} -> {ws, Map.delete(s, :wake)}
      _ -> :none
    end
  end

  # ---------------------------------------------------------------------
  # Attribute (nach Kennung der attributierten Variablen)
  # ---------------------------------------------------------------------

  @doc "Attribute der attributierten Variablen `id`: Map Modul => Term (leer, wenn keine)"
  def attrs(s, id), do: Map.get(s, {:attrs, id}, %{})

  @doc "Attribute, falls vorhanden"
  def fetch_attrs(s, id), do: Map.fetch(s, {:attrs, id})

  def has_attrs?(s, id), do: is_map_key(s, {:attrs, id})

  def put_attrs(s, id, attrs) when is_map(attrs), do: Map.put(s, {:attrs, id}, attrs)

  @doc "Attribute mit `fun` ändern, oder `default` einsetzen, wenn es noch keine gibt"
  def update_attrs(s, id, default, fun), do: Map.update(s, {:attrs, id}, default, fun)

  @doc """
  Eine normale Variable zu einer attributierten machen: an die neue
  attributierte Variable mit Kennung `id` binden (ohne Wecken) und ihr die
  Attribute geben.
  """
  def attach(s, {:var, _} = var, id, attrs),
    do: s |> Map.put(var, {:var, {:attv, id}}) |> Map.put({:attrs, id}, attrs)

  @doc "Kennungen aller attributierten Variablen, die Attribute haben"
  def attv_ids(s), do: for({:attrs, id} <- Map.keys(s), do: id)

  @doc "Bindungen in `s2`, die es in `s1` nicht gab: `[{var, wert}]`"
  def new_bindings(s1, s2),
    do: for({{:var, _} = v, t} <- s2, not Map.has_key?(s1, v), do: {v, t})

  @doc "Alle gebundenen Variablen (für Zyklen: PrologEx.Cyclic)"
  def bound_vars(s), do: for({{:var, _} = v, _} <- s, do: v)

  @doc "Alle Attribute: Liste von `{id, attrs}`"
  def all_attrs(s), do: for({{:attrs, id}, attrs} <- s, do: {id, attrs})

  @doc "Hat irgendeine attributierte Variable Attribute, für die `pred.(attrs)` gilt?"
  def any_attrs?(s, pred) do
    Enum.any?(s, fn
      {{:attrs, _}, attrs} -> pred.(attrs)
      _ -> false
    end)
  end

  # ---------------------------------------------------------------------
  # Weitere Einträge (Schlüssel der Maschine und einzelner Builtins)
  # ---------------------------------------------------------------------

  def get(s, key, default), do: Map.get(s, key, default)
  def fetch(s, key), do: Map.fetch(s, key)
  def put(s, key, v), do: Map.put(s, key, v)
  def update(s, key, default, fun), do: Map.update(s, key, default, fun)

  # ---------------------------------------------------------------------
  # Choice Points
  # ---------------------------------------------------------------------

  @doc "Zustand für einen Choice Point festhalten"
  def snapshot(s), do: s

  @doc "Festgehaltenen Zustand wiederherstellen"
  def restore(snap), do: snap
end
