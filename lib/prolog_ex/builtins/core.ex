defmodule PrologEx.Builtins.Core do
  @moduledoc "Vergleich, Typprüfung, Ein-/Ausgabe, System."
  use PrologEx.Builtin

  defbuiltin "false", [] do
    :fail
  end

  defbuiltin "\\=", [x, y] do
    case PrologEx.unify(x, y, subst()) do
      {:ok, _} -> :fail
      :error -> :ok
    end
  end

  defbuiltin "==", [x, y] do
    resolve(x) == resolve(y)
  end

  defbuiltin "\\==", [x, y] do
    resolve(x) != resolve(y)
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
