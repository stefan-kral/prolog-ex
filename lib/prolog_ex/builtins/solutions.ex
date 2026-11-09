defmodule PrologEx.Builtins.Solutions do
  @moduledoc """
  `bagof/3`, `setof/3` (ISO 8.10.2, 8.10.3), dazu `^/2` und `=@=/2`,
  `\\=@=/2` (Variante, wie SWI).

  `bagof(T, G, L)`:

    * `V^G` in G: die Variablen von V sind existenziell gebunden (auch
      geschachtelt, `X^Y^G`, und nach einem Modul, `M:(X^G)`).
    * Freie Variablen (der Zeuge W): Variablen von G, die weder in T noch
      in einem `V^` vorkommen, in Reihenfolge ihres ersten Auftretens.
    * Ohne freie Variablen: `findall(T, G, L)`, scheitert bei `[]`.
    * Sonst: `findall(W-T, G, Paare)`, nach W sortiert (keysort, stabil –
      wie SICStus, SWI, YAP; ISO nimmt die Reihenfolge des ersten
      Auftretens). Dann je Gruppe von Zeugen, die Varianten voneinander
      sind, eine Lösung: W wird mit jedem Zeugen der Gruppe unifiziert, L
      ist die Liste ihrer T. Beim Backtracking die nächste Gruppe; die
      letzte ohne Choice Point.

  `setof(T, G, S)`: wie bagof, danach jede Liste mit `sort/2` (nach der
  Unifikation von W – sie kann Elemente gleich machen).

  Fehler wie ISO: G ungebunden → instantiation_error, nicht aufrufbar →
  type_error(callable, G); L weder Liste noch Teilliste →
  type_error(list, L).

  `V^G` als gewöhnliches Ziel ruft G (wie SWI, SICStus).
  """
  use PrologEx.Builtin
  alias PrologEx.{Error, Order}
  alias PrologEx.Builtins.Lists

  def meta do
    [
      {"system", "bagof", ["?", "^", "-"]},
      {"system", "setof", ["?", "^", "-"]},
      {"system", "^", ["?", 0]},
      {"system", "forall", [0, 0]},
      {"system", "once", [0]},
      {"system", "ignore", [0]},
      {"system", "call_cleanup", [0, 0]}
    ]
  end

  # forall(Cond, Action): für jede Lösung von Cond gelingt Action
  # once(G) (ISO): die erste Lösung von G; ignore(G): G einmal, sonst true
  # call_cleanup(G, C) (SWI): setup_call_cleanup(true, G, C)
  def library do
    import PrologEx, only: [s: 2, v: 1, rule: 2, a: 1]
    [c, act, g] = [v("C"), v("A"), v("G")]

    [
      rule(s("forall", [c, act]), [s("\\+", [s(",", [c, s("\\+", [act])])])]),
      rule(s("once", [g]), [s("call", [g]), a("!")]),
      rule(s("ignore", [g]), [s(";", [s("->", [s("call", [g]), a("true")]), a("true")])]),
      rule(s("call_cleanup", [g, c]), [s("setup_call_cleanup", [a("true"), g, c])])
    ]
  end

  defbuiltin "bagof", [t, g, l] do
    bagof(t, g, l, subst(), false)
  end

  defbuiltin "setof", [t, g, l] do
    bagof(t, g, l, subst(), true)
  end

  defbuiltin "^", [_v, g] do
    {:call, g}
  end

  defbuiltin "=@=", [x, y] do
    Order.variant?(x, y, subst())
  end

  defbuiltin "\\=@=", [x, y] do
    not Order.variant?(x, y, subst())
  end

  # '$bagof_groups'(Paare, W, L): Paare W'-T nach W' sortiert, gruppiert
  # nach Varianten; je Gruppe eine Lösung W = W'1 = W'2 = ..., L = [T1, ...]
  defbuiltin "$bagof_groups", [pairs, w, l], nondet: true do
    s = subst()

    keyed =
      for p <- Lists.items(pairs, s) do
        {:struct, "-", [k, v]} = PrologEx.unmark_top(PrologEx.Store.walk(p, s))
        {k, {k, v}}
      end

    keyed |> Order.keysort(s) |> groups(s, w, l)
  end

  # ---------------------------------------------------------------------

  defp bagof(t, g, l, s, set?) do
    case Lists.skip_list(l, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> :ok
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end

    {goal, existential} = strip(g, s, [])

    # gebunden: Variablen von T und der V in V^G
    bound = [t | existential] |> list() |> term_vars(s) |> MapSet.new()

    free = goal |> term_vars(s) |> Enum.reject(&MapSet.member?(bound, &1))
    l0 = fresh_var()
    # setof: erst in eine frische Variable sortieren, dann unifizieren – L
    # kann inzwischen über eine freie Variable gebunden sein (setof(t,
    # (L=2;L=1), L) scheitert, kein Typfehler von sort/2; wie Scryer)
    result =
      if set? do
        l1 = fresh_var()
        conj([mk("sort", [l0, l1]), mk("=", [l1, l])])
      else
        mk("=", [l0, l])
      end

    case free do
      [] ->
        # findall(T, G, L0), L0 \== [], L = L0 (setof: sort(L0, L))
        {:call, conj([mk("findall", [t, goal, l0]), mk("\\==", [l0, []]), result])}

      vs ->
        w = mk("$w", vs)
        ps = fresh_var()

        {:call,
         conj([
           mk("findall", [mk("-", [w, t]), goal, ps]),
           mk("\\==", [ps, []]),
           mk("$bagof_groups", [ps, w, l0]),
           result
         ])}
    end
  end

  defp conj([g]), do: g
  defp conj([g | rest]), do: mk(",", [g, conj(rest)])

  # M:G und V^G abstreifen: {Ziel (mit Modul), existenzielle Terme}
  defp strip(g, s, ex) do
    case PrologEx.unmark_top(PrologEx.Store.walk(g, s)) do
      {:var, _} ->
        Error.instantiation!()

      {:struct, ":", [m, inner]} ->
        {goal, ex} = strip(inner, s, ex)
        {mk(":", [m, goal]), ex}

      {:struct, "^", [v, inner]} ->
        strip(inner, s, [v | ex])

      n when is_number(n) or (is_tuple(n) and elem(n, 0) == :rat) ->
        Error.type!("callable", n)

      other ->
        {other, ex}
    end
  end

  # Variablen eines Terms in Reihenfolge des ersten Auftretens
  defp term_vars(t, s), do: PrologEx.Builtins.Order.variables(t, s)

  # Gruppen aus der nach Zeugen sortierten Liste [{k, t}]: Zeugen, die
  # Varianten sind, haben dieselbe kanonische Form (Variablen nach erstem
  # Auftreten nummeriert) – ein Durchgang mit einer Map, O(n log n). Die
  # Gruppen kommen in der Reihenfolge ihres ersten (kleinsten) Zeugen.
  defp groups(sorted, s, w, l) do
    {order, by} =
      Enum.reduce(sorted, {[], %{}}, fn {k, _} = item, {order, by} ->
        c = canonical(k, s)

        case by do
          %{^c => items} -> {order, %{by | c => [item | items]}}
          _ -> {[c | order], Map.put(by, c, [item])}
        end
      end)

    order
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse(Map.fetch!(by, &1)))
    |> solutions(w, l)
  end

  defp solutions([], _w, _l), do: []

  defp solutions([group | rest], w, l) do
    ts = Enum.map(group, &elem(&1, 1))
    sol = {:unify, Enum.map(group, &{w, elem(&1, 0)}) ++ [{l, list(ts)}]}

    case rest do
      [] -> [sol]
      _ -> [sol | fn -> solutions(rest, w, l) end]
    end
  end

  # Term mit Variablen als {:v, Nummer} (Reihenfolge des ersten Auftretens)
  defp canonical(t, s) do
    {c, _} = canon(t, s, %{})
    c
  end

  defp canon(t, s, m) do
    case PrologEx.Store.walk(t, s) do
      {:var, _} = v ->
        case m do
          %{^v => n} -> {{:v, n}, m}
          _ -> {{:v, map_size(m)}, Map.put(m, v, map_size(m))}
        end

      {tag, f, args} when tag in [:struct, :gstruct] ->
        {args, m} = Enum.map_reduce(args, m, &canon(&1, s, &2))
        {{:s, f, args}, m}

      [h | tl] ->
        {h, m} = canon(h, s, m)
        {tl, m} = canon(tl, s, m)
        {{:s, ".", [h, tl]}, m}

      {:glist, l} ->
        canon(PrologEx.unmark(l), s, m)

      other ->
        {other, m}
    end
  end
end
