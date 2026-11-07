defmodule PrologEx.Builtins.ListMore do
  @moduledoc """
  Weitere Prädikate aus SICStus' `library(lists)`:

    * `one_longer(?Longer, ?Shorter)` – Longer hat genau ein Element mehr.
    * `shorter_list(?Short, ?Long)` – Short ist echt kürzer als Long (Long
      muss keine echte Liste sein, nur lang genug); Modus -Short, +Long
      zählt die Skelette auf.
    * `keys_and_values(?Paare, ?Schlüssel, ?Werte)` – `[K1-V1, ...]`,
      `[K1, ...]`, `[V1, ...]`.
    * `transpose(?X, ?Y)` – Y ist die transponierte Matrix von X; beide
      rechteckig, nicht leer (keine Zeile, keine Spalte ist ein Fehlschlag),
      in beide Richtungen.
    * `partition(:Pred, +Liste, ?Kleiner, ?Gleich, ?Größer)` – für jedes X
      `call(Pred, X, R)` mit R ∈ {<, =, >}; R ungebunden:
      instantiation_error, sonst domain_error(order, R).
    * `memberd(?X, ?Liste)` – wie `member/2`, aber ohne doppelte Antworten
      (Neumerkel; `dif/2` in der Rekursion). In Elixir; dieselben Antworten
      wie die Prolog-Fassung in `library(memberd_pl)`.

  Dazu, nicht aus SICStus: `list_frequencies/2` und `list_runs/2`
  (Häufigkeiten bzw. Läufe gleicher Elemente, gleich heißt `==/2`; in
  Elixir, siehe unten).

  Alle (aus SICStus) sind in Prolog definiert (Lösungen und ihre Reihenfolge wie bei
  SICStus). Schnellwege in Elixir, wenn eine der Listen schon fertig ist:
  one_longer/2, shorter_list/2 (Short fertig), keys_and_values/3 – dann
  deterministisch.
  """
  use PrologEx.Builtin, module: "lists"
  alias PrologEx.Builtins.Lists
  alias PrologEx.Order

  # ---------------------------------------------------------------------
  # list_frequencies(+Liste, ?Häufigkeiten), list_runs(+Liste, ?Läufe)
  # (PrologEx): gleich heißt ==/2.
  #
  #   list_frequencies([a,a,b,c,c,b,a,b], [a-3,b-3,c-2])
  #     je verschiedenem Element E-Anzahl, in der Reihenfolge des ersten
  #     Vorkommens (E ist dieses erste Vorkommen)
  #   list_runs([a,a,b,c,c,b,a,b], [2-a,1-b,2-c,1-b,1-a,1-b])
  #     je Lauf gleicher aufeinanderfolgender Elemente Anzahl-E
  #
  # Liste muss eine echte Liste sein (Teilliste: instantiation_error,
  # sonst type_error(list, L)). Sortiert in O(n log n) über die
  # Standardordnung (compare/3 gibt = genau bei ==/2).

  defbuiltin "list_frequencies", [l, fs], protected: false do
    s = subst()
    items = proper_list!(l, s)

    groups =
      items
      |> Enum.with_index()
      |> Enum.sort(fn {a, i}, {b, j} ->
        case Order.compare(a, b, s) do
          :lt -> true
          :gt -> false
          :eq -> i <= j
        end
      end)
      |> Enum.chunk_while(
        nil,
        fn
          {x, i}, nil ->
            {:cont, {x, i, 1}}

          {x, i}, {y, j, n} = acc ->
            if Order.compare(x, y, s) == :eq,
              do: {:cont, {y, j, n + 1}},
              else: {:cont, acc, {x, i, 1}}
        end,
        fn
          nil -> {:cont, nil}
          acc -> {:cont, acc, nil}
        end
      )
      |> Enum.sort_by(&elem(&1, 1))

    {:unify, [{fs, list(for({x, _, n} <- groups, do: mk("-", [x, n])))}]}
  end

  defbuiltin "list_runs", [l, rs], protected: false do
    s = subst()
    items = proper_list!(l, s)

    runs =
      Enum.chunk_while(
        items,
        nil,
        fn
          x, nil ->
            {:cont, {x, 1}}

          x, {y, n} = acc ->
            if Order.compare(x, y, s) == :eq,
              do: {:cont, {y, n + 1}},
              else: {:cont, acc, {x, 1}}
        end,
        fn
          nil -> {:cont, nil}
          acc -> {:cont, acc, nil}
        end
      )

    {:unify, [{rs, list(for({x, n} <- runs, do: mk("-", [n, x])))}]}
  end

  defp proper_list!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> PrologEx.Error.instantiation!()
      _ -> PrologEx.Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  def meta do
    [
      {"lists", "partition", [2, "+", "-", "-", "-"]}
    ]
  end

  defbuiltin "one_longer", [l, s], protected: false, helpers: [{"$one_longer", 2}] do
    sb = subst()
    {nl, rl} = Lists.skip_list(l, sb)
    {ns, rs} = Lists.skip_list(s, sb)

    case {rl, rs} do
      {[], []} -> nl == ns + 1
      {[], {:var, _}} -> ns <= nl - 1 and {:unify, [{rs, fresh_list(nl - 1 - ns)}]}
      {{:var, _}, []} -> nl <= ns + 1 and {:unify, [{rl, fresh_list(ns + 1 - nl)}]}
      {{:var, _}, {:var, _}} -> {:call, mk("$one_longer", [l, s])}
      _ -> false
    end
  end

  defbuiltin "shorter_list", [short, long], protected: false, helpers: [{"$shorter_list", 2}] do
    sb = subst()
    {ns, rs} = Lists.skip_list(short, sb)
    {nl, rl} = Lists.skip_list(long, sb)

    case {rs, rl} do
      # Short fertig: Long braucht mindestens ns + 1 Zellen
      {[], _} when nl > ns ->
        true

      {[], {:var, _}} ->
        {:unify, [{rl, list(fresh_list(ns + 1 - nl), fresh_var())}]}

      {[], _} ->
        false

      _ ->
        {:call, mk("$shorter_list", [short, long])}
    end
  end

  defbuiltin "keys_and_values", [pairs, keys, values],
    protected: false,
    helpers: [{"$keys_and_values", 3}] do
    sb = subst()

    known =
      Enum.find_value([pairs, keys, values], fn l ->
        case Lists.skip_list(l, sb) do
          {n, []} -> n
          _ -> nil
        end
      end)

    case known do
      nil ->
        {:call, mk("$keys_and_values", [pairs, keys, values])}

      n ->
        ks = fresh_list(n)
        vs = fresh_list(n)
        ps = Enum.zip_with(ks, vs, &mk("-", [&1, &2]))
        {:unify, [{pairs, list(ps)}, {keys, list(ks)}, {values, list(vs)}]}
    end
  end

  # partition/5: R muss <, = oder > sein
  defbuiltin "$must_be_order", [r] do
    case deref(r) do
      {:var, _} -> PrologEx.Error.instantiation!()
      {:atom, o} when o in ["<", "=", ">"] -> :ok
      other -> PrologEx.Error.domain!("order", resolve(other))
    end
  end

  # memberd(X, Es): X ist ein Element von Es, ohne doppelte Antworten
  # (Neumerkel) – wie
  #
  #   memberd(X, [E|Es]) :- ( X = E ; dif(X, E), memberd(X, Es) ).
  #
  # Für jedes E entscheidet die Unifikator-Prüfung von dif/2 vorab:
  #   - nie gleich: dif gelingt sofort, E ergibt keine Antwort → weiter
  #   - identisch: die Antwort ist X = E, dif scheitert → letzte Antwort
  #     (kein Choice Point)
  #   - offen: Antwort X = E, beim Backtracking dif(X, E) und weiter
  #     mit dem Rest (über einen erneuten Aufruf)
  # Offener Rest T: T = [X|_], dann T = [E|Es], dif(X, E), memberd(X, Es).
  defbuiltin "memberd", [x, l], nondet: true, protected: false do
    memberd(x, l, subst())
  end

  defp memberd(x, l, s) do
    case PrologEx.Store.walk(l, s) do
      [e | es] ->
        case PrologEx.Builtins.Coroutining.unifier(x, e, s) do
          :different ->
            memberd(x, es, s)

          :identical ->
            [{:unify, []}]

          {:maybe, _, _} ->
            [
              {:unify, [{x, e}]}
              | fn -> [{:call, conj([mk("dif", [x, e]), lists_memberd(x, es)])}] end
            ]
        end

      {:glist, raw} ->
        memberd(x, PrologEx.unmark({:glist, raw}), s)

      {:var, _} = t ->
        e = fresh_var()
        es = fresh_var()

        [
          {:unify, [{t, [x | fresh_var()]}]}
          | fn ->
              [
                {:call, conj([mk("=", [t, [e | es]]), mk("dif", [x, e]), lists_memberd(x, es)])}
              ]
            end
        ]

      _ ->
        []
    end
  end

  defp lists_memberd(x, es), do: mk(":", [a("lists"), mk("memberd", [x, es])])

  defp conj([g]), do: g
  defp conj([g | rest]), do: mk(",", [g, conj(rest)])

  defp fresh_list(0), do: []
  defp fresh_list(k), do: Enum.map(1..k, fn _ -> fresh_var() end)

  # ---------------------------------------------------------------------

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, fact: 1, rule: 2]

    [l, s0, x, ks, vs, k, vv, kvs, xss, yss, xr, yr, rows, rest, col, cols, f, fs, r, rs] =
      Enum.map(~w(L S X Ks Vs K V KVs Xss Yss Xr Yr Rows Rest Col Cols F Fs R Rs), &v/1)

    [p, xs, ls, es, gs, w] = Enum.map(~w(P Xs Ls Es Gs _), &v/1)

    %{
      "lists" => [
        # one_longer/2, shorter_list/2 (wie SICStus/Quintus)
        fact(s("$one_longer", [[w], []])),
        rule(s("$one_longer", [[w | l], [w | s0]]), [s("$one_longer", [l, s0])]),
        fact(s("$shorter_list", [[], [w | w]])),
        rule(s("$shorter_list", [[w | s0], [w | l]]), [s("$shorter_list", [s0, l])]),

        # keys_and_values/3
        fact(s("$keys_and_values", [[], [], []])),
        rule(s("$keys_and_values", [[s("-", [k, vv]) | kvs], [k | ks], [vv | vs]]), [
          s("$keys_and_values", [kvs, ks, vs])
        ]),

        # transpose/2: erst die Form (beide Seiten), dann die Spalten
        rule(s("transpose", [xss, yss]), [
          s("=", [xss, [xr | w]]),
          s("=", [xr, [w | w]]),
          s("=", [yss, [yr | w]]),
          s("=", [yr, [w | w]]),
          s("same_length", [xr, yss]),
          s("same_length", [xss, yr]),
          s("$rows_length", [xss, yss]),
          s("$rows_length", [yss, xss]),
          s("$transpose_cols", [yss, xss])
        ]),
        fact(s("$rows_length", [[], w])),
        rule(s("$rows_length", [[r | rs], l]), [
          s("same_length", [r, l]),
          s("$rows_length", [rs, l])
        ]),
        # die Zeilenlängen stehen schon fest: am Ende sind alle Reste []
        fact(s("$transpose_cols", [[], w])),
        rule(s("$transpose_cols", [[col | cols], rows]), [
          s("$firsts_rests", [rows, col, rest]),
          s("$transpose_cols", [cols, rest])
        ]),
        fact(s("$firsts_rests", [[], [], []])),
        rule(s("$firsts_rests", [[[f | r] | rows], [f | fs], [r | rs]]), [
          s("$firsts_rests", [rows, fs, rs])
        ]),

        # partition/5 (Liste vorn: Indexierung)
        rule(s("partition", [p, xs, ls, es, gs]), [s("$partition5", [xs, p, ls, es, gs])]),
        fact(s("$partition5", [[], w, [], [], []])),
        rule(s("$partition5", [[x | xs], p, ls, es, gs]), [
          s("call", [p, x, r]),
          s("$must_be_order", [r]),
          s("$partition5", [r, x, xs, p, ls, es, gs])
        ]),
        rule(s("$partition5", [a("<"), x, xs, p, [x | ls], es, gs]), [
          s("$partition5", [xs, p, ls, es, gs])
        ]),
        rule(s("$partition5", [a("="), x, xs, p, ls, [x | es], gs]), [
          s("$partition5", [xs, p, ls, es, gs])
        ]),
        rule(s("$partition5", [a(">"), x, xs, p, ls, es, [x | gs]]), [
          s("$partition5", [xs, p, ls, es, gs])
        ])
      ]
    }
  end
end
