defmodule PrologEx.Builtins.ClpbPrims do
  @moduledoc """
  Teile von `library(clpb)` (`priv/library/clpb.pl`) in Elixir.

    * `'$clpb_propagate'(+BDD, -P)` – die Propagation von
      `satisfiable_bdd/1`: welche Variablen nur noch einen Wert zulassen
      und welche gleich sein müssen. P ist
      * `skip`: eine Knotenvariable ist schon gebunden (wie im Original:
        dann keine Propagation),
      * `prop(Vs, Werte, Gleichungen)`: `Vs = Werte` und die Gleichungen
        `D = B` sind zu unifizieren, in der Reihenfolge des Originals.
      Mit allquantifizierten Variablen (Atomen) muss der BDD nach
      Herausrechnen aller anderen Variablen 1 sein, sonst scheitert es.

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
    * `'$clpb_restriction'/4`, `'$clpb_existential'/3` – `bdd_restriction/4`
      (eine Variable auf 0 oder 1 setzen) und `existential/3`.
    * `'$clpb_parse'(+Sat0, +Monotonic, -Sat)` – `parse_sat/2`: Typprüfung
      mit denselben Fehlern wie das Original, Umschreiben auf `*`, `+`,
      `#`, `^` und `card/2`, Atome durch ihre Variablen, neue Variablen
      bekommen Index und Knotentabelle.
    * `'$clpb_sat_bdd'(+Sat, -BDD)` – `sat_bdd/2`: der BDD einer
      umgeschriebenen Formel, `card/2` über das Zählnetz des Originals
      (`counter_network/3`, mit denselben Hilfsvariablen).

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

  # --- parse_sat/2 -------------------------------------------------------------------

  # '$clpb_parse'(+Sat0, +Monotonic, -Sat): must_be_sat/1 (Typprüfung mit
  # denselben Fehlern), sat_rewrite/2 (Synonyme auf *, +, #, ^, card;
  # Atome durch ihre allquantifizierten Variablen) und enumerate_variable/1
  # (Index und leere Knotentabelle für neue Variablen, in der Reihenfolge
  # von term_variables/2)
  defbuiltin "$clpb_parse", [sat0, mono, sat] do
    s = subst()
    mono = PrologEx.walk(mono, s) == a("true")

    unless PrologEx.Builtins.Terms.acyclic?(sat0, s),
      do: clpb_error(mk("domain_error", [a("acyclic_term"), sat0]), sat0)

    if not sat?(sat0, mono, s),
      do: clpb_error(mk("domain_error", [a("clpb_expr"), sat0]), sat0)

    {res, s} = rewrite(sat0, s)

    s =
      res
      |> PrologEx.Builtins.Order.variables(s)
      |> Enum.reduce(s, &enumerate/2)

    case PrologEx.unify(sat, res, s) do
      {:ok, s} -> {:subst, s}
      :error -> :fail
    end
  end

  # error(Formal, unknown(Term)-1) wie die Fehler in Triskas clpb.pl
  defp clpb_error(formal, term),
    do: PrologEx.Error.throw!(mk("error", [formal, unknown_ctx(term)]))

  defp unknown_ctx(term), do: mk("-", [mk("unknown", [term]), 1])

  # instantiation_error/2 des Originals: Kontext instantiation_error(unknown(T), 1)
  defp inst_error(t) do
    PrologEx.Error.throw!(
      mk("error", [a("instantiation_error"), mk("instantiation_error", [mk("unknown", [t]), 1])])
    )
  end

  # is_sat/1
  defp sat?(t, mono, s) do
    case top(t, s) do
      {:var, _} = v ->
        if mono and index_of(v, s) == nil do
          inst_error(v)
        end

        true

      {:struct, "v", [x]} ->
        case PrologEx.walk(x, s) do
          {:var, _} -> true
          i -> i in [0, 1]
        end

      i when is_integer(i) ->
        i in [0, 1]

      {:atom, _} ->
        true

      [] ->
        true

      {:struct, "~", [x]} ->
        sat?(x, mono, s)

      {:struct, op, [x, y]} when op in ["*", "+", "#", "=:=", "=\\=", "=<", ">=", "<", ">"] ->
        sat?(x, mono, s) and sat?(y, mono, s)

      {:struct, op, [ls]} when op in ["+", "*"] ->
        must_be_list(ls, s) |> Enum.all?(&sat?(&1, mono, s))

      {:struct, "^", [x, f]} ->
        match?({:var, _}, PrologEx.walk(x, s)) and sat?(f, mono, s)

      {:struct, "card", [is, fs]} ->
        is |> must_be_list(s) |> Enum.each(&must_be_nonvar(&1, s))
        fs |> must_be_list(s) |> Enum.all?(&sat?(&1, mono, s))

      _ ->
        false
    end
  end

  # must_be(list, _): Elemente der Liste; offene Liste: instantiation_error,
  # sonst type_error(list, _), beide mit Kontext unknown(Liste)-1
  defp must_be_list(l, s), do: must_be_list(l, l, s, [])

  defp must_be_list(l0, l, s, acc) do
    case top(l, s) do
      [] ->
        Enum.reverse(acc)

      [h | t] ->
        must_be_list(l0, t, s, [h | acc])

      {:var, _} ->
        inst_error(l0)

      _ ->
        clpb_error(mk("type_error", [a("list"), l0]), l0)
    end
  end

  # must_be(ground, _, T) ist im Original functor(T, _, _)
  defp must_be_nonvar(t, s) do
    if match?({:var, _}, PrologEx.walk(t, s)), do: PrologEx.Error.instantiation!()
  end

  # sat_rewrite/2; {Term, Substitution} – neue Atome bekommen Variablen
  defp rewrite(t, s) do
    case top(t, s) do
      {:var, _} = v ->
        {v, s}

      i when is_integer(i) ->
        {i, s}

      {:atom, _} = at ->
        atom_var(at, s)

      [] ->
        atom_var([], s)

      {:struct, "v", [x]} ->
        {PrologEx.walk(x, s), s}

      {:struct, op, [p, q]} when op in ["*", "+", "#"] ->
        bin(op, p, q, s)

      {:struct, "^", [x, f]} ->
        {f, s} = rewrite(f, s)
        {mk("^", [PrologEx.walk(x, s), f]), s}

      {:struct, "card", [is, fs]} ->
        {fs, s} = fs |> must_be_list(s) |> Enum.map_reduce(s, &rewrite/2)
        {mk("card", [is, list(fs)]), s}

      {:struct, "~", [p]} ->
        bin("#", 1, p, s)

      {:struct, "=:=", [p, q]} ->
        {np, s} = negate(p, s)
        bin_r("#", np, q, s)

      {:struct, "=\\=", [p, q]} ->
        bin("#", p, q, s)

      {:struct, "=<", [p, q]} ->
        {np, s} = negate(p, s)
        bin_r("+", np, q, s)

      {:struct, ">=", [p, q]} ->
        {nq, s} = negate(q, s)
        bin_r("+", nq, p, s)

      {:struct, "<", [p, q]} ->
        {np, s} = negate(p, s)
        bin_r("*", np, q, s)

      {:struct, ">", [p, q]} ->
        {nq, s} = negate(q, s)
        bin_r("*", nq, p, s)

      {:struct, "+", [ls]} ->
        fold(ls, "+", 0, s)

      {:struct, "*", [ls]} ->
        fold(ls, "*", 1, s)
    end
  end

  defp bin(op, p, q, s) do
    {p, s} = rewrite(p, s)
    bin_r(op, p, q, s)
  end

  # linke Seite schon umgeschrieben
  defp bin_r(op, p, q, s) do
    {q, s} = rewrite(q, s)
    {mk(op, [p, q]), s}
  end

  # ~P umgeschrieben: 1 # P
  defp negate(p, s) do
    {p, s} = rewrite(p, s)
    {mk("#", [1, p]), s}
  end

  # foldl(or/and, Ls, Neutral, F): ((N op L1) op L2) ...
  defp fold(ls, op, neutral, s) do
    ls
    |> must_be_list(s)
    |> Enum.reduce({neutral, s}, fn l, {acc, s} -> bin_r(op, acc, l, s) end)
  end

  # clpb_atom_var/2: die Variable eines Atoms (global über alle sat/1)
  defp atom_var(at, s) do
    {:ok, atoms} = Blackboard.b_value("clpb", "$clpb_atoms", s)

    case Assoc.lookup_value(at, atoms, s) do
      {:ok, v} ->
        {PrologEx.walk(v, s), s}

      :none ->
        v = {:var, PrologEx.Vars.next()}
        s = Atts.put_one(s, v, "clpb", mk("clpb_atom", [at]))
        s = Atts.put_one(s, v, "clpb", mk("clpb_omit_boolean", [a("true")]))
        s = Blackboard.b_put(s, "clpb", "$clpb_atoms", Assoc.put_value(atoms, at, v, s))
        {PrologEx.walk(v, s), s}
    end
  end

  # enumerate_variable/1
  defp enumerate(v, s) do
    if index_of(v, s) != nil do
      s
    else
      {:ok, i} = Blackboard.b_value("clpb", "$clpb_next_var", s)
      i = PrologEx.walk(i, s)
      s = Blackboard.b_put(s, "clpb", "$clpb_next_var", i + 1)
      root = {:var, PrologEx.Vars.next()}
      s = Atts.put_one(s, v, "clpb", mk("clpb", [mk("index_root", [i, root])]))
      Atts.put_one(s, v, "clpb", mk("clpb_hash", [a("t")]))
    end
  end

  # --- sat_bdd/2 ---------------------------------------------------------------------

  # '$clpb_sat_bdd'(+Sat, -BDD): der BDD einer umgeschriebenen Formel
  # (aus parse_sat/2) – Variablen, 0/1, *, +, #, V^F und card/2 (über ein
  # Zählnetz wie counter_network/3 des Originals)
  defbuiltin "$clpb_sat_bdd", [sat, bdd] do
    s = subst()

    try do
      {node, st} = sat_bdd(sat, %{s: s, memo: %{}, idx: %{}})

      case PrologEx.unify(bdd, node, st.s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  defp sat_bdd(t, st) do
    case top(t, st.s) do
      {:var, _} = v ->
        make_node(v, 0, 1, st)

      i when is_integer(i) ->
        {i, st}

      {:struct, "^", [v, f]} ->
        {b, st} = sat_bdd(f, st)
        existential(PrologEx.walk(v, st.s), b, st)

      {:struct, "card", [is, fs]} ->
        counter_network(is, fs, st)

      {:struct, f, [x, y]} ->
        {na, st} = sat_bdd(x, st)
        {nb, st} = sat_bdd(y, st)
        apply_fresh(f, na, nb, st)

      _ ->
        throw(:clpb_fail)
    end
  end

  # apply/4: eigene Merktabelle je Aufruf
  defp apply_fresh(f, na, nb, st) do
    {node, st2} = apply_bdd(f, na, nb, %{st | memo: %{}})
    {node, %{st2 | memo: st.memo}}
  end

  # counter_network/3: Indikatoren 0/1 für jede mögliche Anzahl wahrer
  # Formeln, Hilfsvariablen für Formeln, die keine (neue) Variable sind,
  # das Netz von der Variablen mit dem höchsten Index an aufwärts, dann
  # die Hilfsvariablen herausrechnen
  defp counter_network(cs, fs, st) do
    cs = items(cs, st.s)
    fs = items(fs, st.s)
    indicators = for k <- 0..length(fs), do: indicator(k, cs, st.s)

    {vars, exs, _seen, st} =
      Enum.reduce(fs, {[], [], MapSet.new(), st}, fn f, {vars, exs, seen, st} ->
        case PrologEx.walk(f, st.s) do
          {:var, _} = v ->
            if MapSet.member?(seen, v),
              do: helper(f, vars, exs, seen, st),
              else: {[v | vars], exs, MapSet.put(seen, v), st}

          _ ->
            helper(f, vars, exs, seen, st)
        end
      end)

    {vars, st} =
      vars
      |> Enum.reverse()
      |> Enum.map_reduce(st, fn v, st ->
        {i, st} = var_idx(v, st)
        {{i || 0, v}, st}
      end)

    vars = vars |> Enum.with_index() |> Enum.sort_by(fn {{i, _}, k} -> {i, k} end)
    vars = vars |> Enum.map(fn {{_, v}, _} -> v end) |> Enum.reverse()

    {node, st} = network(vars, indicators, st)

    exs
    |> Enum.reverse()
    |> Enum.reduce({node, st}, fn {ex, bdd}, {node0, st} ->
      {node1, st} = apply_fresh("*", bdd, node0, st)
      {node, st} = existential(ex, node1, st)
      # del_attrs/1: die Hilfsvariable verliert alle clpb-Attribute
      {node, %{st | s: PrologEx.put_attr(st.s, ex, "clpb", []), idx: Map.delete(st.idx, ex)}}
    end)
  end

  # neue Hilfsvariable V mit V =:= F
  defp helper(f, vars, exs, seen, st) do
    v = {:var, PrologEx.Vars.next()}
    s = enumerate(v, st.s)
    v = PrologEx.walk(v, s)
    {sat, s} = rewrite(mk("=:=", [v, f]), s)
    {bdd, st} = sat_bdd(sat, %{st | s: s})
    {[v | vars], [{v, bdd} | exs], seen, st}
  end

  defp network([], [node], st), do: {node, st}

  defp network([var | vars], [i | is0], st) do
    {is, {_, st}} =
      Enum.map_reduce(is0, {i, st}, fn ind, {prev, st} ->
        {node, st} = make_node(var, prev, ind, st)
        {node, {ind, st}}
      end)

    network(vars, is, st)
  end

  # fill_indicators/3: 1, wenn k in Cs steht oder in einem Bereich A-B
  # (Fehler wie between/3)
  defp indicator(k, cs, s) do
    cond do
      Enum.any?(cs, &(PrologEx.walk(&1, s) === k)) ->
        1

      Enum.any?(cs, fn c ->
        case top(c, s) do
          {:struct, "-", [lo, hi]} -> in_range?(k, lo, hi, s)
          _ -> false
        end
      end) ->
        1

      true ->
        0
    end
  end

  defp in_range?(k, lo, hi, s) do
    lo = int_arg(PrologEx.walk(lo, s))

    case PrologEx.walk(hi, s) do
      {:atom, inf} when inf in ["inf", "infinite"] -> k >= lo
      hi -> k >= lo and k <= int_arg(hi)
    end
  end

  defp int_arg(n) when is_integer(n), do: n
  defp int_arg({:var, _}), do: PrologEx.Error.instantiation!()
  defp int_arg(other), do: PrologEx.Error.type!("integer", other)

  # Elemente einer echten Liste
  defp items(l, s) do
    case top(l, s) do
      [h | t] -> [h | items(t, s)]
      _ -> []
    end
  end
end
