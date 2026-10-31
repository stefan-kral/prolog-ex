defmodule PrologEx.Graphs do
  @moduledoc """
  Kern von `library(ugraphs)` und `library(wgraphs)`: gerichtete Graphen
  als Listen von Paaren `Knoten-Nachbarn` (S-Darstellung, wie SWI, Scryer
  und SICStus). Bei `wgraphs` sind die Nachbarn Paare `Nachbar-Gewicht`.

  Intern ist ein Graph eine Liste `{schlüssel, knoten, nachbarn}`, nach
  Schlüssel sortiert; ein Nachbar ist `{schlüssel, term}` oder (gewichtet)
  `{schlüssel, term, gewicht}`. Der Schlüssel ist `PrologEx.Order.key/2`:
  ein Elixir-Term, dessen eingebaute Ordnung die Standardordnung ist und
  der für `==`-gleiche Terme gleich ist. So vergleicht, sortiert und
  sucht (Maps) die BEAM ohne Rückruf; die Knotenterme selbst werden nur
  durchgereicht.

  Wie bei SWI und SICStus wird nicht geprüft, ob die Listen sortiert sind.
  Eine Operation, die einen Knoten braucht, der nicht im Graphen ist
  (Nachbarn eines Nicht-Knotens), scheitert – wie dort. Intern wirft sie
  dafür `:graphs_fail` (siehe `run/1`).
  """
  import PrologEx, only: [mk: 2, list: 1]
  alias PrologEx.Builtins.Lists
  alias PrologEx.{Error, Order}

  # --- Scheitern ------------------------------------------------------------

  @doc "Führt `f` aus; ein Scheitern (`fail!/0`) darin ergibt `:fail`."
  def run(f) do
    f.()
  catch
    :graphs_fail -> :fail
  end

  @doc false
  def fail!, do: throw(:graphs_fail)

  # --- Einlesen -------------------------------------------------------------

  @doc "Elemente einer echten Liste; Teilliste `instantiation_error`, sonst `type_error(list, L)`"
  def items!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  @doc "`A-B` als `{a, b}`; sonst `type_error(pair, T)`"
  def pair!(t, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:struct, "-", [a, b]} -> {a, b}
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("pair", PrologEx.resolve(other, s))
    end
  end

  @doc "Gewicht: eine Zahl"
  def weight!(w, s) do
    case PrologEx.walk(w, s) do
      x when is_number(x) -> x
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("number", PrologEx.resolve(other, s))
    end
  end

  def key(t, s), do: Order.key(t, s)

  @doc "Knotenliste als `[{schlüssel, term}]` (Reihenfolge wie gegeben)"
  def vertex_list!(l, s), do: for(t <- items!(l, s), do: {key(t, s), t})

  @doc "Ungewichteter Graph"
  def ugraph!(g, s) do
    for e <- items!(g, s) do
      {v, ns} = pair!(e, s)
      {key(v, s), v, for(n <- items!(ns, s), do: {key(n, s), n})}
    end
  end

  @doc "Gewichteter Graph"
  def wgraph!(g, s) do
    for e <- items!(g, s) do
      {v, ns} = pair!(e, s)

      wns =
        for x <- items!(ns, s) do
          {n, w} = pair!(x, s)
          {key(n, s), n, weight!(w, s)}
        end

      {key(v, s), v, wns}
    end
  end

  @doc "Nur die Knoten eines Graphen (Nachbarlisten ungeprüft)"
  def vertices!(g, s) do
    for e <- items!(g, s) do
      {v, _} = pair!(e, s)
      v
    end
  end

  @doc "Kanten `U-V` als `{uk, u, vk, v}`"
  def edges!(l, s) do
    for e <- items!(l, s) do
      {u, v} = pair!(e, s)
      {key(u, s), u, key(v, s), v}
    end
  end

  @doc "Kanten `U-(V-W)` als `{uk, u, vk, v, w}`; `weights: false` lässt W ungeprüft"
  def wedges!(l, s, weights \\ true) do
    for e <- items!(l, s) do
      {u, vw} = pair!(e, s)
      {v, w} = pair!(vw, s)
      {key(u, s), u, key(v, s), v, if(weights, do: weight!(w, s), else: 0)}
    end
  end

  # --- Ausgeben -------------------------------------------------------------

  @doc "Graph als Prolog-Term"
  def term(g), do: list(for {_, v, ns} <- g, do: mk("-", [v, list(Enum.map(ns, &nterm/1))]))

  defp nterm({_, t}), do: t
  defp nterm({_, t, w}), do: mk("-", [t, w])

  @doc "Kanten als Prolog-Liste (`U-V` bzw. `U-(V-W)`)"
  def edges_term(g), do: list(for({_, u, ns} <- g, n <- ns, do: mk("-", [u, nterm(n)])))

  # --- Grundbausteine ---------------------------------------------------------

  def nkey(n), do: elem(n, 0)
  def weight({_, _}), do: 1
  def weight({_, _, w}), do: w

  @doc "Schlüssel → Nachbarn"
  def index(g), do: Map.new(g, fn {k, _, ns} -> {k, ns} end)

  @doc "Schlüssel → Term, für Knoten und Nachbarn"
  def terms(g) do
    Enum.reduce(g, %{}, fn {k, v, ns}, m ->
      Enum.reduce(ns, Map.put(m, k, v), fn n, m -> Map.put_new(m, nkey(n), elem(n, 1)) end)
    end)
  end

  @doc """
  Graph aus Knoten `[{k, t}]` und Kanten `{uk, u, vk, v}` bzw.
  `{uk, u, vk, v, w}`; gleiche Kanten einmal (gewichtet: das kleinste
  Gewicht, wie SICStus)
  """
  def build(vs, es) do
    terms =
      Enum.reduce(es, Map.new(vs), fn e, m ->
        m |> Map.put_new(elem(e, 0), elem(e, 1)) |> Map.put_new(elem(e, 2), elem(e, 3))
      end)

    adj = Enum.group_by(es, &elem(&1, 0), &edge_nb/1)

    for k <- terms |> Map.keys() |> Enum.sort(),
        do: {k, Map.fetch!(terms, k), norm(Map.get(adj, k, []))}
  end

  defp edge_nb({_, _, vk, v}), do: {vk, v}
  defp edge_nb({_, _, vk, v, w}), do: {vk, v, w}

  @doc "Nachbarn sortieren, gleiche einmal (gewichtet: das kleinste Gewicht)"
  def norm(ns), do: ns |> Enum.sort_by(&norm_key/1) |> Enum.dedup_by(&nkey/1)

  defp norm_key({k, _}), do: k
  defp norm_key({k, _, w}), do: {k, w}

  @doc "Kanten eines Graphen als `{uk, u, vk, v[, w]}`"
  def edges(g) do
    for {k, u, ns} <- g, n <- ns do
      case n do
        {nk, v} -> {k, u, nk, v}
        {nk, v, w} -> {k, u, nk, v, w}
      end
    end
  end

  @doc "Vereinigung (gleiche Knoten: Nachbarn vereinigen)"
  def union([], g), do: g
  def union(g, []), do: g

  def union([{k1, v1, n1} = a | t1] = g1, [{k2, _, n2} = b | t2] = g2) do
    cond do
      k1 < k2 -> [a | union(t1, g2)]
      k1 > k2 -> [b | union(g1, t2)]
      true -> [{k1, v1, ns_union(n1, n2)} | union(t1, t2)]
    end
  end

  @doc "Differenz: Kanten von g2 aus g1 entfernen (Knoten bleiben)"
  def difference(g, []), do: g
  def difference([], _), do: []

  def difference([{k1, v1, n1} = a | t1] = g1, [{k2, _, n2} | t2] = g2) do
    cond do
      k1 < k2 -> [a | difference(t1, g2)]
      k1 > k2 -> difference(g1, t2)
      true -> [{k1, v1, ns_subtract(n1, n2)} | difference(t1, t2)]
    end
  end

  @doc "Vereinigung zweier Nachbarlisten (gewichtet: kleineres Gewicht)"
  def ns_union([], b), do: b
  def ns_union(a, []), do: a

  def ns_union([x | xt] = a, [y | yt] = b) do
    {kx, ky} = {nkey(x), nkey(y)}

    cond do
      kx < ky -> [x | ns_union(xt, b)]
      kx > ky -> [y | ns_union(a, yt)]
      true -> [min_weight(x, y) | ns_union(xt, yt)]
    end
  end

  defp min_weight({_, _} = x, _), do: x
  defp min_weight({k, t, w1}, {_, _, w2}), do: {k, t, min(w1, w2)}

  @doc "Nachbarn ohne die (nach Schlüssel) aus b"
  def ns_subtract([], _), do: []
  def ns_subtract(a, []), do: a

  def ns_subtract([x | xt] = a, [y | yt] = b) do
    {kx, ky} = {nkey(x), nkey(y)}

    cond do
      kx < ky -> [x | ns_subtract(xt, b)]
      kx > ky -> ns_subtract(a, yt)
      true -> ns_subtract(xt, yt)
    end
  end

  @doc "Knoten (`[{k, t}]`) hinzufügen"
  def add_vertices(g, vs) do
    new = vs |> Enum.sort_by(&elem(&1, 0)) |> Enum.dedup_by(&elem(&1, 0))
    union(g, for({k, t} <- new, do: {k, t, []}))
  end

  @doc "Knoten und alle Kanten von und zu ihnen entfernen"
  def del_vertices(g, vs) do
    del = MapSet.new(vs, &elem(&1, 0))

    for {k, v, ns} <- g,
        not MapSet.member?(del, k),
        do: {k, v, Enum.reject(ns, &MapSet.member?(del, nkey(&1)))}
  end

  @doc "Kanten umdrehen (Knoten bleiben)"
  def transpose(g) do
    flipped =
      for e <- edges(g) do
        case e do
          {uk, u, vk, v} -> {vk, v, uk, u}
          {uk, u, vk, v, w} -> {vk, v, uk, u, w}
        end
      end

    build(for({k, v, _} <- g, do: {k, v}), flipped)
  end

  @doc "Symmetrischer Abschluss: g mit allen umgedrehten Kanten"
  def symmetric_closure(g), do: union(g, transpose(g))

  @doc "Nachbarn von k (scheitert, wenn k kein Knoten ist)"
  def neighbours!(idx, k) do
    case idx do
      %{^k => ns} -> ns
      _ -> fail!()
    end
  end

  # --- Komplement und Komposition ------------------------------------------

  @doc "Komplement: alle Kanten zwischen verschiedenen Knoten, die g nicht hat"
  def complement(g) do
    all = for {k, v, _} <- g, do: {k, v}

    for {k, v, ns} <- g do
      drop = MapSet.new([k | Enum.map(ns, &nkey/1)])
      {k, v, Enum.reject(all, &MapSet.member?(drop, elem(&1, 0)))}
    end
  end

  @doc "Komposition: u→w, wenn u→v in g1 und v→w in g2"
  def compose(g1, g2) do
    {i1, i2} = {index(g1), index(g2)}
    vs = union(for({k, v, _} <- g1, do: {k, v, []}), for({k, v, _} <- g2, do: {k, v, []}))

    for {k, v, _} <- vs do
      ns =
        case i1 do
          %{^k => n1} ->
            Enum.reduce(n1, [], fn n, acc -> ns_union(acc, Map.get(i2, nkey(n), [])) end)

          _ ->
            []
        end

      {k, v, ns}
    end
  end

  # --- Erreichbarkeit ---------------------------------------------------------

  @doc "Von k aus erreichbare Knoten, mit k, sortiert (wie SICStus/SWI: scheitert bei Nicht-Knoten)"
  def reachable(idx, k) do
    _ = neighbours!(idx, k)
    idx |> reach([k], MapSet.new([k])) |> Enum.sort()
  end

  defp reach(_idx, [], seen), do: seen

  defp reach(idx, [q | rest], seen) do
    new = for n <- neighbours!(idx, q), k = nkey(n), not MapSet.member?(seen, k), do: k
    reach(idx, new ++ rest, Enum.reduce(new, seen, &MapSet.put(&2, &1)))
  end

  @doc """
  Transitiver Abschluss. `self: true` (SWI, Scryer): ein Knoten auf einem
  Zyklus erreicht sich selbst; `self: false` (SICStus): nur eine
  ursprüngliche Schlinge bleibt.
  """
  def transitive_closure(g, self) do
    idx = index(g)
    tm = terms(g)

    for {k, v, ns} <- g do
      seen = closure_from(idx, Enum.map(ns, &nkey/1), MapSet.new())

      seen =
        if self or Enum.any?(ns, &(nkey(&1) == k)),
          do: seen,
          else: MapSet.delete(seen, k)

      {k, v, seen |> Enum.sort() |> Enum.map(&{&1, Map.fetch!(tm, &1)})}
    end
  end

  defp closure_from(_idx, [], seen), do: seen

  defp closure_from(idx, [n | rest], seen) do
    if MapSet.member?(seen, n),
      do: closure_from(idx, rest, seen),
      else: closure_from(idx, Enum.map(Map.get(idx, n, []), &nkey/1) ++ rest, MapSet.put(seen, n))
  end

  @doc """
  Transitiver Abschluss gewichtet (SICStus, Floyd): zu jedem erreichbaren
  Knoten die Länge des kürzesten Pfads; die eigene Schlinge bleibt, wie
  sie war.
  """
  def wtransitive_closure(g) do
    idx = index(g)
    tm = terms(g)

    for {k, v, ns} <- g do
      dist = distances(idx, ns)
      own = Enum.find(ns, &(nkey(&1) == k))

      dist =
        case own do
          nil -> Map.delete(dist, k)
          {_, _, w} -> Map.put(dist, k, w)
        end

      {k, v, dist |> Enum.sort() |> Enum.map(fn {n, d} -> {n, Map.fetch!(tm, n), d} end)}
    end
  end

  # Dijkstra ab den Kanten ns (Pfade mit mindestens einer Kante)
  defp distances(idx, ns) do
    {q, seq} =
      Enum.reduce(ns, {:gb_sets.new(), 0}, fn {n, _, w}, {q, i} ->
        {:gb_sets.add({w, i, n}, q), i + 1}
      end)

    distances(idx, q, seq, %{})
  end

  defp distances(idx, q, seq, dist) do
    if :gb_sets.is_empty(q) do
      dist
    else
      {{d, _, n}, q} = :gb_sets.take_smallest(q)

      if Map.has_key?(dist, n) do
        distances(idx, q, seq, dist)
      else
        {q, seq} =
          Enum.reduce(Map.get(idx, n, []), {q, seq}, fn {m, _, w}, {q, i} ->
            if Map.has_key?(dist, m), do: {q, i}, else: {:gb_sets.add({d + w, i, m}, q), i + 1}
          end)

        distances(idx, q, seq, Map.put(dist, n, d))
      end
    end
  end

  @doc "Transitive Reduktion (SICStus): g ohne die Kanten von g ∘ g⁺"
  def transitive_reduction(g), do: difference(g, compose(g, transitive_closure(g, false)))

  # --- Topologisch sortieren --------------------------------------------------

  @doc """
  Topologische Ordnung als Schlüsselliste (wie SWI und SICStus: Knoten
  ohne Vorgänger aufsteigend als Stapel; frei gewordene kommen oben
  drauf). Scheitert bei einem Zyklus oder einem Nachbarn, der kein Knoten
  ist.
  """
  def top_sort(g) do
    indeg0 = Map.new(g, &{elem(&1, 0), 0})

    indeg =
      Enum.reduce(g, indeg0, fn {_, _, ns}, acc ->
        Enum.reduce(ns, acc, fn n, a ->
          k = nkey(n)

          case a do
            %{^k => c} -> %{a | k => c + 1}
            _ -> fail!()
          end
        end)
      end)

    zeros = for {k, _, _} <- g, Map.fetch!(indeg, k) == 0, do: k
    ts(zeros, indeg, index(g), [], map_size(indeg))
  end

  defp ts([], _indeg, _idx, acc, 0), do: Enum.reverse(acc)
  defp ts([], _indeg, _idx, _acc, _left), do: fail!()

  defp ts([z | zs], indeg, idx, acc, left) do
    {indeg, zs} =
      Enum.reduce(Map.fetch!(idx, z), {indeg, zs}, fn n, {d, st} ->
        k = nkey(n)
        c = Map.fetch!(d, k) - 1
        {%{d | k => c}, if(c == 0, do: [k | st], else: st)}
      end)

    ts(zs, indeg, idx, [z | acc], left - 1)
  end

  # --- Starke Zusammenhangskomponenten (Tarjan) ----------------------------

  @doc "Komponenten als sortierte Schlüssellisten; Abbildung Schlüssel → Komponente"
  def components(g) do
    idx = index(g)
    st = %{n: 0, num: %{}, low: %{}, stack: [], on: MapSet.new(), out: []}

    st =
      Enum.reduce(g, st, fn {k, _, _}, st ->
        if Map.has_key?(st.num, k), do: st, else: strong(k, idx, st)
      end)

    comp = for c <- st.out, k <- c, into: %{}, do: {k, c}
    {st.out, comp}
  end

  defp strong(v, idx, st) do
    i = st.n

    st = %{
      st
      | n: i + 1,
        num: Map.put(st.num, v, i),
        low: Map.put(st.low, v, i),
        stack: [v | st.stack],
        on: MapSet.put(st.on, v)
    }

    st =
      Enum.reduce(neighbours!(idx, v), st, fn n, st ->
        w = nkey(n)

        cond do
          not Map.has_key?(idx, w) ->
            fail!()

          not Map.has_key?(st.num, w) ->
            st = strong(w, idx, st)
            %{st | low: Map.put(st.low, v, min(st.low[v], st.low[w]))}

          MapSet.member?(st.on, w) ->
            %{st | low: Map.put(st.low, v, min(st.low[v], st.num[w]))}

          true ->
            st
        end
      end)

    if st.low[v] == st.num[v] do
      {c, rest} = pop_component(st.stack, v, [])
      on = Enum.reduce(c, st.on, &MapSet.delete(&2, &1))
      %{st | stack: rest, on: on, out: [Enum.sort(c) | st.out]}
    else
      st
    end
  end

  defp pop_component([v | rest], v, acc), do: {[v | acc], rest}
  defp pop_component([w | rest], v, acc), do: pop_component(rest, v, [w | acc])

  @doc """
  Reduzierter Graph (SICStus): Knoten sind die Komponenten (sortierte
  Listen), eine Kante, wenn eine Kante zwischen ihnen verläuft (gewichtet:
  das kleinste Gewicht)
  """
  def reduce(g) do
    {cs, comp} = components(g)
    tm = terms(g)
    cterm = Map.new(cs, fn c -> {c, list(Enum.map(c, &Map.fetch!(tm, &1)))} end)

    es =
      for {k, _, ns} <- g, n <- ns, cu = comp[k], cv = comp[nkey(n)], cu != cv do
        case n do
          {_, _} -> {cu, cterm[cu], cv, cterm[cv]}
          {_, _, w} -> {cu, cterm[cu], cv, cterm[cv], w}
        end
      end

    build(Enum.map(cs, &{&1, cterm[&1]}), es)
  end

  # --- Pfade --------------------------------------------------------------------

  @doc """
  Kürzester Pfad (Dijkstra; ungewichtet = Breitensuche): `{kosten, [k]}`.
  Bei gleichen Kosten gewinnt der zuerst gefundene.
  """
  def min_path(idx, from, to) do
    q = :gb_sets.singleton({0, 0, from, nil})
    min_path(q, 1, idx, to, %{})
  end

  defp min_path(q, seq, idx, to, closed) do
    if :gb_sets.is_empty(q), do: fail!()
    {{c, _, v, par}, q} = :gb_sets.take_smallest(q)

    cond do
      v === to ->
        {c, back(closed, par, [v])}

      Map.has_key?(closed, v) ->
        min_path(q, seq, idx, to, closed)

      true ->
        closed = Map.put(closed, v, par)
        {q, seq} = push(neighbours!(idx, v), c, v, closed, q, seq)
        min_path(q, seq, idx, to, closed)
    end
  end

  defp push(ns, c, v, closed, q, seq) do
    Enum.reduce(ns, {q, seq}, fn n, {q, i} ->
      k = nkey(n)

      if Map.has_key?(closed, k),
        do: {q, i},
        else: {:gb_sets.add({c + weight(n), i, k, v}, q), i + 1}
    end)
  end

  defp back(_closed, nil, acc), do: acc
  defp back(closed, k, acc), do: back(closed, Map.fetch!(closed, k), [k | acc])

  @doc """
  Baum der kürzesten Pfade ab `from`: Kanten `{eltern, kind, gewicht}`
  und die erreichten Schlüssel
  """
  def min_paths(idx, from) do
    q = :gb_sets.singleton({0, 0, from, nil, 0})
    min_paths(q, 1, idx, %{}, [])
  end

  defp min_paths(q, seq, idx, closed, edges) do
    if :gb_sets.is_empty(q) do
      {Enum.reverse(edges), Map.keys(closed)}
    else
      {{c, _, v, par, w}, q} = :gb_sets.take_smallest(q)

      if Map.has_key?(closed, v) do
        min_paths(q, seq, idx, closed, edges)
      else
        ns = neighbours!(idx, v)
        closed = Map.put(closed, v, par)

        {q, seq} =
          Enum.reduce(ns, {q, seq}, fn n, {q, i} ->
            k = nkey(n)

            if Map.has_key?(closed, k),
              do: {q, i},
              else: {:gb_sets.add({c + weight(n), i, k, v, weight(n)}, q), i + 1}
          end)

        edges = if par == nil, do: edges, else: [{par, v, w} | edges]
        min_paths(q, seq, idx, closed, edges)
      end
    end
  end

  @doc """
  Längster Pfad von `from` nach `to` (SICStus): `{kosten, [k]}`. Auf dem
  Teilgraphen der Knoten zwischen beiden, der kreisfrei sein muss; in
  topologischer Ordnung von `to` rückwärts, bei gleichen Kosten gewinnt
  der zuerst gefundene (wie SICStus). Anders als dort zählt ein Knoten
  erst als erreicht, wenn ein Pfad zu `to` bekannt ist – sonst ginge eine
  Kante mit Gewicht 0 verloren.
  """
  def max_path(g, from, to) do
    tg = transpose(g)
    {idx, tidx} = {index(g), index(tg)}
    r = MapSet.new(reachable(idx, from))
    r = MapSet.intersection(r, MapSet.new(reachable(tidx, to)))

    sub =
      for {k, v, ns} <- tg,
          MapSet.member?(r, k),
          do: {k, v, Enum.filter(ns, &MapSet.member?(r, nkey(&1)))}

    sidx = index(sub)

    val =
      sub
      |> top_sort()
      |> Enum.reduce(%{to => {[], 0}}, fn v, val ->
        case val do
          %{^v => {path, cost}} ->
            Enum.reduce(Map.fetch!(sidx, v), val, fn n, val ->
              {k, c1} = {nkey(n), cost + weight(n)}

              case val do
                %{^k => {_, c0}} when c1 <= c0 -> val
                _ -> Map.put(val, k, {[v | path], c1})
              end
            end)

          _ ->
            val
        end
      end)

    case val do
      %{^from => {p, c}} -> {c, [from | p]}
      _ -> fail!()
    end
  end

  @doc """
  Maximale Pfade ab `from` (SICStus, Tiefensuche, Nachbarn aufsteigend),
  als lazy Liste von Schlüssellisten für ein nichtdeterministisches
  Builtin; `wrap` macht aus einem Pfad das Ergebnis.
  """
  def paths(idx, from, wrap) do
    case idx do
      %{^from => ns} ->
        on = MapSet.new([from])

        case free(ns, on) do
          [] -> [wrap.([from])]
          cs -> emit(next_path([{[from], on, cs}], idx), idx, wrap)
        end

      _ ->
        []
    end
  end

  defp free(ns, on), do: for(n <- ns, k = nkey(n), not MapSet.member?(on, k), do: k)

  # ein Ergebnis vorausschauen: das letzte ohne Choice Point
  defp emit(:done, _idx, _wrap), do: []

  defp emit({p, st}, idx, wrap) do
    case next_path(st, idx) do
      :done -> [wrap.(p)]
      nxt -> [wrap.(p) | fn -> emit(nxt, idx, wrap) end]
    end
  end

  defp next_path([], _idx), do: :done
  defp next_path([{_, _, []} | rest], idx), do: next_path(rest, idx)

  defp next_path([{q, on, [c | cs]} | rest], idx) do
    st = [{q, on, cs} | rest]

    case idx do
      %{^c => ns} ->
        on2 = MapSet.put(on, c)

        case free(ns, on2) do
          [] -> {Enum.reverse([c | q]), st}
          cands -> next_path([{[c | q], on2, cands} | st], idx)
        end

      _ ->
        next_path(st, idx)
    end
  end

  # --- Spannbäume und Cliquen ---------------------------------------------------

  @doc """
  Spannbaum eines ungerichteten Graphen nach Prim (SICStus): vom ersten
  Knoten aus wird jeweils der kleinste Kandidat mit dem kleinsten schon
  erreichten Nachbarn verbunden. Kanten `{v, w}`; scheitert, wenn der
  Graph leer oder nicht zusammenhängend ist.
  """
  def prim([]), do: fail!()

  def prim([{k0, _, ns0} | rest] = g) do
    reach = MapSet.new([k0])
    cands = ns0 |> Enum.map(&nkey/1) |> Enum.reject(&MapSet.member?(reach, &1))
    prim(length(rest), cands, index(g), reach, [])
  end

  defp prim(0, [], _idx, _reach, acc), do: Enum.reverse(acc)
  defp prim(0, _, _idx, _reach, _acc), do: fail!()
  defp prim(_, [], _idx, _reach, _acc), do: fail!()

  defp prim(i, [v | vs], idx, reach, acc) do
    keys = idx |> neighbours!(v) |> Enum.map(&nkey/1)
    w = Enum.find(keys, &MapSet.member?(reach, &1)) || fail!()
    reach = MapSet.put(reach, v)
    new = Enum.reject(keys, &MapSet.member?(reach, &1))
    prim(i - 1, :lists.umerge(vs, new), idx, reach, [{v, w} | acc])
  end

  @doc """
  Minimaler Spannbaum eines ungerichteten gewichteten Graphen nach Kruskal
  (SICStus): jede Kante einmal (vom größeren zum kleineren Knoten), nach
  Gewicht stabil sortiert. `{kanten {a, b, w}, kosten}`; scheitert, wenn
  der Graph leer oder nicht zusammenhängend ist.
  """
  def kruskal([]), do: fail!()

  def kruskal(g) do
    es =
      for {a, _, ns} <- g,
          {b, _, w} <- Enum.take_while(ns, &(nkey(&1) < a)),
          do: {w, a, b}

    kruskal(length(g), Enum.sort_by(es, &elem(&1, 0)), %{}, [], 0)
  end

  defp kruskal(1, _es, _uf, acc, cost), do: {Enum.reverse(acc), cost}
  defp kruskal(_n, [], _uf, _acc, _cost), do: fail!()

  defp kruskal(n, [{w, a, b} | es], uf, acc, cost) do
    {ra, uf} = find(uf, a)
    {rb, uf} = find(uf, b)

    if ra == rb,
      do: kruskal(n, es, uf, acc, cost),
      else: kruskal(n - 1, es, Map.put(uf, ra, rb), [{a, b, w} | acc], cost + w)
  end

  defp find(uf, x) do
    case uf do
      %{^x => p} ->
        {r, uf} = find(uf, p)
        {r, Map.put(uf, x, r)}

      _ ->
        {x, uf}
    end
  end

  @doc """
  Maximale Cliquen eines ungerichteten Graphen (SICStus, Bron–Kerbosch mit
  Pivot): sortierte Liste sortierter Schlüssellisten; Schlingen zählen
  nicht
  """
  def max_cliques(g) do
    idx = index(g)

    nb =
      Map.new(g, fn {k, _, ns} ->
        {k,
         ns
         |> Enum.map(&nkey/1)
         |> Enum.filter(&(&1 != k and Map.has_key?(idx, &1)))
         |> MapSet.new()}
      end)

    case Map.keys(idx) do
      [] -> []
      ks -> MapSet.new() |> bk(MapSet.new(ks), MapSet.new(), nb, []) |> Enum.sort()
    end
  end

  defp bk(r, p, x, nb, acc) do
    if MapSet.size(p) == 0 do
      if MapSet.size(x) == 0, do: [Enum.sort(r) | acc], else: acc
    else
      pivot = Enum.max_by(MapSet.union(p, x), &MapSet.size(MapSet.intersection(p, nb[&1])))

      {_, _, acc} =
        p
        |> MapSet.difference(nb[pivot])
        |> Enum.sort()
        |> Enum.reduce({p, x, acc}, fn v, {p, x, acc} ->
          nv = nb[v]

          acc =
            bk(MapSet.put(r, v), MapSet.intersection(p, nv), MapSet.intersection(x, nv), nb, acc)

          {MapSet.delete(p, v), MapSet.put(x, v), acc}
        end)

      acc
    end
  end
end
