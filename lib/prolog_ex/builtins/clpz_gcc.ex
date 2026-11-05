defmodule PrologEx.Builtins.ClpzGcc do
  @moduledoc """
  Der Kern von `gcc_global//2` aus clpz (J.-C. Régin, Generalized Arc
  Consistency for Global Cardinality Constraint, AAAI-96): das Wertenetz,
  ein zulässiger, dann maximaler Fluss, die starken Zusammenhangskomponenten
  und die Liste der `neq_num(V, Value)`. Im Original läuft das unter
  `with_local_attributes/3` mit Attributen (edges, parent, flow, index,
  lowlink, in_stack, value) auf den Variablen; hier mit Maps, Schritt für
  Schritt in derselben Reihenfolge (append_edge/3 stellt vorne an, die
  Breitensuche geht die Kanten in dieser Reihenfolge durch), damit der
  Fluss und damit die Ziele genau dieselben sind.

  Knoten: `:s`, `:t`, `{:val, I}` (I-tes noch offenes Paar) und die
  Variablen selbst. Kanten: `{:to, L, U, W, F}` (arc_to) und
  `{:from, L, U, W, F}` (arc_from), F der Index des Flusses.
  """

  # vals: [{Key, L, U, [{V, Anzahl}]}] in der Reihenfolge der Paare;
  # xs: [{V, Anzahl}] aller Variablen (variables_with_num_occurrences/2).
  # Ergebnis: [{V, Key}] (die neq_num-Ziele) oder :fail
  def goals(vals, xs) do
    g = %{edges: %{}, flow: %{}, nf: 0, parent: %{}, value: %{}}

    {g, ids} =
      vals
      |> Enum.with_index()
      |> Enum.reduce({g, []}, fn {{key, l, u, vns}, i}, {g, ids} ->
        val = {:val, i}
        {g, f} = new_flow(g)
        g = add_edge(g, :s, {:to, l, u, val, f})
        g = %{g | edges: Map.put(g.edges, val, [{:from, l, u, :s, f}])}
        g = %{g | value: Map.put(g.value, val, key)}

        g =
          Enum.reduce(vns, g, fn {v, c}, g ->
            {g, f} = new_flow(g)
            g |> add_edge(v, {:from, 0, c, val, f}) |> add_edge(val, {:to, 0, c, v, f})
          end)

        {g, [val | ids]}
      end)

    vals_ids = Enum.reverse(ids)

    g =
      Enum.reduce(xs, g, fn {v, c}, g ->
        {g, f} = new_flow(g)
        g |> add_edge(v, {:to, 0, c, :t, f}) |> add_edge(:t, {:from, 0, c, v, f})
      end)

    case Map.fetch(g.edges, :s) do
      :error ->
        []

      {:ok, es} ->
        g = %{g | parent: Map.put(g.parent, :s, :none)}

        with {:ok, g} <- feasible(es, g),
             {:ok, g} <- maximum_flow(g),
             true <- consistent?(g),
             {:ok, low} <- scc(vals_ids, g) do
          collect_goals(vals_ids, g, low)
        else
          _ -> :fail
        end
    end
  catch
    :gcc_fail -> :fail
  end

  defp new_flow(g), do: {%{g | flow: Map.put(g.flow, g.nf, 0), nf: g.nf + 1}, g.nf}

  # append_edge/3: vorne anstellen
  defp add_edge(g, v, e), do: %{g | edges: Map.update(g.edges, v, [e], &[e | &1])}

  # get_attr(V, edges, Es) – scheitert ohne Kanten
  defp edges!(g, v) do
    case Map.fetch(g.edges, v) do
      {:ok, es} -> es
      :error -> throw(:gcc_fail)
    end
  end

  # feasible_flow/3, make_arc_feasible/3
  defp feasible([], g), do: {:ok, g}

  defp feasible([{:to, l, _u, v, f} = a | as], g) do
    flow = g.flow[f]

    if flow >= l do
      feasible(as, g)
    else
      diff = l - flow
      g = %{g | parent: Map.put(g.parent, v, {:s, {f, diff, :+}})}

      case aug_search([[v]], g) do
        {:ok, levels, g} ->
          path = aug_path(:t, g, [])
          min = path_min(path, diff)
          g = g |> augment(path, min) |> clear(levels)
          feasible([a | as], g)

        :fail ->
          :fail
      end
    end
  end

  # (an S hängen nur arc_to)
  defp feasible([_ | _], _g), do: throw(:gcc_fail)

  # maximum_flow/2
  defp maximum_flow(g) do
    case aug_search([[:s]], g) do
      {:ok, levels, g} ->
        [{_, first, _} | rest] = path = aug_path(:t, g, [])
        min = path_min(rest, first)
        g |> augment(path, min) |> clear(levels) |> maximum_flow()

      :fail ->
        {:ok, g}
    end
  end

  # gcc_augmenting_path/3: Breitensuche Ebene für Ebene
  defp aug_search([vs | _] = levels, g) do
    {tos, g} = reachables(vs, g)

    cond do
      tos == [] -> :fail
      :t in tos -> {:ok, [tos | levels], g}
      true -> aug_search([tos | levels], g)
    end
  end

  defp reachables(vs, g) do
    {acc, g} =
      Enum.reduce(vs, {[], g}, fn v, {acc, g} ->
        Enum.reduce(edges!(g, v), {acc, g}, fn e, {acc, g} -> reachable(e, v, acc, g) end)
      end)

    {Enum.reverse(acc), g}
  end

  defp reachable({:from, _, _, w, f}, p, acc, g) do
    flow = g.flow[f]

    if not Map.has_key?(g.parent, w) and flow > 0,
      do: {[w | acc], %{g | parent: Map.put(g.parent, w, {p, {f, flow, :-}})}},
      else: {acc, g}
  end

  defp reachable({:to, _, u, w, f}, p, acc, g) do
    flow = g.flow[f]

    if not Map.has_key?(g.parent, w) and flow < u,
      do: {[w | acc], %{g | parent: Map.put(g.parent, w, {p, {f, u - flow, :+}})}},
      else: {acc, g}
  end

  # augmenting_path//2 von V zurück bis S
  defp aug_path(:s, _g, acc), do: Enum.reverse(acc)

  defp aug_path(v, g, acc) do
    case Map.get(g.parent, v) do
      {p, aug} -> aug_path(p, g, [aug | acc])
      _ -> throw(:gcc_fail)
    end
  end

  defp path_min(path, min0), do: Enum.reduce(path, min0, fn {_, a, _}, m -> min(m, a) end)

  defp augment(g, path, min) do
    flow =
      Enum.reduce(path, g.flow, fn
        {f, _, :+}, fl -> Map.update!(fl, f, &(&1 + min))
        {f, _, :-}, fl -> Map.update!(fl, f, &(&1 - min))
      end)

    %{g | flow: flow}
  end

  # maplist(maplist(clear_parent), Levels)
  defp clear(g, levels) do
    %{g | parent: Enum.reduce(levels, g.parent, fn l, p -> Map.drop(p, l) end)}
  end

  # gcc_consistent/1: alle Kanten nach T gesättigt
  defp consistent?(g) do
    Enum.all?(edges!(g, :t), fn
      {:from, _, u, _, f} -> g.flow[f] == u
      _ -> throw(:gcc_fail)
    end)
  end

  # scc/2 mit gcc_successors/2 (Tarjan wie im Original): die lowlinks
  defp scc(vs, g) do
    st = %{i: 0, index: %{}, low: %{}, stack: [], on: MapSet.new()}

    st =
      Enum.reduce(vs, st, fn v, st ->
        if Map.has_key?(st.index, v), do: st, else: scc_(v, g, st)
      end)

    {:ok, st.low}
  end

  defp scc_(v, g, st) do
    i = st.i

    st = %{
      st
      | index: Map.put(st.index, v, i),
        low: Map.put(st.low, v, i),
        i: i + 1,
        stack: [v | st.stack],
        on: MapSet.put(st.on, v)
    }

    st =
      Enum.reduce(successors(v, g), st, fn w, st ->
        cond do
          not Map.has_key?(st.index, w) ->
            st = scc_(w, g, st)
            %{st | low: Map.put(st.low, v, min(st.low[v], st.low[w]))}

          MapSet.member?(st.on, w) ->
            %{st | low: Map.put(st.low, v, min(st.low[v], st.low[w]))}

          true ->
            st
        end
      end)

    if st.low[v] == i, do: pop_to(v, i, st), else: st
  end

  defp pop_to(v, n, %{stack: [first | rest]} = st) do
    st = %{st | stack: rest, on: MapSet.delete(st.on, first)}

    if first == v,
      do: st,
      else: pop_to(v, n, %{st | low: Map.put(st.low, first, n)})
  end

  defp successors(v, g) do
    Enum.flat_map(edges!(g, v), fn e ->
      case succ(e, g) do
        nil -> []
        w -> [w]
      end
    end)
  end

  defp succ({:to, _, u, w, f}, g), do: if(g.flow[f] < u, do: w)
  defp succ({:from, _, _, w, f}, g), do: if(g.flow[f] > 0, do: w)

  # gcc_goals//1
  defp collect_goals(vals, g, low) do
    for val <- vals,
        {:to, _, _, v, f} <- edges!(g, val),
        g.flow[f] == 0,
        Map.has_key?(low, v) and Map.has_key?(low, val),
        low[v] != low[val],
        do: {v, g.value[val]}
  end
end
