defmodule PrologEx.Builtins.Assoc do
  @moduledoc """
  `library(assoc)`: Zuordnungen als AVL-Bäume, die Vereinigung von SWI
  (= Scryer) und SICStus.

    * wie SWI und Scryer: `empty_assoc/1`, `is_assoc/1`, `assoc_to_list/2`,
      `assoc_to_keys/2`, `assoc_to_values/2`, `gen_assoc/3`,
      `get_assoc/3,5`, `list_to_assoc/2`, `ord_list_to_assoc/2`,
      `map_assoc/2,3`, `max_assoc/3`, `min_assoc/3`, `put_assoc/4`,
      `del_assoc/4`, `del_min_assoc/4`, `del_max_assoc/4`
    * dazu aus SICStus: `get_next_assoc/4`, `get_prev_assoc/4`,
      `portray_assoc/1`

  Darstellung wie SWI und Scryer: `t` ist leer, `t(K,V,Balance,L,R)` ein
  Knoten (Balance `<`, `-` oder `>`). Einfügen, Löschen und der Aufbau
  aus Listen folgen SWIs Algorithmus genau, die Bäume sind also Term für
  Term dieselben. In Elixir; unveränderte Teilbäume werden geteilt,
  Werte nicht kopiert. Schlüssel nach der Standardordnung (`compare/3`).
  SICStus' `library(assoc)` nimmt unbalancierte Bäume, die bei
  aufsteigend eingefügten Schlüsseln zu Listen entarten; AVL bleibt bei
  O(log n).

  Fehler: ein Assoc als Variable `instantiation_error`, kein Assoc
  `type_error(assoc, X)` (SWI prüft nur bei `get_assoc/3` so und scheitert
  sonst); `list_to_assoc/2` mit doppeltem Schlüssel
  `domain_error(unique_key_pairs, L)`, `ord_list_to_assoc/2` ungeordnet
  `domain_error(key_ordered_pairs, L)` (beides wie SWI).
  """
  use PrologEx.Builtin, module: "assoc"
  alias PrologEx.Builtins.Lists
  alias PrologEx.{Error, Order}
  require PrologEx

  def meta do
    [
      {"assoc", "map_assoc", [1, "?"]},
      {"assoc", "map_assoc", [2, "?", "?"]}
    ]
  end

  # map_assoc/2,3 rufen ein Prädikat: in Prolog, wie SWI (Werte in
  # Schlüsselreihenfolge)
  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, fact: 1, rule: 2]

    [p, t, t0, k, val, b, l, r, l0, l1, r0, r1, ans] =
      Enum.map(~w(P T T0 K V B L R L0 L1 R0 R1 Ans), &v/1)

    w = v("_")

    %{
      "assoc" => [
        rule(s("map_assoc", [p, t]), [s("$map_assoc", [t, p])]),
        fact(s("$map_assoc", [a("t"), w])),
        rule(s("$map_assoc", [s("t", [w, val, w, l, r]), p]), [
          s("$map_assoc", [l, p]),
          s("call", [p, val]),
          s("$map_assoc", [r, p])
        ]),
        rule(s("map_assoc", [p, t0, t]), [s("$map_assoc", [t0, p, t])]),
        fact(s("$map_assoc", [a("t"), w, a("t")])),
        rule(s("$map_assoc", [s("t", [k, val, b, l0, r0]), p, s("t", [k, ans, b, l1, r1])]), [
          s("$map_assoc", [l0, p, l1]),
          s("call", [p, val, ans]),
          s("$map_assoc", [r0, p, r1])
        ])
      ]
    }
  end

  # --- Abfragen ---------------------------------------------------------------

  defbuiltin "empty_assoc", [t] do
    {:unify, [{t, a("t")}]}
  end

  defbuiltin "get_assoc", [key, t, val] do
    s = subst()

    case lookup(walk(key, s), t, s) do
      {:ok, v} -> {:unify, [{val, v}]}
      :none -> :fail
    end
  end

  # get_assoc(+K, +A0, ?V0, ?A, ?V): Wert an K ersetzen (K muss da sein)
  defbuiltin "get_assoc", [key, t0, v0, t, v] do
    s = subst()

    case replace(walk(key, s), t0, walk(v, s), s) do
      {:ok, old, new} -> {:unify, [{v0, old}, {t, new}]}
      :none -> :fail
    end
  end

  defbuiltin "max_assoc", [t, k, v] do
    case extreme(t, :right, subst()) do
      {key, val} -> {:unify, [{k, key}, {v, val}]}
      nil -> :fail
    end
  end

  defbuiltin "min_assoc", [t, k, v] do
    case extreme(t, :left, subst()) do
      {key, val} -> {:unify, [{k, key}, {v, val}]}
      nil -> :fail
    end
  end

  # SICStus: kleinster Schlüssel größer als K (K muss nicht vorkommen)
  defbuiltin "get_next_assoc", [key, t, kn, vn] do
    case neighbour(key, t, :gt, subst()) do
      {k, v} -> {:unify, [{kn, k}, {vn, v}]}
      nil -> :fail
    end
  end

  defbuiltin "get_prev_assoc", [key, t, kp, vp] do
    case neighbour(key, t, :lt, subst()) do
      {k, v} -> {:unify, [{kp, k}, {vp, v}]}
      nil -> :fail
    end
  end

  # wie SWI: ground Key – nachschlagen; sonst alle Paare der Reihe nach
  defbuiltin "gen_assoc", [key, t, val], nondet: true do
    s = subst()

    if PrologEx.Builtins.Order.variables(key, s) == [] do
      case lookup(key, t, s) do
        {:ok, v} -> [{:unify, [{val, v}]}]
        :none -> []
      end
    else
      for {k, v} <- pairs(t, s), do: {:unify, [{key, k}, {val, v}]}
    end
  end

  # --- Umwandeln --------------------------------------------------------------

  defbuiltin "assoc_to_list", [t, l] do
    {:unify, [{l, list(for {k, v} <- pairs(t, subst()), do: mk("-", [k, v]))}]}
  end

  defbuiltin "assoc_to_keys", [t, l] do
    {:unify, [{l, list(for {k, _} <- pairs(t, subst()), do: k)}]}
  end

  defbuiltin "assoc_to_values", [t, l] do
    {:unify, [{l, list(for {_, v} <- pairs(t, subst()), do: v)}]}
  end

  # wie SWI: keysort (stabil), dann streng aufsteigende Schlüssel verlangen
  defbuiltin "list_to_assoc", [l, t] do
    s = subst()
    items = list!(l, s)

    case items do
      [] ->
        {:unify, [{t, a("t")}]}

      _ ->
        ps = items |> Enum.map(&pair!(&1, s)) |> keysort(s)

        if ordered?(ps, s),
          do: {:unify, [{t, build(ps)}]},
          else: Error.domain!("unique_key_pairs", resolve(l))
    end
  end

  defbuiltin "ord_list_to_assoc", [l, t] do
    s = subst()
    items = list!(l, s)

    ps =
      Enum.map(items, fn p ->
        case PrologEx.unmark_top(PrologEx.Store.walk(p, s)) do
          {:struct, "-", [k, v]} -> {k, v}
          _ -> Error.domain!("key_ordered_pairs", resolve(l))
        end
      end)

    cond do
      ps == [] -> {:unify, [{t, a("t")}]}
      ordered?(ps, s) -> {:unify, [{t, build(ps)}]}
      true -> Error.domain!("key_ordered_pairs", resolve(l))
    end
  end

  # wie SWI: ein echter AVL-Baum mit ground Schlüsseln, geordnet, Balance
  # stimmt; sonst scheitert es (keine Fehler)
  defbuiltin "is_assoc", [t] do
    match?({:ok, _, _, _}, check(t, subst()))
  end

  # SICStus: lesbar ausgeben, <k1-v1,k2-v2,...> (nicht wieder einlesbar)
  defbuiltin "portray_assoc", [t] do
    s = subst()
    o = PrologEx.Builtins.Core.writeq_opts()

    text =
      "<" <>
        Enum.map_join(pairs(t, s), ",", fn {k, v} ->
          PrologEx.Writer.format(PrologEx.resolve(mk("-", [k, v]), s), o)
        end) <> ">"

    PrologEx.Builtins.IO.out(text)
    :ok
  end

  # --- Ändern -----------------------------------------------------------------

  defbuiltin "put_assoc", [key, t0, val, t] do
    s = subst()
    {new, _} = insert(t0, walk(key, s), walk(val, s), s)
    {:unify, [{t, new}]}
  end

  defbuiltin "del_assoc", [key, t0, val, t] do
    s = subst()

    case delete(t0, walk(key, s), s) do
      {:ok, v, new, _} -> {:unify, [{val, v}, {t, new}]}
      :none -> :fail
    end
  end

  defbuiltin "del_min_assoc", [t0, key, val, t] do
    s = subst()

    case node!(t0, s) do
      :empty ->
        :fail

      _ ->
        {k, v, new, _} = del_min(t0, s)
        {:unify, [{key, k}, {val, v}, {t, new}]}
    end
  end

  defbuiltin "del_max_assoc", [t0, key, val, t] do
    s = subst()

    case node!(t0, s) do
      :empty ->
        :fail

      _ ->
        {k, v, new, _} = del_max(t0, s)
        {:unify, [{key, k}, {val, v}, {t, new}]}
    end
  end

  # --- Bäume lesen -------------------------------------------------------------

  defp walk(t, s), do: PrologEx.Store.walk(t, s)

  # Schlüssel vergleichen: Ganzzahlen und Atome direkt (wie Order.compare)
  @compile {:inline, kcmp: 3}
  defp kcmp(x, y, _s) when is_integer(x) and is_integer(y),
    do: if(x < y, do: :lt, else: if(x > y, do: :gt, else: :eq))

  defp kcmp({:atom, x}, {:atom, y}, _s),
    do: if(x < y, do: :lt, else: if(x > y, do: :gt, else: :eq))

  defp kcmp(x, y, s), do: Order.compare(x, y, s)

  # :empty oder {K, V, Balance, L, R}; Balance als "<", "-", ">".
  # Die Knoten, die wir selbst bauen, ohne Umweg
  defp node!({:atom, "t"}, _s), do: :empty

  defp node!({tag, "t", [k, v, {:atom, b}, l, r]}, _s)
       when (tag == :gstruct or tag == :struct) and b in ["<", "-", ">"],
       do: {k, v, b, l, r}

  defp node!(t, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(t, s)) do
      {:atom, "t"} ->
        :empty

      {:struct, "t", [k, v, b, l, r]} = n ->
        case PrologEx.Store.walk(b, s) do
          {:atom, bal} when bal in ["<", "-", ">"] -> {k, v, bal, l, r}
          {:var, _} -> Error.instantiation!()
          _ -> Error.type!("assoc", PrologEx.resolve(n, s))
        end

      {:var, _} ->
        Error.instantiation!()

      other ->
        Error.type!("assoc", PrologEx.resolve(other, s))
    end
  end

  @doc false
  # für andere Bibliotheken (clpb): Wert zu key oder :none
  def lookup_value(key, t, s), do: lookup(walk(key, s), t, s)

  @doc false
  # für andere Bibliotheken (clpb): put_assoc/4
  def put_value(t, key, val, s), do: t |> insert(walk(key, s), walk(val, s), s) |> elem(0)

  # die Knoten, die wir selbst bauen, direkt (ohne Zwischentupel)
  defp lookup(key, {tag, "t", [k, v, {:atom, b}, l, r]}, s)
       when (tag == :gstruct or tag == :struct) and b in ["<", "-", ">"] do
    case kcmp(key, k, s) do
      :eq -> {:ok, v}
      :lt -> lookup(key, l, s)
      :gt -> lookup(key, r, s)
    end
  end

  defp lookup(_key, {:atom, "t"}, _s), do: :none

  defp lookup(key, t, s) do
    case node!(t, s) do
      :empty ->
        :none

      {k, v, _, l, r} ->
        case kcmp(key, k, s) do
          :eq -> {:ok, v}
          :lt -> lookup(key, l, s)
          :gt -> lookup(key, r, s)
        end
    end
  end

  defp replace(key, t, nv, s) do
    case node!(t, s) do
      :empty ->
        :none

      {k, v, b, l, r} ->
        case kcmp(key, k, s) do
          :eq ->
            {:ok, v, node(k, nv, b, l, r)}

          :lt ->
            with {:ok, old, nl} <- replace(key, l, nv, s), do: {:ok, old, node(k, v, b, nl, r)}

          :gt ->
            with {:ok, old, nr} <- replace(key, r, nv, s), do: {:ok, old, node(k, v, b, l, nr)}
        end
    end
  end

  defp extreme(t, side, s) do
    case node!(t, s) do
      :empty ->
        nil

      {k, v, _, l, r} ->
        case node!(if(side == :left, do: l, else: r), s) do
          :empty -> {k, v}
          _ -> extreme(if(side == :left, do: l, else: r), side, s)
        end
    end
  end

  # nächster Nachbar in Richtung dir (:gt: kleinster größerer Schlüssel)
  defp neighbour(key, t, dir, s), do: neighbour(key, t, dir, s, nil)

  defp neighbour(key, t, dir, s, best) do
    case node!(t, s) do
      :empty ->
        best

      {k, v, _, l, r} ->
        case {Order.compare(k, key, s), dir} do
          {:gt, :gt} -> neighbour(key, l, dir, s, {k, v})
          {_, :gt} -> neighbour(key, r, dir, s, best)
          {:lt, :lt} -> neighbour(key, r, dir, s, {k, v})
          {_, :lt} -> neighbour(key, l, dir, s, best)
        end
    end
  end

  # Paare in Schlüsselreihenfolge
  defp pairs(t, s), do: pairs(t, s, [])

  defp pairs(t, s, acc) do
    case node!(t, s) do
      :empty -> acc
      {k, v, _, l, r} -> pairs(l, s, [{k, v} | pairs(r, s, acc)])
    end
  end

  # {:ok, Min, Max, Tiefe} für einen gültigen Baum (wie SWIs is_assoc/1)
  defp check(t, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(t, s)) do
      {:atom, "t"} ->
        {:ok, nil, nil, 0}

      {:struct, "t", [k, _v, b, l, r]} ->
        with {:atom, bal} when bal in ["<", "-", ">"] <- PrologEx.Store.walk(b, s),
             true <- PrologEx.Builtins.Order.variables(k, s) == [],
             {:ok, lmin, lmax, ld} <- check(l, s),
             {:ok, rmin, rmax, rd} <- check(r, s),
             true <- lmax == nil or Order.compare(lmax, k, s) == :lt,
             true <- rmin == nil or Order.compare(k, rmin, s) == :lt,
             true <- abs(rd - ld) <= 1,
             true <- bal == balance_of(rd, ld) do
          {:ok, lmin || k, rmax || k, max(ld, rd) + 1}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp balance_of(rd, ld) when rd < ld, do: "<"
  defp balance_of(rd, ld) when rd > ld, do: ">"
  defp balance_of(_, _), do: "-"

  # --- Bäume bauen (SWIs Algorithmus) ------------------------------------------

  # wie mk/2, aber ohne Listen-Durchlauf; Balance-Atome als Literale
  defp node(k, v, b, l, r)
       when PrologEx.is_known_ground(k) and PrologEx.is_known_ground(v) and
              PrologEx.is_known_ground(l) and
              PrologEx.is_known_ground(r),
       do: {:gstruct, "t", [k, v, bal(b), l, r]}

  defp node(k, v, b, l, r), do: {:struct, "t", [k, v, bal(b), l, r]}

  defp bal("<"), do: {:atom, "<"}
  defp bal("-"), do: {:atom, "-"}
  defp bal(">"), do: {:atom, ">"}

  defp leaf(k, v), do: node(k, v, "-", {:atom, "t"}, {:atom, "t"})

  # Einfügen: {Baum, Höhe gewachsen?}
  defp insert({tag, "t", [k, v, {:atom, b}, l, r]}, key, val, s)
       when (tag == :gstruct or tag == :struct) and b in ["<", "-", ">"],
       do: insert_at(k, v, b, l, r, key, val, s)

  defp insert({:atom, "t"}, key, val, _s), do: {leaf(key, val), true}

  defp insert(t, key, val, s) do
    case node!(t, s) do
      :empty -> {leaf(key, val), true}
      {k, v, b, l, r} -> insert_at(k, v, b, l, r, key, val, s)
    end
  end

  defp insert_at(k, v, b, l, r, key, val, s) do
    case kcmp(key, k, s) do
      :eq ->
        {node(k, val, b, l, r), false}

      :lt ->
        case insert(l, key, val, s) do
          {nl, false} -> {node(k, v, b, nl, r), false}
          {nl, true} -> adjust(true, {k, v, b, nl, r}, :left, s)
        end

      :gt ->
        case insert(r, key, val, s) do
          {nr, false} -> {node(k, v, b, l, nr), false}
          {nr, true} -> adjust(true, {k, v, b, l, nr}, :right, s)
        end
    end
  end

  defp adjust(true, {k, v, b0, l, r} = n, side, s) do
    {b1, grown, rebalance} = table(b0, side)

    if rebalance do
      {new, _} = avl_geq(n, s)
      {new, grown}
    else
      {node(k, v, b1, l, r), grown}
    end
  end

  # (alte Balance, Seite) → {neue Balance, gewachsen?, umbauen?}
  defp table("-", :left), do: {"<", true, false}
  defp table("-", :right), do: {">", true, false}
  defp table("<", :left), do: {"-", false, true}
  defp table("<", :right), do: {"-", false, false}
  defp table(">", :left), do: {"-", false, false}
  defp table(">", :right), do: {"-", false, true}

  # Rotationen; {Baum, Höhe geändert?}. n: {K, V, B, L, R} mit der alten
  # Balance und schon geänderten Kindern
  defp avl_geq({a, va, ">", alpha, r}, s) do
    {b, vb, rb, beta, gamma} = node!(r, s)

    case rb do
      ">" ->
        {node(b, vb, "-", node(a, va, "-", alpha, beta), gamma), true}

      "-" ->
        {node(b, vb, "<", node(a, va, ">", alpha, beta), gamma), false}

      "<" ->
        {x, vx, b1, beta2, gamma2} = node!(beta, s)
        {b2, b3} = table2(b1)

        {node(x, vx, "-", node(a, va, b2, alpha, beta2), node(b, vb, b3, gamma2, gamma)), true}
    end
  end

  defp avl_geq({b, vb, "<", l, gamma}, s) do
    {a, va, lb, alpha, beta} = node!(l, s)

    case lb do
      "<" ->
        {node(a, va, "-", alpha, node(b, vb, "-", beta, gamma)), true}

      "-" ->
        {node(a, va, ">", alpha, node(b, vb, "<", beta, gamma)), false}

      ">" ->
        {x, vx, b1, beta2, gamma2} = node!(beta, s)
        {b2, b3} = table2(b1)

        {node(x, vx, "-", node(a, va, b2, alpha, beta2), node(b, vb, b3, gamma2, gamma)), true}
    end
  end

  defp table2("<"), do: {"-", ">"}
  defp table2(">"), do: {"<", "-"}
  defp table2("-"), do: {"-", "-"}

  # Löschen: {:ok, Wert, Baum, Höhe geschrumpft?} oder :none
  defp delete(t, key, s) do
    case node!(t, s) do
      :empty ->
        :none

      {k, v, b, l, r} ->
        case kcmp(key, k, s) do
          :eq ->
            cond do
              node!(l, s) == :empty ->
                {:ok, v, r, true}

              node!(r, s) == :empty ->
                {:ok, v, l, true}

              b == ">" ->
                {k2, v2, nr, shrunk} = del_min(r, s)
                {new, ch} = deladjust(shrunk, {k2, v2, ">", l, nr}, :right, s)
                {:ok, v, new, ch}

              true ->
                {k2, v2, nl, shrunk} = del_max(l, s)
                {new, ch} = deladjust(shrunk, {k2, v2, b, nl, r}, :left, s)
                {:ok, v, new, ch}
            end

          :lt ->
            with {:ok, val, nl, shrunk} <- delete(l, key, s) do
              {new, ch} = deladjust(shrunk, {k, v, b, nl, r}, :left, s)
              {:ok, val, new, ch}
            end

          :gt ->
            with {:ok, val, nr, shrunk} <- delete(r, key, s) do
              {new, ch} = deladjust(shrunk, {k, v, b, l, nr}, :right, s)
              {:ok, val, new, ch}
            end
        end
    end
  end

  defp del_min(t, s) do
    {k, v, b, l, r} = node!(t, s)

    case node!(l, s) do
      :empty ->
        {k, v, r, true}

      _ ->
        {key, val, nl, shrunk} = del_min(l, s)
        {new, ch} = deladjust(shrunk, {k, v, b, nl, r}, :left, s)
        {key, val, new, ch}
    end
  end

  defp del_max(t, s) do
    {k, v, b, l, r} = node!(t, s)

    case node!(r, s) do
      :empty ->
        {k, v, l, true}

      _ ->
        {key, val, nr, shrunk} = del_max(r, s)
        {new, ch} = deladjust(shrunk, {k, v, b, l, nr}, :right, s)
        {key, val, new, ch}
    end
  end

  defp deladjust(false, {k, v, b, l, r}, _side, _s), do: {node(k, v, b, l, r), false}

  defp deladjust(true, {k, v, b0, l, r} = n, side, s) do
    {b1, shrunk, rebalance} = deltable(b0, side)

    if rebalance,
      do: avl_geq(n, s),
      else: {node(k, v, b1, l, r), shrunk}
  end

  defp deltable("-", :right), do: {"<", false, false}
  defp deltable("-", :left), do: {">", false, false}
  defp deltable("<", :right), do: {"-", true, true}
  defp deltable("<", :left), do: {"-", true, false}
  defp deltable(">", :right), do: {"-", true, false}
  defp deltable(">", :left), do: {"-", true, true}

  @doc false
  # für andere Bibliotheken (clpb): AVL-Baum aus streng aufsteigend
  # sortierten Paaren {Schlüssel, Wert}, in O(n)
  def from_sorted([]), do: a("t")
  def from_sorted(ps), do: build(ps)

  # ausgewogener Baum aus n sortierten Paaren (wie SWIs list_to_assoc/5)
  defp build(ps) do
    {t, [], _} = build(length(ps), ps)
    t
  end

  defp build(1, [{k, v} | more]), do: {leaf(k, v), more, 1}

  defp build(2, [{k1, v1}, {k2, v2} | more]),
    do: {node(k2, v2, "<", leaf(k1, v1), a("t")), more, 2}

  defp build(n, ps) do
    n0 = n - 1
    rn = div(n0, 2)
    ln = rn + rem(n0, 2)
    {l, [{k, v} | upper], ld} = build(ln, ps)
    {r, more, rd} = build(rn, upper)
    {node(k, v, balance_of(rd, ld), l, r), more, ld + 1}
  end

  # --- Listen ------------------------------------------------------------------

  defp list!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  # wie keysort/2
  defp pair!(p, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(p, s)) do
      {:struct, "-", [k, v]} -> {k, v}
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("pair", PrologEx.resolve(other, s))
    end
  end

  defp keysort(ps, s), do: Order.keysort(Enum.map(ps, fn {k, _} = kv -> {k, kv} end), s)

  defp ordered?([_], _s), do: true

  defp ordered?([{k1, _}, {k2, _} = p | rest], s),
    do: Order.compare(k1, k2, s) == :lt and ordered?([p | rest], s)
end
