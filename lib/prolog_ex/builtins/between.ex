defmodule PrologEx.Builtins.Between do
  @moduledoc """
  `library(between)` wie SICStus:

    * `gen_nat(?N)`: N ist eine natürliche Zahl; ungebunden zählt es
      0, 1, 2, ... auf (ohne Ende).
    * `gen_int(?I)`: I ist eine ganze Zahl; ungebunden in der Reihenfolge
      0, 1, -1, 2, -2, ... (ohne Ende).
    * `numlist(?Lower, ?Step, ?Upper, ?Length, ?List)`: List ist
      `[Lower, Lower+Step, ..., Upper]` mit Length Elementen (mindestens
      einem). Die Länge kommt aus Length, aus List (fertige Liste) oder aus
      Lower, Step, Upper; Lower und Step aus den Argumenten oder den ersten
      Elementen der Liste – `numlist(L, 2, U, N, [1, X, Y, Z])` gibt
      `L = 1, U = 7, N = 4, X = 3, Y = 5, Z = 7`. Reicht das nicht:
      instantiation_error.
    * dazu (wie in SICStus' library(between)) `between/3`, `repeat/1`
      (eingebaut) und `numlist/2,3` (aus library(lists)).

  Kein Argument außer Ganzzahlen und Variablen: `type_error(integer, X)`.
  """
  use PrologEx.Builtin, module: "between"
  alias PrologEx.Builtins.Lists
  alias PrologEx.Error

  defbuiltin "gen_nat", [n], nondet: true do
    case deref(n) do
      k when is_integer(k) -> if k >= 0, do: [:ok], else: []
      {:var, _} -> count(n, 0, &(&1 + 1))
      other -> Error.type!("integer", resolve(other))
    end
  end

  defbuiltin "gen_int", [i], nondet: true do
    case deref(i) do
      k when is_integer(k) -> [:ok]
      {:var, _} -> count(i, 0, &if(&1 > 0, do: -&1, else: -&1 + 1))
      other -> Error.type!("integer", resolve(other))
    end
  end

  # unendliche lazy Liste x = k, x = next(k), ...
  defp count(x, k, next), do: [{:unify, [{x, k}]} | fn -> count(x, next.(k), next) end]

  defbuiltin "numlist", [lower, step, upper, len, list] do
    s = subst()
    lo = int_or_var!(lower, s)
    st = int_or_var!(step, s)
    up = int_or_var!(upper, s)
    n0 = int_or_var!(len, s)

    {prefix, rest} = Lists.skip_list(list, s)
    items = Lists.items_prefix(list, s)

    n =
      cond do
        is_integer(n0) -> n0
        rest == [] -> prefix
        is_integer(lo) and is_integer(st) and is_integer(up) -> count_from(lo, st, up)
        true -> Error.instantiation!()
      end

    cond do
      n == :none or n < 1 ->
        :fail

      not (rest == [] or match?({:var, _}, rest)) ->
        :fail

      true ->
        first = elem_int(Enum.at(items, 0), s)
        second = if n >= 2, do: elem_int(Enum.at(items, 1), s)

        l = if is_integer(lo), do: lo, else: first

        stp =
          if is_integer(st),
            do: st,
            else: if(is_integer(l) and is_integer(second), do: second - l)

        cond do
          # ein Element ist keine Zahl: die Unifikation scheitert ohnehin
          :bad in [first, second] -> :fail
          not is_integer(l) -> Error.instantiation!()
          n >= 2 and not is_integer(stp) -> Error.instantiation!()
          true -> unify_all(lower, step, upper, len, list, l, stp, n)
        end
    end
  end

  # Länge aus Lower, Step, Upper (oder :none, wenn Upper nicht erreicht wird)
  defp count_from(lo, 0, up), do: if(lo == up, do: Error.instantiation!(), else: :none)

  defp count_from(lo, st, up) do
    d = up - lo
    if rem(d, st) == 0 and div(d, st) >= 0, do: div(d, st) + 1, else: :none
  end

  defp unify_all(lower, step, upper, len, list, l, stp, n) do
    elems = for i <- 0..(n - 1), do: l + i * (stp || 0)
    pairs = [{lower, l}, {upper, List.last(elems)}, {len, n}, {list, PrologEx.list(elems)}]
    {:unify, if(stp, do: [{step, stp} | pairs], else: pairs)}
  end

  # Element der Liste: Zahl, nil (ungebunden oder fehlt) oder :bad
  defp elem_int(nil, _s), do: nil

  defp elem_int(t, s) do
    case PrologEx.walk(t, s) do
      k when is_integer(k) -> k
      {:var, _} -> nil
      _ -> :bad
    end
  end

  defp int_or_var!(t, s) do
    case PrologEx.walk(t, s) do
      k when is_integer(k) -> k
      {:var, _} -> nil
      other -> Error.type!("integer", PrologEx.resolve(other, s))
    end
  end
end
