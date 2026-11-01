defmodule PrologEx.Builtins.RbtreePrims do
  @moduledoc """
  Kern von `library(rbtrees)` (`priv/library/rbtrees.pl`): Rot-Schwarz-
  Bäume in der Darstellung von SWI-Prolog (Vitor Santos Costa, Jan
  Wielemaker u. a.), die Operationen in Elixir.

  Ein Baum ist `t(Nil, Wurzel)`; `Nil` ist der gemeinsame leere Knoten
  `black('', _, _, '')`, jeder andere Knoten `red(L, K, V, R)` oder
  `black(L, K, V, R)`. Einfügen (Cormen u. a.), Löschen, der Aufbau aus
  geordneten Listen und alle Umbauten folgen SWIs Code Klausel für
  Klausel; die Bäume sind Term für Term dieselben (ein Test vergleicht
  das). Schlüssel nach der Standardordnung (`compare/3`).

  Die Prädikate scheitern, wo SWIs scheitern; ein Baum als Variable ist
  ein `instantiation_error`, etwas anderes als ein Baum
  `type_error(rbtree, X)` (SWI: keine passende Regel).
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.Lists
  alias PrologEx.{Error, Order}

  @leaf {:atom, ""}

  # --- Abfragen ---------------------------------------------------------------

  defbuiltin "$rb_lookup", [key, val, t] do
    s = subst()
    {_, root} = tree!(t, s)

    case lookup(key, root, s) do
      {:ok, v} -> {:unify, [{val, v}]}
      :none -> :fail
    end
  end

  defbuiltin "$rb_min", [t, key, val] do
    s = subst()
    {_, root} = tree!(t, s)

    case extreme(root, 1, s) do
      {k, v} -> {:unify, [{key, k}, {val, v}]}
      :none -> :fail
    end
  end

  defbuiltin "$rb_max", [t, key, val] do
    s = subst()
    {_, root} = tree!(t, s)

    case extreme(root, 4, s) do
      {k, v} -> {:unify, [{key, k}, {val, v}]}
      :none -> :fail
    end
  end

  # wie SWI: Key muss im Baum sein
  defbuiltin "$rb_next", [t, key, next, val] do
    s = subst()
    {_, root} = tree!(t, s)

    case neighbour(root, key, :next, nil, s) do
      {k, v} -> {:unify, [{next, k}, {val, v}]}
      :none -> :fail
    end
  end

  defbuiltin "$rb_previous", [t, key, prev, val] do
    s = subst()
    {_, root} = tree!(t, s)

    case neighbour(root, key, :previous, nil, s) do
      {k, v} -> {:unify, [{prev, k}, {val, v}]}
      :none -> :fail
    end
  end

  defbuiltin "$rb_size", [t, n] do
    s = subst()
    {_, root} = tree!(t, s)
    {:unify, [{n, length(pairs(root, s, []))}]}
  end

  defbuiltin "$rb_visit", [t, l] do
    s = subst()
    {_, root} = tree!(t, s)
    {:unify, [{l, list(for {k, v} <- pairs(root, s, []), do: mk("-", [k, v]))}]}
  end

  defbuiltin "$rb_keys", [t, l] do
    s = subst()
    {_, root} = tree!(t, s)
    {:unify, [{l, list(for {k, _} <- pairs(root, s, []), do: k)}]}
  end

  defbuiltin "$rb_visit_range", [t, min, max, l] do
    s = subst()
    {_, root} = tree!(t, s)
    {:unify, [{l, list(for {k, v} <- range(root, min, max, s, []), do: mk("-", [k, v]))}]}
  end

  # wie SWI: alle Paare der Reihe nach, mit Unifikation
  defbuiltin "$rb_in", [key, val, t], nondet: true do
    s = subst()
    {_, root} = tree!(t, s)
    for {k, v} <- pairs(root, s, []), do: {:unify, [{key, k}, {val, v}]}
  end

  # Werte in Präordnung (Reihenfolge der Aufrufe in SWIs rb_map/2,3)
  defbuiltin "$rb_values_pre", [t, l] do
    s = subst()
    {_, root} = tree!(t, s)
    {:unify, [{l, list(pre(root, s, []) |> Enum.reverse())}]}
  end

  # derselbe Baum mit neuen Werten, in Präordnung (pre) oder Inordnung (in)
  defbuiltin "$rb_set_values", [t, order, l, nt] do
    s = subst()
    {nil_, root} = tree!(t, s)
    vals = Lists.items(l, s)

    {new, []} =
      case deref(order) do
        {:atom, "pre"} -> set_pre(root, vals, s)
        {:atom, "in"} -> set_in(root, vals, s)
      end

    {:unify, [{nt, mk("t", [nil_, new])}]}
  end

  # derselbe Baum mit frischen Werten; Paare K-NeuerWert in Inordnung
  defbuiltin "$rb_clone", [t, nt, ps] do
    s = subst()
    {nil_, root} = tree!(t, s)
    {new, acc} = clone(root, s, [])
    pairs = acc |> Enum.reverse() |> Enum.map(fn {k, v} -> mk("-", [k, v]) end)
    {:unify, [{nt, mk("t", [nil_, new])}, {ps, list(pairs)}]}
  end

  # wie SWI: ganz prüfen (Farben, Schwarzhöhe, Ordnung), sonst scheitern
  defbuiltin "$rb_is_rbtree", [t] do
    s = subst()

    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:struct, "t", [nil_, root]} ->
        Order.equal?(nil_, root, s) or check(root, s)

      _ ->
        false
    end
  end

  # --- Ändern ------------------------------------------------------------------

  defbuiltin "$rb_insert", [t0, key, val, t] do
    s = subst()
    {nil_, root} = tree!(t0, s)
    {new, _} = insert(root, key, val, nil_, false, s)
    {:unify, [{t, mk("t", [nil_, fix_root(new, s)])}]}
  end

  defbuiltin "$rb_insert_new", [t0, key, val, t] do
    s = subst()
    {nil_, root} = tree!(t0, s)

    case insert(root, key, val, nil_, true, s) do
      :exists -> :fail
      {new, _} -> {:unify, [{t, mk("t", [nil_, fix_root(new, s)])}]}
    end
  end

  defbuiltin "$rb_update", [t0, key, old, val, t] do
    s = subst()
    {nil_, root} = tree!(t0, s)

    case update(root, key, val, s) do
      {:ok, v0, new} -> {:unify, [{old, v0}, {t, mk("t", [nil_, new])}]}
      :none -> :fail
    end
  end

  defbuiltin "$rb_delete", [t0, key, val, t] do
    s = subst()
    {nil_, root} = tree!(t0, s)

    run(fn ->
      {v, new, _} = delete(root, key, s)
      {:unify, [{val, v}, {t, mk("t", [nil_, new])}]}
    end)
  end

  defbuiltin "$rb_del_min", [t0, key, val, t] do
    s = subst()
    {nil_, root} = tree!(t0, s)

    run(fn ->
      {k, v, new, _} = del_min(root, nil_, s)
      {:unify, [{key, k}, {val, v}, {t, mk("t", [nil_, new])}]}
    end)
  end

  defbuiltin "$rb_del_max", [t0, key, val, t] do
    s = subst()
    {nil_, root} = tree!(t0, s)

    run(fn ->
      {k, v, new, _} = del_max(root, nil_, s)
      {:unify, [{key, k}, {val, v}, {t, mk("t", [nil_, new])}]}
    end)
  end

  # Aufbau aus einer nach Schlüsseln aufsteigenden Liste (wie SWI); sort:
  # erst sortieren (list_to_rbtree/2). Doppelte Schlüssel:
  # domain_error(unique_key_pairs, L), ungeordnet
  # domain_error(key_ordered_pairs, L) (wie library(assoc))
  defbuiltin "$rb_from_list", [l, sort, t] do
    s = subst()
    sorting = deref(sort) == {:atom, "true"}
    items = items!(l, s)
    items = if sorting, do: Order.sort_unique(items, s), else: items

    ps =
      Enum.map(items, fn e ->
        case PrologEx.unmark_top(PrologEx.walk(e, s)) do
          {:struct, "-", [k, v]} -> {k, v}
          {:var, _} -> Error.instantiation!()
          other -> Error.type!("pair", PrologEx.resolve(other, s))
        end
      end)

    case strictly_ascending?(ps, s) do
      true -> :ok
      :dup when sorting -> Error.domain!("unique_key_pairs", PrologEx.resolve(l, s))
      _ -> Error.domain!("key_ordered_pairs", PrologEx.resolve(l, s))
    end

    nil_ = mk("black", [@leaf, fresh_var(), fresh_var(), @leaf])
    arr = List.to_tuple(ps)
    n = tuple_size(arr)

    root =
      case n do
        0 -> nil_
        1 -> mk("black", [nil_, elem(elem(arr, 0), 0), elem(elem(arr, 0), 1), nil_])
        _ -> construct(1, n, arr, trunc(:math.log(n) / :math.log(2)), nil_)
      end

    {:unify, [{t, mk("t", [nil_, root])}]}
  end

  # --- Lesen -------------------------------------------------------------------

  defp tree!(t, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:struct, "t", [nil_, root]} -> {nil_, root}
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("rbtree", PrologEx.resolve(other, s))
    end
  end

  # :leaf ('') oder {farbe, l, k, v, r}
  defp node(t, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:atom, ""} -> :leaf
      {:struct, "black", [l, k, v, r]} -> {:black, l, k, v, r}
      {:struct, "red", [l, k, v, r]} -> {:red, l, k, v, r}
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("rbtree", PrologEx.resolve(other, s))
    end
  end

  # der leere Knoten: black('', _, _, _)
  defp nil?({:black, l, _, _, _}, s), do: node(l, s) == :leaf
  defp nil?(_, _s), do: false
  defp nil_t?(t, s), do: nil?(node(t, s), s)

  defp black?(t, s), do: match?({:black, _, _, _, _}, node(t, s))
  defp red?(t, s), do: match?({:red, _, _, _, _}, node(t, s))

  defp b(c, l, k, v, r), do: mk(Atom.to_string(c), [l, k, v, r])

  defp lookup(key, t, s) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      :none
    else
      {_, l, k, v, r} = d

      case Order.compare(k, key, s) do
        :gt -> lookup(key, l, s)
        :lt -> lookup(key, r, s)
        :eq -> {:ok, v}
      end
    end
  end

  # kleinster (Seite 1, links) bzw. größter (Seite 4, rechts) Eintrag
  defp extreme(t, side, s) do
    case node(t, s) do
      :leaf ->
        :none

      {_, l, k, v, r} = d ->
        child = if side == 1, do: l, else: r

        cond do
          nil?(d, s) and side == 1 -> :none
          node(child, s) == :leaf -> :none
          nil_t?(child, s) -> {k, v}
          true -> extreme(child, side, s)
        end
    end
  end

  defp neighbour(t, key, dir, cand, s) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      :none
    else
      {_, l, k, v, r} = d

      case {Order.compare(k, key, s), dir} do
        {:gt, :next} ->
          neighbour(l, key, dir, {k, v}, s)

        {:lt, :next} ->
          neighbour(r, key, dir, cand, s)

        {:gt, :previous} ->
          neighbour(l, key, dir, cand, s)

        {:lt, :previous} ->
          neighbour(r, key, dir, {k, v}, s)

        {:eq, :next} ->
          case extreme(r, 1, s) do
            :none -> cand || :none
            kv -> kv
          end

        {:eq, :previous} ->
          case extreme(l, 4, s) do
            :none -> cand || :none
            kv -> kv
          end
      end
    end
  end

  # Inordnung, ohne leere Knoten
  defp pairs(t, s, acc) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      acc
    else
      {_, l, k, v, r} = d
      pairs(l, s, [{k, v} | pairs(r, s, acc)])
    end
  end

  defp range(t, min, max, s, acc) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      acc
    else
      {_, l, k, v, r} = d

      cond do
        Order.compare(k, min, s) == :lt -> range(r, min, max, s, acc)
        Order.compare(k, max, s) == :gt -> range(l, min, max, s, acc)
        true -> range(l, min, max, s, [{k, v} | range(r, min, max, s, acc)])
      end
    end
  end

  # Werte in Präordnung, umgekehrt gesammelt
  defp pre(t, s, acc) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      acc
    else
      {_, l, _, v, r} = d
      pre(r, s, pre(l, s, [v | acc]))
    end
  end

  defp set_pre(t, vals, s) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      {t, vals}
    else
      {c, l, k, _, r} = d
      [v | vals] = vals
      {nl, vals} = set_pre(l, vals, s)
      {nr, vals} = set_pre(r, vals, s)
      {b(c, nl, k, v, nr), vals}
    end
  end

  defp set_in(t, vals, s) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      {t, vals}
    else
      {c, l, k, _, r} = d
      {nl, [v | vals]} = set_in(l, vals, s)
      {nr, vals} = set_in(r, vals, s)
      {b(c, nl, k, v, nr), vals}
    end
  end

  # acc: Paare umgekehrt in Inordnung
  defp clone(t, s, acc) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      {t, acc}
    else
      {c, l, k, _, r} = d
      nv = fresh_var()
      {nl, acc} = clone(l, s, acc)
      {nr, acc} = clone(r, s, [{k, nv} | acc])
      {b(c, nl, k, nv, nr), acc}
    end
  end

  # --- Prüfen (wie SWIs is_rbtree/1) ------------------------------------------

  defp check(root, s) do
    case node(root, s) do
      {:black, l, k, _, r} ->
        bls = path_blacks(l, s, 0)
        check(l, :inf, k, bls, s) and check(r, k, :inf, bls, s)

      _ ->
        false
    end
  catch
    :bad -> false
  end

  defp path_blacks(t, s, n) do
    case node(t, s) do
      {:black, l, _, _, _} = d -> if nil?(d, s), do: n, else: path_blacks(l, s, n + 1)
      {:red, l, _, _, _} -> path_blacks(l, s, n)
      :leaf -> throw(:bad)
    end
  end

  defp check(t, min, max, bls, s) do
    case node(t, s) do
      {:black, l, k, _, r} = d ->
        if nil?(d, s) do
          bls == 0
        else
          in_range?(k, min, max, s) and check(l, min, k, bls - 1, s) and
            check(r, k, max, bls - 1, s)
        end

      {:red, l, k, _, r} ->
        in_range?(k, min, max, s) and black?(l, s) and black?(r, s) and
          check(l, min, k, bls, s) and check(r, k, max, bls, s)

      :leaf ->
        false
    end
  end

  defp in_range?(k, min, max, s) do
    (min == :inf or Order.compare(k, min, s) == :gt) and
      (max == :inf or Order.compare(k, max, s) == :lt)
  end

  # --- Einfügen (SWI: insert2, fix_left, fix_right, fix_root) ----------------

  defp fix_root(t, s) do
    {_, l, k, v, r} = node(t, s)
    b(:black, l, k, v, r)
  end

  # {baum, :done | :not_done} oder :exists (nur new = true)
  defp insert(t, key, val, nil_, new, s) do
    d = node(t, s)

    if nil_leaf?(d, s) do
      {b(:red, nil_, key, val, nil_), :not_done}
    else
      {c, l, k0, v0, r} = d

      case {Order.compare(key, k0, s), c} do
        {:eq, _} when new ->
          :exists

        {:eq, _} ->
          {b(c, l, k0, val, r), :done}

        {:lt, :red} ->
          with {nl, f} <- insert(l, key, val, nil_, new, s), do: {b(:red, nl, k0, v0, r), f}

        {:gt, :red} ->
          with {nr, f} <- insert(r, key, val, nil_, new, s), do: {b(:red, l, k0, v0, nr), f}

        {:lt, :black} ->
          with {il, f} <- insert(l, key, val, nil_, new, s),
               do: fix_left(f, b(:black, il, k0, v0, r), s)

        {:gt, :black} ->
          with {ir, f} <- insert(r, key, val, nil_, new, s),
               do: fix_right(f, b(:black, l, k0, v0, ir), s)
      end
    end
  end

  # black('', _, _, '')
  defp nil_leaf?({:black, l, _, _, r}, s), do: node(l, s) == :leaf and node(r, s) == :leaf
  defp nil_leaf?(_, _s), do: false

  defp fix_left(:done, t, _s), do: {t, :done}

  defp fix_left(:not_done, t, s) do
    {:black, tl, kc, vc, tr} = node(t, s)

    case {node(tl, s), node(tr, s)} do
      {{:red, al, ak, av, x}, {:red, de, kd, vd, ep}} ->
        cond do
          red?(x, s) ->
            {b(:red, b(:black, al, ak, av, x), kc, vc, b(:black, de, kd, vd, ep)), :not_done}

          red?(al, s) ->
            {b(:red, b(:black, al, ak, av, x), kc, vc, b(:black, de, kd, vd, ep)), :not_done}

          true ->
            {t, :done}
        end

      {{:red, al, ka, va, x}, _} ->
        cond do
          red?(x, s) ->
            {:red, be, kb, vb, ga} = node(x, s)
            {b(:black, b(:red, al, ka, va, be), kb, vb, b(:red, ga, kc, vc, tr)), :done}

          red?(al, s) ->
            # black(red(red(Al,KA,VA,Be),KB,VB,Ga),KC,VC,De)
            {b(:black, al, ka, va, b(:red, x, kc, vc, tr)), :done}

          true ->
            {t, :done}
        end

      _ ->
        {t, :done}
    end
  end

  defp fix_right(:done, t, _s), do: {t, :done}

  defp fix_right(:not_done, t, s) do
    {:black, tl, kc, vc, tr} = node(t, s)

    case {node(tl, s), node(tr, s)} do
      {{:red, ep, kd, vd, de}, {:red, y, ka, va, al}} ->
        if red?(y, s) or red?(al, s),
          do: {b(:red, b(:black, ep, kd, vd, de), kc, vc, b(:black, y, ka, va, al)), :not_done},
          else: {t, :done}

      {_, {:red, y, ka, va, al}} ->
        cond do
          red?(y, s) ->
            {:red, ga, kb, vb, be} = node(y, s)
            {b(:black, b(:red, tl, kc, vc, ga), kb, vb, b(:red, be, ka, va, al)), :done}

          red?(al, s) ->
            # black(De,KC,VC,red(Ga,KB,VB,red(Be,KA,VA,Al)))
            {b(:black, b(:red, tl, kc, vc, y), ka, va, al), :done}

          true ->
            {t, :done}
        end

      _ ->
        {t, :done}
    end
  end

  # --- Ändern eines Werts --------------------------------------------------------

  defp update(t, key, val, s) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      :none
    else
      {c, l, k0, v0, r} = d

      case Order.compare(k0, key, s) do
        :eq ->
          {:ok, v0, b(c, l, k0, val, r)}

        :gt ->
          with {:ok, old, nl} <- update(l, key, val, s), do: {:ok, old, b(c, nl, k0, v0, r)}

        :lt ->
          with {:ok, old, nr} <- update(r, key, val, s), do: {:ok, old, b(c, l, k0, v0, nr)}
      end
    end
  end

  # --- Löschen (SWI: delete, delete_*_node, delete_next, fixup2/3) ------------

  defp run(f) do
    f.()
  catch
    :rb_fail -> :fail
  end

  defp fail!, do: throw(:rb_fail)

  # {wert, baum, flag}
  defp delete(t, key, s) do
    d = node(t, s)

    if d == :leaf or nil?(d, s) do
      fail!()
    else
      {c, l, k0, v0, r} = d

      case Order.compare(key, k0, s) do
        :lt ->
          {v, nl, f0} = delete(l, key, s)
          {nt, f} = fixup_left(f0, b(c, nl, k0, v0, r), s)
          {v, nt, f}

        :gt ->
          {v, nr, f0} = delete(r, key, s)
          {nt, f} = fixup_right(f0, b(c, l, k0, v0, nr), s)
          {v, nt, f}

        :eq ->
          {out, f} = if c == :red, do: delete_red_node(l, r, s), else: delete_black_node(l, r, s)
          {v0, out, f}
      end
    end
  end

  defp delete_red_node(l, r, s) do
    cond do
      nil_t?(l, s) and nil_t?(r, s) ->
        {l, :done}

      nil_leaf?(node(l, s), s) ->
        {r, :done}

      nil_leaf?(node(r, s), s) ->
        {l, :done}

      true ->
        {nk, nv, nr, d0} = delete_next(r, s)
        fixup_right(d0, b(:red, l, nk, nv, nr), s)
    end
  end

  defp delete_black_node(l, r, s) do
    dl = node(l, s)
    dr = node(r, s)

    cond do
      nil?(dl, s) and nil?(dr, s) ->
        {l, :not_done}

      nil_leaf?(dl, s) and match?({:red, _, _, _, _}, dr) ->
        {:red, rl, k, v, rr} = dr
        {b(:black, rl, k, v, rr), :done}

      nil_leaf?(dl, s) ->
        {r, :not_done}

      match?({:red, _, _, _, _}, dl) and nil_leaf?(dr, s) ->
        {:red, ll, k, v, lr} = dl
        {b(:black, ll, k, v, lr), :done}

      nil_leaf?(dr, s) ->
        {l, :not_done}

      true ->
        {nk, nv, nr, d0} = delete_next(r, s)
        fixup_right(d0, b(:black, l, nk, nv, nr), s)
    end
  end

  # {k, v, baum, flag}: kleinster Eintrag heraus
  defp delete_next(t, s) do
    case node(t, s) do
      {c, l, k, v, r} ->
        dl = node(l, s)

        cond do
          c == :red and nil_leaf?(dl, s) ->
            {k, v, r, :done}

          c == :black and nil_leaf?(dl, s) ->
            case node(r, s) do
              {:red, l1, k1, v1, r1} -> {k, v, b(:black, l1, k1, v1, r1), :done}
              _ -> {k, v, r, :not_done}
            end

          true ->
            {k0, v0, nl, d0} = delete_next(l, s)
            {out, d} = fixup_left(d0, b(c, nl, k, v, r), s)
            {k0, v0, out, d}
        end

      :leaf ->
        fail!()
    end
  end

  defp fixup_left(:done, t, _s), do: {t, :done}
  defp fixup_left(:not_done, t, s), do: fixup2(t, s)

  defp fixup_right(:done, t, _s), do: {t, :done}
  defp fixup_right(:not_done, t, s), do: fixup3(t, s)

  # links ist ein Schwarz zu wenig
  defp fixup2(t, s) do
    {c, l, kb, vb, r} = node(t, s)
    unless black?(l, s), do: fail!()

    case {c, node(r, s)} do
      {:black, {:red, x, kd, vd, y}} ->
        unless black?(x, s) and black?(y, s), do: fail!()
        {t1, _} = fixup2(b(:red, l, kb, vb, x), s)
        {b(:black, t1, kd, vd, y), :done}

      {_, {:black, x, kd, vd, y}} ->
        dx = node(x, s)
        dy = node(y, s)

        cond do
          match?({:black, _, _, _, _}, dx) and match?({:black, _, _, _, _}, dy) ->
            if c == :red,
              do: {b(:black, l, kb, vb, b(:red, x, kd, vd, y)), :done},
              else: {b(:black, l, kb, vb, b(:red, x, kd, vd, y)), :not_done}

          match?({:red, _, _, _, _}, dx) and match?({:black, _, _, _, _}, dy) ->
            {:red, ga, kc, vc, de} = dx
            {b(c, b(:black, l, kb, vb, ga), kc, vc, b(:black, de, kd, vd, y)), :done}

          match?({:red, _, _, _, _}, dy) ->
            {:red, ep, ke, ve, fi} = dy
            {b(c, b(:black, l, kb, vb, x), kd, vd, b(:black, ep, ke, ve, fi)), :done}

          true ->
            fail!()
        end

      _ ->
        fail!()
    end
  end

  # rechts ist ein Schwarz zu wenig
  defp fixup3(t, s) do
    {c, l, kb, vb, r} = node(t, s)
    unless black?(r, s), do: fail!()

    case {c, node(l, s)} do
      {:black, {:red, x, kd, vd, y}} ->
        unless black?(x, s) and black?(y, s), do: fail!()
        {t1, _} = fixup3(b(:red, y, kb, vb, r), s)
        {b(:black, x, kd, vd, t1), :done}

      {_, {:black, x, kd, vd, y}} ->
        dx = node(x, s)
        dy = node(y, s)

        cond do
          match?({:black, _, _, _, _}, dx) and match?({:black, _, _, _, _}, dy) ->
            if c == :red,
              do: {b(:black, b(:red, x, kd, vd, y), kb, vb, r), :done},
              else: {b(:black, b(:red, x, kd, vd, y), kb, vb, r), :not_done}

          match?({:black, _, _, _, _}, dx) and match?({:red, _, _, _, _}, dy) ->
            {:red, de, kc, vc, ga} = dy
            {b(c, b(:black, x, kd, vd, de), kc, vc, b(:black, ga, kb, vb, r)), :done}

          match?({:red, _, _, _, _}, dx) ->
            {:red, fi, ke, ve, ep} = dx
            {b(c, b(:black, fi, ke, ve, ep), kd, vd, b(:black, y, kb, vb, r)), :done}

          true ->
            fail!()
        end

      _ ->
        fail!()
    end
  end

  # {k, v, baum, flag}
  defp del_min(t, nil_, s) do
    case node(t, s) do
      {c, l, k, v, r} ->
        if nil_t?(l, s) do
          {out, f} =
            if c == :red, do: delete_red_node(nil_, r, s), else: delete_black_node(nil_, r, s)

          {k, v, out, f}
        else
          if node(l, s) == :leaf, do: fail!()
          {k0, v0, nl, f0} = del_min(l, nil_, s)
          {nt, f} = fixup_left(f0, b(c, nl, k, v, r), s)
          {k0, v0, nt, f}
        end

      :leaf ->
        fail!()
    end
  end

  defp del_max(t, nil_, s) do
    case node(t, s) do
      {c, l, k, v, r} ->
        if node(r, s) != :leaf and nil_t?(r, s) do
          {out, f} =
            if c == :red, do: delete_red_node(l, nil_, s), else: delete_black_node(l, nil_, s)

          {k, v, out, f}
        else
          if node(r, s) == :leaf, do: fail!()
          {k0, v0, nr, f0} = del_max(r, nil_, s)
          {nt, f} = fixup_right(f0, b(c, l, k, v, nr), s)
          {k0, v0, nt, f}
        end

      :leaf ->
        fail!()
    end
  end

  # --- Aufbau ------------------------------------------------------------------------

  defp construct(lo, hi, _arr, _depth, nil_) when hi < lo, do: nil_

  defp construct(lo, lo, arr, depth, nil_) do
    {k, v} = elem(arr, lo - 1)
    build_node(depth, nil_, k, v, nil_)
  end

  defp construct(lo, hi, arr, depth, nil_) do
    i = div(lo + hi, 2)
    {k, v} = elem(arr, i - 1)
    left = construct(lo, i - 1, arr, depth - 1, nil_)
    right = construct(i + 1, hi, arr, depth - 1, nil_)
    build_node(depth, left, k, v, right)
  end

  defp build_node(0, l, k, v, r), do: b(:red, l, k, v, r)
  defp build_node(_, l, k, v, r), do: b(:black, l, k, v, r)

  # true, :dup (gleiche Schlüssel) oder :order
  defp strictly_ascending?([], _s), do: true
  defp strictly_ascending?([_], _s), do: true

  defp strictly_ascending?([{k1, _}, {k2, _} = b | rest], s) do
    case Order.compare(k1, k2, s) do
      :lt -> strictly_ascending?([b | rest], s)
      :eq -> :dup
      :gt -> :order
    end
  end

  defp items!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end
end
