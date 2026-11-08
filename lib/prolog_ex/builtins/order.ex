defmodule PrologEx.Builtins.Order do
  @moduledoc """
  Termvergleich und Sortieren nach Standardordnung (`PrologEx.Order`),
  dazu term_variables/2 und subsumes_term/2.
  """
  use PrologEx.Builtin
  alias PrologEx.Order
  alias PrologEx.Builtins.Lists
  require PrologEx.Cyclic

  defbuiltin "==", [x, y] do
    Order.equal?(x, y, subst())
  end

  defbuiltin "\\==", [x, y] do
    not Order.equal?(x, y, subst())
  end

  defbuiltin "@<", [x, y] do
    Order.compare(x, y, subst()) == :lt
  end

  defbuiltin "@>", [x, y] do
    Order.compare(x, y, subst()) == :gt
  end

  defbuiltin "@=<", [x, y] do
    Order.compare(x, y, subst()) != :gt
  end

  defbuiltin "@>=", [x, y] do
    Order.compare(x, y, subst()) != :lt
  end

  defbuiltin "compare", [order, x, y] do
    case deref(order) do
      {:var, _} -> :ok
      {:atom, o} when o in ["<", "=", ">"] -> :ok
      {:atom, _} = o -> PrologEx.Error.domain!("order", o)
      [] -> PrologEx.Error.domain!("order", [])
      other -> PrologEx.Error.type!("atom", resolve(other))
    end

    sym =
      case Order.compare(x, y, subst()) do
        :lt -> "<"
        :eq -> "="
        :gt -> ">"
      end

    {:unify, [{order, a(sym)}]}
  end

  # sort/2: sortiert und entfernt Duplikate (==)
  defbuiltin "sort", [l, sorted] do
    s = subst()
    items = proper_list!(l, s)
    check_partial_list!(sorted, s)
    {:unify, [{sorted, list(Order.sort_unique(items, s))}]}
  end

  # msort/2: sortiert, Duplikate bleiben
  defbuiltin "msort", [l, sorted] do
    s = subst()
    items = proper_list!(l, s)
    check_partial_list!(sorted, s)
    {:unify, [{sorted, list(Order.sort(items, s))}]}
  end

  # keysort/2: Liste von Schlüssel-Wert-Paaren K-V, stabil nach Schlüssel
  defbuiltin "keysort", [l, sorted] do
    s = subst()
    items = proper_list!(l, s)
    check_partial_list!(sorted, s)

    # ISO Kor. 2: jedes Element von Sorted ist Variable oder Paar
    for e <- Lists.items_prefix(sorted, s) do
      case PrologEx.unmark_top(PrologEx.Store.walk(e, s)) do
        {:var, _} -> :ok
        {:struct, "-", [_, _]} -> :ok
        other -> PrologEx.Error.type!("pair", PrologEx.resolve(other, s))
      end
    end

    keyed =
      Enum.map(items, fn item ->
        case PrologEx.unmark_top(PrologEx.Store.walk(item, s)) do
          {:struct, "-", [k, _v]} -> {k, item}
          {:var, _} -> PrologEx.Error.instantiation!()
          other -> PrologEx.Error.type!("pair", PrologEx.resolve(other, s))
        end
      end)

    {:unify, [{sorted, list(Order.keysort(keyed, s))}]}
  end

  # term_variables(T, Vs): Variablen von T, Tiefensuche von links, ohne
  # Wiederholung
  defbuiltin "term_variables", [t, vs] do
    # ISO 8.5.5.3: Vs muss eine (Teil-)Liste sein
    check_partial_list!(vs, subst())
    {:unify, [{vs, list(variables(t, subst()))}]}
  end

  # subsumes_term(G, S): S ist eine Instanz von G. Einseitiges Matching:
  # nur Variablen von G werden (lokal) gebunden, Variablen von S gelten als
  # Konstanten – so entstehen keine zyklischen Terme (g(X) vs. g(f(X)))
  # und es bleiben keine Bindungen zurück.
  defbuiltin "subsumes_term", [general, specific] do
    s = subst()
    vs = variables(specific, s)

    try do
      match(general, specific, s, MapSet.new(vs), %{}, 0) != :error
    catch
      # ein Zyklus (d in match/6): nach der Definition (ISO 8.2.4) mit der
      # zyklenfesten Unifikation – G = S, ohne eine Variable von S zu binden
      :"$cyclic" ->
        case PrologEx.unify(general, specific, s) do
          {:ok, s2} -> variables(vs, s2) == vs
          :error -> false
        end
    end
  end

  # ---------------------------------------------------------------------

  @doc false
  def variables(t, s) do
    {acc, _seen} = vars(t, s, {[], %{}}, 0)
    Enum.reverse(acc)
  catch
    # ein Zyklus (d in vars/4): von vorn, gebundene Variablen nur einmal
    :"$cyclic" ->
      {acc, _seen} = vars_c(t, s, {[], %{}})
      Enum.reverse(acc)
  end

  @doc "Die erste Variable des Terms (in Reihenfolge des Auftretens) oder nil"
  def first_var(t, s) do
    case first_var(t, s, %{}, 0) do
      {:found, v} -> v
      _memo -> nil
    end
  catch
    :"$cyclic" ->
      case variables(t, s) do
        [v | _] -> v
        [] -> nil
      end
  end

  # {:found, V} oder das Memo der schon als variablenfrei bekannten
  # Teilterme (PrologEx.Share)
  defp first_var(t0, s, memo, d) do
    t = PrologEx.Store.walk(t0, s)
    d = PrologEx.Cyclic.step(t, t0, d, s)

    case t do
      {:var, _} = v ->
        {:found, v}

      {:struct, _, args} = st ->
        case PrologEx.Share.get(memo, st) do
          {:ok, _} ->
            memo

          :error ->
            case first_var_in(args, s, memo, d) do
              {:found, _} = r -> r
              memo -> PrologEx.Share.put(memo, st, true)
            end
        end

      [h | tl] ->
        case first_var(h, s, memo, d) do
          {:found, _} = r -> r
          memo -> first_var(tl, s, memo, d)
        end

      _ ->
        memo
    end
  end

  defp first_var_in([], _s, memo, _d), do: memo

  defp first_var_in([a | as], s, memo, d) do
    case first_var(a, s, memo, d) do
      {:found, _} = r -> r
      memo -> first_var_in(as, s, memo, d)
    end
  end

  # seen: gesehene Variablen und (PrologEx.Share) schon abgelaufene
  # Teilterme – ein geteilter Teilterm bringt beim zweiten Mal nichts Neues
  # d: Bindungen auf dem Pfad (PrologEx.Cyclic)
  defp vars(t0, s, {acc, seen} = st, d) do
    t = PrologEx.Store.walk(t0, s)
    d = PrologEx.Cyclic.step(t, t0, d, s)

    case t do
      {:var, _} = v ->
        if Map.has_key?(seen, v), do: st, else: {[v | acc], Map.put(seen, v, true)}

      {:struct, _, args} = t ->
        case PrologEx.Share.get(seen, t) do
          {:ok, _} ->
            st

          :error ->
            {acc, seen} = Enum.reduce(args, st, &vars(&1, s, &2, d))
            {acc, PrologEx.Share.put(seen, t, true)}
        end

      [h | tl] = l when is_tuple(h) or is_list(h) ->
        case PrologEx.Share.get(seen, l) do
          {:ok, _} ->
            st

          :error ->
            {acc, seen} = vars(tl, s, vars(h, s, st, d), d)
            {acc, PrologEx.Share.put(seen, l, true)}
        end

      [h | tl] ->
        vars(tl, s, vars(h, s, st, d), d)

      _atomic_or_marked_ground ->
        st
    end
  end

  # zyklenfest: jede gebundene Variable nur einmal ablaufen
  defp vars_c({:var, _} = v, s, {acc, seen} = st) do
    case Map.has_key?(seen, v) do
      true ->
        st

      false ->
        case PrologEx.Store.binding(s, v) do
          {:ok, t} -> vars_c(t, s, {acc, Map.put(seen, v, true)})
          :error -> {[v | acc], Map.put(seen, v, true)}
        end
    end
  end

  defp vars_c({:struct, _, args}, s, st), do: Enum.reduce(args, st, &vars_c(&1, s, &2))
  defp vars_c([h | tl], s, st), do: vars_c(tl, s, vars_c(h, s, st))
  defp vars_c(_, _s, st), do: st

  # Ergebnis: neue lokale Bindungen oder :error
  # d: wie oft eine Seite auf dem Pfad über eine Bindung lief (PrologEx.Cyclic)
  defp match(g0, sp0, s, frozen, m, d) do
    g = PrologEx.Store.walk(g0, s)
    sp = PrologEx.Store.walk(sp0, s)

    d =
      if g === g0 and sp === sp0 do
        d
      else
        d = d + 1
        if d > 2 * map_size(s), do: throw(:"$cyclic"), else: d
      end

    case g do
      {:var, _} ->
        cond do
          MapSet.member?(frozen, g) -> if g === sp, do: m, else: :error
          Map.has_key?(m, g) -> if Order.equal?(Map.fetch!(m, g), sp, s), do: m, else: :error
          true -> Map.put(m, g, sp)
        end

      _ ->
        case sp do
          {:var, _} ->
            :error

          _ ->
            # Paar-Memo (PrologEx.Share) in der Bindungs-Map: geteilte
            # Teilterme (zwei DAGs) nur einmal abgleichen
            compound = (is_tuple(g) and elem(g, 0) != :atom) or (is_list(g) and g != [])

            cond do
              # derselbe Teilterm gehört zu Specific: seine Variablen sind
              # eingefroren und passen nur auf sich selbst
              compound and PrologEx.Share.same?(g, sp) ->
                m

              compound ->
                case PrologEx.Share.get2(m, g, sp) do
                  {:ok, _} ->
                    m

                  :error ->
                    case match_nonvar(g, sp, s, frozen, m, d) do
                      :error -> :error
                      m -> PrologEx.Share.put2(m, g, sp, true)
                    end
                end

              true ->
                match_nonvar(g, sp, s, frozen, m, d)
            end
        end
    end
  end

  defp match_nonvar(g, sp, s, frozen, m, d) do
    case {parts(g), parts(sp)} do
      {{f, ga}, {f, sa}} when length(ga) == length(sa) -> match_args(ga, sa, s, frozen, m, d)
      {{:atomic, x}, {:atomic, y}} -> if Order.equal?(x, y, s), do: m, else: :error
      _ -> :error
    end
  end

  defp match_args([], [], _s, _frozen, m, _d), do: m

  defp match_args([g | gs], [x | xs], s, frozen, m, d) do
    case match(g, x, s, frozen, m, d) do
      :error -> :error
      m -> match_args(gs, xs, s, frozen, m, d)
    end
  end

  defp parts(t) do
    case uncons(t) do
      {:cons, h, tl} ->
        {".", [h, tl]}

      _ ->
        case t do
          {tag, f, args} when tag in [:struct, :gstruct] -> {f, args}
          other -> {:atomic, other}
        end
    end
  end

  defp proper_list!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> PrologEx.Error.instantiation!()
      _ -> PrologEx.Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  # das Ergebnis-Argument muss eine (evtl. offene) Liste oder Variable sein
  defp check_partial_list!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> :ok
      _ -> PrologEx.Error.type!("list", PrologEx.resolve(l, s))
    end
  end
end
