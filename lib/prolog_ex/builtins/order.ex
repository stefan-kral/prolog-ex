defmodule PrologEx.Builtins.Order do
  @moduledoc """
  Termvergleich und Sortieren nach Standardordnung (`PrologEx.Order`),
  dazu term_variables/2 und subsumes_term/2.
  """
  use PrologEx.Builtin
  alias PrologEx.Order
  alias PrologEx.Builtins.Lists

  defbuiltin "==", [x, y] do
    Order.compare(x, y, subst()) == :eq
  end

  defbuiltin "\\==", [x, y] do
    Order.compare(x, y, subst()) != :eq
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

    keyed =
      Enum.map(items, fn item ->
        case PrologEx.unmark_top(PrologEx.walk(item, s)) do
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
    {:unify, [{vs, list(variables(t, subst()))}]}
  end

  # subsumes_term(G, S): S ist eine Instanz von G. Einseitiges Matching:
  # nur Variablen von G werden (lokal) gebunden, Variablen von S gelten als
  # Konstanten – so entstehen keine zyklischen Terme (g(X) vs. g(f(X)))
  # und es bleiben keine Bindungen zurück.
  defbuiltin "subsumes_term", [general, specific] do
    s = subst()
    frozen = MapSet.new(variables(specific, s))
    match(general, specific, s, frozen, %{}) != :error
  end

  # ---------------------------------------------------------------------

  @doc false
  def variables(t, s) do
    {acc, _seen} = vars(t, s, {[], MapSet.new()})
    Enum.reverse(acc)
  end

  defp vars(t, s, {acc, seen} = st) do
    case PrologEx.walk(t, s) do
      {:var, _} = v ->
        if MapSet.member?(seen, v), do: st, else: {[v | acc], MapSet.put(seen, v)}

      {:struct, _, args} ->
        Enum.reduce(args, st, &vars(&1, s, &2))

      [h | tl] ->
        vars(tl, s, vars(h, s, st))

      _atomic_or_marked_ground ->
        st
    end
  end

  # Ergebnis: neue lokale Bindungen oder :error
  defp match(g, sp, s, frozen, m) do
    g = PrologEx.walk(g, s)
    sp = PrologEx.walk(sp, s)

    case g do
      {:var, _} ->
        cond do
          MapSet.member?(frozen, g) -> if g === sp, do: m, else: :error
          Map.has_key?(m, g) -> if Order.equal?(Map.fetch!(m, g), sp, s), do: m, else: :error
          true -> Map.put(m, g, sp)
        end

      _ ->
        case sp do
          {:var, _} -> :error
          _ -> match_nonvar(g, sp, s, frozen, m)
        end
    end
  end

  defp match_nonvar(g, sp, s, frozen, m) do
    case {parts(g), parts(sp)} do
      {{f, ga}, {f, sa}} when length(ga) == length(sa) -> match_args(ga, sa, s, frozen, m)
      {{:atomic, x}, {:atomic, y}} -> if Order.equal?(x, y, s), do: m, else: :error
      _ -> :error
    end
  end

  defp match_args([], [], _s, _frozen, m), do: m

  defp match_args([g | gs], [x | xs], s, frozen, m) do
    case match(g, x, s, frozen, m) do
      :error -> :error
      m -> match_args(gs, xs, s, frozen, m)
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
