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
    * `'$clpb_sat'(+Sat0, +Monotonic, -R)` – `sat/1` bis auf die
      Propagation: `ands(Glieder)` zum einzelnen Aufrufen oder `bdd(BDD)`,
      mit den Wurzeln vereinigt und dort abgelegt.
    * `'$clpb_tautology'/1`, `'$clpb_verify'/4`, `'$clpb_rebuild'/4` –
      `tautology/1`, der Hook beim Binden, `root_rebuild_bdd/2`.
    * `'$clpb_sat_count'(+Sat0, +Monotonic, ?N)` – `sat_count/2`.
    * `'$clpb_attribute_goals'/4`, `'$clpb_project'/1` – die Restziele
      (`attribute_goals//1`, `project_attributes/2`).
    * `'$clpb_labeling_vars'/2`, `'$clpb_random_bindings'/2`,
      `'$clpb_weighted'/6` – die Rechenteile von `labeling/1`,
      `random_labeling/2` und `weighted_maximum/3`.

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
    case dense(bdd, s) do
      {:ok, g} -> propagate(g, bdd, s)
      :bound -> {a("skip"), s}
    end
  end

  defp propagate(g, bdd, s) do
    with vars = g.vars,
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

      vix = g.var |> Tuple.to_list() |> Enum.map(&Map.fetch!(idx, &1)) |> List.to_tuple()
      {prop(vs, Map.merge(g, %{vix: vix, vix_of: idx}), idx, s), s}
    else
      :fail -> throw(:clpb_fail)
    end
  end

  defp prop(vs, g, idx, s) do
    classes = classify(vs, [g.root], g, :atomics.new(max(g.n, 1), signed: false), [])

    eqs = for {:eq, v, val} <- classes, do: {v, val}
    bs = for {:fb, b, bnodes} <- classes, do: {b, bnodes}
    ds = for {:nd, d} <- classes, do: d

    # Besucht-Marken der Gleichsetzungs-Prüfung: Generationen statt Löschen
    vis = :atomics.new(max(g.n, 1), signed: false)
    gen = :counters.new(1, [])

    aliases =
      for {b, bnodes} <- bs,
          bi = Map.fetch!(idx, b),
          d <- ds,
          di = Map.fetch!(idx, d),
          di > bi,
          always_false?(:high, di, bnodes, g, vis, gen),
          always_false?(:low, di, bnodes, g, vis, gen),
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

  # Der BDD als dichte Arrays für die Propagation: die inneren Knoten in
  # Präordnung (wie bdd_nodes/3) mit 0..n-1 nummeriert, je Knoten die
  # Variable und die Kinder als Code (-1 = Blatt 0, -2 = Blatt 1, sonst
  # Nummer); :bound, wenn eine Variable gebunden ist (var_unbound/1 im
  # Original). vars: die Variablen in Knotenreihenfolge ohne Wiederholung.
  @leaf0 -1
  @leaf1 -2

  defp dense(bdd, s) do
    {root, {num, entries}} = dense_visit(bdd, s, {%{}, %{}})
    n = map_size(num)
    rows = for i <- 0..(n - 1)//1, do: Map.fetch!(entries, i)
    vars = Enum.map(rows, &elem(&1, 0))

    {:ok,
     %{
       n: n,
       root: root,
       var: List.to_tuple(vars),
       low: rows |> Enum.map(&elem(&1, 1)) |> List.to_tuple(),
       high: rows |> Enum.map(&elem(&1, 2)) |> List.to_tuple(),
       ids: rows |> Enum.map(&elem(&1, 3)) |> List.to_tuple(),
       nodes: Enum.map(rows, &elem(&1, 4)),
       vars: Enum.uniq(vars)
     }}
  catch
    :bound -> :bound
  end

  # Code des Teilbaums; die Nummer vergibt die Präordnung (erst der Knoten,
  # dann Low, dann High)
  defp dense_visit(t, s, {num, entries} = acc) do
    case PrologEx.unmark_top(PrologEx.Store.walk(t, s)) do
      {:struct, "node", [id, var, low, high, _aux]} = node ->
        id = PrologEx.Store.walk(id, s)

        case num do
          %{^id => i} ->
            {i, acc}

          _ ->
            var =
              case PrologEx.Store.walk(var, s) do
                {:var, _} = v -> v
                _ -> throw(:bound)
              end

            i = map_size(num)
            {lc, acc} = dense_visit(low, s, {Map.put(num, id, i), entries})
            {hc, {num, entries}} = dense_visit(high, s, acc)
            {i, {num, Map.put(entries, i, {var, lc, hc, id, node})}}
        end

      0 ->
        {@leaf0, acc}

      1 ->
        {@leaf1, acc}
    end
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
          {:struct, "index_root", [i, _]} -> PrologEx.Store.walk(i, s)
          _ -> nil
        end
    end
  end

  # --- Klassen (variables_classification//2) -----------------------------------------

  # visited: Besucht-Marken (1) über alle Variablen hinweg; die Knoten einer
  # gefundenen Ebene werden wieder freigegeben
  defp classify([], _frontier, _g, _visited, acc), do: Enum.reverse(acc)

  defp classify([v | vs], frontier, g, visited, acc) do
    vi = Map.fetch!(g.vix_of, v)

    case with_variable(frontier, vi, g, visited, [], []) do
      {:ok, level} ->
        lows = Enum.map(level, &elem(g.low, &1))
        highs = Enum.map(level, &elem(g.high, &1))

        acc =
          cond do
            Enum.all?(lows, &(&1 == @leaf0)) -> [{:eq, v, 1} | acc]
            Enum.all?(highs, &(&1 == @leaf0)) -> [{:eq, v, 0} | acc]
            true -> acc
          end

        acc =
          if Enum.all?(level, &(elem(g.low, &1) != @leaf1 and elem(g.high, &1) != @leaf1)),
            do: [{:fb, v, level} | acc],
            else: acc

        acc =
          if Enum.all?(level, &(elem(g.low, &1) == @leaf0 or elem(g.high, &1) == @leaf0)),
            do: [{:nd, v} | acc],
            else: acc

        Enum.each(level, &:atomics.put(visited, &1 + 1, 0))
        classify(vs, level, g, visited, acc)

      :fail ->
        classify(vs, frontier, g, visited, acc)
    end
  end

  # nodes_with_variable//2: die Knoten mit Variablen-Index vi unterhalb der
  # Front (Tiefensuche, Low vor High); ein Pfad zu 1 oder ein Knoten
  # unterhalb von vi: :fail – dann werden die Marken dieses Laufs
  # zurückgenommen (wie im Original, wo der Besucht-Zustand dann verworfen
  # wird)
  defp with_variable([], _vi, _g, _visited, level, _marked), do: {:ok, Enum.reverse(level)}

  defp with_variable([@leaf1 | _], _vi, _g, visited, _level, marked) do
    Enum.each(marked, &:atomics.put(visited, &1 + 1, 0))
    :fail
  end

  defp with_variable([@leaf0 | rest], vi, g, visited, level, marked),
    do: with_variable(rest, vi, g, visited, level, marked)

  defp with_variable([n | rest], vi, g, visited, level, marked) do
    if :atomics.get(visited, n + 1) == 1 do
      with_variable(rest, vi, g, visited, level, marked)
    else
      :atomics.put(visited, n + 1, 1)
      marked = [n | marked]
      ovi = elem(g.vix, n)

      cond do
        ovi > vi ->
          Enum.each(marked, &:atomics.put(visited, &1 + 1, 0))
          :fail

        ovi == vi ->
          with_variable(rest, vi, g, visited, [n | level], marked)

        true ->
          with_variable([elem(g.low, n), elem(g.high, n) | rest], vi, g, visited, level, marked)
      end
    end
  end

  # --- Gleichsetzungen (always_false/3) -------------------------------------------------

  # für jeden Knoten der Ebene von B: auf der Seite `which` hat jeder
  # erreichbare Knoten der Ebene di auf der Gegenseite 0; besuchte Knoten
  # (Marke = aktuelle Generation) gelten als erfüllt
  defp always_false?(which, di, level, g, vis, gen) do
    :counters.add(gen, 1, 1)
    stamp = :counters.get(gen, 1)
    {side, opp} = if which == :high, do: {g.high, g.low}, else: {g.low, g.high}
    opposite_false(Enum.map(level, &elem(side, &1)), di, opp, g, vis, stamp)
  end

  defp opposite_false([], _di, _opp, _g, _vis, _stamp), do: true

  defp opposite_false([c | rest], di, opp, g, vis, stamp) when c < 0,
    do: opposite_false(rest, di, opp, g, vis, stamp)

  defp opposite_false([n | rest], di, opp, g, vis, stamp) do
    if :atomics.get(vis, n + 1) == stamp do
      opposite_false(rest, di, opp, g, vis, stamp)
    else
      :atomics.put(vis, n + 1, stamp)
      vi = elem(g.vix, n)

      cond do
        vi == di ->
          elem(opp, n) == @leaf0 and opposite_false(rest, di, opp, g, vis, stamp)

        # unterhalb von di kommt die Ebene nicht mehr vor
        vi > di ->
          opposite_false(rest, di, opp, g, vis, stamp)

        true ->
          opposite_false([elem(g.low, n), elem(g.high, n) | rest], di, opp, g, vis, stamp)
      end
    end
  end

  # --- apply/4 und make_node/4 -------------------------------------------------------

  defbuiltin "$clpb_apply", [f, na, nb, node] do
    s = subst()
    {:atom, op} = PrologEx.Store.walk(f, s)

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
      {res, st} =
        make_node(PrologEx.Store.walk(var, s), top(low, s), top(high, s), %{s: s, idx: %{}})

      case PrologEx.unify(node, res, st.s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  defp top(t, s), do: PrologEx.unmark_top(PrologEx.Store.walk(t, s))

  # Kennung für Schlüssel: Blätter false/true (wie node_id/2), Knoten ihre ID
  defp nid(0, _s), do: false
  defp nid(1, _s), do: true
  defp nid({:struct, "node", [id | _]}, s), do: PrologEx.Store.walk(id, s)

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
        va = PrologEx.Store.walk(va, st.s)

        {less, st} =
          case nb do
            n when is_integer(n) ->
              {true, st}

            {:struct, "node", [_, vb, _, _, _]} ->
              {ia, st} = var_idx(va, st)
              {ib, st} = var_idx(PrologEx.Store.walk(vb, st.s), st)
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

  defp same_var?(va, {:struct, "node", [_, vb | _]}, s), do: va == PrologEx.Store.walk(vb, s)

  defp split_b(f, na, {:struct, "node", [_, vb, lb, hb, _]}, st) do
    {low, st} = apply_bdd(f, na, lb, st)
    {high, st} = apply_bdd(f, na, hb, st)
    make_node(PrologEx.Store.walk(vb, st.s), top(low, st.s), top(high, st.s), st)
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
      key = node_key(key_code(low, s), key_code(high, s))

      case Assoc.lookup_value(key, hash, s) do
        {:ok, node} ->
          {top(node, s), st}

        :none ->
          {:ok, id} = Blackboard.b_value("clpb", "$clpb_next_node", s)
          id = PrologEx.Store.walk(id, s)
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
        restrict(top(node, s), PrologEx.Store.walk(vi, s), PrologEx.Store.walk(value, s), %{
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
      {r, st} = existential(PrologEx.Store.walk(v, s), top(bdd, s), %{s: s, memo: %{}, idx: %{}})

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
  defp existential(v, bdd, st), do: quantify("+", v, bdd, st)

  # universal/3 (sat_count/2): BDD[V:=0] * BDD[V:=1]
  defp universal(v, bdd, st), do: quantify("*", v, bdd, st)

  defp quantify(op, v, bdd, st) do
    {vi, st} = var_idx(v, st)
    if vi == nil, do: throw(:clpb_fail)
    {na, st} = restrict(bdd, vi, 0, Map.put(st, :rmemo, %{}))
    {nb, st} = restrict(bdd, vi, 1, %{st | rmemo: %{}})
    {node, st2} = apply_bdd(op, na, nb, %{st | memo: %{}})
    {node, %{st2 | memo: st.memo}}
  end

  # bdd_restriction_//4: der BDD mit der Variablen mit Index vi auf value
  defp restrict(node, _vi, _value, st) when is_integer(node), do: {node, st}

  defp restrict({:struct, "node", [id, var, low, high, _]} = node, vi, value, st) do
    case PrologEx.Store.walk(var, st.s) do
      0 ->
        restrict(top(low, st.s), vi, value, st)

      1 ->
        restrict(top(high, st.s), vi, value, st)

      n when is_number(n) or (is_tuple(n) and elem(n, 0) == :rat) ->
        PrologEx.Error.domain!("clpb_expr", n)

      v ->
        {i0, st} = var_idx(v, st)
        id = PrologEx.Store.walk(id, st.s)

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
    {res, s} = parse(sat0, PrologEx.Store.walk(mono, s) == a("true"), s)

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
        case PrologEx.Store.walk(x, s) do
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
        match?({:var, _}, PrologEx.Store.walk(x, s)) and sat?(f, mono, s)

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
    if match?({:var, _}, PrologEx.Store.walk(t, s)), do: PrologEx.Error.instantiation!()
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
        {PrologEx.Store.walk(x, s), s}

      {:struct, op, [p, q]} when op in ["*", "+", "#"] ->
        bin(op, p, q, s)

      {:struct, "^", [x, f]} ->
        {f, s} = rewrite(f, s)
        {mk("^", [PrologEx.Store.walk(x, s), f]), s}

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
        {PrologEx.Store.walk(v, s), s}

      :none ->
        v = {:var, PrologEx.Vars.next()}
        s = Atts.put_one(s, v, "clpb", mk("clpb_atom", [at]))
        s = Atts.put_one(s, v, "clpb", mk("clpb_omit_boolean", [a("true")]))
        s = Blackboard.b_put(s, "clpb", "$clpb_atoms", Assoc.put_value(atoms, at, v, s))
        {PrologEx.Store.walk(v, s), s}
    end
  end

  # enumerate_variable/1
  defp enumerate(v, s) do
    if index_of(v, s) != nil do
      s
    else
      {:ok, i} = Blackboard.b_value("clpb", "$clpb_next_var", s)
      i = PrologEx.Store.walk(i, s)
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
        existential(PrologEx.Store.walk(v, st.s), b, st)

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
        case PrologEx.Store.walk(f, st.s) do
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
    v = PrologEx.Store.walk(v, s)
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
      Enum.any?(cs, &(PrologEx.Store.walk(&1, s) === k)) ->
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
    lo = int_arg(PrologEx.Store.walk(lo, s))

    case PrologEx.Store.walk(hi, s) do
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

  # --- sat/1 -------------------------------------------------------------------------

  # '$clpb_sat'(+Sat0, +Monotonic, -R): R = ands(Ands), wenn sich Sat0 in
  # mehrere Konjunktionsglieder zerlegen lässt (sat_ands//1; dann ruft
  # sat/1 sich für jedes auf), sonst R = bdd(BDD): Sat0 übersetzt, mit den
  # BDDs aller beteiligten Wurzeln verknüpft, die Knotentabellen neu
  # aufgebaut, die Wurzeln vereinigt und Formel und BDD dort abgelegt –
  # bereit für satisfiable_bdd/1
  defbuiltin "$clpb_sat", [sat0, mono, validation, r] do
    s = subst()

    case ands(sat0, s) do
      {:split, items, s} ->
        case PrologEx.unify(r, mk("ands", [list(items)]), s) do
          {:ok, s} -> {:subst, s}
          :error -> :fail
        end

      :single ->
        try do
          {bdd, g, s} = sat_single(sat0, PrologEx.Store.walk(mono, s) == a("true"), s)

          # ohne clpb:validation gleich die Propagation (satisfiable_bdd/1)
          # auf demselben eingelesenen BDD; mit ihr erst is_bdd/1 in Prolog
          {res, s} =
            cond do
              PrologEx.Store.walk(validation, s) == a("true") -> {mk("bdd", [bdd]), s}
              bdd === 0 -> throw(:clpb_fail)
              bdd === 1 -> {a("skip"), s}
              true -> propagate(g, bdd, s)
            end

          case PrologEx.unify(r, res, s) do
            {:ok, s} -> {:subst, s}
            :error -> :fail
          end
        catch
          :clpb_fail -> :fail
        end
    end
  end

  defp sat_single(sat0, mono, s) do
    {sat, s} = parse(sat0, mono, s)
    {bdd, st} = sat_bdd(sat, %{s: s, memo: %{}, idx: %{}})
    roots = sat_roots(sat, st.s)

    # roots_and/3: die Formeln und BDDs der Wurzeln dazunehmen
    {formula, bdd, st} =
      Enum.reduce(roots, {sat0, bdd, st}, fn root, {f0, b0, st} ->
        case Atts.get_one(root, "clpb", "clpb_bdd", st.s) do
          nil ->
            {f0, b0, st}

          fb ->
            {:struct, "-", [f, b]} = top(fb, st.s)
            {b, st} = apply_fresh("*", top(b, st.s), b0, st)
            {mk("*", [f, f0]), b, st}
        end
      end)

    {s, g} =
      if is_integer(bdd), do: {st.s, nil}, else: rebuild_hashes(bdd, st.s)

    s =
      case roots do
        [] ->
          s

        [root | rest] ->
          # del_bdd/1 und maplist(=(Root), Roots): die übrigen Wurzeln
          # an die erste binden – ihre Attribute sind damit unerreichbar,
          # und das Wecken bliebe ohne Wirkung (sie haben keinen Index)
          s = Enum.reduce(rest, s, &Map.put(&2, &1, root))
          Atts.put_one(s, root, "clpb", mk("clpb_bdd", [mk("-", [formula, bdd])]))
      end

    {bdd, g, s}
  end

  # parse_sat/2
  defp parse(sat0, mono, s) do
    unless PrologEx.Builtins.Terms.acyclic?(sat0, s),
      do: clpb_error(mk("domain_error", [a("acyclic_term"), sat0]), sat0)

    if not sat?(sat0, mono, s),
      do: clpb_error(mk("domain_error", [a("clpb_expr"), sat0]), sat0)

    {res, s} = rewrite(sat0, s)
    s = res |> PrologEx.Builtins.Order.variables(s) |> Enum.reduce(s, &enumerate/2)
    {res, s}
  end

  # sat_roots/2: die (verschiedenen) Wurzeln der Variablen
  defp sat_roots(sat, s) do
    sat
    |> PrologEx.Builtins.Order.variables(s)
    |> Enum.map(fn v ->
      case Atts.get_one(v, "clpb", "clpb", s) do
        nil -> throw(:clpb_fail)
        ir -> with {:struct, "index_root", [_, root]} <- top(ir, s), do: root
      end
    end)
    |> list()
    |> PrologEx.Builtins.Order.variables(s)
  end

  # rebuild_hashes/1: die Knotentabellen der Variablen des BDDs enthalten
  # danach genau seine Knoten. Statt jeden Knoten einzeln einzufügen (wie
  # das Original) je Variable die Schlüssel node(LID, HID) einmal sortieren
  # und den AVL-Baum in O(n) bauen – derselbe Inhalt, nur die Form des
  # Baums kann anders sein.
  defp rebuild_hashes(bdd, s) do
    case dense(bdd, s) do
      {:ok, g} -> {rebuild_hashes(g, bdd, s), g}
      # eine gebundene Knotenvariable: wie put_atts/2 im Original
      :bound -> rebuild_bound(bdd, s)
    end
  end

  defp rebuild_hashes(g, _bdd, s) do
    code = fn
      @leaf0 -> 0
      @leaf1 -> 1
      c -> elem(g.ids, c) + 2
    end

    g.nodes
    |> Enum.with_index()
    |> Enum.group_by(
      fn {_, i} -> elem(g.var, i) end,
      fn {node, i} ->
        k = node_key(code.(elem(g.low, i)), code.(elem(g.high, i)))
        {k, {k, node}}
      end
    )
    |> Enum.reduce(s, fn {var, entries}, s ->
      tree = entries |> List.keysort(0) |> Enum.map(&elem(&1, 1)) |> Assoc.from_sorted()
      Atts.put_one(s, var, "clpb", mk("clpb_hash", [tree]))
    end)
  end

  defp rebuild_bound(bdd, s) do
    Enum.each(node_list(bdd, s), fn {:struct, "node", [_, var | _]} ->
      case PrologEx.Store.walk(var, s) do
        {:var, _} -> :ok
        other -> PrologEx.Error.uninstantiation!(PrologEx.resolve(other, s))
      end
    end)
  end

  # Schlüssel der Knotentabellen (low_high_key/3): die Kinder als Codes
  # (Blatt 0 → 0, Blatt 1 → 1, Knoten → ID + 2), beide zu einer Zahl
  # gepaart (Cantor). Eindeutig, und Zahlen vergleicht der AVL-Baum
  # billiger als Terme node(LID, HID) – um ein Fünftel schneller.
  defp key_code(0, _s), do: 0
  defp key_code(1, _s), do: 1
  defp key_code({:struct, "node", [id | _]}, s), do: PrologEx.Store.walk(id, s) + 2

  defp node_key(a, b), do: div((a + b) * (a + b + 1), 2) + b

  # die Knoten in der Reihenfolge von bdd_nodes/3 (Präordnung, Low zuerst)
  defp node_list(bdd, s) do
    {acc, _} = node_list(top(bdd, s), s, {[], MapSet.new()})
    Enum.reverse(acc)
  end

  defp node_list({:struct, "node", [id, _, low, high, _]} = node, s, {acc, seen}) do
    id = PrologEx.Store.walk(id, s)

    if MapSet.member?(seen, id) do
      {acc, seen}
    else
      st = {[node | acc], MapSet.put(seen, id)}
      st = node_list(top(low, s), s, st)
      node_list(top(high, s), s, st)
    end
  end

  defp node_list(_, _s, st), do: st

  # sat_ands//1: Konjunktionsglieder von Sat0 – A*B, *(Ls), ~ über A+B und
  # +(Ls). Offene Listen bindet das Original beim Zurücksetzen: alle an
  # [], die letzte an so viele neue Variablen, dass es zwei Glieder sind.
  defp ands(sat0, s) do
    if PrologEx.Builtins.Terms.acyclic?(sat0, s) do
      try do
        segs = sat_ands(sat0, s, []) |> Enum.reverse()
        n = Enum.count(segs, &match?({:item, _}, &1))
        tails = for {:tail, _, _} = t <- segs, do: t

        cond do
          tails == [] and n < 2 ->
            :single

          true ->
            last = List.last(tails)
            k = if tails == [], do: 0, else: max(0, 2 - n)

            {items, s} =
              Enum.flat_map_reduce(segs, s, fn
                {:item, t}, s ->
                  {[t], s}

                {:tail, v, kind} = t, s ->
                  fresh =
                    if t == last,
                      do: for(_ <- 1..k//1, do: {:var, PrologEx.Vars.next()}),
                      else: []

                  {:ok, s} = PrologEx.unify(v, list(fresh), s)
                  {Enum.map(fresh, &if(kind == :not, do: mk("~", [&1]), else: &1)), s}
              end)

            {:split, items, s}
        end
      catch
        :no_ands -> :single
      end
    else
      :single
    end
  end

  defp sat_ands(x, s, acc) do
    case top(x, s) do
      {:var, _} -> [{:item, x} | acc]
      {:struct, "*", [a, b]} -> sat_ands(b, s, sat_ands(a, s, acc))
      {:struct, "*", [ls]} -> seq(ls, s, :and, acc)
      {:struct, "~", [y]} -> not_ors(y, s, acc)
      _ -> [{:item, x} | acc]
    end
  end

  defp not_ors(x, s, acc) do
    case top(x, s) do
      {:var, _} -> [{:item, mk("~", [x])} | acc]
      {:struct, "+", [a, b]} -> not_ors(b, s, not_ors(a, s, acc))
      {:struct, "+", [ls]} -> seq(ls, s, :not, acc)
      _ -> [{:item, mk("~", [x])} | acc]
    end
  end

  # sat_ands_//1, not_ors_//1: die Elemente selbst (bzw. ~L); ein anderer
  # Rest als eine Variable oder [] lässt sat_ands//1 scheitern
  defp seq(l, s, kind, acc) do
    case top(l, s) do
      [] -> acc
      [h | t] -> seq(t, s, kind, [{:item, if(kind == :not, do: mk("~", [h]), else: h)} | acc])
      {:var, _} = v -> [{:tail, v, kind} | acc]
      _ -> throw(:no_ands)
    end
  end

  # --- tautology/1 -------------------------------------------------------------------

  # '$clpb_tautology'(+Sat): Sat (übersetzt) ist unter den bisherigen
  # Bedingungen immer wahr – für jedes Konjunktionsglied ist der BDD von
  # ~Glied verknüpft mit den BDDs der Wurzeln 0. Wie im Original ohne
  # bleibende Änderungen (dort über throw/catch): die Substitution der
  # Rechnung wird verworfen. Den Neuaufbau der Knotentabellen
  # (rebuild_hashes/1) spart das: er entfernt nur Einträge, und mit mehr
  # Einträgen entsteht derselbe kanonische BDD.
  defbuiltin "$clpb_tautology", [sat] do
    s = subst()

    items =
      case ands(sat, s) do
        {:split, items, _} -> items
        :single -> [sat]
      end

    try do
      Enum.all?(items, &tautology?(&1, s))
    catch
      :clpb_fail -> false
    end
  end

  defp tautology?(sat, s) do
    roots = sat_roots(sat, s)
    st = %{s: s, memo: %{}, idx: %{}}

    {ands, st} =
      Enum.reduce(roots, {1, st}, fn root, {b0, st} ->
        case Atts.get_one(root, "clpb", "clpb_bdd", st.s) do
          nil ->
            {b0, st}

          fb ->
            {:struct, "-", [_, b]} = top(fb, st.s)
            apply_fresh("*", top(b, st.s), b0, st)
        end
      end)

    {bdd, st} = sat_bdd(mk("#", [1, sat]), st)
    {b, _st} = apply_fresh("*", bdd, ands, st)
    b == 0
  end

  # --- verify_attributes/3 und root_rebuild_bdd/2 -------------------------------------

  # '$clpb_verify'(+Var, +Other, +Monotonic, -Goals): der Hook beim Binden
  # von Var an Other (Var noch ungebunden). Goals wie im Original:
  #   * Other 0/1: den BDD der Wurzel einschränken – [satisfiable_bdd(BDD)]
  #   * Other ein Atom: [root_rebuild_bdd(Root, Formel)]
  #   * sonst (Variable, Formel): die Wurzeln von Var und Other vereinigen,
  #     [root_rebuild_bdd(Root, Konjunktion ihrer Formeln)]
  defbuiltin "$clpb_verify", [var, other, mono, gs] do
    s = subst()

    try do
      {goals, s} = verify(var, other, PrologEx.Store.walk(mono, s) == a("true"), s)

      case PrologEx.unify(gs, list(goals), s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  defp verify(var, other, mono, s) do
    case Atts.get_one(var, "clpb", "clpb", s) do
      nil ->
        {[], s}

      ir ->
        {:struct, "index_root", [i, root]} = top(ir, s)

        case top(other, s) do
          o when is_integer(o) ->
            if o not in [0, 1], do: clpb_error(mk("domain_error", [a("clpb_expr"), o]), o)
            {sat, bdd0} = formula_bdd(root, s)

            {bdd, st} =
              restrict(bdd0, PrologEx.Store.walk(i, s), o, %{s: s, idx: %{}, rmemo: %{}})

            s = Atts.put_one(st.s, root, "clpb", mk("clpb_bdd", [mk("-", [sat, bdd])]))
            {[mk("satisfiable_bdd", [bdd])], s}

          o when o == [] or (is_tuple(o) and elem(o, 0) == :atom) ->
            {sat0, _} = formula_bdd(root, s)
            {[mk("root_rebuild_bdd", [root, sat0])], s}

          _ ->
            {sat0, _} = formula_bdd(root, s)
            {other_sat, s} = parse(other, mono, s)
            roots = sat_roots(mk("*", [sat0, other_sat]), s)

            fs =
              for r <- roots, fb = Atts.get_one(r, "clpb", "clpb_bdd", s), fb != nil do
                {:struct, "-", [f, _]} = top(fb, s)
                f
              end

            if fs == [], do: throw(:clpb_fail)
            [f | fs] = fs
            conj = Enum.reduce(fs, f, &mk("*", [&2, &1]))
            s = Enum.reduce(roots, s, &Atts.del_one(&2, &1, "clpb", "clpb_bdd"))
            [root | rest] = roots
            s = Enum.reduce(rest, s, &Map.put(&2, &1, root))
            {[mk("root_rebuild_bdd", [root, conj])], s}
        end
    end
  end

  # root_get_formula_bdd/3: {Formel, BDD} der Wurzel, sonst scheitern
  defp formula_bdd(root, s) do
    case Atts.get_one(root, "clpb", "clpb_bdd", s) do
      nil ->
        throw(:clpb_fail)

      fb ->
        {:struct, "-", [f, b]} = top(fb, s)
        {f, top(b, s)}
    end
  end

  # '$clpb_rebuild'(+Root, +Formel, +Monotonic, -BDD): root_rebuild_bdd/2
  # bis auf is_bdd/1 und satisfiable_bdd/1
  defbuiltin "$clpb_rebuild", [root, formula, mono, bdd] do
    s = subst()

    try do
      {sat, s} = parse(formula, PrologEx.Store.walk(mono, s) == a("true"), s)
      {b, st} = sat_bdd(sat, %{s: s, memo: %{}, idx: %{}})
      s = Atts.put_one(st.s, root, "clpb", mk("clpb_bdd", [mk("-", [formula, b])]))

      case PrologEx.unify(bdd, b, s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  # --- sat_count/2 -------------------------------------------------------------------

  # '$clpb_sat_count'(+Sat0, +Monotonic, ?N): die Zahl der Belegungen der
  # Variablen von Sat0, die Sat0 und die bisherigen Bedingungen erfüllen.
  # Wie im Original: Sat0 übersetzen, mit den BDDs der Wurzeln verknüpfen,
  # alle anderen Variablen herausrechnen (Atome mit ∀, sonst ∃), die
  # Variablen von Sat0 von 1 an neu nummerieren und über die Knoten
  # zählen. Alle Änderungen dabei werden verworfen (dort throw/catch);
  # nur N wird unifiziert.
  defbuiltin "$clpb_sat_count", [sat0, mono, n] do
    s = subst()

    try do
      count = sat_count(sat0, PrologEx.Store.walk(mono, s) == a("true"), s)

      case PrologEx.unify(n, count, s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  defp sat_count(sat0, mono, s0) do
    {sat, s} = parse(sat0, mono, s0)
    {bdd, st} = sat_bdd(sat, %{s: s, memo: %{}, idx: %{}})

    {bdd1, st} =
      Enum.reduce(sat_roots(sat, st.s), {bdd, st}, fn root, {b0, st} ->
        case Atts.get_one(root, "clpb", "clpb_bdd", st.s) do
          nil ->
            {b0, st}

          fb ->
            {:struct, "-", [_, b]} = top(fb, st.s)
            apply_fresh("*", top(b, st.s), b0, st)
        end
      end)

    # die übrigen Variablen des BDDs (nicht in Sat0) herausrechnen
    vs = PrologEx.Builtins.Order.variables(sat0, st.s)
    in_sat0 = MapSet.new(vs)

    others =
      for {:struct, "node", [_, var | _]} <- node_list(bdd1, st.s),
          v = PrologEx.Store.walk(var, st.s),
          match?({:var, _}, v),
          not MapSet.member?(in_sat0, v),
          uniq: true,
          do: v

    {univs, exis} = Enum.split_with(others, &(Atts.get_one(&1, "clpb", "clpb_atom", st.s) != nil))
    {bdd2, st} = Enum.reduce(univs, {bdd1, st}, fn v, {b, st} -> universal(v, b, st) end)
    {bdd3, st} = Enum.reduce(exis, {bdd2, st}, fn v, {b, st} -> existential(v, b, st) end)

    # renumber_variable/3: die Variablen von Sat0 in Index-Reihenfolge 1, 2, …
    renum =
      vs
      |> Enum.with_index()
      |> Enum.sort_by(fn {v, k} -> {index_of(v, st.s) || 0, k} end)
      |> Enum.with_index(1)
      |> Map.new(fn {{v, _}, i} -> {v, i} end)

    vnum = length(vs) + 1
    ctx = %{s: st.s, renum: renum, vnum: vnum}
    {count0, _memo} = bdd_count(bdd3, ctx, %{})
    pow2(var_u(bdd3, ctx) - 1) * count0
  end

  # bdd_count/3: Belegungen unterhalb eines Knotens; übersprungene Ebenen
  # zählen doppelt (2^Abstand). Merktabelle nach Knoten-ID (im Original
  # die Aux-Variable des Knotens).
  defp bdd_count(node, _ctx, memo) when is_integer(node), do: {node, memo}

  defp bdd_count({:struct, "node", [id, var, low, high, _]}, ctx, memo) do
    id = PrologEx.Store.walk(id, ctx.s)

    case memo do
      %{^id => c} ->
        {c, memo}

      _ ->
        low = top(low, ctx.s)
        high = top(high, ctx.s)
        {lc, memo} = bdd_count(low, ctx, memo)
        {hc, memo} = bdd_count(high, ctx, memo)
        i = count_idx(PrologEx.Store.walk(var, ctx.s), ctx)
        c = pow2(var_u(low, ctx) - i - 1) * lc + pow2(var_u(high, ctx) - i - 1) * hc
        {c, Map.put(memo, id, c)}
    end
  end

  # var_u/3: Index der Variablen des Knotens, für Blätter VNum
  defp var_u(node, ctx) when is_integer(node), do: ctx.vnum

  defp var_u({:struct, "node", [_, var | _]}, ctx),
    do: count_idx(PrologEx.Store.walk(var, ctx.s), ctx)

  # der neue Index (oder, für eine nicht umnummerierte Variable, der alte)
  defp count_idx(v, ctx) do
    Map.get(ctx.renum, v) || index_of(v, ctx.s) || throw(:clpb_fail)
  end

  defp pow2(k) when k >= 0, do: Integer.pow(2, k)
  defp pow2(_), do: throw(:clpb_fail)

  # --- Restziele: attribute_goals//1 und project_attributes/2 -------------------------

  # '$clpb_attribute_goals'(+Var, +Monotonic, +Modus, -Goals): die Restziele
  # einer Variablen wie attribute_goals//1 des Originals (Modus anf oder
  # bdd für clpb_residuals(bdd)), mit denselben Änderungen an den
  # Attributen: die Formel der Wurzel wird abgeräumt (die anderen
  # Variablen der Wurzel geben dann nichts mehr aus), die Variablen des
  # BDDs verlieren ihre clpb-Attribute. Scheitert wie das Original.
  defbuiltin "$clpb_attribute_goals", [var, mono, mode, gs] do
    s = subst()
    mono = PrologEx.Store.walk(mono, s) == a("true")
    bdd_mode = PrologEx.Store.walk(mode, s) == a("bdd")

    try do
      {goals, s} = attribute_goals(PrologEx.Store.walk(var, s), mono, bdd_mode, s)

      case PrologEx.unify(gs, list(goals), s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  defp attribute_goals(var, mono, bdd_mode, s) do
    case Atts.get_one(var, "clpb", "clpb", s) do
      nil ->
        cond do
          Atts.get_one(var, "clpb", "clpb_max", s) != nil ->
            {[], Atts.del_one(s, var, "clpb", "clpb_max")}

          (fb = Atts.get_one(var, "clpb", "clpb_bdd", s)) != nil and
              PrologEx.Builtins.Order.variables(fb, s) == [] ->
            {[], Atts.del_one(s, var, "clpb", "clpb_bdd")}

          true ->
            throw(:clpb_fail)
        end

      ir ->
        {:struct, "index_root", [_, root]} = top(ir, s)

        case Atts.get_one(root, "clpb", "clpb_bdd", s) do
          nil ->
            boolean(var, s)

          fb ->
            {:struct, "-", [formula, bdd]} = top(fb, s)
            bdd = top(bdd, s)
            s = Atts.del_one(s, root, "clpb", "clpb_bdd")

            {goals, s} =
              if bdd_mode,
                do: {[clpb_goal("$clpb_bdd", list(bdd_projection(bdd, s)))], s},
                else: anf_goals(formula, mono, s)

            atom_goals =
              case Atts.get_one(var, "clpb", "clpb_atom", s) do
                nil -> []
                at -> [clpb_goal("sat", mk("=:=", [var, at]))]
              end

            # Variablen der Formel, die nicht im BDD vorkommen, sind boolesch
            s = Enum.reduce(bdd_variables(bdd, s), s, &del_clpb(&2, &1))

            rest =
              formula
              |> PrologEx.Builtins.Order.variables(s)
              |> Enum.filter(&(index_of(&1, s) != nil))

            {bools, s} =
              Enum.reduce(rest, {[], s}, fn v, {acc, s} ->
                {g, s} = boolean(v, s)
                {acc ++ g, s}
              end)

            {goals ++ atom_goals ++ bools, s}
        end
    end
  end

  defp clpb_goal(name, arg), do: mk(":", [a("clpb"), mk(name, [arg])])

  # del_clpb/1
  defp del_clpb(s, v) do
    s
    |> Atts.del_one(v, "clpb", "clpb")
    |> Atts.del_one(v, "clpb", "clpb_hash")
    |> Atts.del_one(v, "clpb", "clpb_atom")
  end

  # boolean//1: sat(V =:= V), außer die Variable ist dafür markiert
  defp boolean(v, s) do
    s = del_clpb(s, v)

    if Atts.get_one(v, "clpb", "clpb_omit_boolean", s) != nil do
      {[], Atts.del_one(s, v, "clpb", "clpb_omit_boolean")}
    else
      {[clpb_goal("sat", mk("=:=", [v, v]))], s}
    end
  end

  # bdd_variables/2: die ungebundenen Variablen der Knoten, ohne Wiederholung
  defp bdd_variables(bdd, s) do
    for {:struct, "node", [_, var | _]} <- node_list(bdd, s),
        v = PrologEx.Store.walk(var, s),
        match?({:var, _}, v),
        uniq: true,
        do: v
  end

  # nodes//1 (clpb_residuals(bdd)): ID-(v(Var,Index) -> High ; Low)
  defp bdd_projection(bdd, s) do
    for {:struct, "node", [_, var0, low, high, _]} = node <- node_list(bdd, s) do
      var0 = PrologEx.Store.walk(var0, s)
      vi = index_of(var0, s) || throw(:clpb_fail)
      ite = mk("->", [mk("v", [var_or_atom(var0, s), vi]), projection(top(high, s), s)])
      mk("-", [projection(node, s), mk(";", [ite, projection(top(low, s), s)])])
    end
  end

  defp projection(0, _s), do: a("false")
  defp projection(1, _s), do: a("true")
  defp projection(node, s), do: mk("node", [nid(node, s)])

  # Restziele in (meist) algebraischer Normalform: Konjunktionsglieder der
  # Formel, nach Variablen zusammengefasst (ands_fusion/2), je als ANF,
  # sortiert, ohne 1, Variablen getrennt, wo möglich
  defp anf_goals(formula, mono, s) do
    {items, s} = ands_first(formula, s)

    fused =
      items
      |> Enum.map(fn f ->
        k = f |> PrologEx.Builtins.Order.variables(s) |> in_index_order(s) |> list()
        {k, {k, f}}
      end)
      |> PrologEx.Order.keysort(s)
      |> group_consecutive(s)
      |> Enum.map(fn {_k, fs} -> conjunction(fs) end)

    {anfs, s} =
      Enum.map_reduce(fused, s, fn f, s ->
        {sat, s} = parse(f, mono, s)
        {node, st} = sat_bdd(sat, %{s: s, memo: %{}, idx: %{}})
        {node_anf(node, mono, st.s), st.s}
      end)

    anfs = anfs |> PrologEx.Order.sort_unique(s) |> Enum.reject(&(&1 === 1))
    {anfs, s} = separation(anfs, [], mono, s)
    {Enum.map(anfs, &clpb_goal("sat", &1)), s}
  end

  # variables_in_index_order/2 (ohne Index: 0; stabil)
  defp in_index_order(vs, s) do
    vs
    |> Enum.with_index()
    |> Enum.sort_by(fn {v, k} -> {index_of(v, s) || 0, k} end)
    |> Enum.map(&elem(&1, 0))
  end

  # group_pairs_by_key/2: aufeinanderfolgende gleiche (==) Schlüssel
  defp group_consecutive(pairs, s) do
    pairs
    |> Enum.chunk_while(
      nil,
      fn {k, v}, acc ->
        case acc do
          nil ->
            {:cont, {k, [v]}}

          {k0, vs} ->
            if PrologEx.Order.equal?(k0, k, s),
              do: {:cont, {k0, [v | vs]}},
              else: {:cont, {k0, Enum.reverse(vs)}, {k, [v]}}
        end
      end,
      fn
        nil -> {:cont, nil}
        {k0, vs} -> {:cont, {k0, Enum.reverse(vs)}, nil}
      end
    )
  end

  # list_to_conjunction/2: [] ist 1, sonst ((L1*L2)*L3)...
  defp conjunction([]), do: 1
  defp conjunction([l | ls]), do: Enum.reduce(ls, l, &mk("*", [&2, &1]))

  # phrase(sat_ands(F), Ands): die erste Lösung – offene Listen werden []
  defp ands_first(formula, s) do
    segs = sat_ands(formula, s, []) |> Enum.reverse()

    Enum.flat_map_reduce(segs, s, fn
      {:item, t}, s ->
        {[t], s}

      {:tail, v, _}, s ->
        {:ok, s} = PrologEx.unify(v, [], s)
        {[], s}
    end)
  catch
    :no_ands -> throw(:clpb_fail)
  end

  # node_anf/2: die ANF eines BDDs als Formel; die Monome von node_xors/2
  # (mit Merktabelle je Knoten – das Original rechnet sie für jeden Pfad
  # neu)
  defp node_anf(node, mono, s) do
    {xors, _} = node_xors(node, s, %{})

    conjs =
      Enum.map(xors, fn m ->
        m
        |> Enum.map(fn
          {:var, _} = v -> if mono, do: mk("v", [v]), else: v
          x -> x
        end)
        |> conjunction()
      end)

    xor = fn [c | rest] -> Enum.reduce(rest, c, &mk("#", [&2, &1])) end

    case conjs do
      [v, c | rest] ->
        if clpb_var?(v),
          do: mk("=\\=", [v, xor.([c | rest])]),
          else: anf_one(conjs, xor)

      _ ->
        anf_one(conjs, xor)
    end
  end

  defp anf_one(conjs, xor) do
    case conjs do
      [1, v, c | rest] ->
        if clpb_var?(v), do: mk("=:=", [v, xor.([c | rest])]), else: xor.(conjs)

      [] ->
        throw(:clpb_fail)

      _ ->
        xor.(conjs)
    end
  end

  defp clpb_var?({:var, _}), do: true
  defp clpb_var?({:struct, "v", [_]}), do: true
  defp clpb_var?(_), do: false

  # node_xors/2: Monome (sortierte Listen von Variablen/Atomen), die
  # gerade oft vorkommenden heben sich auf (A#A = 0)
  defp node_xors(0, _s, memo), do: {[], memo}
  defp node_xors(1, _s, memo), do: {[[]], memo}

  defp node_xors({:struct, "node", [id, var0, low, high, _]}, s, memo) do
    id = PrologEx.Store.walk(id, s)

    case memo do
      %{^id => xs} ->
        {xs, memo}

      _ ->
        var = var_or_atom(PrologEx.Store.walk(var0, s), s)
        {ls0, memo} = node_xors(top(low, s), s, memo)
        {hs0, memo} = node_xors(top(high, s), s, memo)
        raw = ls0 ++ Enum.map(ls0, &[var | &1]) ++ Enum.map(hs0, &[var | &1])
        xs = normalize_xors(raw, s)
        {xs, Map.put(memo, id, xs)}
    end
  end

  # wie im Original: jedes Monom sortieren (Standardordnung, ohne
  # Doppelte), nach Monomen sortieren, gerade Anzahlen streichen, 1 aus
  # den Monomen entfernen
  defp normalize_xors(raw, s) do
    raw
    |> Enum.map(fn m ->
      m = PrologEx.Order.sort_unique(m, s)
      k = list(m)
      {k, {k, m}}
    end)
    |> PrologEx.Order.keysort(s)
    |> group_consecutive(s)
    |> Enum.filter(fn {_k, ms} -> rem(length(ms), 2) == 1 end)
    |> Enum.map(fn {_k, [m | _]} -> Enum.reject(m, &(&1 === 1)) end)
  end

  # variables_separation/2: Formeln in Teile zerlegen, wo
  # (A^F)*(B^F) = F gilt, bis zum Fixpunkt
  defp separation(fs0, ds0, mono, s) do
    {out, rest, s} = separation_(fs0, ds0, mono, s)
    ds2 = for {:done, f} <- out, do: f
    fs3 = for {:anf, f} <- out, do: f
    fs5 = PrologEx.Order.sort_unique(rest ++ fs3, s)
    ds4 = PrologEx.Order.sort_unique(ds0 ++ ds2, s)
    if fs5 == [], do: {ds4, s}, else: separation(fs5, ds4, mono, s)
  end

  defp separation_([], _ds, _mono, s), do: {[], [], s}

  defp separation_([f0 | fs0], ds, mono, s) do
    if Enum.any?(ds, &PrologEx.Order.equal?(f0, &1, s)) do
      separation_(fs0, ds, mono, s)
    else
      {f, s} = rewrite(f0, s)
      {bdd, st} = sat_bdd(f, %{s: s, memo: %{}, idx: %{}})

      vs =
        bdd
        |> bdd_variables(st.s)
        |> Enum.reject(&(Atts.get_one(&1, "clpb", "clpb_atom", st.s) != nil))

      {nodes, st} = Enum.map_reduce(vs, st, fn v, st -> existential(v, bdd, st) end)

      pairs =
        for {a, i} <- Enum.with_index(nodes),
            b <- Enum.drop(nodes, i + 1),
            do: {a, b}

      {anfs, st} =
        pairs
        |> group_consecutive(st.s)
        |> Enum.flat_map_reduce(st, fn {bdd1, bdds}, st ->
          {sep, st} =
            Enum.flat_map_reduce(bdds, st, fn bdd2, st ->
              {and_, st} = apply_fresh("*", bdd1, bdd2, st)
              {if(PrologEx.Order.equal?(and_, bdd, st.s), do: [bdd2], else: []), st}
            end)

          if sep == [],
            do: {[], st},
            else: {Enum.map([bdd1 | sep], &node_anf(&1, mono, st.s)), st}
        end)

      if anfs != [] do
        {Enum.map(anfs, &{:anf, &1}), fs0, st.s}
      else
        {out, rest, s} = separation_(fs0, ds, mono, st.s)
        {[{:done, f0} | out], rest, s}
      end
    end
  end

  # '$clpb_project'(+QueryVars, +Monotonic): project_attributes/2 – alle
  # Variablen der BDDs, die keine Anfragevariablen sind (und keine Atome),
  # werden herausgerechnet (auch in der Formel: V^F) und bekommen
  # clpb_omit_boolean(true)
  defbuiltin "$clpb_project", [qvs] do
    s = subst()

    try do
      qvs =
        qvs
        |> items(s)
        |> Enum.map(&PrologEx.Store.walk(&1, s))
        |> Enum.filter(&(match?({:var, _}, &1) and index_of(&1, s) != nil))

      roots =
        qvs
        |> Enum.map(fn v ->
          {:struct, "index_root", [_, root]} = top(Atts.get_one(v, "clpb", "clpb", s), s)
          root
        end)
        |> PrologEx.Order.sort_unique(s)

      in_query = MapSet.new(qvs)
      {:subst, Enum.reduce(roots, s, &remove_hidden(&1, in_query, &2))}
    catch
      :clpb_fail -> :fail
    end
  end

  defp remove_hidden(root, in_query, s) do
    {formula, bdd0} = formula_bdd(root, s)

    hidden =
      bdd0
      |> bdd_variables(s)
      |> Enum.reject(&MapSet.member?(in_query, &1))
      |> Enum.reject(&(Atts.get_one(&1, "clpb", "clpb_atom", s) != nil))

    st = %{s: s, memo: %{}, idx: %{}}
    {bdd, st} = Enum.reduce(hidden, {bdd0, st}, fn v, {b, st} -> existential(v, b, st) end)

    {ex_formula, s} =
      Enum.reduce(hidden, {formula, st.s}, fn e, {f, s} ->
        {mk("^", [e, f]), Atts.put_one(s, e, "clpb", mk("clpb_omit_boolean", [a("true")]))}
      end)

    Atts.put_one(s, root, "clpb", mk("clpb_bdd", [mk("-", [ex_formula, bdd])]))
  end

  # --- labeling/1, random_labeling/2, weighted_maximum/3 ------------------------------

  # '$clpb_labeling_vars'(+Vs0, -Vs): die Prüfungen von labeling/1 (eine
  # Liste aus Variablen, 0 und 1) und die Variablen in Index-Reihenfolge;
  # das Binden selbst bleibt Prolog (indomains/1), weil jede Bindung die
  # Hooks wecken muss, bevor die nächste kommt
  defbuiltin "$clpb_labeling_vars", [vs0, vs] do
    s = subst()

    unless PrologEx.Builtins.Terms.acyclic?(vs0, s),
      do: clpb_error(mk("type_error", [a("list"), vs0]), vs0)

    items = must_be_list(vs0, s)

    Enum.each(items, fn v ->
      case PrologEx.Store.walk(v, s) do
        {:var, _} -> :ok
        b when b === 0 or b === 1 -> :ok
        other -> clpb_error(mk("domain_error", [a("clpb_variable"), other]), other)
      end
    end)

    {:unify, [{vs, list(in_index_order(items, s))}]}
  end

  # '$clpb_random_bindings'(+BDD, -Bs): random_bindings//2 – vom Kopf des
  # BDDs abwärts je Knoten 0 oder 1, gewichtet mit der Zahl der Lösungen
  # darunter (bdd_count/3 nach Umnummerieren der Variablen); Zufallszahlen
  # aus demselben Generator wie random_integer/3
  defbuiltin "$clpb_random_bindings", [bdd, bs] do
    s = subst()

    try do
      bdd = top(bdd, s)
      ivs = bdd |> bdd_variables(s) |> in_index_order(s)
      renum = ivs |> Enum.with_index(1) |> Map.new()
      ctx = %{s: s, renum: renum, vnum: length(ivs) + 1}
      {:unify, [{bs, list(random_bindings(bdd, ctx, %{}))}]}
    catch
      :clpb_fail -> :fail
    end
  end

  defp random_bindings(1, _ctx, _memo), do: []

  defp random_bindings({:struct, "node", [_, var, low, high, _]} = node, ctx, memo) do
    {total, memo} = bdd_count(node, ctx, memo)
    low = top(low, ctx.s)
    {lcount, memo} = bdd_count(low, ctx, memo)

    # weighted_maybe/2: random_integer(0, Total, X), X < LCount
    if total > 0 and PrologEx.Builtins.Random.int_below(total) < lcount do
      [mk("=", [var, 0]) | random_bindings(low, ctx, memo)]
    else
      [mk("=", [var, 1]) | random_bindings(top(high, ctx.s), ctx, memo)]
    end
  end

  defp random_bindings(_, _ctx, _memo), do: throw(:clpb_fail)

  # '$clpb_weighted'(+Ws, +Vars, +BDD0, -BDD, -Pairs, ?Max): der Teil von
  # weighted_maximum/3 zwischen single_bdd/1 und max_labeling/2 – die
  # Variablen außerhalb von Vars herausrechnen, Gewichte je Variable in
  # Index-Reihenfolge zusammenfassen (Var-Gewicht), das Maximum über den
  # BDD (bdd_maximum/3; Maximum und Richtung je Knoten im Attribut
  # clpb_max(max(Max, Dir)) seiner Aux-Variablen, wie das Original – dort
  # liest max_labeling/2 sie)
  defbuiltin "$clpb_weighted", [ws, vars, bdd0, bdd, pairs, max] do
    s = subst()

    try do
      ws = items(ws, s)
      vars = vars |> items(s) |> Enum.map(&PrologEx.Store.walk(&1, s))
      if length(ws) != length(vars), do: throw(:clpb_fail)
      bdd0 = top(bdd0, s)
      in_vars = MapSet.new(vars)
      others = bdd0 |> bdd_variables(s) |> Enum.reject(&MapSet.member?(in_vars, &1))

      {b, st} =
        Enum.reduce(others, {bdd0, %{s: s, memo: %{}, idx: %{}}}, fn v, {b, st} ->
          existential(v, b, st)
        end)

      s = st.s

      # keysort nach I-V (Index, dann Standardordnung), gleiche
      # Variablen zusammenfassen
      ps =
        vars
        |> Enum.zip(ws)
        |> Enum.map(fn {v, w} ->
          k = mk("-", [index_of(v, s) || 0, v])
          {k, {k, {v, PrologEx.Store.walk(w, s)}}}
        end)
        |> PrologEx.Order.keysort(s)
        |> group_consecutive(s)
        |> Enum.map(fn {_k, [{v, _} | _] = vws} ->
          {v, vws |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
        end)

      {m, s} = bdd_maximum(b, ps, s)
      pairs_term = list(Enum.map(ps, fn {v, w} -> mk("-", [v, w]) end))

      with {:ok, s} <- PrologEx.unify(bdd, b, s),
           {:ok, s} <- PrologEx.unify(pairs, pairs_term, s),
           {:ok, s} <- PrologEx.unify(max, m, s) do
        {:subst, s}
      else
        :error -> :fail
      end
    catch
      :clpb_fail -> :fail
    end
  end

  # bdd_maximum/3
  defp bdd_maximum(1, ps, s), do: {positive_sum(ps), s}

  defp bdd_maximum({:struct, "node", [_, var, low, high, aux]}, ps0, s) do
    aux = PrologEx.Store.walk(aux, s)

    case Atts.get_one(aux, "clpb", "clpb_max", s) do
      nil ->
        var = PrologEx.Store.walk(var, s)
        {weight, ps} = skip_to_var(var, ps0, s)
        low = top(low, s)
        high = top(high, s)

        {m, dir, s} =
          cond do
            low === 0 ->
              {mh, to_h, s} = bdd_maximum_(high, ps, s)
              {to_h + mh + weight, a("high"), s}

            high === 0 ->
              {ml, to_l, s} = bdd_maximum_(low, ps, s)
              {to_l + ml, a("low"), s}

            true ->
              {ml, to_l, s} = bdd_maximum_(low, ps, s)
              {mh, to_h, s} = bdd_maximum_(high, ps, s)
              m0 = to_l + ml
              m1 = to_h + mh + weight

              dir =
                cond do
                  m0 == m1 -> {:var, PrologEx.Vars.next()}
                  m0 < m1 -> a("high")
                  true -> a("low")
                end

              {max(m0, m1), dir, s}
          end

        {m, Atts.put_one(s, aux, "clpb", mk("clpb_max", [mk("max", [m, dir])]))}

      mx ->
        {:struct, "max", [m, _]} = top(mx, s)
        {PrologEx.Store.walk(m, s), s}
    end
  end

  defp bdd_maximum(_, _ps, _s), do: throw(:clpb_fail)

  defp bdd_maximum_(node, ps, s) do
    {m, s} = bdd_maximum(node, ps, s)
    {m, between_weights(node, ps, s), s}
  end

  # die positiven Gewichte vor der Variablen des Knotens
  defp between_weights(1, _ps, _s), do: 0

  defp between_weights({:struct, "node", [_, var | _]}, ps, s) do
    var = PrologEx.Store.walk(var, s)

    ps
    |> Enum.take_while(fn {v, _} -> v != var end)
    |> positive_sum()
    |> tap(fn _ -> if not Enum.any?(ps, fn {v, _} -> v == var end), do: throw(:clpb_fail) end)
  end

  defp skip_to_var(var, ps, _s) do
    case Enum.split_while(ps, fn {v, _} -> v != var end) do
      {_, [{_, w} | rest]} -> {w, rest}
      _ -> throw(:clpb_fail)
    end
  end

  defp positive_sum(ps), do: ps |> Enum.map(&elem(&1, 1)) |> Enum.filter(&(&1 > 0)) |> Enum.sum()
end
