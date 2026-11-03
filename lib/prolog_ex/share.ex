defmodule PrologEx.Share do
  @moduledoc """
  Geteilte Teilterme erkennen: ein Memo für Durchläufe über Terme
  (Kompaktieren, Kopieren, Auflösen, ...), damit ein Teilterm, der an
  mehreren Stellen steht (ein DAG wie `T1 = f(T0, T0)` oder die Knoten
  eines BDDs), nur einmal bearbeitet wird. Ohne das wird ein DAG Pfad für
  Pfad abgelaufen – bei k Stufen 2^k-mal.

  Die BEAM kennt keine Tabelle über Speicheradressen. Das Memo ordnet
  deshalb nach {Funktor, Stelligkeit, erstes Argument falls atomar} (bei
  Listenzellen nur ein Schlüssel) und erkennt einen Treffer an der
  physischen Identität (`:erts_debug.same/2`). Je Schlüssel bleiben die
  letzten `@bucket` Einträge, ohne atomares erstes Argument die letzten
  `@bucket_nokey` (dort ist der geteilte Teilterm meist der zuletzt
  bearbeitete). Das ist eine Heuristik für die Geschwindigkeit, nie für
  das Ergebnis: Ein Treffer verlangt Identität und liefert, was die
  Rechnung ergäbe; ohne Treffer wird gerechnet.

  Ins Memo kommen nur Strukturen mit einem zusammengesetzten Argument
  (nur sie können einen DAG aufbauen; eine mit lauter atomaren Argumenten
  kostet bei jedem Besuch nur ihre Stelligkeit).

  Das Memo ist eine gewöhnliche Map (die Schlüssel sind Tupel mit
  `:"$s"` vorn, dazu der Zähler `:"$n"`), so dass ein Durchlauf es in
  seiner vorhandenen Map mitführen kann. Es wirkt erst nach den ersten
  `@start` Strukturen eines Durchlaufs: Kleine Terme – fast alle – zahlen
  so nur den Zähler, und die Mehrarbeit ohne Memo ist auf `@start`
  Strukturen begrenzt (danach wird jeder Teilterm nur einmal bearbeitet).
  Fehlt `:erts_debug.same/2`, findet `get/2` nie etwas.
  """

  @bucket 8
  @bucket_nokey 2
  # die ersten @start Strukturen eines Durchlaufs ohne Memo: kleine Terme
  # (fast alle) zahlen so nur einen Zähler; die Mehrarbeit ohne Memo ist
  # damit auf @start Strukturen begrenzt
  @start 32
  @available Code.ensure_loaded?(:erts_debug) and function_exported?(:erts_debug, :same, 2)

  if @available do
    @doc "Das gemerkte Ergebnis für genau diesen (physischen) Term: {:ok, v} oder :error"
    def get(memo, t) do
      if not inner?(t) or Map.get(memo, :"$n", 0) < @start, do: :error, else: lookup(memo, t)
    end

    defp lookup(memo, t) do
      case Map.get(memo, key(t)) do
        nil ->
          :error

        bucket ->
          case Enum.find(bucket, fn {orig, _} -> :erts_debug.same(orig, t) end) do
            {_, v} -> {:ok, v}
            nil -> :error
          end
      end
    end

    @doc "Ergebnis v für den Term t merken"
    def put(memo, t, v) do
      if inner?(t) do
        case Map.get(memo, :"$n", 0) do
          n when n < @start -> Map.put(memo, :"$n", n + 1)
          _ -> store(memo, t, v)
        end
      else
        memo
      end
    end

    defp store(memo, t, v) do
      k = key(t)
      n = if elem(k, 3) == nil, do: @bucket_nokey, else: @bucket
      Map.put(memo, k, Enum.take([{t, v} | Map.get(memo, k, [])], n))
    end

    @doc "Wie get/2, für ein Paar von Termen (Vergleichen, Unifizieren)"
    def get2(memo, a, b) do
      if not inner?(a) or Map.get(memo, :"$n", 0) < @start do
        :error
      else
        case Map.get(memo, pkey(a)) do
          nil ->
            :error

          bucket ->
            case Enum.find(bucket, fn {a0, b0, _} ->
                   :erts_debug.same(a0, a) and :erts_debug.same(b0, b)
                 end) do
              {_, _, v} -> {:ok, v}
              nil -> :error
            end
        end
      end
    end

    @doc "Wie put/3, für ein Paar von Termen"
    def put2(memo, a, b, v) do
      if inner?(a) do
        case Map.get(memo, :"$n", 0) do
          n when n < @start ->
            Map.put(memo, :"$n", n + 1)

          _ ->
            k = pkey(a)
            n = if elem(k, 3) == nil, do: @bucket_nokey, else: @bucket
            Map.put(memo, k, Enum.take([{a, b, v} | Map.get(memo, k, [])], n))
        end
      else
        memo
      end
    end

    @doc "Sind a und b physisch derselbe Term? (O(1))"
    def same?(a, b), do: :erts_debug.same(a, b)
  else
    def get(_memo, _t), do: :error
    def put(memo, _t, _v), do: memo
    def get2(_memo, _a, _b), do: :error
    def put2(memo, _a, _b, _v), do: memo
    def same?(_a, _b), do: false
  end

  # Nur Strukturen mit einem zusammengesetzten Argument kommen ins Memo:
  # eine mit lauter atomaren Argumenten (Zahlen, Atome, Variablen) kostet
  # bei jedem Besuch nur ihre Stelligkeit und kann nichts aufblähen – so
  # zahlen etwa Paare X-Y oder Datensätze nichts. Listenzellen: der Kopf
  # zusammengesetzt (die Aufrufer merken sich nur solche).
  defp inner?({tag, _f, args}) when tag in [:struct, :gstruct], do: Enum.any?(args, &compound?/1)
  defp inner?({:glist, _}), do: true
  defp inner?([_ | _]), do: true
  defp inner?(_), do: false

  defp compound?({:atom, _}), do: false
  defp compound?({:var, _}), do: false
  defp compound?(t) when is_tuple(t), do: true
  defp compound?([_ | _]), do: true
  defp compound?(_), do: false

  defp key({:struct, f, args}), do: {:"$s", f, length(args), first(args)}
  defp key({:gstruct, f, args}), do: {:"$s", f, length(args), first(args)}
  defp key([h | _]), do: {:"$s", ".", 2, first([h])}
  defp key({:glist, l}), do: {:"$s", ".", 2, first(l)}

  defp pkey(t), do: put_elem(key(t), 0, :"$p")

  defp first([a | _]) when is_integer(a) or is_atom(a), do: a
  defp first([{:atom, _} = a | _]), do: a
  defp first(_), do: nil
end
