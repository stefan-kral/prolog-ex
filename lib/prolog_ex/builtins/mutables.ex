defmodule PrologEx.Builtins.Mutables do
  @moduledoc """
  `library(mutables)`: veränderbare Terme mit backtrackbarer Zuweisung,
  wie SICStus (dort eingebaut).

    * `create_mutable(+Wert, -Mutable)`  neues Mutable mit Wert
    * `get_mutable(?Wert, +Mutable)`     aktuellen Wert unifizieren
    * `update_mutable(+Wert, +Mutable)`  Wert ersetzen; Backtracking
                                         stellt den alten wieder her
    * `mutable(@X)`                      ist X ein Mutable?

  Der Wert darf keine ungebundene Variable sein (instantiation_error),
  wird aber nicht kopiert: Variablen darin bleiben dieselben.

  Umsetzung: ein Mutable ist `'$mutable'(V)` mit einer versteckten
  attributierten Variablen V; der Wert ist ihr Attribut `$mutable`. So ist
  update_mutable/2 ein O(log n)-Eintrag in der Substitution, Backtracking
  nimmt ihn wie jede Bindung zurück, und die Kompaktierung hält den Wert
  am Leben, solange das Mutable erreichbar ist. `copy_term/2` und
  `findall/3` kopieren das Mutable ohne Wert (wie Attribute).
  """
  use PrologEx.Builtin, module: "mutables"
  alias PrologEx.Error

  @attr "$mutable"

  defbuiltin "create_mutable", [value, m] do
    s = subst()
    nonvar!(value, s)
    cell = fresh_var()
    s = PrologEx.put_attr(s, cell, @attr, value)

    case PrologEx.unify(m, mk("$mutable", [cell]), s) do
      {:ok, s} -> {:subst, s}
      _ -> :fail
    end
  end

  defbuiltin "get_mutable", [value, m] do
    s = subst()
    {:unify, [{value, Map.fetch!(PrologEx.get_attrs(cell!(m, s), s), @attr)}]}
  end

  defbuiltin "update_mutable", [value, m] do
    s = subst()
    nonvar!(value, s)
    {:subst, PrologEx.put_attr(s, cell!(m, s), @attr, value)}
  end

  defbuiltin "mutable", [x] do
    cell(deref(x), subst()) != nil
  end

  @doc """
  Für Antworten im Toplevel: jedes Mutable in einem aufgelösten Term als
  `'$mutable'(Wert)` (mit aufgelöstem Wert) statt mit seiner Zelle.
  """
  def show(t, s) do
    if Enum.any?(s, &match?({{:attrs, _}, %{@attr => _}}, &1)),
      do: show_term(t, s, MapSet.new()),
      else: t
  end

  # seen: Zellen auf dem Weg hierher – ein Mutable, das sich selbst
  # enthält, wird beim zweiten Mal mit seiner Zelle gezeigt
  defp show_term({:struct, "$mutable", [{:var, {:attv, id}}]} = t, s, seen) do
    case Map.get(s, {:attrs, id}, %{}) do
      %{@attr => value} ->
        if MapSet.member?(seen, id),
          do: t,
          else: mk("$mutable", [show_term(PrologEx.resolve(value, s), s, MapSet.put(seen, id))])

      _ ->
        t
    end
  end

  defp show_term({:struct, f, args}, s, seen),
    do: {:struct, f, Enum.map(args, &show_term(&1, s, seen))}

  defp show_term([_ | _] = l, s, seen), do: show_list(l, s, seen, [])
  defp show_term(t, _s, _seen), do: t

  # über den Listenrücken iterativ (lange Listen)
  defp show_list([h | t], s, seen, acc), do: show_list(t, s, seen, [show_term(h, s, seen) | acc])
  defp show_list(tail, s, seen, acc), do: :lists.reverse(acc, show_term(tail, s, seen))

  # ---------------------------------------------------------------------

  defp nonvar!(t, s) do
    if match?({:var, _}, PrologEx.walk(t, s)), do: Error.instantiation!()
  end

  defp cell!(m, s) do
    case PrologEx.walk(m, s) do
      {:var, _} ->
        Error.instantiation!()

      t ->
        cell(t, s) || Error.type!("mutable", PrologEx.resolve(t, s))
    end
  end

  # die Zellvariable eines Mutables, sonst nil
  defp cell(t, s) do
    with {:struct, "$mutable", [v]} <- PrologEx.unmark_top(t),
         v = PrologEx.walk(v, s),
         true <- PrologEx.attv?(v),
         true <- Map.has_key?(PrologEx.get_attrs(v, s), @attr) do
      v
    else
      _ -> nil
    end
  end
end
