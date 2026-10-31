defmodule PrologEx.Builtins.Ordsets do
  @moduledoc """
  `library(ordsets)`: Mengen als geordnete Listen ohne Duplikate (nach der
  Standardordnung der Terme), die Vereinigung der Bibliotheken von SWI
  (= Scryer) und SICStus:

    * SWI/Scryer: `is_ordset/1`, `list_to_ord_set/2`, `ord_add_element/3`,
      `ord_del_element/3`, `ord_selectchk/3`, `ord_intersect/2,3`,
      `ord_intersection/2,3,4`, `ord_disjoint/2`, `ord_subtract/3`,
      `ord_union/2,3,4`, `ord_subset/2`, `ord_empty/1`, `ord_memberchk/2`,
      `ord_symdiff/3`, `ord_seteq/2`
    * dazu aus SICStus: `ord_member/2`, `ord_nonmember/2`,
      `ord_setproduct/3`, `ord_disjoint_union/3`, `ordset_order/3`

  In Elixir (Mischläufe über die Listen mit `PrologEx.Order.compare/3`),
  deterministisch. Semantik wie SWI und SICStus; anders als dort (die bei
  einer Nicht-Liste still scheitern oder Teillisten binden) prüfen die
  Prädikate ihre Mengen wie `sort/2`: Teilliste `instantiation_error`,
  keine Liste `type_error(list, X)` – außer dem Typtest `is_ordset/1`,
  der dann scheitert. Dass die Listen geordnet sind, wird (wie dort) nicht
  geprüft.
  """
  use PrologEx.Builtin, module: "ordsets"
  alias PrologEx.Builtins.Lists
  alias PrologEx.{Error, Order}

  defbuiltin "is_ordset", [t] do
    s = subst()

    case Lists.skip_list(t, s) do
      {_, []} -> strictly_increasing?(Lists.items(t, s), s)
      _ -> false
    end
  end

  defbuiltin "ord_empty", [t] do
    {:unify, [{t, []}]}
  end

  defbuiltin "list_to_ord_set", [l, set] do
    s = subst()
    items = set!(l, s)
    {:unify, [{set, list(Order.sort_unique(items, s))}]}
  end

  defbuiltin "ord_seteq", [a, b] do
    Order.equal?(a, b, subst())
  end

  # --- Elemente -------------------------------------------------------------

  defbuiltin "ord_memberchk", [e, set] do
    member?(e, set!(set, subst()), subst())
  end

  defbuiltin "ord_member", [e, set] do
    member?(e, set!(set, subst()), subst())
  end

  defbuiltin "ord_nonmember", [e, set] do
    not member?(e, set!(set, subst()), subst())
  end

  defbuiltin "ord_add_element", [set, e, set2] do
    s = subst()
    {:unify, [{set2, list(union(set!(set, s), [e], s))}]}
  end

  defbuiltin "ord_del_element", [set, e, set2] do
    s = subst()
    {:unify, [{set2, list(subtract(set!(set, s), [e], s))}]}
  end

  # ord_selectchk(+Item, ?Set1, ?Set2): Set1 gegeben – Item muss darin sein
  # und wird entfernt; sonst Set2 gegeben – Item darf nicht darin sein und
  # wird eingefügt (wie SWI und Scryer, beide Richtungen)
  defbuiltin "ord_selectchk", [item, set1, set2] do
    s = subst()

    case Lists.skip_list(set1, s) do
      {_, {:var, _}} ->
        items = set!(set2, s)

        if member?(item, items, s),
          do: :fail,
          else: {:unify, [{set1, list(union(items, [item], s))}]}

      _ ->
        items = set!(set1, s)

        if member?(item, items, s),
          do: {:unify, [{set2, list(subtract(items, [item], s))}]},
          else: :fail
    end
  end

  # --- Zwei Mengen ----------------------------------------------------------

  defbuiltin "ord_union", [a, b, u] do
    s = subst()
    {:unify, [{u, list(union(set!(a, s), set!(b, s), s))}]}
  end

  # ord_union(+Alt, +Neu, -Vereinigung, -WirklichNeu): WirklichNeu = Neu \ Alt
  defbuiltin "ord_union", [a, b, u, new] do
    s = subst()
    {xs, ys} = {set!(a, s), set!(b, s)}
    {:unify, [{u, list(union(xs, ys, s))}, {new, list(subtract(ys, xs, s))}]}
  end

  defbuiltin "ord_intersection", [a, b, i] do
    s = subst()
    {:unify, [{i, list(intersection(set!(a, s), set!(b, s), s))}]}
  end

  # veraltet in SWI, gleich ord_intersection/3
  defbuiltin "ord_intersect", [a, b, i] do
    s = subst()
    {:unify, [{i, list(intersection(set!(a, s), set!(b, s), s))}]}
  end

  # ord_intersection(+S1, +S2, -Schnitt, -Differenz): Differenz = S2 \ S1
  defbuiltin "ord_intersection", [a, b, i, d] do
    s = subst()
    {xs, ys} = {set!(a, s), set!(b, s)}
    {:unify, [{i, list(intersection(xs, ys, s))}, {d, list(subtract(ys, xs, s))}]}
  end

  defbuiltin "ord_subtract", [a, b, d] do
    s = subst()
    {:unify, [{d, list(subtract(set!(a, s), set!(b, s), s))}]}
  end

  defbuiltin "ord_symdiff", [a, b, d] do
    s = subst()
    {:unify, [{d, list(symdiff(set!(a, s), set!(b, s), s))}]}
  end

  defbuiltin "ord_subset", [a, b] do
    s = subst()
    subset?(set!(a, s), set!(b, s), s)
  end

  defbuiltin "ord_disjoint", [a, b] do
    s = subst()
    not intersect?(set!(a, s), set!(b, s), s)
  end

  defbuiltin "ord_intersect", [a, b] do
    s = subst()
    intersect?(set!(a, s), set!(b, s), s)
  end

  # SICStus: Vereinigung nur, wenn die Mengen disjunkt sind
  defbuiltin "ord_disjoint_union", [a, b, u] do
    s = subst()
    {xs, ys} = {set!(a, s), set!(b, s)}

    if intersect?(xs, ys, s),
      do: :fail,
      else: {:unify, [{u, list(union(xs, ys, s))}]}
  end

  # SICStus: geordnete Menge aller Paare X-Y (X aus S1, Y aus S2)
  defbuiltin "ord_setproduct", [a, b, p] do
    s = subst()
    {xs, ys} = {set!(a, s), set!(b, s)}
    {:unify, [{p, list(for(x <- xs, y <- ys, do: mk("-", [x, y])))}]}
  end

  # SICStus: <, = oder >, wenn S1 Teilmenge, gleich oder Obermenge von S2;
  # sonst scheitert es
  defbuiltin "ordset_order", [a, b, rel] do
    s = subst()
    {xs, ys} = {set!(a, s), set!(b, s)}

    case {subset?(xs, ys, s), subset?(ys, xs, s)} do
      {true, true} -> {:unify, [{rel, a("=")}]}
      {true, false} -> {:unify, [{rel, a("<")}]}
      {false, true} -> {:unify, [{rel, a(">")}]}
      _ -> :fail
    end
  end

  # --- Listen von Mengen ----------------------------------------------------

  defbuiltin "ord_union", [sets, u] do
    s = subst()
    all = sets |> set!(s) |> Enum.flat_map(&set!(&1, s))
    {:unify, [{u, list(Order.sort_unique(all, s))}]}
  end

  # Schnitt einer nicht leeren Liste von Mengen (leere Liste: scheitert,
  # wie SWI; SICStus verlangt sie nicht leer); die kürzeste zuerst
  defbuiltin "ord_intersection", [sets, i] do
    s = subst()

    case sets |> set!(s) |> Enum.map(&set!(&1, s)) |> Enum.sort_by(&length/1) do
      [] -> :fail
      [first | rest] -> {:unify, [{i, list(Enum.reduce(rest, first, &intersection(&2, &1, s)))}]}
    end
  end

  # --- Mischläufe -------------------------------------------------------------

  @doc false
  def union([], ys, _s), do: ys
  def union(xs, [], _s), do: xs

  def union([x | xt] = xs, [y | yt] = ys, s) do
    case Order.compare(x, y, s) do
      :lt -> [x | union(xt, ys, s)]
      :eq -> [x | union(xt, yt, s)]
      :gt -> [y | union(xs, yt, s)]
    end
  end

  @doc false
  def intersection([], _ys, _s), do: []
  def intersection(_xs, [], _s), do: []

  def intersection([x | xt] = xs, [y | yt] = ys, s) do
    case Order.compare(x, y, s) do
      :lt -> intersection(xt, ys, s)
      :eq -> [x | intersection(xt, yt, s)]
      :gt -> intersection(xs, yt, s)
    end
  end

  @doc false
  def subtract([], _ys, _s), do: []
  def subtract(xs, [], _s), do: xs

  def subtract([x | xt] = xs, [y | yt] = ys, s) do
    case Order.compare(x, y, s) do
      :lt -> [x | subtract(xt, ys, s)]
      :eq -> subtract(xt, yt, s)
      :gt -> subtract(xs, yt, s)
    end
  end

  defp symdiff([], ys, _s), do: ys
  defp symdiff(xs, [], _s), do: xs

  defp symdiff([x | xt] = xs, [y | yt] = ys, s) do
    case Order.compare(x, y, s) do
      :lt -> [x | symdiff(xt, ys, s)]
      :eq -> symdiff(xt, yt, s)
      :gt -> [y | symdiff(xs, yt, s)]
    end
  end

  defp subset?([], _ys, _s), do: true
  defp subset?(_xs, [], _s), do: false

  defp subset?([x | xt] = xs, [y | yt], s) do
    case Order.compare(x, y, s) do
      :lt -> false
      :eq -> subset?(xt, yt, s)
      :gt -> subset?(xs, yt, s)
    end
  end

  defp intersect?([], _ys, _s), do: false
  defp intersect?(_xs, [], _s), do: false

  defp intersect?([x | xt] = xs, [y | yt] = ys, s) do
    case Order.compare(x, y, s) do
      :lt -> intersect?(xt, ys, s)
      :eq -> true
      :gt -> intersect?(xs, yt, s)
    end
  end

  # bis zum ersten Element, das nicht kleiner ist
  defp member?(_e, [], _s), do: false

  defp member?(e, [y | yt], s) do
    case Order.compare(y, e, s) do
      :lt -> member?(e, yt, s)
      :eq -> true
      :gt -> false
    end
  end

  defp strictly_increasing?([], _s), do: true
  defp strictly_increasing?([_], _s), do: true

  defp strictly_increasing?([x, y | rest], s),
    do: Order.compare(x, y, s) == :lt and strictly_increasing?([y | rest], s)

  # Menge als Liste ihrer Elemente; geprüft wie bei sort/2
  defp set!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end
end
