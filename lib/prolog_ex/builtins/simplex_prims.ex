defmodule PrologEx.Builtins.SimplexPrims do
  @moduledoc """
  Kern von `library(simplex)` (`priv/library/simplex.pl`, Markus Triska):
  die Pivot-Schleife `simplex/2` und der Aufbau der Tableau-Zeilen
  `linsum_row/3` in Elixir. Das Profil (bench/prof/calls.exs) zeigte gut
  drei Viertel aller Prädikataufrufe dort, ein Viertel allein in
  `all_times_plus/4` (Zeile + Faktor · Pivotzeile).

  `'$simplex_simplex'(Tableau0, R)`: `R = ok(Tableau)` (optimal),
  `fallback` (im Tableau steht etwas anderes als Ganzzahlen und Brüche –
  dann rechnet das Original in Prolog), oder Scheitern (unbeschränkt, wie
  das Original). Jeder Schritt folgt dem Original: Optimalitätstest
  (`all_nonnegative/2`), Pivotspalte (erste negativste unter den aktiven,
  `first_negative/7` und `pivot_column/6`), Pivotzeile (erste kleinste
  Schranke B/Ae mit Ae > 0, `pivot_row/7`), Teilen der Pivotzeile,
  Gauß-Elimination (eine Zeile mit derselben Basisvariablen wie die
  Pivotzeile wird durch sie ersetzt, auch die Zielzeile), Basistausch
  (`swap_basic/4`). Gleichheit der Basisvariablen wie `==/2`, Arithmetik
  exakt wie `is/2` (`PrologEx.Rational`). Damit sind die Tableaus Term
  für Term dieselben; ein Test vergleicht das mit `simplex_ref/2`.

  `'$simplex_maximum_flow'(S, T)`: der maximale Fluss für Transport- und
  Zuordnungsproblem (`maximum_flow/2`, Edmonds-Karp über attributierte
  Variablen), siehe unten.

  Dazu `gauss_elimination/4`, `row_eliminate/4` und `find_row/3`
  außerhalb der Schleife (`'$simplex_gauss'/4`,
  `'$simplex_row_eliminate'/4`, `'$simplex_find_row'/3`).

  `'$simplex_linsum_row'(Vars, Linsum, Row)`: je Variable der Koeffizient
  aus `[C*V, ...]` (der erste, wie `member/2`), sonst 0 – über eine Map
  statt einer Suche je Variable. Scheitert bei nicht ganz gebundenen
  Termen; dann rechnet das Original (`linsum_row_ref/3`).
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.Atts
  alias PrologEx.Rational

  defbuiltin "$simplex_simplex", [t0, r] do
    case read_tableau(PrologEx.unmark(resolve(t0))) do
      {:ok, tab} ->
        case run(tab) do
          {:ok, tab} -> {:unify, [{r, mk("ok", [write_tableau(tab)])}]}
          :unbounded -> :fail
        end

      :error ->
        {:unify, [{r, a("fallback")}]}
    end
  end

  defbuiltin "$simplex_linsum_row", [vs, ls, cs] do
    vars = PrologEx.unmark(resolve(vs))
    terms = PrologEx.unmark(resolve(ls))

    if proper_ground?(vars) and proper_ground?(terms) do
      {:unify, [{cs, list(row_of(vars, coeffs(terms, %{})))}]}
    else
      :fail
    end
  end

  # gauss_elimination/4 und row_eliminate/4 außerhalb der Schleife
  # (Zwei-Phasen-Aufbau: proper_form/5, eliminate_artificial/5);
  # scheitern, wenn eine Zeile nicht nur Ganzzahlen und Brüche enthält –
  # dann rechnet das Original
  defbuiltin "$simplex_gauss", [rows0, prow, col, rows] do
    with {:ok, rs} <- read_rows(PrologEx.unmark(resolve(rows0))),
         {:ok, pr} <- read_row(PrologEx.unmark(resolve(prow))),
         c when is_integer(c) and c >= 0 <- deref(col) do
      {:unify, [{rows, list(write_rows(gauss(rs, pr, c)))}]}
    else
      _ -> :fail
    end
  end

  defbuiltin "$simplex_row_eliminate", [row0, prow, col, row] do
    with {:ok, r} <- read_row(PrologEx.unmark(resolve(row0))),
         {:ok, pr} <- read_row(PrologEx.unmark(resolve(prow))),
         c when is_integer(c) and c >= 0 <- deref(col) do
      {:unify, [{row, write_row(eliminate(r, pr, c))}]}
    else
      _ -> :fail
    end
  end

  # find_row/3: die erste Zeile row(V, _, _) mit V == Variable – nur die
  # Köpfe der Zeilen ansehen, ohne das Tableau aufzulösen
  defbuiltin "$simplex_find_row", [var, rows, r] do
    s = subst()
    v = resolve(var)

    case find_row(PrologEx.Store.walk(rows, s), v, s) do
      {:ok, row} -> {:unify, [{r, row}]}
      _ -> :fail
    end
  end

  defp find_row(l, v, s) do
    case PrologEx.uncons(l) do
      {:cons, row, rest} ->
        row = PrologEx.Store.walk(row, s)

        case row do
          {tag, "row", [rv, _, _]} when tag in [:struct, :gstruct] ->
            if PrologEx.resolve(rv, s) === v,
              do: {:ok, row},
              else: find_row(PrologEx.Store.walk(rest, s), v, s)

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  # --- maximaler Fluss (Transport- und Zuordnungsproblem) ----------------

  # maximum_flow/2 (Edmonds-Karp über attributierte Variablen des Moduls
  # simplex: node/1, edges/1, flow/1, parent/1), Schritt für Schritt wie
  # das Original: Breitensuche Ebene für Ebene (Knoten und Kanten in ihrer
  # Reihenfolge, ein Knoten bekommt parent/1 beim ersten Erreichen), bis
  # eine Ebene die Senke enthält; den Pfad über parent/1 zurück, sein
  # Minimum (inf zählt nicht), den Fluss jeder Kante erhöhen bzw.
  # senken, parent/1 aller besuchten Knoten löschen, von vorn. Ohne Pfad
  # bleibt alles, wie es war (wie die gescheiterte Bedingung im Original).
  # Scheitert bei Unerwartetem (Fluss keine Ganzzahl, ...); dann rechnet
  # maximum_flow_ref/2.
  @flow_mod "simplex"

  defbuiltin "$simplex_maximum_flow", [src, sink] do
    s = subst()

    with {:var, _} = sv <- deref(src),
         {:var, _} = tv <- deref(sink) do
      try do
        {:subst, max_flow(sv, tv, s)}
      catch
        :fallback -> :fail
      end
    else
      _ -> :fail
    end
  end

  defp max_flow(sv, tv, s) do
    case bfs([[sv]], tv, s) do
      {:found, levels, s} ->
        [{_, first, _} | rest] = path = trace(tv, sv, s)
        min = path_min(rest, first)
        if min == :inf, do: throw(:fallback)
        s = augment_all(path, min, s)
        max_flow(sv, tv, clear_levels(levels, s))

      :none ->
        s
    end
  end

  defp bfs([vs | _] = levels, t, s) do
    case reach_level(vs, s, []) do
      {[_ | _] = tos, s} ->
        levels = [tos | levels]
        if identical_member?(tos, t), do: {:found, levels, s}, else: bfs(levels, t, s)

      _ ->
        :none
    end
  end

  defp identical_member?([], _t), do: false
  defp identical_member?([v | vs], t), do: v === t or identical_member?(vs, t)

  # reachables//1: je Knoten seine Kanten; ein Knoten ohne edges/1 lässt
  # die Suche scheitern (wie get_atts/2 im Original)
  defp reach_level([], s, acc), do: {:lists.reverse(acc), s}

  defp reach_level([v | vs], s, acc) do
    case Atts.get_one(v, @flow_mod, "edges", s) do
      nil ->
        :fail

      es ->
        {s, acc} = reach_edges(walk(es, s), v, s, acc)
        reach_level(vs, s, acc)
    end
  end

  defp reach_edges(es, p, s, acc) do
    case PrologEx.uncons(es) do
      {:cons, e, rest} ->
        {s, acc} = reach(PrologEx.unmark_top(walk(e, s)), p, s, acc)
        reach_edges(walk(rest, s), p, s, acc)

      _ ->
        {s, acc}
    end
  end

  # reachable//2: Rückwärtskante mit Fluss > 0, Vorwärtskante mit Platz
  defp reach({tag, "arc_from", [w, f, _]}, p, s, acc) when tag in [:struct, :gstruct] do
    w = walk(w, s)

    with nil <- Atts.get_one(w, @flow_mod, "parent", s),
         flow when flow != nil <- Atts.get_one(f, @flow_mod, "flow", s),
         flow = int!(walk(flow, s)),
         true <- flow > 0 do
      {set_parent(s, w, p, f, flow, "-"), [w | acc]}
    else
      _ -> {s, acc}
    end
  end

  defp reach({tag, "arc_to", [w, f, c]}, p, s, acc) when tag in [:struct, :gstruct] do
    w = walk(w, s)

    with nil <- Atts.get_one(w, @flow_mod, "parent", s),
         flow when flow != nil <- Atts.get_one(f, @flow_mod, "flow", s),
         flow = int!(walk(flow, s)),
         c = walk(c, s),
         true <- c == {:atom, "inf"} or flow < int!(c) do
      diff = if c == {:atom, "inf"}, do: c, else: c - flow
      {set_parent(s, w, p, f, diff, "+"), [w | acc]}
    else
      _ -> {s, acc}
    end
  end

  defp reach(_edge, _p, _s, _acc), do: throw(:fallback)

  defp set_parent(s, w, p, f, amount, sign),
    do:
      Atts.put_one(
        s,
        w,
        @flow_mod,
        mk("parent", [mk("-", [p, mk("augment", [f, amount, a(sign)])])])
      )

  # augmenting_path//2: von der Senke über parent/1 zurück zur Quelle
  defp trace(v, sv, _s) when v === sv, do: []

  defp trace(v, sv, s) do
    with {tag, "-", [v1, aug]} when tag in [:struct, :gstruct] <-
           walk(Atts.get_one(v, @flow_mod, "parent", s) || throw(:fallback), s),
         {tag2, "augment", [f, amount, sign]} when tag2 in [:struct, :gstruct] <- walk(aug, s) do
      [{f, walk(amount, s), walk(sign, s)} | trace(walk(v1, s), sv, s)]
    else
      _ -> throw(:fallback)
    end
  end

  # path_minimum/3: inf zählt nicht
  defp path_min([], m), do: inf_atom(m)
  defp path_min([{_, {:atom, "inf"}, _} | rest], m), do: path_min(rest, m)
  defp path_min([{_, a, _} | rest], {:atom, "inf"}), do: path_min(rest, int!(a))
  defp path_min([{_, a, _} | rest], m), do: path_min(rest, min(int!(m), int!(a)))

  defp inf_atom({:atom, "inf"}), do: :inf
  defp inf_atom(m), do: int!(m)

  # augment/2 je Kante: flow/1 um min erhöhen (+) bzw. senken (-)
  defp augment_all([], _min, s), do: s

  defp augment_all([{f, _, sign} | rest], min, s) do
    flow = int!(walk(Atts.get_one(f, @flow_mod, "flow", s) || throw(:fallback), s))

    new =
      case sign do
        {:atom, "+"} -> flow + min
        {:atom, "-"} -> flow - min
        _ -> throw(:fallback)
      end

    augment_all(rest, min, Atts.put_one(s, f, @flow_mod, mk("flow", [new])))
  end

  # clear_parent/1 für alle besuchten Knoten
  defp clear_levels([], s), do: s
  defp clear_levels([vs | levels], s), do: clear_levels(levels, clear_level(vs, s))

  defp clear_level([], s), do: s
  defp clear_level([v | vs], s), do: clear_level(vs, Atts.del_one(s, v, @flow_mod, "parent"))

  defp int!(x) when is_integer(x), do: x
  defp int!(_), do: throw(:fallback)

  defp walk(t, s), do: PrologEx.Store.walk(t, s)

  # --- linsum_row ---------------------------------------------------------

  # erster Koeffizient je Variable (member/2 nimmt den ersten Treffer)
  defp coeffs([], m), do: m

  defp coeffs([{:struct, "*", [c, v]} | ts], m),
    do: coeffs(ts, if(is_map_key(m, v), do: m, else: Map.put(m, v, c)))

  defp coeffs([_ | ts], m), do: coeffs(ts, m)

  defp row_of([], _m), do: []
  defp row_of([v | vs], m), do: [Map.get(m, v, 0) | row_of(vs, m)]

  defp proper_ground?([]), do: true
  defp proper_ground?([h | t]), do: ground?(h) and proper_ground?(t)
  defp proper_ground?(_), do: false

  defp ground?({:var, _}), do: false
  defp ground?({:struct, _, args}), do: proper_ground?(args)
  defp ground?([h | t]), do: ground?(h) and ground?(t)
  defp ground?(_), do: true

  # --- Tableau lesen und schreiben ----------------------------------------

  # {Zielzeile, Variablen, Indikatoren, Zeilen}; eine Zeile {Var, Koeffizienten, rechte Seite}
  defp read_tableau({:struct, "tableau", [obj, vars, inds, rows]}) do
    with {:ok, obj} <- read_row(obj),
         true <- is_list(vars),
         {:ok, inds} <- numbers(inds),
         {:ok, rows} <- read_rows(rows) do
      {:ok, {obj, vars, inds, rows}}
    else
      _ -> :error
    end
  end

  defp read_tableau(_), do: :error

  defp read_row({:struct, "row", [v, left, right]}) do
    with {:ok, left} <- numbers(left), true <- exact?(right), do: {:ok, {v, left, right}}
  end

  defp read_row(_), do: :error

  defp read_rows([]), do: {:ok, []}

  defp read_rows([r | rs]) do
    with {:ok, r} <- read_row(r), {:ok, rs} <- read_rows(rs), do: {:ok, [r | rs]}
  end

  defp read_rows(_), do: :error

  defp numbers(l), do: if(exact_list?(l), do: {:ok, l}, else: :error)

  defp exact_list?([]), do: true
  defp exact_list?([x | xs]), do: exact?(x) and exact_list?(xs)
  defp exact_list?(_), do: false

  defp exact?(x) when is_integer(x), do: true
  defp exact?({:rat, _, _}), do: true
  defp exact?(_), do: false

  defp write_tableau({obj, vars, inds, rows}),
    do: mk("tableau", [write_row(obj), list(vars), list(inds), list(write_rows(rows))])

  defp write_row({v, left, right}), do: mk("row", [v, list(left), right])

  defp write_rows([]), do: []
  defp write_rows([r | rs]), do: [write_row(r) | write_rows(rs)]

  # --- Pivot-Schleife -----------------------------------------------------

  defp run({{_, ol, _} = obj, vars, inds, rows} = tab) do
    if optimal?(ol, inds) do
      {:ok, tab}
    else
      pcol = pivot_column(ol, inds)

      case pivot_row(rows, pcol, nil, nil, 0) do
        nil ->
          :unbounded

        prow ->
          {leaving, left0, right0} = Enum.at(rows, prow)
          pe = nth(left0, pcol)
          row1 = {leaving, divide_all(left0, pe), Rational.divide(right0, pe)}
          [obj | rows] = gauss([obj | rows], row1, pcol)

          case swap_basic(rows, leaving, Enum.at(vars, pcol)) do
            {:ok, rows} -> run({obj, vars, inds, rows})
            :none -> :unbounded
          end
      end
    end
  end

  # all_nonnegative/2: inaktive Spalten (Indikator 0) zählen nicht
  defp optimal?([c | cs], [i | is]),
    do: (zero?(i) or Rational.sign(c) >= 0) and optimal?(cs, is)

  defp optimal?(_, _), do: true

  # first_negative/7, dann pivot_column/6: kleinster Koeffizient (der erste
  # bei Gleichstand) unter den aktiven, gesucht ab dem ersten negativen
  defp pivot_column(ls, is), do: first_negative(ls, is, 0)

  defp first_negative([l | ls], [i | is], idx) do
    if not zero?(i) and Rational.sign(l) < 0,
      do: min_column(ls, is, l, idx + 1, idx),
      else: first_negative(ls, is, idx + 1)
  end

  defp min_column([l | ls], [i | is], min, idx, best) do
    if not zero?(i) and Rational.cmp(l, min) == :lt,
      do: min_column(ls, is, l, idx + 1, idx),
      else: min_column(ls, is, min, idx + 1, best)
  end

  defp min_column(_, _, _, _, best), do: best

  # pivot_row/7: Zeile mit der kleinsten Schranke B/Ae (Ae > 0), bei
  # Gleichstand die erste; keine solche Zeile: unbeschränkt (nil)
  defp pivot_row([], _pcol, _min, best, _idx), do: best

  defp pivot_row([{_, left, b} | rows], pcol, min, best, idx) do
    ae = nth(left, pcol)

    if Rational.sign(ae) > 0 do
      bound = Rational.divide(b, ae)

      if min == nil or Rational.cmp(bound, min) == :lt,
        do: pivot_row(rows, pcol, bound, idx, idx + 1),
        else: pivot_row(rows, pcol, min, best, idx + 1)
    else
      pivot_row(rows, pcol, min, best, idx + 1)
    end
  end

  # gauss_elimination/4 mit row_eliminate/4 und all_times_plus/4
  defp gauss([], _prow, _col), do: []

  defp gauss([{var, _, _} = row | rows], {pvar, _, _} = prow, col) do
    row = if var === pvar, do: prow, else: eliminate(row, prow, col)
    [row | gauss(rows, prow, col)]
  end

  # row_eliminate/4: Zeile - Koeffizient · Pivotzeile (0: unverändert)
  defp eliminate({var, ls0, r0} = row, {_, pls, pr}, col) do
    coeff = nth(ls0, col)

    if zero?(coeff) do
      row
    else
      m = Rational.neg(coeff)
      {var, times_plus(pls, m, ls0), add(mul(pr, m), r0)}
    end
  end

  defp times_plus([a | as], t, [b | bs]), do: [add(mul(a, t), b) | times_plus(as, t, bs)]
  defp times_plus(_, _, _), do: []

  defp divide_all([], _d), do: []
  defp divide_all([x | xs], d), do: [Rational.divide(x, d) | divide_all(xs, d)]

  # swap_basic/4: in der ersten Zeile mit Basisvariable old wird sie new
  defp swap_basic([], _old, _new), do: :none

  defp swap_basic([{var, l, r} = row | rows], old, new) do
    if var === old do
      {:ok, [{new, l, r} | rows]}
    else
      with {:ok, rows} <- swap_basic(rows, old, new), do: {:ok, [row | rows]}
    end
  end

  defp nth([x | _], 0), do: x
  defp nth([_ | xs], n), do: nth(xs, n - 1)

  defp zero?(0), do: true
  defp zero?(_), do: false

  # Ganzzahlen direkt, Brüche über PrologEx.Rational
  defp add(a, b) when is_integer(a) and is_integer(b), do: a + b
  defp add(a, b), do: Rational.add(a, b)
  defp mul(a, b) when is_integer(a) and is_integer(b), do: a * b
  defp mul(a, b), do: Rational.mul(a, b)
end
