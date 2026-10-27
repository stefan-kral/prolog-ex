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
      {:var, _} -> PrologEx.Error.instantiation!()
      other -> PrologEx.Error.type!("integer", other)
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
      {a, _} when is_integer(a) -> PrologEx.Error.type!("not_less_than_zero", a)
      {{:var, _}, 0} -> :fail
      {{:var, _}, b} when is_integer(b) and b > 0 -> {:unify, [{x, b - 1}]}
      {{:var, _}, b} when is_integer(b) -> PrologEx.Error.type!("not_less_than_zero", b)
      {{:var, _}, {:var, _}} -> PrologEx.Error.instantiation!()
      {{:var, _}, b} -> PrologEx.Error.type!("integer", b)
      {a, _} -> PrologEx.Error.type!("integer", a)
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

  # write/1, print/1, writeq/1, write_canonical/1, write_term/2 (ISO 8.14.2):
  # Operator-Schreibweise wie gprolog, siehe PrologEx.Writer
  defbuiltin "write", [x] do
    PrologEx.Builtins.IO.out(PrologEx.Writer.format(resolve(x), numbervars: true))
    :ok
  end

  defbuiltin "print", [x] do
    PrologEx.Builtins.IO.out(PrologEx.Writer.format(resolve(x), writeq_opts()))
    :ok
  end

  defbuiltin "writeq", [x] do
    PrologEx.Builtins.IO.out(PrologEx.Writer.format(resolve(x), writeq_opts()))
    :ok
  end

  defbuiltin "write_canonical", [x] do
    PrologEx.Builtins.IO.out(PrologEx.Writer.format(resolve(x), quoted: true, ignore_ops: true))
    :ok
  end

  defbuiltin "write_term", [x, opts] do
    PrologEx.Builtins.IO.out(PrologEx.Writer.format(resolve(x), write_options(opts, subst())))
    :ok
  end

  # writeq: quoted, numbervars; Zeichenlisten als "..." bei
  # double_quotes=chars (wie die Antworten)
  @doc false
  def writeq_opts do
    [
      quoted: true,
      numbervars: true,
      strings: PrologEx.Flags.get("double_quotes") == {:atom, "chars"}
    ]
  end

  # Optionen von write_term/2: quoted/1, ignore_ops/1, numbervars/1
  # (ISO), variable_names/1 (ISO Cor.2), max_depth/1, spacing/1,
  # priority/1 (SWI)
  @doc false
  def write_options(opts, s) do
    case PrologEx.Builtins.Lists.skip_list(opts, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> PrologEx.Error.instantiation!()
      _ -> PrologEx.Error.type!("list", PrologEx.resolve(opts, s))
    end

    opts
    |> PrologEx.Builtins.Lists.items(s)
    |> Enum.map(&write_option(PrologEx.unmark(PrologEx.resolve(&1, s)), s))
  end

  @bool_options %{"quoted" => :quoted, "ignore_ops" => :ignore_ops, "numbervars" => :numbervars}

  defp write_option({:var, _}, _s), do: PrologEx.Error.instantiation!()

  # bekannte Option mit ungebundenem Wert: instantiation_error (ISO 8.14.2.3)
  defp write_option({:struct, name, [{:var, _}]}, _s)
       when name in ~w(quoted ignore_ops numbervars max_depth priority spacing variable_names portray),
       do: PrologEx.Error.instantiation!()

  defp write_option({:struct, name, [{:atom, b}]}, _s)
       when is_map_key(@bool_options, name) and b in ["true", "false"],
       do: {@bool_options[name], b == "true"}

  defp write_option({:struct, "max_depth", [n]}, _s) when is_integer(n) and n >= 0,
    do: {:max_depth, n}

  defp write_option({:struct, "priority", [n]}, _s) when is_integer(n) and n in 0..1200,
    do: {:priority, n}

  defp write_option({:struct, "spacing", [{:atom, sp}]}, _s)
       when sp in ["standard", "next_argument"],
       do: {:spacing, String.to_atom(sp)}

  defp write_option({:struct, "variable_names", [l]} = opt, _s) do
    # Name = Var; ist Var gebunden, wird der Eintrag nicht gebraucht
    names =
      proper_items!(l, opt)
      |> Enum.flat_map(fn
        {:struct, "=", [{:atom, name}, {:var, _} = v]} -> [{v, name}]
        {:struct, "=", [{:atom, _}, _]} -> []
        {:struct, "=", [{:var, _}, _]} -> PrologEx.Error.instantiation!()
        {:var, _} -> PrologEx.Error.instantiation!()
        _ -> PrologEx.Error.domain!("write_option", opt)
      end)
      # der erste Eintrag für eine Variable gilt
      |> Enum.reverse()
      |> Map.new()

    {:variable_names, names}
  end

  defp write_option(other, _s), do: PrologEx.Error.domain!("write_option", other)

  defp proper_items!(l, opt) do
    case l do
      [] -> []
      [h | t] -> [h | proper_items!(t, opt)]
      {:var, _} -> PrologEx.Error.instantiation!()
      _ -> PrologEx.Error.domain!("write_option", opt)
    end
  end

  defbuiltin "nl", [] do
    PrologEx.Builtins.IO.out("\n")
    :ok
  end

  defbuiltin "listing", [] do
    PrologEx.Builtins.IO.out(PrologEx.Listing.listing(db(), :all, context_module()))
    :ok
  end

  defbuiltin "listing", [spec] do
    PrologEx.Builtins.IO.out(PrologEx.Listing.listing(db(), resolve(spec), context_module()))
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
      {:var, _} -> PrologEx.Error.instantiation!()
      other -> PrologEx.Error.type!("integer", other)
    end
  end
end
