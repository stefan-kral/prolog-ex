defmodule PrologEx.Builtins.ClpbPrims do
  @moduledoc """
  Teile von `library(clpb)` (`priv/library/clpb.pl`) in Elixir.

    * `'$clpb_propagate'(+BDD, -P)` – die Propagation von
      `satisfiable_bdd/1`: welche Variablen nur noch einen Wert zulassen
      und welche gleich sein müssen. P ist
      * `skip`: eine Knotenvariable ist schon gebunden (wie im Original:
        dann keine Propagation),
      * `universal`: allquantifizierte Variablen (Atome) kommen vor – das
        übernimmt der Prolog-Code des Originals,
      * `prop(Vs, Werte, Gleichungen)`: `Vs = Werte` und die Gleichungen
        `D = B` sind zu unifizieren, in der Reihenfolge des Originals.

  Dieselbe Rechnung wie `bdd_variables_classification/3` und
  `aliasing_consistency/3` in Triskas Code, Schritt für Schritt: die
  Variablen in Index-Reihenfolge, je Variable die Knoten der Ebene (ein
  Pfad zu 1 oder eine übersprungene Ebene: keine Klasse), die
  Besucht-Markierungen als Mengen von Knoten-IDs statt Attributen.
  Ein BDD-Knoten ist `node(ID, Var, Low, High, Aux)`, Blätter sind 0 und 1;
  der Index einer Variablen steht in ihrem Attribut
  `clpb(index_root(Index, Root))`.

    * `'$clpb_apply'(+F, +NA, +NB, -Node)` – `apply/4`: NA F NB für F in
      `+`, `*`, `#` als BDD, mit Merktabelle je Aufruf; Rekursion und
      Vergabe der Knoten-IDs in derselben Reihenfolge wie Triskas
      `apply//4` (erst Low, dann High).
    * `'$clpb_make_node'(+Var, +Low, +High, -Node)` – `make_node/4`:
      Low, wenn Low == High; sonst der vorhandene Knoten aus der
      Hashtabelle von Var (Attribut `clpb_hash`, ein AVL-Baum mit
      Schlüssel `node(LID, HID)`) oder ein neuer mit der nächsten ID
      (backtrackbarer Wert `'$clpb_next_node'`), der dort eingetragen wird.

  Der Zustand bleibt, wo ihn der Prolog-Code erwartet (Attribute,
  backtrackbarer Zähler), damit beide Teile zusammenpassen, solange es
  noch Prolog-Teile gibt.
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.{Assoc, Atts, Blackboard}

  defbuiltin "$clpb_propagate", [bdd, p] do
    try do
      {res, s} = propagate(bdd, subst())

      case PrologEx.unify(p, res, s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  # {P, Substitution}: mit Atomen (allquantifizierten Variablen) erst die
  # Prüfung von bdd_variables_classification/3 – nach Herausrechnen aller
  # anderen Variablen muss der BDD 1 sein; die dabei gebauten Knoten
  # bleiben (wie im Original)
  defp propagate(bdd, s) do
    with {:ok, order, nodes} <- preorder(bdd, s),
         vars = distinct_vars(order, nodes),
         {:ok, idx} <- indices(vars, s) do
      vs = Enum.sort_by(vars, &Map.fetch!(idx, &1))
      {universal, es} = Enum.split_with(vs, &(Atts.get_one(&1, "clpb", "clpb_atom", s) != nil))

      s =
        if universal == [] do
          s
        else
          st = %{s: s, memo: %{}, idx: idx}

          {res, st} =
            Enum.reduce(es, {top(bdd, s), st}, fn v, {b, st} -> existential(v, b, st) end)

          if res == 1, do: st.s, else: throw(:clpb_fail)
        end

      {prop(vs, bdd, nodes, idx, s), s}
    else
      :bound -> {a("skip"), s}
      :fail -> throw(:clpb_fail)
    end
  end

  defp prop(vs, bdd, nodes, idx, s) do
    classes = classify(vs, [child(bdd, s)], MapSet.new(), nodes, idx, [])

    eqs = for {:eq, v, val} <- classes, do: {v, val}
    bs = for {:fb, b, bnodes} <- classes, do: {b, bnodes}
    ds = for {:nd, d} <- classes, do: d

    aliases =
      for {b, bnodes} <- bs,
          bi = Map.fetch!(idx, b),
          d <- ds,
          di = Map.fetch!(idx, d),
          di > bi,
          always_false?(:high, di, bnodes, nodes, idx),
          always_false?(:low, di, bnodes, nodes, idx),
          # wie [DA=BA] im Original: D = B (bestimmt, welche Variable
          # gebunden wird – sichtbar in Antworten und beim labeling);
          # Atome statt ihrer Variablen (var_or_atom/2)
          do: mk("=", [var_or_atom(d, s), var_or_atom(b, s)])

    mk("prop", [
      list(Enum.map(eqs, &elem(&1, 0))),
      list(Enum.map(eqs, &elem(&1, 1))),
      list(aliases)
    ])
  end

  defp var_or_atom(v, s), do: Atts.get_one(v, "clpb", "clpb_atom", s) || v

  # --- BDD lesen -----------------------------------------------------------------

  # Kind eines Knotens: 0, 1 oder {:n, ID}
  defp child(t, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      0 -> 0
      1 -> 1
      {:struct, "node", [id | _]} -> {:n, PrologEx.walk(id, s)}
    end
  end

  # alle inneren Knoten in Präordnung (wie bdd_nodes/3) und
  # ID => {Var, Low, High}; :bound, wenn eine Variable gebunden ist
  # (var_unbound/1 im Original)
  defp preorder(bdd, s) do
    {order, nodes} = visit(bdd, s, [], %{})
    {:ok, Enum.reverse(order), nodes}
  catch
    :bound -> :bound
  end

  defp visit(t, s, order, nodes) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:struct, "node", [id, var, low, high, _aux]} ->
        id = PrologEx.walk(id, s)

        if Map.has_key?(nodes, id) do
          {order, nodes}
        else
          var =
            case PrologEx.walk(var, s) do
              {:var, _} = v -> v
              _ -> throw(:bound)
            end

          nodes = Map.put(nodes, id, {var, child(low, s), child(high, s)})
          {order, nodes} = visit(low, s, [id | order], nodes)
          visit(high, s, order, nodes)
        end

      _ ->
        {order, nodes}
    end
  end

  # Variablen in der Reihenfolge der Knoten, ohne Wiederholung
  defp distinct_vars(order, nodes) do
    order
    |> Enum.map(fn id -> elem(Map.fetch!(nodes, id), 0) end)
    |> Enum.uniq()
  end

  # Index jeder Variablen; ohne Index scheitert die Propagation (wie
  # var_index/2 in variables_classification//2)
  defp indices(vars, s) do
    Enum.reduce_while(vars, {:ok, %{}}, fn v, {:ok, acc} ->
      case index_of(v, s) do
        nil -> {:halt, :fail}
        i -> {:cont, {:ok, Map.put(acc, v, i)}}
      end
    end)
  end

  defp index_of(v, s) do
    case Atts.get_one(v, "clpb", "clpb", s) do
      nil ->
        nil

      ir ->
        case top(ir, s) do
          {:struct, "index_root", [i, _]} -> PrologEx.walk(i, s)
          _ -> nil
        end
    end
  end

  # --- Klassen (variables_classification//2) -----------------------------------------

  defp classify([], _frontier, _visited, _nodes, _idx, acc), do: Enum.reverse(acc)

  defp classify([v | vs], frontier, visited, nodes, idx, acc) do
    vi = Map.fetch!(idx, v)

    case with_variable(frontier, vi, visited, nodes, idx) do
      {:ok, level, visited} ->
        lhs = for {:n, id} <- level, do: Map.fetch!(nodes, id)

        acc =
          cond do
            Enum.all?(lhs, fn {_, low, _} -> low == 0 end) -> [{:eq, v, 1} | acc]
            Enum.all?(lhs, fn {_, _, high} -> high == 0 end) -> [{:eq, v, 0} | acc]
            true -> acc
          end

        acc =
          if Enum.all?(lhs, fn {_, low, high} -> low != 1 and high != 1 end),
            do: [{:fb, v, level} | acc],
            else: acc

        acc =
          if Enum.all?(lhs, fn {_, low, high} -> low == 0 or high == 0 end),
            do: [{:nd, v} | acc],
            else: acc

        visited = Enum.reduce(level, visited, fn {:n, id}, vis -> MapSet.delete(vis, id) end)
        classify(vs, level, visited, nodes, idx, acc)

      :fail ->
        classify(vs, frontier, visited, nodes, idx, acc)
    end
  end

  # nodes_with_variable//2: die Knoten mit Variablen-Index vi unterhalb der
  # Front; ein Pfad zu 1 oder ein Knoten unterhalb von vi: :fail
  defp with_variable([], _vi, visited, _nodes, _idx), do: {:ok, [], visited}
  defp with_variable([1 | _], _vi, _visited, _nodes, _idx), do: :fail

  defp with_variable([0 | rest], vi, visited, nodes, idx),
    do: with_variable(rest, vi, visited, nodes, idx)

  defp with_variable([{:n, id} = n | rest], vi, visited, nodes, idx) do
    if MapSet.member?(visited, id) do
      with_variable(rest, vi, visited, nodes, idx)
    else
      visited = MapSet.put(visited, id)
      {var, low, high} = Map.fetch!(nodes, id)
      ovi = Map.fetch!(idx, var)

      cond do
        ovi > vi ->
          :fail

        ovi == vi ->
          with {:ok, r, visited} <- with_variable(rest, vi, visited, nodes, idx),
               do: {:ok, [n | r], visited}

        true ->
          with {:ok, r1, visited} <- with_variable([low, high], vi, visited, nodes, idx),
               {:ok, r2, visited} <- with_variable(rest, vi, visited, nodes, idx),
               do: {:ok, r1 ++ r2, visited}
      end
    end
  end

  # --- Gleichsetzungen (always_false/3) -------------------------------------------------

  defp always_false?(which, di, level, nodes, idx) do
    opposite = if which == :high, do: :low, else: :high

    result =
      Enum.reduce_while(level, MapSet.new(), fn {:n, id}, vis ->
        case opposite_false(opposite, di, pick(which, Map.fetch!(nodes, id)), vis, nodes, idx) do
          {:ok, vis} -> {:cont, vis}
          :fail -> {:halt, :fail}
        end
      end)

    result != :fail
  end

  defp pick(:low, {_, low, _}), do: low
  defp pick(:high, {_, _, high}), do: high

  # opposite_always_false//3: unterhalb von t hat jeder Knoten der Ebene di
  # auf der Gegenseite 0; Blätter und besuchte Knoten gelten als erfüllt
  defp opposite_false(_opp, _di, leaf, vis, _nodes, _idx) when leaf in [0, 1], do: {:ok, vis}

  defp opposite_false(opp, di, {:n, id}, vis, nodes, idx) do
    if MapSet.member?(vis, id) do
      {:ok, vis}
    else
      vis = MapSet.put(vis, id)
      {var, low, high} = node = Map.fetch!(nodes, id)

      if Map.fetch!(idx, var) == di do
        if pick(opp, node) == 0, do: {:ok, vis}, else: :fail
      else
        with {:ok, vis} <- opposite_false(opp, di, low, vis, nodes, idx),
             do: opposite_false(opp, di, high, vis, nodes, idx)
      end
    end
  end

  # --- apply/4 und make_node/4 -------------------------------------------------------

  defbuiltin "$clpb_apply", [f, na, nb, node] do
    s = subst()
    {:atom, op} = PrologEx.walk(f, s)

    try do
      {res, st} = apply_bdd(op, na, nb, %{s: s, memo: %{}, idx: %{}})

      case PrologEx.unify(node, res, st.s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  defbuiltin "$clpb_make_node", [var, low, high, node] do
    s = subst()

    try do
      {res, st} = make_node(PrologEx.walk(var, s), top(low, s), top(high, s), %{s: s, idx: %{}})

      case PrologEx.unify(node, res, st.s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  defp top(t, s), do: PrologEx.unmark_top(PrologEx.walk(t, s))

  # Kennung für Schlüssel: Blätter false/true (wie node_id/2), Knoten ihre ID
  defp nid(0, _s), do: false
  defp nid(1, _s), do: true
  defp nid({:struct, "node", [id | _]}, s), do: PrologEx.walk(id, s)

  defp nid_term(0, _s), do: a("false")
  defp nid_term(1, _s), do: a("true")
  defp nid_term({:struct, "node", [id | _]}, s), do: PrologEx.walk(id, s)

  defp apply_bdd(f, na, nb, st) do
    na = top(na, st.s)
    nb = top(nb, st.s)

    cond do
      is_integer(na) and is_integer(nb) ->
        {bool_op(f, na, nb), st}

      (r = shortcut(f, na, nb)) != nil ->
        {r, st}

      true ->
        key = {f, nid(na, st.s), nid(nb, st.s)}

        case st.memo do
          %{^key => node} ->
            {node, st}

          _ ->
            {node, st} = apply_split(f, na, nb, st)
            {node, %{st | memo: Map.put(st.memo, key, node)}}
        end
    end
  end

  defp bool_op("+", a, b), do: Bitwise.bor(a, b)
  defp bool_op("*", a, b), do: Bitwise.band(a, b)
  defp bool_op("#", a, b), do: Bitwise.bxor(a, b)
  defp bool_op(_, _, _), do: throw(:clpb_fail)

  defp shortcut("+", na, nb) do
    cond do
      na == 0 -> nb
      na == 1 -> 1
      nb == 0 -> na
      nb == 1 -> 1
      true -> nil
    end
  end

  defp shortcut("*", na, nb) do
    cond do
      na == 0 -> 0
      na == 1 -> nb
      nb == 0 -> 0
      nb == 1 -> na
      true -> nil
    end
  end

  defp shortcut(_, _, _), do: nil

  # apply_//4: nach der Variablen mit dem kleineren Index aufteilen
  defp apply_split(f, na, nb, st) do
    case {na, nb} do
      {{:struct, "node", [_, va, la, ha, _]}, _} ->
        va = PrologEx.walk(va, st.s)

        {less, st} =
          case nb do
            n when is_integer(n) ->
              {true, st}

            {:struct, "node", [_, vb, _, _, _]} ->
              {ia, st} = var_idx(va, st)
              {ib, st} = var_idx(PrologEx.walk(vb, st.s), st)
              {ia != nil and ib != nil and ia < ib, st}
          end

        cond do
          less ->
            {low, st} = apply_bdd(f, la, nb, st)
            {high, st} = apply_bdd(f, ha, nb, st)
            make_node(va, top(low, st.s), top(high, st.s), st)

          match?({:struct, "node", _}, nb) and same_var?(va, nb, st.s) ->
            {:struct, "node", [_, _, lb, hb, _]} = nb
            {low, st} = apply_bdd(f, la, lb, st)
            {high, st} = apply_bdd(f, ha, hb, st)
            make_node(va, top(low, st.s), top(high, st.s), st)

          true ->
            split_b(f, na, nb, st)
        end

      _ ->
        split_b(f, na, nb, st)
    end
  end

  defp same_var?(va, {:struct, "node", [_, vb | _]}, s), do: va == PrologEx.walk(vb, s)

  defp split_b(f, na, {:struct, "node", [_, vb, lb, hb, _]}, st) do
    {low, st} = apply_bdd(f, na, lb, st)
    {high, st} = apply_bdd(f, na, hb, st)
    make_node(PrologEx.walk(vb, st.s), top(low, st.s), top(high, st.s), st)
  end

  defp split_b(_f, _na, _nb, _st), do: throw(:clpb_fail)

  defp var_idx(v, st) do
    case st.idx do
      %{^v => i} ->
        {i, st}

      _ ->
        i = index_of(v, st.s)
        {i, %{st | idx: Map.put(st.idx, v, i)}}
    end
  end

  defp make_node(var, low, high, st) do
    s = st.s

    if nid(low, s) == nid(high, s) do
      {low, st}
    else
      hash = Atts.get_one(var, "clpb", "clpb_hash", s) || throw(:clpb_fail)
      key = mk("node", [nid_term(low, s), nid_term(high, s)])

      case Assoc.lookup_value(key, hash, s) do
        {:ok, node} ->
          {top(node, s), st}

        :none ->
          {:ok, id} = Blackboard.b_value("clpb", "$clpb_next_node", s)
          id = PrologEx.walk(id, s)
          s = Blackboard.b_put(s, "clpb", "$clpb_next_node", id + 1)
          node = {:struct, "node", [id, var, low, high, {:var, PrologEx.Vars.next()}]}
          hash = Assoc.put_value(hash, key, node, s)
          s = Atts.put_one(s, var, "clpb", mk("clpb_hash", [hash]))
          {node, %{st | s: s}}
      end
    end
  end

  # --- bdd_restriction/4 und existential/3 -------------------------------------------

  defbuiltin "$clpb_restriction", [node, vi, value, res] do
    s = subst()

    try do
      {r, st} =
        restrict(top(node, s), PrologEx.walk(vi, s), PrologEx.walk(value, s), %{
          s: s,
          idx: %{},
          rmemo: %{}
        })

      case PrologEx.unify(res, r, st.s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  defbuiltin "$clpb_existential", [v, bdd, node] do
    s = subst()

    try do
      {r, st} = existential(PrologEx.walk(v, s), top(bdd, s), %{s: s, memo: %{}, idx: %{}})

      case PrologEx.unify(node, r, st.s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  # existential/3: V herausrechnen – BDD[V:=0] + BDD[V:=1]; eigene
  # Merktabellen für jede Einschränkung und für apply (wie das Original)
  defp existential(v, bdd, st) do
    {vi, st} = var_idx(v, st)
    if vi == nil, do: throw(:clpb_fail)
    {na, st} = restrict(bdd, vi, 0, Map.put(st, :rmemo, %{}))
    {nb, st} = restrict(bdd, vi, 1, %{st | rmemo: %{}})
    {node, st2} = apply_bdd("+", na, nb, %{st | memo: %{}})
    {node, %{st2 | memo: st.memo}}
  end

  # bdd_restriction_//4: der BDD mit der Variablen mit Index vi auf value
  defp restrict(node, _vi, _value, st) when is_integer(node), do: {node, st}

  defp restrict({:struct, "node", [id, var, low, high, _]} = node, vi, value, st) do
    case PrologEx.walk(var, st.s) do
      0 ->
        restrict(top(low, st.s), vi, value, st)

      1 ->
        restrict(top(high, st.s), vi, value, st)

      n when is_number(n) ->
        PrologEx.Error.domain!("clpb_expr", n)

      v ->
        {i0, st} = var_idx(v, st)
        id = PrologEx.walk(id, st.s)

        cond do
          i0 == nil ->
            throw(:clpb_fail)

          i0 == vi ->
            {if(value == 0, do: top(low, st.s), else: top(high, st.s)), st}

          i0 > vi ->
            {node, st}

          Map.has_key?(st.rmemo, id) ->
            {Map.fetch!(st.rmemo, id), st}

          true ->
            {lres, st} = restrict(top(low, st.s), vi, value, st)
            {hres, st} = restrict(top(high, st.s), vi, value, st)
            {res, st} = make_node(v, lres, hres, st)
            {res, %{st | rmemo: Map.put(st.rmemo, id, res)}}
        end
    end
  end

  defp restrict(other, _vi, _value, st),
    do: PrologEx.Error.domain!("node", PrologEx.resolve(other, st.s))
end
