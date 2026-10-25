defmodule PrologEx.Builtins.Lists do
  @moduledoc """
  Listenprädikate: append/3, length/2, member/2, numlist/2,3, between/3
  (alle vom Benutzer überschreibbar), dazu die Hilfsfunktion `skip_list/2`.

  ## member/2, between/3

  Lösungen als lazy Liste (siehe `PrologEx.Builtin`): die nächste Lösung
  entsteht erst beim Backtracking, und nach der letzten bleibt kein Choice
  Point. member/2 läuft die Listenzellen entlang; trifft es auf einen
  ungebundenen Rest, übernimmt die klassische Definition `$member/2`
  (erzeugt dann wie üblich `[X|_]`, `[_,X|_]`, ...). between/3 erlaubt
  `inf`/`infinite` als obere Grenze; ist X gebunden, wird nur geprüft.

  ## numlist/3, numlist/2

  `numlist(Lo, Hi, L)`: L = [Lo, ..., Hi] (scheitert bei Lo > Hi), in
  Elixir gebaut und gleich als ground Liste markiert.
  `numlist(N, L)` ist in Prolog definiert: `numlist(N, L) :- numlist(1, N, L).`

  ## append/3 – hybrid

  Ist das erste Argument eine echte Liste (Ende `[]`), wird das Ergebnis
  direkt in Elixir gebaut und unifiziert – deterministisch, ohne Choice
  Points. Ist das erste Argument eine markierte ground Liste, übernimmt
  `++` der BEAM die Arbeit. Sonst (erstes Argument offen oder keine Liste)
  läuft die klassische Definition `$append/3` aus der Prolog-Bibliothek,
  z. B. für `append(X, Y, [1,2,3])`.

  ## length/2

  Über `skip_list/2`: Länge des gebundenen Präfixes und der Rest.

    * Rest `[]`: echte Liste, `Len` wird mit der Länge unifiziert
    * Rest ungebunden, `Len` Zahl: Rest wird zu einer Liste frischer
      Variablen passender Länge (deterministisch)
    * Rest und `Len` ungebunden: zählt Längen 0, 1, 2, ... auf (lazy)
  """
  use PrologEx.Builtin, module: "lists"

  @doc false
  def library do
    import PrologEx, only: [s: 2, v: 1, fact: 1, rule: 2]
    [h, t, l, r, x, h2, i, i0, i1, e] = Enum.map(~w(H T L R X H2 I I0 I1 E), &v/1)

    n = v("N")

    [
      fact(s("$append", [[], l, l])),
      rule(s("$append", [[h | t], l, [h | r]]), [s("$append", [t, l, r])]),
      rule(s("numlist", [n, l]), [s("numlist", [1, n, l])]),
      # select/3 wie in SWI: der Listenrest steht vorn im Hilfsprädikat, die
      # Indexierung macht das letzte Element deterministisch; der Rest R
      # wird schrittweise aufgebaut und geteilt (O(1) je Lösung)
      rule(s("select", [x, [h | t], r]), [s("$select3", [t, h, x, r])]),
      fact(s("$select3", [t, h, h, t])),
      rule(s("$select3", [[h2 | t], h, x, [h | r]]), [s("$select3", [t, h2, x, r])]),
      # nth0/4, nth1/4 bei offenem Index: ebenso
      fact(s("$nth4", [t, h, i, i, h, t])),
      rule(s("$nth4", [[h2 | t], h, i0, i, e, [h | r]]), [
        s("is", [i1, s("+", [i0, 1])]),
        s("$nth4", [t, h2, i1, i, e, r])
      ]),
      fact(s("$same_length", [[], []])),
      rule(s("$same_length", [[v("_") | t], [v("_") | l]]), [s("$same_length", [t, l])]),
      # permutation/2 ohne Schnellweg (wie SWI)
      fact(s("$perm", [[], []])),
      rule(s("$perm", [l, [h | t]]), [s("select", [h, l, r]), s("$perm", [r, t])]),
      fact(s("$member", [h, [h | v("_")]])),
      rule(s("$member", [h, [v("_") | t]]), [s("$member", [h, t])])
    ]
    |> then(&%{"lists" => &1, "apply" => maplist_library()})
  end

  @doc false
  def meta, do: for(n <- 1..7, do: {"apply", "maplist", [n | List.duplicate("?", n)]})

  # maplist(G, L1, ..., Ln), n = 1..7:
  #   maplist(G, L1, ..., Ln) :- '$maplist'(L1, ..., Ln, G).
  #   '$maplist'([], ..., [], _).
  #   '$maplist'([X1|T1], ..., [Xn|Tn], G) :- call(G, X1, ..., Xn), '$maplist'(T1, ..., Tn, G).
  # Die Listen stehen vorn, damit die Indexierung nach dem ersten Argument
  # greift: bei fertiger erster Liste bleibt kein Choice Point.
  defp maplist_library do
    g = PrologEx.v("G")

    for n <- 1..7, clause <- maplist_clauses(n, g), do: clause
  end

  defp maplist_clauses(n, g) do
    import PrologEx, only: [s: 2, v: 1, fact: 1, rule: 2]
    ls = for k <- 1..n, do: v("L#{k}")
    xs = for k <- 1..n, do: v("X#{k}")
    ts = for k <- 1..n, do: v("T#{k}")

    [
      rule(s("maplist", [g | ls]), [s("$maplist", ls ++ [g])]),
      fact(s("$maplist", List.duplicate([], n) ++ [v("_")])),
      rule(
        s("$maplist", Enum.zip_with(xs, ts, fn x, t -> [x | t] end) ++ [g]),
        [s("call", [g | xs]), s("$maplist", ts ++ [g])]
      )
    ]
  end

  defbuiltin "append", [x, y, z], protected: false, helpers: [{"$append", 3}] do
    case prefix(x, subst()) do
      {:ok, front} -> {:unify, [{z, join(front, y, subst())}]}
      :partial -> {:call, mk("$append", [x, y, z])}
    end
  end

  # permutation(Xs, Ys) wie in SWI (gleiche Reihenfolge der Lösungen).
  # Schnellweg: Xs ist eine echte Liste und Ys ungebunden – dann werden die
  # Permutationen direkt erzeugt (lazy, lexikographisch nach Position, die
  # letzte deterministisch). Sonst Prolog über select/3, das bei bekanntem
  # Ys früh abschneidet.
  defbuiltin "permutation", [xs, ys], nondet: true, protected: false, helpers: [{"$perm", 2}] do
    s = subst()
    {nx, tx} = skip_list(xs, s)
    {ny, ty} = skip_list(ys, s)

    case {tx, ty} do
      {[], {:var, _}} when ny == 0 ->
        elems = xs |> items(s) |> List.to_tuple()
        perm_stream(elems, List.to_tuple(Enum.to_list(0..(nx - 1)//1)), ys)

      # umgekehrt: Xs ungebunden. SWI legt das k-te Element von Ys an die
      # σ(k)-te Stelle, σ lexikographisch – also σ aufzählen und invers
      # einsetzen
      {{:var, _}, []} when nx == 0 ->
        elems = ys |> items(s) |> List.to_tuple()
        perm_stream_inv(elems, List.to_tuple(Enum.to_list(0..(ny - 1)//1)), xs)

      {[], []} ->
        if nx == ny, do: [{:call, mk("$perm", [xs, ys])}], else: []

      {{:var, _}, []} ->
        [{:call, mk(",", [mk("length", [xs, ny]), mk("$perm", [xs, ys])])}]

      {[], {:var, _}} ->
        [{:call, mk(",", [mk("length", [ys, nx]), mk("$perm", [xs, ys])])}]

      {{:var, _}, {:var, _}} ->
        n = fresh_var()

        [
          {:call,
           mk(",", [
             mk("length", [xs, n]),
             mk(",", [mk("length", [ys, n]), mk("$perm", [xs, ys])])
           ])}
        ]

      {{:var, _}, _} ->
        PrologEx.Error.type!("list", resolve(ys))

      _ ->
        PrologEx.Error.type!("list", resolve(xs))
    end
  end

  defp perm_stream(elems, idx, ys) do
    perm = for i <- Tuple.to_list(idx), do: elem(elems, i)
    res = {:unify, [{ys, PrologEx.list(perm, [])}]}

    case next_perm(idx) do
      :none -> [res]
      nxt -> [res | fn -> perm_stream(elems, nxt, ys) end]
    end
  end

  defp perm_stream_inv(elems, pos, xs) do
    n = tuple_size(pos)

    perm =
      Enum.reduce(0..(n - 1)//1, pos, fn k, acc -> put_elem(acc, elem(pos, k), elem(elems, k)) end)

    res = {:unify, [{xs, PrologEx.list(Tuple.to_list(perm), [])}]}

    case next_perm(pos) do
      :none -> [res]
      nxt -> [res | fn -> perm_stream_inv(elems, nxt, xs) end]
    end
  end

  # nächste Permutation in lexikographischer Ordnung (Tupel von Indizes)
  @doc false
  def next_perm(t) do
    n = tuple_size(t)

    case pivot(t, n - 2) do
      -1 ->
        :none

      i ->
        j = successor(t, i, n - 1)
        t = t |> put_elem(i, elem(t, j)) |> put_elem(j, elem(t, i))
        reverse_from(t, i + 1, n - 1)
    end
  end

  defp pivot(_t, i) when i < 0, do: -1
  defp pivot(t, i) when elem(t, i) < elem(t, i + 1), do: i
  defp pivot(t, i), do: pivot(t, i - 1)

  defp successor(t, i, j) when elem(t, j) > elem(t, i), do: j
  defp successor(t, i, j), do: successor(t, i, j - 1)

  defp reverse_from(t, a, b) when a < b,
    do: t |> put_elem(a, elem(t, b)) |> put_elem(b, elem(t, a)) |> reverse_from(a + 1, b - 1)

  defp reverse_from(t, _a, _b), do: t

  defbuiltin "numlist", [lo, hi, l], protected: false do
    case {deref(lo), deref(hi)} do
      {a, b} when is_integer(a) and is_integer(b) and a > b -> :fail
      {a, b} when is_integer(a) and is_integer(b) -> {:unify, [{l, {:glist, Enum.to_list(a..b)}}]}
      {{:var, _}, _} -> PrologEx.Error.instantiation!()
      {_, {:var, _}} -> PrologEx.Error.instantiation!()
      {a, b} -> PrologEx.Error.type!("integer", if(is_integer(a), do: b, else: a))
    end
  end

  defbuiltin "member", [x, l], nondet: true, protected: false, helpers: [{"$member", 2}] do
    member_cells(x, deref(l), subst())
  end

  defbuiltin "between", [lo, hi, x], nondet: true, protected: false, module: "system" do
    l = int_arg(deref(lo))

    h =
      case deref(hi) do
        {:atom, inf} when inf in ["inf", "infinite"] -> :inf
        other -> int_arg(other)
      end

    case deref(x) do
      n when is_integer(n) -> if n >= l and (h == :inf or n <= h), do: [:ok], else: []
      {:var, _} -> between_from(l, h, x)
      other -> PrologEx.Error.type!("integer", other)
    end
  end

  # same_length(A, B): gleich lange Listen; ist eine fertig, wird die
  # andere mit frischen Variablen aufgefüllt (deterministisch)
  defbuiltin "same_length", [la, lb], protected: false, helpers: [{"$same_length", 2}] do
    s = subst()
    {na, ra} = skip_list(la, s)
    {nb, rb} = skip_list(lb, s)

    case {ra, rb} do
      {[], []} -> na == nb
      {[], {:var, _}} -> nb <= na and {:unify, [{rb, fresh_list(na - nb)}]}
      {{:var, _}, []} -> na <= nb and {:unify, [{ra, fresh_list(nb - na)}]}
      {{:var, _}, {:var, _}} -> {:call, mk("$same_length", [la, lb])}
      _ -> false
    end
  end

  # nth0(I, L, E), nth1(I, L, E): E ist das I-te Element (ab 0 bzw. 1)
  # nth0(I, L, E, R), nth1(I, L, E, R): dazu R = L ohne dieses Element
  defbuiltin "nth0", [i, l, e], nondet: true, protected: false do
    nth(0, i, l, e, nil, subst())
  end

  defbuiltin "nth1", [i, l, e], nondet: true, protected: false do
    nth(1, i, l, e, nil, subst())
  end

  defbuiltin "nth0", [i, l, e, r], nondet: true, protected: false, helpers: [{"$nth4", 6}] do
    nth(0, i, l, e, r, subst())
  end

  defbuiltin "nth1", [i, l, e, r], nondet: true, protected: false, helpers: [{"$nth4", 6}] do
    nth(1, i, l, e, r, subst())
  end

  defbuiltin "length", [l, len], nondet: true, protected: false, module: "system" do
    {n, rest} = skip_list(l, subst())

    case rest do
      [] ->
        [{:unify, [{len, n}]}]

      {:var, _} ->
        case deref(len) do
          k when is_integer(k) and k >= n ->
            [{:unify, [{rest, fresh_list(k - n)}]}]

          k when is_integer(k) and k >= 0 ->
            []

          k when is_integer(k) ->
            PrologEx.Error.domain!("not_less_than_zero", k)

          {:var, _} ->
            Stream.map(Stream.iterate(0, &(&1 + 1)), fn i ->
              {:unify, [{rest, fresh_list(i)}, {len, n + i}]}
            end)

          other ->
            PrologEx.Error.type!("integer", other)
        end

      _ ->
        PrologEx.Error.type!("list", resolve(l))
    end
  end

  # ---------------------------------------------------------------------

  # '$skip_list'(-Len, +List, -Rest) wie SWI: Len Zellen überspringen,
  # Rest ist [] (echte Liste), eine Variable (offene Liste), ein anderer
  # Term (keine Liste) oder – bei einer zyklischen Liste – eine Zelle
  # [_|_] im Zyklus. Terminiert immer.
  defbuiltin "$skip_list", [len, l, rest], module: "system" do
    {n, r} = skip_list(l, subst())
    {:unify, [{len, n}, {rest, r}]}
  end

  @doc """
  Läuft die Liste entlang, solange Zellen gebunden sind.
  Liefert `{länge_des_präfixes, rest}`; `rest` ist dereferenziert:
  `[]` (echte Liste), eine Variable (offene Liste), etwas anderes – oder
  bei einer zyklischen Liste (`X = [a|X]`) eine Zelle `[_|_]` im Zyklus.

  Zyklen erkennt Brents Algorithmus. Ein Zyklus läuft immer über gebundene
  Variablen (Elixir-Terme selbst sind azyklisch); verglichen werden daher
  nur die rohen Variablen im Rest der Zellen – zweimal dieselbe heißt:
  dieselbe Stelle, also ein Zyklus. Native Abschnitte kosten nichts extra.
  """
  def skip_list(t, subst), do: skip(t, subst, 0, nil, 1, 0)

  # raw: der Rest, noch nicht dereferenziert; tort/power/lam: Brent
  defp skip({:var, _} = raw, subst, n, raw, _power, _lam), do: {n, PrologEx.walk(raw, subst)}

  defp skip({:var, _} = raw, subst, n, tort, power, lam) do
    {tort, power, lam} = if lam == power, do: {raw, power * 2, 1}, else: {tort, power, lam + 1}

    case PrologEx.walk(raw, subst) do
      [_ | t] -> skip(t, subst, n + 1, tort, power, lam)
      {:glist, l} -> skip_raw(l, n)
      other -> {n, other}
    end
  end

  defp skip([_ | t], subst, n, tort, power, lam), do: skip(t, subst, n + 1, tort, power, lam)
  defp skip({:glist, l}, _subst, n, _tort, _power, _lam), do: skip_raw(l, n)
  defp skip(other, _subst, n, _tort, _power, _lam), do: {n, other}

  # Innerhalb einer glist: rohe Zellen ohne Variablen
  defp skip_raw([_ | t], n), do: skip_raw(t, n + 1)
  defp skip_raw(t, n), do: {n, t}

  @doc "Elemente des gebundenen Anfangs einer (auch offenen) Liste."
  def items_prefix(t, subst) do
    case PrologEx.walk(t, subst) do
      [h | tl] -> [h | items_prefix(tl, subst)]
      {:glist, l} -> raw_prefix(l)
      _ -> []
    end
  end

  defp raw_prefix([h | t]), do: [h | raw_prefix(t)]
  defp raw_prefix(_), do: []

  @doc "Elemente einer echten Liste (Elemente nicht dereferenziert)."
  def items(t, subst) do
    case PrologEx.walk(t, subst) do
      [h | tl] -> [h | items(tl, subst)]
      {:glist, l} -> l
      [] -> []
    end
  end

  # Vorderteil für append: {:ok, {:glist, l}} | {:ok, {:items, [..]}} | :partial
  defp prefix(x, subst) do
    case PrologEx.walk(x, subst) do
      {:glist, l} -> if proper?(l), do: {:ok, {:glist, l}}, else: :partial
      _ -> collect(x, subst, [])
    end
  end

  defp collect(x, subst, acc) do
    case PrologEx.walk(x, subst) do
      [] -> {:ok, {:items, Enum.reverse(acc)}}
      [h | t] -> collect(t, subst, [h | acc])
      {:glist, l} -> if proper?(l), do: {:ok, {:items, Enum.reverse(acc, l)}}, else: :partial
      _ -> :partial
    end
  end

  defp proper?([_ | t]), do: proper?(t)
  defp proper?(t), do: t == []

  defp join({:glist, l}, y, subst) do
    case PrologEx.walk(y, subst) do
      [] -> {:glist, l}
      {:glist, ly} -> {:glist, l ++ ly}
      _ -> l ++ y
    end
  end

  defp join({:items, items}, y, _subst), do: PrologEx.list(items, y)

  # member/2: eine Lösung pro Zelle; ist der Rest [], ist es die letzte
  # Weiter geht es nur, wenn der Rest eine Liste oder ungebunden ist;
  # sonst ([] oder z. B. [a|b]) ist dies die letzte Lösung
  defp member_cells(x, [h | t], s) do
    case PrologEx.walk(t, s) do
      next when is_list(next) and next != [] ->
        [{:unify, [{x, h}]} | fn -> member_cells(x, next, s) end]

      {tag, _} = next when tag in [:glist, :var] ->
        [{:unify, [{x, h}]} | fn -> member_cells(x, next, s) end]

      _end ->
        [{:unify, [{x, h}]}]
    end
  end

  defp member_cells(x, {:glist, cells}, _s), do: member_raw(x, cells)
  defp member_cells(x, {:var, _} = rest, _s), do: [{:call, mk("$member", [x, rest])}]
  defp member_cells(_x, _not_a_list, _s), do: []

  # innerhalb einer glist: rohe Zellen, keine Variablen
  defp member_raw(x, [h | [_ | _] = t]), do: [{:unify, [{x, h}]} | fn -> member_raw(x, t) end]
  defp member_raw(x, [h | _end]), do: [{:unify, [{x, h}]}]

  # --- Zellen durchlaufen ----------------------------------------------
  # {:cons, kopf, rest} | :end ([] oder keine Liste) | {:open, variable}
  defp cell(t, s) do
    t = PrologEx.walk(t, s)

    case uncons(t) do
      {:cons, h, tl} -> {:cons, h, tl}
      :empty -> :end
      :other -> if match?({:var, _}, t), do: {:open, t}, else: :end
    end
  end

  # geht es nach dieser Zelle noch weiter (Zelle oder offener Rest)?
  defp more?(t, s), do: cell(t, s) != :end

  # nth: base 0 oder 1; r = nil (nth/3) oder Restliste (nth/4)
  defp nth(base, i, l, e, r, s) do
    case PrologEx.walk(i, s) do
      k when is_integer(k) and k >= base -> nth_at(k - base, l, e, r, [], 0, s)
      k when is_integer(k) -> []
      {:var, _} when r == nil -> nth_enum(base, i, l, e, nil, [], 0, s)
      # nth/4 mit offenem Index: in Prolog ($nth4), damit der Rest geteilt wird
      {:var, _} -> [{:call, nth4_goal(base, i, l, e, r)}]
      other -> PrologEx.Error.type!("integer", other)
    end
  end

  defp nth4_goal(base, i, l, e, r) do
    h = fresh_var()
    t = fresh_var()
    mk(",", [mk("=", [l, cons(h, t)]), mk("$nth4", [t, h, base, i, e, r])])
  end

  # Index bekannt: deterministisch
  defp nth_at(idx, l, e, r, pre, j, s) do
    case cell(l, s) do
      {:cons, h, tl} when j == idx ->
        [{:unify, [{e, h}] ++ rest_pair(r, pre, [], tl)}]

      {:cons, h, tl} ->
        nth_at(idx, tl, e, r, [h | pre], j + 1, s)

      {:open, tail} ->
        # offene Liste: bis zum Index mit frischen Variablen auffüllen
        fill = fresh_list(idx - j)
        ft = fresh_var()
        [{:unify, [{tail, PrologEx.list(fill ++ [e], ft)}] ++ rest_pair(r, pre, fill, ft)}]

      :end ->
        []
    end
  end

  # Index offen: alle Positionen lazy aufzählen
  defp nth_enum(base, i, l, e, r, pre, j, s) do
    case cell(l, s) do
      {:cons, h, tl} ->
        res = {:unify, [{i, j + base}, {e, h}] ++ rest_pair(r, pre, [], tl)}

        if more?(tl, s),
          do: [res | fn -> nth_enum(base, i, tl, e, r, [h | pre], j + 1, s) end],
          else: [res]

      {:open, tail} ->
        # offene Liste: E an Position j, j+1, ... erzeugen; bei nth/4 mit
        # fertiger Restliste ist die Zahl der Positionen begrenzt
        nth_open(base, i, tail, e, j, 0)

      :end ->
        []
    end
  end

  defp nth_open(base, i, tail, e, j, k) do
    res = {:unify, [{tail, PrologEx.list(fresh_list(k) ++ [e], fresh_var())}, {i, j + k + base}]}
    [res | fn -> nth_open(base, i, tail, e, j, k + 1) end]
  end

  # Restliste für nth/4: Präfix ++ Füllung ++ Rest
  defp rest_pair(nil, _pre, _fill, _tail), do: []
  defp rest_pair(r, pre, fill, tail), do: [{r, PrologEx.list(Enum.reverse(pre, fill), tail)}]

  # between/3: L, L+1, ..., H; bei H = :inf unendlich (Integer < Atom)
  defp between_from(l, h, _x) when h != :inf and l > h, do: []
  defp between_from(h, h, x), do: [{:unify, [{x, h}]}]
  defp between_from(l, h, x), do: [{:unify, [{x, l}]} | fn -> between_from(l + 1, h, x) end]

  defp int_arg(n) when is_integer(n), do: n
  defp int_arg({:var, _}), do: PrologEx.Error.instantiation!()
  defp int_arg(other), do: PrologEx.Error.type!("integer", other)

  defp fresh_list(0), do: []
  defp fresh_list(k), do: Enum.map(1..k, fn _ -> fresh_var() end)
end
