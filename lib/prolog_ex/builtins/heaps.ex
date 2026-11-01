defmodule PrologEx.Builtins.Heaps do
  @moduledoc """
  `library(heaps)`: Prioritätswarteschlangen (Min-Heaps), die Vereinigung
  der Bibliotheken von SWI und SICStus:

    * beide: `empty_heap/1`, `add_to_heap/4`, `get_from_heap/4`,
      `delete_from_heap/4`, `heap_size/2`, `heap_to_list/2`,
      `list_to_heap/2`, `min_of_heap/3`, `min_of_heap/5`, `is_heap/1`
    * SWI: `merge_heaps/3`, `singleton_heap/3`
    * SICStus: `portray_heap/1`

  Schlüssel (Prioritäten) nach der Standardordnung, die Werte beliebig.
  Anders als bei SWI und SICStus (beide lassen offen, welches von mehreren
  Paaren mit gleichem Schlüssel zuerst kommt) ist der Heap stabil: gleiche
  Schlüssel kommen in der Reihenfolge, in der sie hinzugefügt wurden
  (`list_to_heap/2`: Reihenfolge der Liste). Nach `merge_heaps/3` gilt das
  je Ausgangsheap.

  `delete_from_heap(+Heap0, ?Key, ?Value, -Heap)` entfernt das erste Paar
  (nach Priorität), das mit `Key-Value` unifiziert – so geht beides:
  SICStus (Schlüssel gegeben, Wert gesucht) und SWI (Wert gegeben,
  Schlüssel gesucht).

  Darstellung: `heap(Größe, Zähler, Baum)` mit einem Leftist-Heap als Baum
  (`t` leer, sonst `t(Key, Nr, Value, Rang, L, R)`; Nr ist die laufende
  Nummer für die Stabilität). Einfügen, Entnehmen und Verschmelzen
  kosten im schlechtesten Fall O(log n) – auch wenn derselbe Heap beim
  Backtracking mehrfach benutzt wird (SWIs Pairing-Heap braucht dann bis
  zu O(n) je Entnahme, weil seine Schranke nur amortisiert gilt).
  `list_to_heap/2` ist linear. In Elixir.

  Fehler: ein Heap als Variable `instantiation_error`, kein Heap
  `type_error(heap, X)`; ein Listenelement ohne `-` `type_error(pair, X)`.
  `is_heap/1` prüft den ganzen Baum und scheitert sonst.
  """
  use PrologEx.Builtin, module: "heaps"
  alias PrologEx.Builtins.Lists
  alias PrologEx.{Error, Order}

  @empty {:atom, "t"}

  defbuiltin "empty_heap", [h] do
    case deref(h) do
      {:var, _} -> {:unify, [{h, heap(0, 0, @empty)}]}
      _ -> elem(heap!(h, subst()), 0) == 0
    end
  end

  defbuiltin "singleton_heap", [h, k, v] do
    s = subst()

    case deref(h) do
      {:var, _} ->
        {:unify, [{h, heap(1, 1, node(k, 0, v, @empty, @empty))}]}

      _ ->
        case heap!(h, s) do
          {1, _, t} ->
            {rk, _, rv, _, _, _} = node!(t, s)
            {:unify, [{k, rk}, {v, rv}]}

          _ ->
            :fail
        end
    end
  end

  defbuiltin "add_to_heap", [h0, k, v, h] do
    s = subst()
    {n, next, t} = heap!(h0, s)
    {:unify, [{h, heap(n + 1, next + 1, merge(t, node(k, next, v, @empty, @empty), s))}]}
  end

  defbuiltin "get_from_heap", [h0, k, v, h] do
    s = subst()

    case heap!(h0, s) do
      {0, _, _} ->
        :fail

      {n, next, t} ->
        {rk, _, rv, _, l, r} = node!(t, s)
        {:unify, [{k, rk}, {v, rv}, {h, heap(n - 1, next, merge(l, r, s))}]}
    end
  end

  # das erste Paar nach Priorität, das mit Key-Value unifiziert
  defbuiltin "delete_from_heap", [h0, k, v, h] do
    s = subst()
    {n, next, t} = heap!(h0, s)
    items = sorted(t, s)

    found =
      items
      |> Enum.with_index()
      |> Enum.find_value(fn {{ik, _, iv}, i} ->
        with {:ok, s1} <- PrologEx.unify(k, ik, s),
             {:ok, s2} <- PrologEx.unify(v, iv, s1),
             do: {i, s2},
             else: (_ -> nil)
      end)

    case found do
      nil ->
        :fail

      {i, s2} ->
        unify_heap(h, heap(n - 1, next, build(List.delete_at(items, i), s)), s2)
    end
  end

  defbuiltin "merge_heaps", [h0, h1, h] do
    s = subst()
    {n0, x0, t0} = heap!(h0, s)
    {n1, x1, t1} = heap!(h1, s)
    {:unify, [{h, heap(n0 + n1, max(x0, x1), merge(t0, t1, s))}]}
  end

  defbuiltin "heap_size", [h, n] do
    {:unify, [{n, elem(heap!(h, subst()), 0)}]}
  end

  defbuiltin "heap_to_list", [h, l] do
    s = subst()
    {_, _, t} = heap!(h, s)
    {:unify, [{l, list(for {k, _, v} <- sorted(t, s), do: mk("-", [k, v]))}]}
  end

  defbuiltin "list_to_heap", [l, h] do
    s = subst()

    items =
      l
      |> items!(s)
      |> Enum.with_index()
      |> Enum.map(fn {e, i} ->
        case PrologEx.unmark_top(PrologEx.walk(e, s)) do
          {:struct, "-", [k, v]} -> {k, i, v}
          {:var, _} -> Error.instantiation!()
          other -> Error.type!("pair", PrologEx.resolve(other, s))
        end
      end)

    n = length(items)
    {:unify, [{h, heap(n, n, build(items, s))}]}
  end

  defbuiltin "min_of_heap", [h, k, v] do
    s = subst()

    case heap!(h, s) do
      {0, _, _} ->
        :fail

      {_, _, t} ->
        {rk, _, rv, _, _, _} = node!(t, s)
        {:unify, [{k, rk}, {v, rv}]}
    end
  end

  # die beiden kleinsten: die Wurzel und die kleinere Wurzel der Kinder
  defbuiltin "min_of_heap", [h, k1, v1, k2, v2] do
    s = subst()
    {_, _, t} = heap!(h, s)

    case node!(t, s) do
      :empty ->
        :fail

      {rk, _, rv, _, l, r} ->
        second =
          case {node!(l, s), node!(r, s)} do
            {:empty, :empty} -> :fail
            {a, :empty} -> a
            {:empty, b} -> b
            {a, b} -> if before?(a, b, s), do: a, else: b
          end

        case second do
          :fail -> :fail
          {sk, _, sv, _, _, _} -> {:unify, [{k1, rk}, {v1, rv}, {k2, sk}, {v2, sv}]}
        end
    end
  end

  # wie SWI und SICStus: ganz prüfen, sonst scheitern
  defbuiltin "is_heap", [h] do
    s = subst()

    case PrologEx.unmark_top(PrologEx.walk(h, s)) do
      {:struct, "heap", [n, x, t]} ->
        with n when is_integer(n) and n >= 0 <- PrologEx.walk(n, s),
             x when is_integer(x) and x >= 0 <- PrologEx.walk(x, s),
             {:ok, ^n, _} <- check(t, nil, s) do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  # SICStus: lesbar ausgeben, nach Priorität: heap{Value->Key, ...}
  defbuiltin "portray_heap", [h] do
    s = subst()
    {_, _, t} = heap!(h, s)
    o = PrologEx.Builtins.Core.writeq_opts()
    show = fn x -> PrologEx.Writer.format(PrologEx.resolve(x, s), o) end

    PrologEx.Builtins.IO.out(
      "heap{" <>
        Enum.map_join(sorted(t, s), ", ", fn {k, _, v} -> show.(v) <> "->" <> show.(k) end) <> "}"
    )

    :ok
  end

  # --- Leftist-Heap -------------------------------------------------------------

  defp heap(n, next, t), do: mk("heap", [n, next, t])

  # Rang = Länge des rechten Rückens; der kürzere Rücken nach rechts
  defp node(k, q, v, a, b, s \\ %{}) do
    {ra, rb} = {rank(a, s), rank(b, s)}

    if ra >= rb,
      do: mk("t", [k, q, v, rb + 1, a, b]),
      else: mk("t", [k, q, v, ra + 1, b, a])
  end

  defp rank(t, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:atom, "t"} -> 0
      {:struct, "t", [_, _, _, r, _, _]} -> PrologEx.walk(r, s)
    end
  end

  defp merge(a, b, s) do
    case {node!(a, s), node!(b, s)} do
      {:empty, _} ->
        b

      {_, :empty} ->
        a

      {{ka, qa, va, _, la, ra} = x, {kb, qb, vb, _, lb, rb} = y} ->
        if before?(x, y, s),
          do: node(ka, qa, va, la, merge(ra, b, s), s),
          else: node(kb, qb, vb, lb, merge(a, rb, s), s)
    end
  end

  # (Schlüssel, Nr) lexikographisch; bei Gleichstand der linke
  defp before?({ka, qa, _, _, _, _}, {kb, qb, _, _, _, _}, s) do
    case Order.compare(ka, kb, s) do
      :lt -> true
      :gt -> false
      :eq -> qa <= qb
    end
  end

  # aus Elementen {k, nr, v}: Einzelheaps paarweise verschmelzen (linear)
  defp build([], _s), do: @empty

  defp build(items, s) do
    items
    |> Enum.map(fn {k, q, v} -> node(k, q, v, @empty, @empty) end)
    |> pairwise(s)
  end

  defp pairwise([t], _s), do: t
  defp pairwise(ts, s), do: ts |> merge_pairs(s, []) |> pairwise(s)

  defp merge_pairs([a, b | rest], s, acc), do: merge_pairs(rest, s, [merge(a, b, s) | acc])
  defp merge_pairs([a], _s, acc), do: Enum.reverse([a | acc])
  defp merge_pairs([], _s, acc), do: Enum.reverse(acc)

  # alle Elemente {k, nr, v}, nach Priorität
  defp sorted(t, s) do
    t
    |> collect(s, [])
    |> Enum.sort_by(fn {k, q, _} -> {Order.key(k, s), q} end)
  end

  defp collect(t, s, acc) do
    case node!(t, s) do
      :empty -> acc
      {k, q, v, _, l, r} -> collect(r, s, collect(l, s, [{k, q, v} | acc]))
    end
  end

  # {:ok, größe, rang}; Heap-Bedingung, Rang und Leftist-Eigenschaft
  defp check(t, parent, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:atom, "t"} ->
        {:ok, 0, 0}

      {:struct, "t", [k, q, v, r, l, rt]} ->
        with q when is_integer(q) <- PrologEx.walk(q, s),
             r when is_integer(r) <- PrologEx.walk(r, s),
             true <- parent == nil or not before?({k, q, v, r, l, rt}, parent, s),
             {:ok, nl, rl} <- check(l, {k, q, v, r, l, rt}, s),
             {:ok, nr, rr} <- check(rt, {k, q, v, r, l, rt}, s),
             true <- rl >= rr and r == rr + 1 do
          {:ok, nl + nr + 1, r}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # --- Lesen und Prüfen ---------------------------------------------------------

  defp heap!(h, s) do
    case PrologEx.unmark_top(PrologEx.walk(h, s)) do
      {:struct, "heap", [n, x, t]} = hp ->
        case {PrologEx.walk(n, s), PrologEx.walk(x, s)} do
          {n, x} when is_integer(n) and is_integer(x) -> {n, x, t}
          _ -> Error.type!("heap", PrologEx.resolve(hp, s))
        end

      {:var, _} ->
        Error.instantiation!()

      other ->
        Error.type!("heap", PrologEx.resolve(other, s))
    end
  end

  defp node!(t, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:atom, "t"} ->
        :empty

      {:struct, "t", [k, q, v, r, l, rt]} = n ->
        case {PrologEx.walk(q, s), PrologEx.walk(r, s)} do
          {q, r} when is_integer(q) and is_integer(r) -> {k, q, v, r, l, rt}
          _ -> Error.type!("heap", PrologEx.resolve(n, s))
        end

      {:var, _} ->
        Error.instantiation!()

      other ->
        Error.type!("heap", PrologEx.resolve(other, s))
    end
  end

  defp items!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  defp unify_heap(h, heap, s2) do
    case PrologEx.unify(h, heap, s2) do
      {:ok, s3} -> {:subst, s3}
      _ -> :fail
    end
  end
end
