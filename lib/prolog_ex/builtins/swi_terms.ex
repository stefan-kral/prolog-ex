defmodule PrologEx.Builtins.SwiTerms do
  @moduledoc """
  Weitere Prädikate über Terme wie SWI (Heimat `library(swi)`, `variant/2`
  in `library(terms)`), dazu die Tabelle für `distinct/1,2` aus
  `library(solution_sequences)`:

    * `variant(A, B)`: dasselbe wie `A =@= B`.
    * `unifiable(X, Y, Unifier)`: die Bindungen, die `X = Y` machte, als
      Liste `V = T` (zuletzt angelegte Variable zuerst, wie SWI), ohne sie zu
      machen; scheitert, wenn X und Y nicht unifizierbar sind.
    * `term_singletons(T, Vs)`: die Variablen, die in T genau einmal
      vorkommen, in der Reihenfolge des Auftretens.
    * `duplicate_term(T, C)`: wie `copy_term/2` (Terme sind hier ohnehin
      nicht veränderbar).
    * `atom_to_term(Atom, T, Bindings)`: `read_term_from_atom/3` mit
      `variable_names(Bindings)`.
  """
  use PrologEx.Builtin
  alias PrologEx.{Order, Store}

  defbuiltin "variant", [x, y] do
    Order.variant?(x, y, subst())
  end

  defbuiltin "unifiable", [x, y, u] do
    s = subst()

    case PrologEx.unify(x, y, s) do
      {:ok, s2} ->
        pairs =
          for({v, t} <- Store.new_bindings(s, s2), do: {v, t})
          |> Enum.sort_by(fn {{:var, id}, _} -> id end, :desc)
          |> Enum.map(fn {v, t} -> mk("=", [v, t]) end)

        {:unify, [{u, list(pairs)}]}

      :error ->
        :fail
    end
  end

  defbuiltin "term_singletons", [t, vs] do
    s = subst()
    {order, counts} = count_vars([t], s, [], %{}, MapSet.new())
    {:unify, [{vs, list(for v <- Enum.reverse(order), counts[v] == 1, do: v)}]}
  end

  # Vorkommen je Variable; seen: Bindungen, über die der Weg schon lief
  # (zyklische Terme)
  defp count_vars([], _s, order, counts, _seen), do: {order, counts}

  defp count_vars([t0 | rest], s, order, counts, seen) do
    {t, last} = PrologEx.Cyclic.walk_last(t0, s, nil)

    if last != nil and MapSet.member?(seen, last) do
      count_vars(rest, s, order, counts, seen)
    else
      seen = if last, do: MapSet.put(seen, last), else: seen

      case t do
        {:var, _} = v ->
          case counts do
            %{^v => n} -> count_vars(rest, s, order, %{counts | v => n + 1}, seen)
            _ -> count_vars(rest, s, [v | order], Map.put(counts, v, 1), seen)
          end

        {:struct, _, args} ->
          count_vars(args ++ rest, s, order, counts, seen)

        [h | tl] ->
          count_vars([h, tl | rest], s, order, counts, seen)

        _ ->
          count_vars(rest, s, order, counts, seen)
      end
    end
  end

  # atom_to_term(+Atom, -T, -Bindings): wie read_term_from_atom/3 mit
  # variable_names(Bindings)
  defbuiltin "atom_to_term", [at, t, b] do
    {:call, mk("read_term_from_atom", [at, t, list([mk("variable_names", [b])])])}
  end

  defbuiltin "duplicate_term", [t, c] do
    {:call, mk("copy_term", [t, c])}
  end

  # --- distinct/1,2: gesehene Varianten, nicht backtrackbar --------------

  @key :prolog_ex_distinct

  defbuiltin "$distinct_new", [t] do
    id = System.unique_integer([:positive])
    Process.put({@key, id}, MapSet.new())
    {:unify, [{t, id}]}
  end

  defbuiltin "$distinct_add", [t, w] do
    s = subst()
    id = Store.walk(t, s)
    seen = Process.get({@key, id}, MapSet.new())
    k = PrologEx.Builtins.Memo.variant_key(w, s)

    if MapSet.member?(seen, k) do
      :fail
    else
      Process.put({@key, id}, MapSet.put(seen, k))
      :ok
    end
  end

  defbuiltin "$distinct_free", [t] do
    Process.delete({@key, Store.walk(t, subst())})
    :ok
  end
end
