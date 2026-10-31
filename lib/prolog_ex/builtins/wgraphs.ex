defmodule PrologEx.Builtins.Wgraphs do
  @moduledoc """
  `library(wgraphs)` wie SICStus: gerichtete gewichtete Graphen als Listen
  von Paaren `Knoten-Kanten`, die Kanten Paare `Nachbar-Gewicht` (nach
  Nachbar sortiert, jeder Nachbar selbst ein Knoten); Gewichte sind Zahlen
  (bei SICStus nichtnegative Ganzzahlen). Eine Kante als Term:
  `U-(V-W)`.

  `wgraph_to_ugraph/2`, `ugraph_to_wgraph/2,3`,
  `vertices_edges_to_wgraph/3`, `vertices/2`, `edges/2`, `add_vertices/3`,
  `del_vertices/3`, `add_edges/3`, `del_edges/3`, `transpose_wgraph/2`,
  `neighbors/3`, `neighbours/3`, `transitive_closure/2`,
  `symmetric_closure/2`, `top_sort/2`, `max_path/5`, `min_path/5`,
  `min_paths/3`, `path/3`, `reduce/2`, `reachable/3`, `random_wgraph/4`,
  `min_tree/3`.

  Doppelte Kanten (beim Aufbau, `add_edges/3`, `symmetric_closure/2`)
  behalten das kleinste Gewicht, wie SICStus. Der transitive Abschluss
  gibt zu jedem erreichbaren Knoten die Länge des kürzesten Pfads (ohne
  neue Schlingen), `min_path/5` und `min_paths/3` nach Dijkstra,
  `min_tree/3` nach Kruskal. In Elixir (`PrologEx.Graphs`).
  """
  use PrologEx.Builtin, module: "wgraphs"
  alias PrologEx.Builtins.{Random, Ugraphs}
  alias PrologEx.{Error, Graphs}

  # --- Umwandeln ------------------------------------------------------------------

  defbuiltin "wgraph_to_ugraph", [wg, g] do
    ug =
      for {k, v, ns} <- Graphs.wgraph!(wg, subst()),
          do: {k, v, for({nk, n, _} <- ns, do: {nk, n})}

    {:unify, [{g, Graphs.term(ug)}]}
  end

  defbuiltin "ugraph_to_wgraph", [g, wg] do
    wg1 =
      for {k, v, ns} <- Graphs.ugraph!(g, subst()), do: {k, v, for({nk, n} <- ns, do: {nk, n, 1})}

    {:unify, [{wg, Graphs.term(wg1)}]}
  end

  # Teilgraph mit den Gewichten aus WG; scheitert, wenn eine Kante oder ein
  # Knoten dort fehlt (wie SICStus)
  defbuiltin "ugraph_to_wgraph", [sub, wg, wsub] do
    s = subst()
    idx = Graphs.index(Graphs.wgraph!(wg, s))

    Graphs.run(fn ->
      out =
        for {k, v, ns} <- Graphs.ugraph!(sub, s) do
          wns = Map.new(Graphs.neighbours!(idx, k), &{elem(&1, 0), &1})
          {k, v, for({nk, _} <- ns, do: Map.get(wns, nk) || Graphs.fail!())}
        end

      {:unify, [{wsub, Graphs.term(out)}]}
    end)
  end

  defbuiltin "vertices_edges_to_wgraph", [vs, es, g] do
    s = subst()
    {:unify, [{g, Graphs.term(Graphs.build(Graphs.vertex_list!(vs, s), Graphs.wedges!(es, s)))}]}
  end

  # --- Knoten und Kanten --------------------------------------------------------------

  defbuiltin "vertices", [g, vs] do
    {:unify, [{vs, list(Graphs.vertices!(g, subst()))}]}
  end

  defbuiltin "edges", [g, es] do
    {:unify, [{es, Graphs.edges_term(Graphs.wgraph!(g, subst()))}]}
  end

  defbuiltin "add_vertices", [g, vs, ng] do
    s = subst()

    {:unify,
     [{ng, Graphs.term(Graphs.add_vertices(Graphs.wgraph!(g, s), Graphs.vertex_list!(vs, s)))}]}
  end

  defbuiltin "del_vertices", [g, vs, ng] do
    s = subst()

    {:unify,
     [{ng, Graphs.term(Graphs.del_vertices(Graphs.wgraph!(g, s), Graphs.vertex_list!(vs, s)))}]}
  end

  defbuiltin "add_edges", [g, es, ng] do
    s = subst()
    new = Graphs.build([], Graphs.wedges!(es, s))
    {:unify, [{ng, Graphs.term(Graphs.union(Graphs.wgraph!(g, s), new))}]}
  end

  # Kanten U-(V-W) entfernen; das Gewicht zählt nicht
  defbuiltin "del_edges", [g, es, ng] do
    s = subst()
    old = Graphs.build([], Graphs.wedges!(es, s, false))
    {:unify, [{ng, Graphs.term(Graphs.difference(Graphs.wgraph!(g, s), old))}]}
  end

  defbuiltin "neighbors", [v, g, ns] do
    Ugraphs.neighbours(v, g, ns, subst())
  end

  defbuiltin "neighbours", [v, g, ns] do
    Ugraphs.neighbours(v, g, ns, subst())
  end

  # --- Abgeleitete Graphen ---------------------------------------------------------

  defbuiltin "transpose_wgraph", [g, t] do
    {:unify, [{t, Graphs.term(Graphs.transpose(Graphs.wgraph!(g, subst())))}]}
  end

  defbuiltin "transitive_closure", [g, c] do
    {:unify, [{c, Graphs.term(Graphs.wtransitive_closure(Graphs.wgraph!(g, subst())))}]}
  end

  defbuiltin "symmetric_closure", [g, c] do
    {:unify, [{c, Graphs.term(Graphs.symmetric_closure(Graphs.wgraph!(g, subst())))}]}
  end

  defbuiltin "reduce", [g, r] do
    Graphs.run(fn -> {:unify, [{r, Graphs.term(Graphs.reduce(Graphs.wgraph!(g, subst())))}]} end)
  end

  # --- Ordnen und Suchen -------------------------------------------------------------

  defbuiltin "top_sort", [g, l] do
    s = subst()

    Graphs.run(fn ->
      wg = Graphs.wgraph!(g, s)
      tm = Graphs.terms(wg)
      {:unify, [{l, list(Enum.map(Graphs.top_sort(wg), &Map.fetch!(tm, &1)))}]}
    end)
  end

  defbuiltin "reachable", [v, g, r] do
    s = subst()

    Graphs.run(fn ->
      wg = Graphs.wgraph!(g, s)
      tm = Graphs.terms(wg)
      ks = Graphs.reachable(Graphs.index(wg), Graphs.key(v, s))
      {:unify, [{r, list(Enum.map(ks, &Map.fetch!(tm, &1)))}]}
    end)
  end

  defbuiltin "min_path", [v1, v2, g, p, c] do
    s = subst()

    Graphs.run(fn ->
      wg = Graphs.wgraph!(g, s)
      tm = Graphs.terms(wg)
      {cost, ks} = Graphs.min_path(Graphs.index(wg), Graphs.key(v1, s), Graphs.key(v2, s))
      {:unify, [{p, list(Enum.map(ks, &Map.get(tm, &1, v1)))}, {c, cost}]}
    end)
  end

  # Baum der kürzesten Pfade als gewichteter Graph (Gewichte der Kanten)
  defbuiltin "min_paths", [v, g, t] do
    s = subst()

    Graphs.run(fn ->
      wg = Graphs.wgraph!(g, s)
      tm = Graphs.terms(wg)
      {edges, reached} = Graphs.min_paths(Graphs.index(wg), Graphs.key(v, s))
      vs = for k <- reached, do: {k, Map.fetch!(tm, k)}
      es = for {a, b, w} <- edges, do: {a, tm[a], b, tm[b], w}
      {:unify, [{t, Graphs.term(Graphs.build(vs, es))}]}
    end)
  end

  defbuiltin "max_path", [v1, v2, g, p, c] do
    s = subst()

    Graphs.run(fn ->
      wg = Graphs.wgraph!(g, s)
      tm = Graphs.terms(wg)
      {cost, ks} = Graphs.max_path(wg, Graphs.key(v1, s), Graphs.key(v2, s))
      {:unify, [{p, list(Enum.map(ks, &Map.fetch!(tm, &1)))}, {c, cost}]}
    end)
  end

  defbuiltin "path", [v, g, p], nondet: true do
    s = subst()
    wg = Graphs.wgraph!(g, s)
    tm = Graphs.terms(wg)
    wrap = fn ks -> {:unify, [{p, list(Enum.map(ks, &Map.fetch!(tm, &1)))}]} end
    Graphs.paths(Graphs.index(wg), Graphs.key(v, s), wrap)
  end

  # --- Bäume, Zufall ----------------------------------------------------------------

  defbuiltin "min_tree", [g, t, c] do
    s = subst()

    Graphs.run(fn ->
      wg = Graphs.wgraph!(g, s)
      tm = Graphs.terms(wg)
      {edges, cost} = Graphs.kruskal(wg)

      es =
        for {a, b, w} <- edges,
            e <- [{a, tm[a], b, tm[b], w}, {b, tm[b], a, tm[a], w}],
            do: e

      vs = for {k, v, _} <- wg, do: {k, v}
      {:unify, [{t, Graphs.term(Graphs.build(vs, es))}, {c, cost}]}
    end)
  end

  # Knoten 1..N, jede Kante mit Wahrscheinlichkeit P, Gewicht in 1..W
  defbuiltin "random_wgraph", [p, n, w, g] do
    {prob, size} = {Ugraphs.probability!(deref(p)), Ugraphs.size!(deref(n))}

    maxw =
      case deref(w) do
        x when is_integer(x) and x >= 1 -> x
        {:var, _} -> Error.instantiation!()
        x when is_integer(x) -> Error.domain!("not_less_than_one", x)
        x -> Error.type!("integer", x)
      end

    weight = fn -> Random.draw(&:rand.uniform_s(maxw, &1)) end
    {:unify, [{g, Ugraphs.random_ugraph(prob, size, weight)}]}
  end
end
