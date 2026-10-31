defmodule PrologEx.Builtins.Ugraphs do
  @moduledoc """
  `library(ugraphs)`: gerichtete ungewichtete Graphen als Listen von
  Paaren `Knoten-Nachbarn` (Knoten und Nachbarn nach der Standardordnung,
  jeder Nachbar selbst ein Knoten), die Vereinigung der Bibliotheken von
  SWI (= Scryer) und SICStus:

    * beide: `vertices_edges_to_ugraph/3`, `vertices/2`, `edges/2`,
      `add_vertices/3`, `del_vertices/3`, `add_edges/3`, `del_edges/3`,
      `transpose_ugraph/2`, `neighbors/3`, `neighbours/3`, `complement/2`,
      `compose/3`, `transitive_closure/2`, `top_sort/2`, `reachable/3`
    * SWI und Scryer: `top_sort/3`, `ugraph_union/3`, `connect_ugraph/3`
    * SICStus: `symmetric_closure/2`, `transitive_reduction/2`,
      `max_path/5`, `min_path/5`, `min_paths/3`, `path/3`, `reduce/2`,
      `random_ugraph/3`, `min_tree/3`, `max_cliques/2`

  In Elixir (`PrologEx.Graphs`). Ein ungerichteter Graph hat zu jeder
  Kante die Gegenkante. Wo SWI und SICStus sich unterscheiden: beim
  transitiven Abschluss erreicht ein Knoten auf einem Zyklus sich selbst
  (wie SWI und Scryer; SICStus lässt diese Schlingen weg).

  Bewusst anders als die Vorbilder, in Randfällen:
    * `path/3` nimmt auch über eine Schlinge keinen Knoten zweimal
      (SICStus: `[1,1]` bei `1-[1]`)
    * `min_tree/3` eines Graphen mit einem Knoten ist `[V-[]]` (SICStus:
      `[]`); `min_paths/3` (gewichtet) enthält den Startknoten auch ohne
      Kanten
    * `max_path/5` (gewichtet) verliert keine Kante mit Gewicht 0
    * `del_vertices/3` entfernt alle genannten Knoten (SWI behält einen,
      wenn davor ein Knoten genannt ist, der fehlt)
  """
  use PrologEx.Builtin, module: "ugraphs"
  alias PrologEx.Builtins.Random
  alias PrologEx.{Error, Graphs}

  # --- Aufbauen und Zerlegen ---------------------------------------------------

  defbuiltin "vertices_edges_to_ugraph", [vs, es, g] do
    s = subst()
    {:unify, [{g, Graphs.term(Graphs.build(Graphs.vertex_list!(vs, s), Graphs.edges!(es, s)))}]}
  end

  defbuiltin "vertices", [g, vs] do
    {:unify, [{vs, list(Graphs.vertices!(g, subst()))}]}
  end

  defbuiltin "edges", [g, es] do
    {:unify, [{es, Graphs.edges_term(Graphs.ugraph!(g, subst()))}]}
  end

  defbuiltin "add_vertices", [g, vs, ng] do
    s = subst()

    {:unify,
     [{ng, Graphs.term(Graphs.add_vertices(Graphs.ugraph!(g, s), Graphs.vertex_list!(vs, s)))}]}
  end

  defbuiltin "del_vertices", [g, vs, ng] do
    s = subst()

    {:unify,
     [{ng, Graphs.term(Graphs.del_vertices(Graphs.ugraph!(g, s), Graphs.vertex_list!(vs, s)))}]}
  end

  defbuiltin "add_edges", [g, es, ng] do
    s = subst()
    new = Graphs.build([], Graphs.edges!(es, s))
    {:unify, [{ng, Graphs.term(Graphs.union(Graphs.ugraph!(g, s), new))}]}
  end

  defbuiltin "del_edges", [g, es, ng] do
    s = subst()
    old = Graphs.build([], Graphs.edges!(es, s))
    {:unify, [{ng, Graphs.term(Graphs.difference(Graphs.ugraph!(g, s), old))}]}
  end

  # SWI: Vereinigung zweier Graphen
  defbuiltin "ugraph_union", [g1, g2, g] do
    s = subst()
    {:unify, [{g, Graphs.term(Graphs.union(Graphs.ugraph!(g1, s), Graphs.ugraph!(g2, s)))}]}
  end

  defbuiltin "neighbors", [v, g, ns] do
    neighbours(v, g, ns, subst())
  end

  defbuiltin "neighbours", [v, g, ns] do
    neighbours(v, g, ns, subst())
  end

  # --- Abgeleitete Graphen ---------------------------------------------------------

  defbuiltin "transpose_ugraph", [g, t] do
    {:unify, [{t, Graphs.term(Graphs.transpose(Graphs.ugraph!(g, subst())))}]}
  end

  defbuiltin "complement", [g, c] do
    {:unify, [{c, Graphs.term(Graphs.complement(Graphs.ugraph!(g, subst())))}]}
  end

  defbuiltin "compose", [g1, g2, c] do
    s = subst()
    {:unify, [{c, Graphs.term(Graphs.compose(Graphs.ugraph!(g1, s), Graphs.ugraph!(g2, s)))}]}
  end

  # wie SWI und Scryer: ein Knoten auf einem Zyklus erreicht sich selbst
  defbuiltin "transitive_closure", [g, c] do
    {:unify, [{c, Graphs.term(Graphs.transitive_closure(Graphs.ugraph!(g, subst()), true))}]}
  end

  defbuiltin "transitive_reduction", [g, r] do
    {:unify, [{r, Graphs.term(Graphs.transitive_reduction(Graphs.ugraph!(g, subst())))}]}
  end

  defbuiltin "symmetric_closure", [g, c] do
    {:unify, [{c, Graphs.term(Graphs.symmetric_closure(Graphs.ugraph!(g, subst())))}]}
  end

  defbuiltin "reduce", [g, r] do
    Graphs.run(fn -> {:unify, [{r, Graphs.term(Graphs.reduce(Graphs.ugraph!(g, subst())))}]} end)
  end

  # --- Ordnen und Suchen -------------------------------------------------------------

  defbuiltin "top_sort", [g, l] do
    top_sort(g, l, [], subst())
  end

  # SWI: Differenzliste – L ist die Ordnung, gefolgt von Tail
  defbuiltin "top_sort", [g, tail, l] do
    top_sort(g, l, tail, subst())
  end

  # SWI: neuer Knoten Start vor allen anderen, mit Kanten zu allen
  defbuiltin "connect_ugraph", [g, start, ng] do
    s = subst()

    case Graphs.vertices!(g, s) do
      [] ->
        {:unify, [{start, 0}, {ng, []}]}

      [first | _] = vs ->
        st =
          case deref(first) do
            {:var, _} -> Error.instantiation!()
            x when is_number(x) -> x - 1
            _ -> 0
          end

        {:unify, [{start, st}, {ng, cons(mk("-", [st, list(vs)]), g)}]}
    end
  end

  defbuiltin "reachable", [v, g, r] do
    s = subst()

    Graphs.run(fn ->
      ug = Graphs.ugraph!(g, s)
      tm = Graphs.terms(ug)
      ks = Graphs.reachable(Graphs.index(ug), Graphs.key(v, s))
      {:unify, [{r, list(Enum.map(ks, &Map.get(tm, &1, v)))}]}
    end)
  end

  defbuiltin "min_path", [v1, v2, g, p, l] do
    s = subst()

    Graphs.run(fn ->
      ug = Graphs.ugraph!(g, s)
      tm = Graphs.terms(ug)
      {k1, k2} = {Graphs.key(v1, s), Graphs.key(v2, s)}
      {c, ks} = Graphs.min_path(Graphs.index(ug), k1, k2)
      {:unify, [{p, list(Enum.map(ks, &Map.get(tm, &1, v1)))}, {l, c}]}
    end)
  end

  defbuiltin "min_paths", [v, g, t] do
    s = subst()

    Graphs.run(fn ->
      ug = Graphs.ugraph!(g, s)
      tm = Graphs.terms(ug)
      {edges, reached} = Graphs.min_paths(Graphs.index(ug), Graphs.key(v, s))
      vs = for k <- reached, do: {k, Map.fetch!(tm, k)}
      es = for {a, b, _} <- edges, do: {a, tm[a], b, tm[b]}
      {:unify, [{t, Graphs.term(Graphs.build(vs, es))}]}
    end)
  end

  defbuiltin "max_path", [v1, v2, g, p, c] do
    s = subst()

    Graphs.run(fn ->
      ug = Graphs.ugraph!(g, s)
      tm = Graphs.terms(ug)
      {cost, ks} = Graphs.max_path(ug, Graphs.key(v1, s), Graphs.key(v2, s))
      {:unify, [{p, list(Enum.map(ks, &Map.fetch!(tm, &1)))}, {c, cost}]}
    end)
  end

  defbuiltin "path", [v, g, p], nondet: true do
    s = subst()
    ug = Graphs.ugraph!(g, s)
    tm = Graphs.terms(ug)
    wrap = fn ks -> {:unify, [{p, list(Enum.map(ks, &Map.fetch!(tm, &1)))}]} end
    Graphs.paths(Graphs.index(ug), Graphs.key(v, s), wrap)
  end

  # --- Bäume, Cliquen, Zufall ------------------------------------------------------

  defbuiltin "min_tree", [g, t, c] do
    s = subst()

    Graphs.run(fn ->
      ug = Graphs.ugraph!(g, s)
      tm = Graphs.terms(ug)
      edges = Graphs.prim(ug)
      es = for {a, b} <- edges, e <- [{a, tm[a], b, tm[b]}, {b, tm[b], a, tm[a]}], do: e
      vs = for {k, v, _} <- ug, do: {k, v}
      {:unify, [{t, Graphs.term(Graphs.build(vs, es))}, {c, length(edges)}]}
    end)
  end

  defbuiltin "max_cliques", [g, cs] do
    ug = Graphs.ugraph!(g, subst())
    tm = Graphs.terms(ug)
    cliques = for c <- Graphs.max_cliques(ug), do: list(Enum.map(c, &Map.fetch!(tm, &1)))
    {:unify, [{cs, list(cliques)}]}
  end

  defbuiltin "random_ugraph", [p, n, g] do
    {prob, size} = {probability!(deref(p)), size!(deref(n))}
    {:unify, [{g, random_ugraph(prob, size)}]}
  end

  # --- Hilfen --------------------------------------------------------------------------

  @doc false
  # wie SWI und SICStus: die Nachbarliste, wie sie im Graphen steht
  def neighbours(v, g, ns, s) do
    k = Graphs.key(v, s)

    Enum.find_value(Graphs.items!(g, s), :fail, fn e ->
      {u, uns} = Graphs.pair!(e, s)
      if Graphs.key(u, s) == k, do: {:unify, [{ns, uns}]}
    end)
  end

  defp top_sort(g, l, tail, s) do
    Graphs.run(fn ->
      ug = Graphs.ugraph!(g, s)
      tm = Graphs.terms(ug)
      {:unify, [{l, list(Enum.map(Graphs.top_sort(ug), &Map.fetch!(tm, &1)), tail)}]}
    end)
  end

  @doc false
  # Wahrscheinlichkeit: ein Float in [0.0, 1.0] (wie SICStus)
  def probability!(x) when is_float(x) and x >= 0.0 and x <= 1.0, do: x
  def probability!({:var, _}), do: Error.instantiation!()

  def probability!(x) when is_float(x),
    do: Error.error!(mk("domain_error", [mk("between", [0.0, 1.0]), x]))

  def probability!(x), do: Error.type!("float", x)

  @doc false
  def size!(n) when is_integer(n) and n >= 0, do: n
  def size!({:var, _}), do: Error.instantiation!()
  def size!(n) when is_integer(n), do: Error.domain!("not_less_than_zero", n)
  def size!(n), do: Error.type!("integer", n)

  @doc false
  # Knoten 1..N, jede Kante zwischen verschiedenen Knoten mit
  # Wahrscheinlichkeit P; `weight` gibt (gewichtet) das Gewicht
  def random_ugraph(p, n, weight \\ nil) do
    list(
      for i <- 1..n//1 do
        ns =
          for j <- 1..n//1, j != i, Random.draw(&:rand.uniform_real_s/1) <= p do
            if weight, do: mk("-", [j, weight.()]), else: j
          end

        mk("-", [i, list(ns)])
      end
    )
  end
end
