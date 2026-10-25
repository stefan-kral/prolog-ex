defmodule PrologEx.Builtins.Reif do
  @moduledoc """
  `library(reif)`: reifizierte Gleichheit und Kontrolle (Neumerkel, Kral:
  "Indexing dif/2", 2016) – dieselben Prädikate und Antworten wie die reine
  Prolog-Fassung `library(reif_pl)`, aber mit Schnellwegen in Elixir:

    * `=(X, Y, T)`, `dif(X, Y, T)`: die Unifikator-Prüfung von dif/2
      entscheidet vorab – identisch / nie gleich: deterministisch; sonst zwei
      Antworten (`T = true, X = Y` und `T = false, dif(X, Y)`).
    * `if_(If_1, Then_0, Else_0)`: ist die Bedingung `X = Y` oder
      `dif(X, Y)` (das `=/3`, `dif/3` dieser Bibliothek), ohne T und
      ohne call/N: entschieden → gleich Then bzw. Else; offen → zwei
      Zweige. `(A, B)` und `(A ; B)` als Bedingung werden zu
      geschachtelten if_/3. Sonst wie in Prolog über `call(If_1, T)`.
    * `memberd_t(E, Xs, T)`: läuft die Liste in Elixir entlang (wie
      memberd/2), nur offene Elemente geben einen Zweig.
    * `tfilter(C_2, Es, Fs)`, `tpartition(P_2, Xs, Ts, Fs)` mit `=(Y)` oder
      `dif(Y)`: die entschiedenen Elemente in einem Schritt, ein Zweig erst
      beim ersten offenen.

  `(',')/3`, `(;)/3`, `cond_t/3`, `tmember/2`, `tmember_t/3` und die
  allgemeinen Fälle sind Prolog (wie in reif_pl), benutzen aber das
  schnelle if_/3.
  """
  use PrologEx.Builtin, module: "reif"
  alias PrologEx.Builtins.Coroutining
  alias PrologEx.Error

  def meta do
    [
      {"reif", "if_", [1, 0, 0]},
      {"reif", "cond_t", [1, 0, "?"]},
      {"reif", "tfilter", [2, "?", "?"]},
      {"reif", "tpartition", [2, "?", "?", "?"]},
      {"reif", ",", [1, 1, "?"]},
      {"reif", ";", [1, 1, "?"]},
      {"reif", "tmember", [2, "?"]},
      {"reif", "tmember_t", [2, "?", "?"]}
    ]
  end

  # --- =/3, dif/3 -------------------------------------------------------

  defbuiltin "=", [x, y, t], nondet: true, protected: false do
    reified(x, y, t, true, subst())
  end

  defbuiltin "dif", [x, y, t], nondet: true, protected: false do
    reified(x, y, t, false, subst())
  end

  # pos: T für "gleich" (true bei =/3, false bei dif/3)
  defp reified(x, y, t, pos, s) do
    eq = a(to_string(pos))
    ne = a(to_string(not pos))

    case Coroutining.unifier(x, y, s) do
      :identical ->
        [{:unify, [{t, eq}]}]

      :different ->
        [{:unify, [{t, ne}]}]

      {:maybe, _, _} ->
        [
          {:unify, [{t, eq}, {x, y}]}
          | fn -> with_dif(x, y, s, fn s -> unify_or_fail(t, ne, s) end) end
        ]
    end
  end

  # dif(X, Y) stellen, dann k.(s); Ergebnis: Liste mit höchstens einer Lösung
  defp with_dif(x, y, s, k) do
    case Coroutining.dif(x, y, s) do
      :fail -> []
      {:ok, s} -> k.(s)
    end
  end

  defp unify_or_fail(t, v, s) do
    case PrologEx.unify(t, v, s) do
      {:ok, s} -> [{:subst, s}]
      :error -> []
    end
  end

  # --- if_/3 --------------------------------------------------------------

  defbuiltin "if_", [c, th, el], nondet: true, protected: false, helpers: [{"$if_t", 3}] do
    s = subst()
    {m, cond} = strip(c, s, context_module())

    case cond do
      {:struct, op, [x, y]} when op in ["=", "dif"] ->
        if reif?(db(), m, op) do
          if_eq(x, y, op == "=", th, el, s)
        else
          if_general(c, th, el)
        end

      # reifizierte Konjunktion und Disjunktion: geschachtelte if_/3
      {:struct, ",", [a1, b1]} ->
        if reif?(db(), m, ","),
          do: [{:call, if_goal(q(m, a1), if_goal(q(m, b1), th, el), el)}],
          else: if_general(c, th, el)

      {:struct, ";", [a1, b1]} ->
        if reif?(db(), m, ";"),
          do: [{:call, if_goal(q(m, a1), th, if_goal(q(m, b1), th, el))}],
          else: if_general(c, th, el)

      _ ->
        if_general(c, th, el)
    end
  end

  # Bedingung X = Y (eq?) bzw. dif(X, Y)
  defp if_eq(x, y, eq?, th, el, s) do
    {on_eq, on_ne} = if eq?, do: {th, el}, else: {el, th}

    case Coroutining.unifier(x, y, s) do
      :identical ->
        [{:call, on_eq}]

      :different ->
        [{:call, on_ne}]

      {:maybe, _, _} ->
        [
          {:call, mk(",", [mk("=", [x, y]), on_eq])}
          | fn -> with_dif(x, y, s, fn s -> [{:call, on_ne, s}] end) end
        ]
    end
  end

  defp if_general(c, th, el) do
    t = fresh_var()
    [{:call, mk(",", [mk("call", [c, t]), mk("$if_t", [t, th, el])])}]
  end

  defbuiltin "$if_t", [t, th, el] do
    case deref(t) do
      {:atom, "true"} -> {:call, th}
      {:atom, "false"} -> {:call, el}
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("boolean", resolve(other))
    end
  end

  defp if_goal(c, th, el), do: mk(":", [a("reif"), mk("if_", [c, th, el])])

  # --- memberd_t/3 ----------------------------------------------------------

  defbuiltin "memberd_t", [e, xs, t],
    nondet: true,
    protected: false,
    helpers: [{"$i_memberd_t", 3}] do
    memberd_t(e, xs, t, subst())
  end

  defp memberd_t(e, l, t, s) do
    case PrologEx.walk(l, s) do
      [x | rest] ->
        case Coroutining.unifier(x, e, s) do
          :different ->
            memberd_t(e, rest, t, s)

          :identical ->
            [{:unify, [{t, a("true")}]}]

          {:maybe, _, _} ->
            [
              {:unify, [{x, e}, {t, a("true")}]}
              | fn ->
                  with_dif(x, e, s, fn s ->
                    [{:call, mk(":", [a("reif"), mk("memberd_t", [e, rest, t])]), s}]
                  end)
                end
            ]
        end

      {:glist, _} = g ->
        memberd_t(e, PrologEx.unmark(g), t, s)

      [] ->
        [{:unify, [{t, a("false")}]}]

      {:var, _} = v ->
        # offene Liste: wie in Prolog aufzählen
        [{:call, mk("$i_memberd_t", [v, e, t])}]

      _ ->
        []
    end
  end

  # --- tfilter/3, tpartition/4 ----------------------------------------------

  defbuiltin "tfilter", [c, es, fs],
    nondet: true,
    protected: false,
    helpers: [{"$tfilter", 3}] do
    s = subst()

    case eq_closure(c, s, context_module(), db()) do
      {y, eq?} -> filter(c, y, eq?, es, fs, [], s)
      nil -> [{:call, mk("$tfilter", [c, es, fs])}]
    end
  end

  # entschiedene Elemente sammeln (acc umgekehrt); beim ersten offenen zwei
  # Zweige, der Rest dann wieder über tfilter/3
  defp filter(c, y, eq?, l, fs, acc, s) do
    case PrologEx.walk(l, s) do
      [e | rest] ->
        case Coroutining.unifier(y, e, s) do
          {:maybe, _, _} ->
            open_filter(c, y, eq?, e, rest, fs, acc, s)

          # behalten: bei =(Y) die gleichen, bei dif(Y) die verschiedenen
          r ->
            acc = if r == :identical == eq?, do: [e | acc], else: acc
            filter(c, y, eq?, rest, fs, acc, s)
        end

      {:glist, _} = g ->
        filter(c, y, eq?, PrologEx.unmark(g), fs, acc, s)

      [] ->
        [{:unify, [{fs, list(Enum.reverse(acc))}]}]

      {:var, _} = v ->
        fr = fresh_var()

        [
          {:call,
           mk(",", [
             mk("=", [fs, PrologEx.list(Enum.reverse(acc), fr)]),
             mk("$tfilter", [c, v, fr])
           ])}
        ]

      _ ->
        []
    end
  end

  defp open_filter(c, y, eq?, e, rest, fs, acc, s) do
    fr = fresh_var()
    keep = PrologEx.list(Enum.reverse([e | acc]), fr)
    drop = PrologEx.list(Enum.reverse(acc), fr)
    {on_eq, on_ne} = if eq?, do: {keep, drop}, else: {drop, keep}
    again = mk(":", [a("reif"), mk("tfilter", [c, rest, fr])])

    [
      {:call, mk(",", [mk("=", [y, e]), mk(",", [mk("=", [fs, on_eq]), again])])}
      | fn ->
          with_dif(y, e, s, fn s -> [{:call, mk(",", [mk("=", [fs, on_ne]), again]), s}] end)
        end
    ]
  end

  defbuiltin "tpartition", [p, xs, ts, fs],
    nondet: true,
    protected: false,
    helpers: [{"$tpartition", 4}] do
    s = subst()

    case eq_closure(p, s, context_module(), db()) do
      {y, eq?} -> partition(p, y, eq?, xs, ts, fs, [], [], s)
      nil -> [{:call, mk("$tpartition", [xs, p, ts, fs])}]
    end
  end

  defp partition(p, y, eq?, l, ts, fs, at, af, s) do
    case PrologEx.walk(l, s) do
      [e | rest] ->
        case Coroutining.unifier(y, e, s) do
          {:maybe, _, _} ->
            open_partition(p, y, eq?, e, rest, ts, fs, at, af, s)

          r ->
            if r == :identical == eq?,
              do: partition(p, y, eq?, rest, ts, fs, [e | at], af, s),
              else: partition(p, y, eq?, rest, ts, fs, at, [e | af], s)
        end

      {:glist, _} = g ->
        partition(p, y, eq?, PrologEx.unmark(g), ts, fs, at, af, s)

      [] ->
        [{:unify, [{ts, list(Enum.reverse(at))}, {fs, list(Enum.reverse(af))}]}]

      {:var, _} = v ->
        {rt, rf} = {fresh_var(), fresh_var()}

        [
          {:call,
           conj([
             mk("=", [ts, PrologEx.list(Enum.reverse(at), rt)]),
             mk("=", [fs, PrologEx.list(Enum.reverse(af), rf)]),
             mk("$tpartition", [v, p, rt, rf])
           ])}
        ]

      _ ->
        []
    end
  end

  defp open_partition(p, y, eq?, e, rest, ts, fs, at, af, s) do
    {rt, rf} = {fresh_var(), fresh_var()}
    again = mk(":", [a("reif"), mk("tpartition", [p, rest, rt, rf])])

    in_t = [
      mk("=", [ts, PrologEx.list(Enum.reverse([e | at]), rt)]),
      mk("=", [fs, PrologEx.list(Enum.reverse(af), rf)])
    ]

    in_f = [
      mk("=", [ts, PrologEx.list(Enum.reverse(at), rt)]),
      mk("=", [fs, PrologEx.list(Enum.reverse([e | af]), rf)])
    ]

    {on_eq, on_ne} = if eq?, do: {in_t, in_f}, else: {in_f, in_t}

    [
      {:call, conj([mk("=", [y, e]) | on_eq] ++ [again])}
      | fn -> with_dif(y, e, s, fn s -> [{:call, conj(on_ne ++ [again]), s}] end) end
    ]
  end

  # --- Hilfen -------------------------------------------------------------

  # Closure =(Y) oder dif(Y) dieser Bibliothek: {Y, eq?}, sonst nil
  defp eq_closure(c, s, ctx, db) do
    {m, inner} = strip(c, s, ctx)

    case inner do
      {:struct, op, [y]} when op in ["=", "dif"] ->
        if reif?(db, m, op), do: {y, op == "="}

      _ ->
        nil
    end
  end

  # M:G abstreifen (auch mehrfach): {Modul, G}
  defp strip(t, s, m) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:struct, ":", [mm, g]} ->
        case PrologEx.walk(mm, s) do
          {:atom, name} -> strip(g, s, name)
          _ -> {m, PrologEx.unmark_top(PrologEx.walk(t, s))}
        end

      other ->
        {m, other}
    end
  end

  # Ist name/3, gerufen in Modul m, das Prädikat dieser Bibliothek (Elixir
  # oder Prolog)? Sonst gilt die Definition des Benutzers.
  defp reif?(db, m, name), do: match?({:builtin, "reif", _}, PrologEx.locate(db, m, name, 3))

  defp q(m, g), do: mk(":", [a(m), g])

  defp conj([g]), do: g
  defp conj([g | gs]), do: mk(",", [g, conj(gs)])

  # ---------------------------------------------------------------------

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, rule: 2, fact: 1]

    [x, xs, e, es, t, fs, fs0, ts, ts0, c, p, a1, b1, th] =
      Enum.map(~w(X Xs E Es T Fs Fs0 Ts Ts0 C P A B Then), &v/1)

    w = v("_")
    tru = a("true")
    fal = a("false")

    %{
      "reif" => [
        # (',')/3, (;)/3, cond_t/3
        rule(s(",", [a1, b1, t]), [s("if_", [a1, s("call", [b1, t]), s("=", [t, fal])])]),
        rule(s(";", [a1, b1, t]), [s("if_", [a1, s("=", [t, tru]), s("call", [b1, t])])]),
        rule(s("cond_t", [c, th, t]), [
          s("if_", [c, s(",", [th, s("=", [t, tru])]), s("=", [t, fal])])
        ]),

        # offene Liste in memberd_t/3
        fact(s("$i_memberd_t", [[], w, fal])),
        rule(s("$i_memberd_t", [[x | xs], e, t]), [
          s("if_", [s("=", [x, e]), s("=", [t, tru]), s("$i_memberd_t", [xs, e, t])])
        ]),

        # tfilter/3, tpartition/4 allgemein (wie reif_pl)
        fact(s("$tfilter", [w, [], []])),
        rule(s("$tfilter", [c, [e | es], fs0]), [
          s("if_", [s("call", [c, e]), s("=", [fs0, [e | fs]]), s("=", [fs0, fs])]),
          s("$tfilter", [c, es, fs])
        ]),
        fact(s("$tpartition", [[], w, [], []])),
        rule(s("$tpartition", [[x | xs], p, ts0, fs0]), [
          s("if_", [
            s("call", [p, x]),
            s(",", [s("=", [ts0, [x | ts]]), s("=", [fs0, fs])]),
            s(",", [s("=", [fs0, [x | fs]]), s("=", [ts0, ts])])
          ]),
          s("$tpartition", [xs, p, ts, fs])
        ]),

        # tmember/2, tmember_t/3
        rule(s("tmember", [p, [x | xs]]), [
          s("if_", [s("call", [p, x]), tru, s("tmember", [p, xs])])
        ]),
        fact(s("tmember_t", [w, [], fal])),
        rule(s("tmember_t", [p, [x | xs], t]), [
          s("if_", [s("call", [p, x]), s("=", [t, tru]), s("tmember_t", [p, xs, t])])
        ])
      ]
    }
  end
end
