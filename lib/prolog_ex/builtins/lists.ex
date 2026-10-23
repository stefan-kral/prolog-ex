defmodule PrologEx.Builtins.Lists do
  @moduledoc """
  Listenprädikate: append/3 und length/2 (beide vom Benutzer
  überschreibbar), dazu die Hilfsfunktion `skip_list/2`.

  ## append/3 – hybrid

  Ist das erste Argument eine echte Liste (Ende `[]`), wird das Ergebnis
  direkt in Elixir gebaut und unifiziert – deterministisch, ohne Choice
  Points. Ist das erste Argument eine markierte ground Liste, übernimmt
  `++` der BEAM die Arbeit. Sonst (erstes Argument offen oder keine Liste)
  läuft die klassische Definition `$append/3` aus der Prolog-Bibliothek,
  z. B. für `append(X, Y, [1,2,3])`.

  ## length/2

  Über `skip_list/2`: Länge des gebundenen Präfixes und der Rest.

    * Rest `[]`: echte Liste, `Len` wird mit der Länge unifiziert
    * Rest ungebunden, `Len` Zahl: Rest wird zu einer Liste frischer
      Variablen passender Länge (deterministisch)
    * Rest und `Len` ungebunden: zählt Längen 0, 1, 2, ... auf (lazy)
  """
  use PrologEx.Builtin

  @doc false
  def library do
    import PrologEx, only: [s: 2, v: 1, fact: 1, rule: 2]
    [h, t, l, r] = Enum.map(~w(H T L R), &v/1)

    [
      fact(s("$append", [[], l, l])),
      rule(s("$append", [[h | t], l, [h | r]]), [s("$append", [t, l, r])])
    ]
  end

  defbuiltin "append", [x, y, z], protected: false do
    case prefix(x, subst()) do
      {:ok, front} -> {:unify, [{z, join(front, y, subst())}]}
      :partial -> {:call, mk("$append", [x, y, z])}
    end
  end

  defbuiltin "length", [l, len], nondet: true, protected: false do
    {n, rest} = skip_list(l, subst())

    case rest do
      [] ->
        [{:unify, [{len, n}]}]

      {:var, _} ->
        case deref(len) do
          k when is_integer(k) and k >= n ->
            [{:unify, [{rest, fresh_list(k - n)}]}]

          k when is_integer(k) and k >= 0 ->
            []

          k when is_integer(k) ->
            raise "domain_error(not_less_than_zero, #{k})"

          {:var, _} ->
            Stream.map(Stream.iterate(0, &(&1 + 1)), fn i ->
              {:unify, [{rest, fresh_list(i)}, {len, n + i}]}
            end)

          other ->
            raise "type_error(integer, #{format(other)})"
        end

      _ ->
        raise "type_error(list, #{format(resolve(l))})"
    end
  end

  # ---------------------------------------------------------------------

  @doc """
  Läuft die Liste entlang, solange Zellen gebunden sind.
  Liefert `{länge_des_präfixes, rest}`; `rest` ist dereferenziert:
  `[]` (echte Liste), eine Variable (offene Liste) oder etwas anderes.
  """
  def skip_list(t, subst), do: skip(PrologEx.walk(t, subst), subst, 0)

  defp skip([_ | t], subst, n), do: skip(PrologEx.walk(t, subst), subst, n + 1)
  defp skip({:glist, l}, _subst, n), do: skip_raw(l, n)
  defp skip(other, _subst, n), do: {n, other}

  # Innerhalb einer glist: rohe Zellen ohne Variablen
  defp skip_raw([_ | t], n), do: skip_raw(t, n + 1)
  defp skip_raw(t, n), do: {n, t}

  @doc "Elemente einer echten Liste (Elemente nicht dereferenziert)."
  def items(t, subst) do
    case PrologEx.walk(t, subst) do
      [h | tl] -> [h | items(tl, subst)]
      {:glist, l} -> l
      [] -> []
    end
  end

  # Vorderteil für append: {:ok, {:glist, l}} | {:ok, {:items, [..]}} | :partial
  defp prefix(x, subst) do
    case PrologEx.walk(x, subst) do
      {:glist, l} -> if proper?(l), do: {:ok, {:glist, l}}, else: :partial
      _ -> collect(x, subst, [])
    end
  end

  defp collect(x, subst, acc) do
    case PrologEx.walk(x, subst) do
      [] -> {:ok, {:items, Enum.reverse(acc)}}
      [h | t] -> collect(t, subst, [h | acc])
      {:glist, l} -> if proper?(l), do: {:ok, {:items, Enum.reverse(acc, l)}}, else: :partial
      _ -> :partial
    end
  end

  defp proper?([_ | t]), do: proper?(t)
  defp proper?(t), do: t == []

  defp join({:glist, l}, y, subst) do
    case PrologEx.walk(y, subst) do
      [] -> {:glist, l}
      {:glist, ly} -> {:glist, l ++ ly}
      _ -> l ++ y
    end
  end

  defp join({:items, items}, y, _subst), do: PrologEx.list(items, y)

  defp fresh_list(0), do: []
  defp fresh_list(k), do: Enum.map(1..k, fn _ -> fresh_var() end)
end
