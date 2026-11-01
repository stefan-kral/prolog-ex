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
  """
  use PrologEx.Builtin

  defbuiltin "$clpb_propagate", [bdd, p] do
    {:unify, [{p, propagate(bdd, subst())}]}
  end

  defp propagate(bdd, s) do
    with {:ok, order, nodes} <- preorder(bdd, s),
         vars = distinct_vars(order, nodes),
         {:ok, idx} <- indices(vars, s) do
      vs = Enum.sort_by(vars, &Map.fetch!(idx, &1))
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
            # gebunden wird – sichtbar in Antworten und beim labeling)
            do: mk("=", [d, b])

      mk("prop", [
        list(Enum.map(eqs, &elem(&1, 0))),
        list(Enum.map(eqs, &elem(&1, 1))),
        list(aliases)
      ])
    else
      :bound -> a("skip")
      :universal -> a("universal")
    end
  end

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

  # Index jeder Variablen; :universal bei einer allquantifizierten
  defp indices(vars, s) do
    Enum.reduce_while(vars, {:ok, %{}}, fn v, {:ok, acc} ->
      attrs = v |> PrologEx.get_attrs(s) |> Map.get("clpb", []) |> PrologEx.unmark() |> items()

      cond do
        Enum.any?(attrs, &match?({:struct, "clpb_atom", [_]}, &1)) ->
          {:halt, :universal}

        i = index(attrs, s) ->
          {:cont, {:ok, Map.put(acc, v, i)}}

        true ->
          {:halt, :universal}
      end
    end)
  end

  defp index(attrs, s) do
    Enum.find_value(attrs, fn
      {:struct, "clpb", [ir]} ->
        case PrologEx.unmark_top(PrologEx.walk(ir, s)) do
          {:struct, "index_root", [i, _]} -> PrologEx.walk(i, s)
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp items([]), do: []
  defp items([h | t]), do: [h | items(t)]
  defp items(_), do: []

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
end
