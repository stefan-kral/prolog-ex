defmodule PrologEx.Builtins.Lists do
  @moduledoc """
  Listenprädikate: append/3, length/2, member/2, numlist/2,3, between/3
  (alle vom Benutzer überschreibbar), dazu die Hilfsfunktion `skip_list/2`.

  ## member/2, between/3

  Lösungen als lazy Liste (siehe `PrologEx.Builtin`): die nächste Lösung
  entsteht erst beim Backtracking, und nach der letzten bleibt kein Choice
  Point. member/2 läuft die Listenzellen entlang; trifft es auf einen
  ungebundenen Rest, übernimmt die klassische Definition `$member/2`
  (erzeugt dann wie üblich `[X|_]`, `[_,X|_]`, ...). between/3 erlaubt
  `inf`/`infinite` als obere Grenze; ist X gebunden, wird nur geprüft.

  ## numlist/3, numlist/2

  `numlist(Lo, Hi, L)`: L = [Lo, ..., Hi] (scheitert bei Lo > Hi), in
  Elixir gebaut und gleich als ground Liste markiert.
  `numlist(N, L)` ist in Prolog definiert: `numlist(N, L) :- numlist(1, N, L).`

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

    n = v("N")

    [
      fact(s("$append", [[], l, l])),
      rule(s("$append", [[h | t], l, [h | r]]), [s("$append", [t, l, r])]),
      rule(s("numlist", [n, l]), [s("numlist", [1, n, l])]),
      fact(s("$member", [h, [h | v("_")]])),
      rule(s("$member", [h, [v("_") | t]]), [s("$member", [h, t])])
    ]
  end

  defbuiltin "append", [x, y, z], protected: false, helpers: [{"$append", 3}] do
    case prefix(x, subst()) do
      {:ok, front} -> {:unify, [{z, join(front, y, subst())}]}
      :partial -> {:call, mk("$append", [x, y, z])}
    end
  end

  defbuiltin "numlist", [lo, hi, l], protected: false do
    case {deref(lo), deref(hi)} do
      {a, b} when is_integer(a) and is_integer(b) and a > b -> :fail
      {a, b} when is_integer(a) and is_integer(b) -> {:unify, [{l, {:glist, Enum.to_list(a..b)}}]}
      {{:var, _}, _} -> raise "instantiation_error"
      {_, {:var, _}} -> raise "instantiation_error"
      {a, b} -> raise "type_error(integer, #{format(if is_integer(a), do: b, else: a)})"
    end
  end

  defbuiltin "member", [x, l], nondet: true, protected: false, helpers: [{"$member", 2}] do
    member_cells(x, deref(l), subst())
  end

  defbuiltin "between", [lo, hi, x], nondet: true, protected: false do
    l = int_arg(deref(lo))

    h =
      case deref(hi) do
        {:atom, inf} when inf in ["inf", "infinite"] -> :inf
        other -> int_arg(other)
      end

    case deref(x) do
      n when is_integer(n) -> if n >= l and (h == :inf or n <= h), do: [:ok], else: []
      {:var, _} -> between_from(l, h, x)
      other -> raise "type_error(integer, #{format(other)})"
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

  # member/2: eine Lösung pro Zelle; ist der Rest [], ist es die letzte
  # Weiter geht es nur, wenn der Rest eine Liste oder ungebunden ist;
  # sonst ([] oder z. B. [a|b]) ist dies die letzte Lösung
  defp member_cells(x, [h | t], s) do
    case PrologEx.walk(t, s) do
      next when is_list(next) and next != [] ->
        [{:unify, [{x, h}]} | fn -> member_cells(x, next, s) end]

      {tag, _} = next when tag in [:glist, :var] ->
        [{:unify, [{x, h}]} | fn -> member_cells(x, next, s) end]

      _end ->
        [{:unify, [{x, h}]}]
    end
  end

  defp member_cells(x, {:glist, cells}, _s), do: member_raw(x, cells)
  defp member_cells(x, {:var, _} = rest, _s), do: [{:call, mk("$member", [x, rest])}]
  defp member_cells(_x, _not_a_list, _s), do: []

  # innerhalb einer glist: rohe Zellen, keine Variablen
  defp member_raw(x, [h | [_ | _] = t]), do: [{:unify, [{x, h}]} | fn -> member_raw(x, t) end]
  defp member_raw(x, [h | _end]), do: [{:unify, [{x, h}]}]

  # between/3: L, L+1, ..., H; bei H = :inf unendlich (Integer < Atom)
  defp between_from(l, h, _x) when h != :inf and l > h, do: []
  defp between_from(h, h, x), do: [{:unify, [{x, h}]}]
  defp between_from(l, h, x), do: [{:unify, [{x, l}]} | fn -> between_from(l + 1, h, x) end]

  defp int_arg(n) when is_integer(n), do: n
  defp int_arg({:var, _}), do: raise("instantiation_error")
  defp int_arg(other), do: raise("type_error(integer, #{format(other)})")

  defp fresh_list(0), do: []
  defp fresh_list(k), do: Enum.map(1..k, fn _ -> fresh_var() end)
end
