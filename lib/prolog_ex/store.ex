defmodule PrologEx.Store do
  @moduledoc """
  Der Bindungsspeicher: alle Zugriffe auf die Substitution laufen über
  dieses Modul. Die Maschine, die Builtins und die Kompaktierung kennen
  nur diese Schnittstelle, nicht die Darstellung.

  Darstellung: ein veränderlicher Speicher im Prozesswörterbuch mit Trail.
  Einträge (Schlüssel im Prozesswörterbuch):

    * `{:var, id} => Term` – Bindung einer Variablen,
    * `{:attrs, id} => %{Modul => Term}` – Attribute der attributierten
      Variablen `{:var, {:attv, id}}`,
    * `:wake => [Var]` – seit dem letzten Wecken gebundene attributierte
      Variablen (neueste vorn), siehe `bind/3` und `take_wake/1`,
    * weitere Schlüssel der Maschine und einzelner Builtins (Ebene von
      call_with_depth_limit/3, backtrackbares Blackboard), siehe `get/3`,
      `put/3`, `update/4`.

  Jede Änderung wird im Trail vermerkt: `{Zeit, Schlüssel, alter Wert}`
  (:undefined: der Schlüssel war neu), neueste vorn. Die Zeit ist ein Zähler, der
  mit jeder Änderung steigt; der Wert `s`, den alle Operationen zurückgeben
  und den die Maschine als "Substitution" durchreicht, ist die Zeit der
  letzten Änderung – eine Marke. Choice Points merken sich die Marke
  (`snapshot/1`), `restore/1` spult den Trail bis zu ihr zurück. Lesen
  (`walk/2`, `attrs/2`, …) ignoriert die Marke und sieht den aktuellen
  Zustand.

  Daraus folgt die Disziplin für alle Aufrufer: eine Operation, die bindet
  und ihr Ergebnis dann doch nicht weiterverwendet (fehlgeschlagene
  Unifikation, Probe-Unifikation, eine Unter-Maschine, deren Bindungen
  nicht nach außen gelangen), muss mit `restore/1` auf ihre Eingangsmarke
  zurück. Und wer nach einer Unter-Maschine weiterrechnet, tut das mit
  deren letzter Marke oder nach `restore/1` – nie mit einer älteren Marke,
  solange jüngere Einträge im Trail stehen.

  Der Speicher gehört dem Prozess; verschachtelte Maschinen (findall,
  Restziele, …) teilen ihn, jede kennt ihre Startmarke (`floor`) und löscht
  beim Aufräumen (`sweep/3`) nur, was sie selbst angelegt hat.
  """

  @trail :prolog_ex_trail

  @type t :: non_neg_integer()

  @doc "Marke des aktuellen Zustands (für eine neue Maschine)"
  @spec new() :: t
  def new, do: top()

  @doc "Zeit der letzten Änderung (0: leer)"
  def top do
    case Process.get(@trail) do
      [{ts, _, _} | _] -> ts
      _ -> 0
    end
  end

  @doc "Anzahl der Trail-Einträge seit der Marke (Statistik)"
  def count_since(mark), do: count_since(Process.get(@trail, []), mark, 0)

  defp count_since([{ts, _, _} | more], mark, n) when ts > mark,
    do: count_since(more, mark, n + 1)

  defp count_since(_, _mark, n), do: n

  # --- die eine Schreibstelle -----------------------------------------------

  # Die Zeit der Änderung liegt über der des Trail-Kopfs und über der
  # Marke s des Aufrufers (nach einem Zurücksetzen kann der Kopf älter sein
  # als die Marke; eine neue Änderung muss trotzdem über allen Marken
  # liegen, die noch jemand hält)
  @compile {:inline, write: 3, erase: 2, stamp: 1}
  defp write(key, val, s) do
    old = :erlang.put(key, val)
    stamp({key, old, s})
  end

  defp erase(key, s) do
    old = :erlang.erase(key)
    stamp({key, old, s})
  end

  # (alter Wert :undefined: der Schlüssel war neu)
  defp stamp({key, old, s}) do
    case :erlang.get(@trail) do
      [{ts, _, _} | _] = tr ->
        ts = max(ts, s) + 1
        :erlang.put(@trail, [{ts, key, old} | tr])
        ts

      _ ->
        :erlang.put(@trail, [{s + 1, key, old}])
        s + 1
    end
  end

  # ---------------------------------------------------------------------
  # Bindungen
  # ---------------------------------------------------------------------

  @doc "Variable bis zu einer freien Variablen oder einem Nicht-Variablen-Term verfolgen"
  # (:erlang.get/1 direkt: Process.get/1 kostet zwei Aufrufe mehr)
  def walk({:var, _} = var, s) do
    case :erlang.get(var) do
      :undefined -> var
      t -> walk(t, s)
    end
  end

  def walk(t, _s), do: t

  @doc "Direkte Bindung einer Variablen (ein Schritt), falls gebunden"
  @spec binding(t, term) :: {:ok, term} | :error
  def binding(_s, {:var, _} = var) do
    case :erlang.get(var) do
      :undefined -> :error
      t -> {:ok, t}
    end
  end

  @doc """
  Einzige Stelle, an der Variablen gebunden werden. Eine attributierte
  Variable wird zusätzlich unter `:wake` vermerkt; die Maschine weckt
  danach ihre Ziele. Für normale Variablen kostet das nichts.
  """
  def bind({:var, {:attv, _}} = var, t, s) do
    s = write(var, t, s)
    write(:wake, [var | Process.get(:wake, [])], s)
  end

  def bind({:var, _} = var, t, s), do: write(var, t, s)

  @doc """
  Bindung setzen, ohne zu wecken (für Variablen, deren Wecken der Aufrufer
  selbst übernimmt oder die er gerade entbunden hatte; für normale
  Variablen dasselbe wie `bind/3`).
  """
  def put_binding(s, {:var, _} = var, t), do: write(var, t, s)

  @doc "Bindung wieder lösen (vorübergehend, etwa während verify_attributes/3 läuft)"
  def unbind(s, {:var, _} = var), do: erase(var, s)

  # ---------------------------------------------------------------------
  # Wecken
  # ---------------------------------------------------------------------

  @doc "Sind seit dem letzten Wecken attributierte Variablen gebunden worden?"
  def wake?(_s), do: Process.get(:wake) != nil

  @doc """
  Die seit dem letzten Wecken gebundenen attributierten Variablen (neueste
  vorn) entnehmen: `{vars, s}` oder `:none`.
  """
  def take_wake(s) do
    case Process.get(:wake) do
      nil -> :none
      ws -> {ws, erase(:wake, s)}
    end
  end

  # ---------------------------------------------------------------------
  # Attribute (nach Kennung der attributierten Variablen)
  # ---------------------------------------------------------------------

  @doc "Attribute der attributierten Variablen `id`: Map Modul => Term (leer, wenn keine)"
  def attrs(_s, id), do: Process.get({:attrs, id}, %{})

  @doc "Attribute, falls vorhanden"
  def fetch_attrs(_s, id) do
    case Process.get({:attrs, id}) do
      nil -> :error
      m -> {:ok, m}
    end
  end

  def has_attrs?(_s, id), do: Process.get({:attrs, id}) != nil

  def put_attrs(s, id, attrs) when is_map(attrs), do: write({:attrs, id}, attrs, s)

  @doc "Attribute mit `fun` ändern, oder `default` einsetzen, wenn es noch keine gibt"
  def update_attrs(s, id, default, fun) do
    key = {:attrs, id}

    case Process.get(key) do
      nil -> write(key, default, s)
      old -> write(key, fun.(old), s)
    end
  end

  @doc """
  Eine normale Variable zu einer attributierten machen: an die neue
  attributierte Variable mit Kennung `id` binden (ohne Wecken) und ihr die
  Attribute geben.
  """
  def attach(s, {:var, _} = var, id, attrs) do
    s = write(var, {:var, {:attv, id}}, s)
    write({:attrs, id}, attrs, s)
  end

  @doc "Kennungen aller attributierten Variablen, die Attribute haben"
  def attv_ids(_s), do: for({{:attrs, id}, _} <- Process.get(), do: id)

  @doc "Alle Attribute: Liste von `{id, attrs}`"
  def all_attrs(_s), do: for({{:attrs, id}, attrs} <- Process.get(), do: {id, attrs})

  @doc "Hat irgendeine attributierte Variable Attribute, für die `pred.(attrs)` gilt?"
  def any_attrs?(_s, pred) do
    Enum.any?(Process.get(), fn
      {{:attrs, _}, attrs} -> pred.(attrs)
      _ -> false
    end)
  end

  # ---------------------------------------------------------------------
  # Weitere Einträge (Schlüssel der Maschine und einzelner Builtins)
  # ---------------------------------------------------------------------

  def get(_s, key, default), do: Process.get(key, default)

  def fetch(_s, key) do
    case Process.get(key) do
      nil -> :error
      v -> {:ok, v}
    end
  end

  def put(s, key, v), do: write(key, v, s)

  def update(s, key, default, fun) do
    case Process.get(key) do
      nil -> write(key, default, s)
      old -> write(key, fun.(old), s)
    end
  end

  # ---------------------------------------------------------------------
  # Choice Points
  # ---------------------------------------------------------------------

  @doc "Zustand für einen Choice Point festhalten: die Marke"
  def snapshot(s), do: s

  @doc "Alle Änderungen nach der Marke zurücknehmen; Ergebnis: die Marke"
  def restore(mark) do
    case Process.get(@trail) do
      [{ts, _, _} | _] = tr when ts > mark ->
        Process.put(@trail, undo(tr, mark))
        mark

      _ ->
        mark
    end
  end

  defp undo([{ts, key, old} | more], mark) when ts > mark do
    if old == :undefined, do: :erlang.erase(key), else: :erlang.put(key, old)
    undo(more, mark)
  end

  defp undo(tr, _mark), do: tr

  @doc """
  Alle Änderungen nach der Marke zurücknehmen und als Protokoll
  zurückgeben, mit dem `reattach/1` sie wieder einspielt (eine aufbewahrte
  Unter-Maschine, deren Bindungen die äußere nicht sehen soll).
  """
  def detach(mark) do
    case Process.get(@trail) do
      [{ts, _, _} | _] = tr when ts > mark ->
        {log, rest} = detach(tr, mark, [])
        Process.put(@trail, rest)
        log

      _ ->
        []
    end
  end

  # log: älteste vorn, Einträge {ts, key, alt, neu}
  defp detach([{ts, key, old} | more], mark, log) when ts > mark do
    new = if old == :undefined, do: :erlang.erase(key), else: :erlang.put(key, old)
    detach(more, mark, [{ts, key, old, new} | log])
  end

  defp detach(rest, _mark, log), do: {log, rest}

  @doc "Ein Protokoll von `detach/1` wieder einspielen"
  def reattach(log) do
    tr =
      Enum.reduce(log, Process.get(@trail, []), fn {ts, key, old, new}, tr ->
        Process.put(key, new)
        [{ts, key, old} | tr]
      end)

    Process.put(@trail, tr)
    :ok
  end

  # ---------------------------------------------------------------------
  # Aufräumen (Kompaktierung)
  # ---------------------------------------------------------------------

  @doc """
  Aufräumen für die Maschine mit Startmarke `floor`: Einträge für
  Schlüssel, die sie selbst angelegt hat (Eintrag mit altem Wert nil nach
  der Marke `opaque`) und die nicht in `live` (Map erreichbarer Schlüssel)
  stehen, verschwinden samt Schlüssel. Zwischen zwei aufeinanderfolgenden
  Marken (`marks`: die Choice Points, aufsteigend) setzt niemand zurück;
  dort bleibt je Schlüssel nur der älteste Eintrag – sein alter Wert ist,
  was ein Zurücksetzen auf die untere Marke wiederherstellen muss.
  Ergebnis: Anzahl der verbleibenden Trail-Einträge seit `floor`.
  """
  def sweep(floor, live, opaque, marks) do
    tr = Process.get(@trail, [])
    {prefix, rest} = split(tr, floor, [])
    bound = max(floor, opaque)

    # von dieser Maschine angelegt: der erste Eintrag des Schlüssels seit
    # floor hat alten Wert :undefined (ein später neu angelegter Schlüssel, den es
    # bei floor schon gab, zählt nicht – sein alter Wert muss zurückkommen)
    {created, _} =
      Enum.reduce(prefix, {%{}, %{}}, fn {ts, key, old}, {created, seen} ->
        cond do
          is_map_key(seen, key) ->
            {created, seen}

          old == :undefined and ts > bound ->
            {Map.put(created, key, true), Map.put(seen, key, true)}

          true ->
            {created, Map.put(seen, key, true)}
        end
      end)

    dead = for {key, _} <- created, not is_map_key(live, key), into: %{}, do: {key, true}

    for {key, _} <- dead, do: Process.delete(key)

    {kept, _, _} =
      Enum.reduce(prefix, {[], %{}, marks}, fn {ts, key, _} = e, {kept, seen, marks} ->
        # neues Intervall: ab der nächsten Marke zählt der Schlüssel neu
        {seen, marks} = next_interval(ts, seen, marks)

        cond do
          is_map_key(dead, key) -> {kept, seen, marks}
          is_map_key(seen, key) -> {kept, seen, marks}
          true -> {[e | kept], Map.put(seen, key, true), marks}
        end
      end)

    Process.put(@trail, kept ++ rest)
    length(kept)
  end

  defp next_interval(ts, _seen, [m | more]) when ts > m, do: next_interval(ts, %{}, more)
  defp next_interval(_ts, seen, marks), do: {seen, marks}

  # Einträge über der Marke (umgekehrt, also älteste vorn – der Trail hat
  # die neuesten vorn) und der Rest
  defp split([{ts, _, _} = e | more], mark, acc) when ts > mark, do: split(more, mark, [e | acc])
  defp split(rest, _mark, acc), do: {acc, rest}

  # ---------------------------------------------------------------------
  # Sichern und Laden (Sitzung des Toplevels, Vorausrechnen in einem
  # anderen Prozess)
  # ---------------------------------------------------------------------

  @doc "Der ganze Speicher samt Trail als Liste von Paaren"
  def dump do
    for {k, _} = e <- Process.get(), store_key?(k), do: e
  end

  @doc "Einen mit `dump/0` gesicherten Speicher in diesen Prozess laden"
  def load(entries), do: Enum.each(entries, fn {k, v} -> Process.put(k, v) end)

  @doc false
  def store_key?({:var, _}), do: true
  def store_key?({:attrs, _}), do: true
  def store_key?(:wake), do: true
  def store_key?(@trail), do: true
  # Ebene von call_with_depth_limit/3, backtrackbares Blackboard
  def store_key?(:"$depth"), do: true
  def store_key?(:"$bb_b"), do: true
  def store_key?(_), do: false
end
