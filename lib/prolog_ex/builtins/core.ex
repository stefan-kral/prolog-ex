defmodule PrologEx.Builtins.Core do
  @moduledoc "Vergleich, Typprüfung, Ein-/Ausgabe, System."
  use PrologEx.Builtin

  defbuiltin "false", [] do
    :fail
  end

  # repeat/0: unendlich viele Lösungen als lazy Liste – jedes Backtracking
  # holt die nächste (konstanter Speicher in Fehlschlag-Schleifen)
  defbuiltin "repeat", [], nondet: true do
    repeat_forever()
  end

  defp repeat_forever, do: [:ok | &repeat_forever/0]

  # repeat/1 ist in Prolog definiert (siehe library/0); hier nur die Prüfung
  defbuiltin "$must_be_integer", [x] do
    case deref(x) do
      n when is_integer(n) -> :ok
      {:var, _} -> raise "instantiation_error"
      other -> raise "type_error(integer, #{format(other)})"
    end
  end

  # $repeat(N), N >= 1: genau N Lösungen als lazy Liste – der Rest wird
  # erst beim Backtracking erzeugt, nach der letzten bleibt kein Choice Point
  defbuiltin "$repeat", [n], nondet: true do
    repeat_n(deref(n))
  end

  defp repeat_n(1), do: [:ok]
  defp repeat_n(n), do: [:ok | fn -> repeat_n(n - 1) end]

  @doc false
  # repeat(N): Prüfung in Prolog, Aufzählung in Elixir ($repeat/1)
  def library do
    import PrologEx, only: [s: 2, v: 1, rule: 2]
    n = v("N")

    [rule(s("repeat", [n]), [s("$must_be_integer", [n]), s(">", [n, 0]), s("$repeat", [n])])]
  end

  # succ(X, Y): Y = X + 1 für natürliche Zahlen (in beide Richtungen)
  defbuiltin "succ", [x, y] do
    case {deref(x), deref(y)} do
      {a, _} when is_integer(a) and a >= 0 -> {:unify, [{y, a + 1}]}
      {a, _} when is_integer(a) -> raise "type_error(not_less_than_zero, #{a})"
      {{:var, _}, 0} -> :fail
      {{:var, _}, b} when is_integer(b) and b > 0 -> {:unify, [{x, b - 1}]}
      {{:var, _}, b} when is_integer(b) -> raise "type_error(not_less_than_zero, #{b})"
      {{:var, _}, {:var, _}} -> raise "instantiation_error"
      {{:var, _}, b} -> raise "type_error(integer, #{format(b)})"
      {a, _} -> raise "type_error(integer, #{format(a)})"
    end
  end

  defbuiltin "unify_with_occurs_check", [x, y] do
    # gelingt die Unifikation mit Occurs-Check, liefert die gewöhnliche
    # Unifikation dieselben Bindungen (gleicher Algorithmus)
    case PrologEx.unify_with_occurs_check(x, y, subst()) do
      {:ok, _} -> {:unify, [{x, y}]}
      :error -> :fail
    end
  end

  defbuiltin "\\=", [x, y] do
    case PrologEx.unify(x, y, subst()) do
      {:ok, _} -> :fail
      :error -> :ok
    end
  end

  # --- Typprüfungen ------------------------------------------------------

  defbuiltin "var", [x] do
    match?({:var, _}, deref(x))
  end

  defbuiltin "nonvar", [x] do
    not match?({:var, _}, deref(x))
  end

  defbuiltin "atom", [x] do
    atom?(deref(x))
  end

  defbuiltin "number", [x] do
    is_number(deref(x))
  end

  defbuiltin "integer", [x] do
    is_integer(deref(x))
  end

  defbuiltin "float", [x] do
    is_float(deref(x))
  end

  defbuiltin "atomic", [x] do
    t = deref(x)
    is_number(t) or atom?(t)
  end

  defbuiltin "compound", [x] do
    compound?(deref(x))
  end

  defbuiltin "callable", [x] do
    t = deref(x)
    compound?(t) or atom?(t)
  end

  defbuiltin "is_list", [x] do
    {_n, rest} = PrologEx.Builtins.Lists.skip_list(x, subst())
    rest == []
  end

  @doc false
  def atom?(t), do: t == [] or match?({:atom, _}, t)

  @doc false
  def compound?(t) do
    case t do
      [_ | _] -> true
      {:glist, _} -> true
      {:struct, _, _} -> true
      {:gstruct, _, _} -> true
      _ -> false
    end
  end

  # --- Ausgabe -----------------------------------------------------------

  defbuiltin "write", [x] do
    IO.write(format(resolve(x)))
    :ok
  end

  defbuiltin "print", [x] do
    IO.write(format(resolve(x)))
    :ok
  end

  defbuiltin "writeq", [x] do
    IO.write(format(resolve(x)))
    :ok
  end

  defbuiltin "nl", [] do
    IO.write("\n")
    :ok
  end

  defbuiltin "listing", [] do
    IO.write(PrologEx.Listing.listing(db(), :all))
    :ok
  end

  defbuiltin "listing", [spec] do
    IO.write(PrologEx.Listing.listing(db(), resolve(spec)))
    :ok
  end

  # --- DCG ---------------------------------------------------------------

  defbuiltin "phrase", [g, l] do
    {:call, PrologEx.DCG.body(resolve(g), l, [])}
  end

  defbuiltin "phrase", [g, l, r] do
    {:call, PrologEx.DCG.body(resolve(g), l, r)}
  end

  # --- System ------------------------------------------------------------

  defbuiltin "halt", [] do
    throw({:prolog_halt, 0})
  end

  defbuiltin "halt", [code] do
    case deref(code) do
      n when is_integer(n) -> throw({:prolog_halt, n})
      {:var, _} -> raise "instantiation_error"
      other -> raise "type_error(integer, #{format(other)})"
    end
  end
end
