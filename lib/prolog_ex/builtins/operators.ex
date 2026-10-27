defmodule PrologEx.Builtins.Operators do
  @moduledoc """
  `op/3` und `current_op/3` (ISO 8.14.3, 8.14.4).

  `op/3` prüft wie ISO (mit Cor. 3): instantiation_error,
  type_error(integer|atom|list), domain_error(operator_priority |
  operator_specifier), permission_error(modify, operator, ',') und
  permission_error(create, operator, Op) für `[]`, `{}`, `|` (außer als
  Infix mit Priorität ≥ 1001 oder 0) und für Infix neben Postfix
  desselben Namens. Erst wenn alle Namen geprüft sind, ändert sich die
  Tabelle. Operatoren sind global (wie im Modulsystem festgelegt) und
  gelten ab dem nächsten gelesenen Term.

  `current_op(?P, ?Typ, ?Op)` zählt die aktuelle Tabelle auf (dazu gehören
  die Deklarationen wie `dynamic`, `meta_predicate`).

  Dazu `char_conversion/2` und `current_char_conversion/2` (siehe
  `PrologEx.CharConversion`).
  """
  use PrologEx.Builtin
  alias PrologEx.{Error, Ops}

  @specs ~w(xfx xfy yfx fy fx xf yf)

  defbuiltin "op", [p, t, ops] do
    {p, t, ops} = {resolve(p), resolve(t), PrologEx.unmark(resolve(ops))}
    names = check!(p, t, ops)
    {:atom, type} = t
    for name <- names, do: Ops.add(p, type, name)
    :ok
  end

  defp check!(p, t, ops) do
    if match?({:var, _}, p) or match?({:var, _}, t), do: Error.instantiation!()
    names = op_names!(ops)
    unless is_integer(p), do: Error.type!("integer", p)
    unless match?({:atom, _}, t), do: Error.type!("atom", t)
    unless p in 0..1200, do: Error.domain!("operator_priority", p)
    {:atom, type} = t
    unless type in @specs, do: Error.domain!("operator_specifier", t)

    for name <- names do
      if name == ",", do: Error.permission!("modify", "operator", a(","))
      if name in ["[]", "{}"], do: Error.permission!("create", "operator", a(name))

      if name == "|" and (Ops.class(type) != :infix or (p > 0 and p < 1001)),
        do: Error.permission!("create", "operator", a("|"))

      # ISO: kein Name zugleich Infix und Postfix
      other = %{infix: :postfix, postfix: :infix}[Ops.class(type)]

      if p > 0 and other && Ops.lookup(Ops.table(), name, other),
        do: Error.permission!("create", "operator", a(name))
    end

    names
  end

  # Atom oder Liste von Atomen; [] ist das Atom '[]' (ISO)
  defp op_names!({:var, _}), do: Error.instantiation!()
  defp op_names!([]), do: ["[]"]
  defp op_names!({:atom, n}), do: [n]

  defp op_names!([_ | _] = l) do
    {items, tail} = items(l, [])

    case tail do
      [] -> :ok
      {:var, _} -> Error.instantiation!()
      _ -> Error.type!("list", l)
    end

    if Enum.any?(items, &match?({:var, _}, &1)), do: Error.instantiation!()

    for item <- items do
      case item do
        {:atom, n} -> n
        [] -> "[]"
        other -> Error.type!("atom", other)
      end
    end
  end

  defp op_names!(other), do: Error.type!("list", other)

  defp items([h | t], acc), do: items(t, [h | acc])
  defp items(tail, acc), do: {Enum.reverse(acc), tail}

  @doc "op(P, T, Ops) in den Spiegel der Operatortabelle übernehmen (schon geprüft)"
  def mirror(p, {:atom, type}, ops) when is_integer(p) do
    for name <- names(ops), do: PrologEx.Ops.add(p, type, name)
    :ok
  end

  def mirror(_, _, _), do: :ok

  defp names({:atom, n}), do: [n]
  defp names([h | t]), do: names(h) ++ names(t)
  defp names({:glist, l}), do: names(l)
  defp names(_), do: []

  # --- Zeichenumsetzung (ISO 8.14.5, 8.14.6; Fehler wie gprolog/SICStus) ---

  defbuiltin "char_conversion", [i, o] do
    {ii, oo} = {resolve(i), resolve(o)}
    if match?({:var, _}, ii) or match?({:var, _}, oo), do: Error.instantiation!()
    PrologEx.CharConversion.put(char!(ii), char!(oo))
    :ok
  end

  # nur Paare mit In ≠ Out (Zeichen ohne Eintrag stehen nicht in der Tabelle)
  defbuiltin "current_char_conversion", [i, o], nondet: true do
    {ii, oo} = {resolve(i), resolve(o)}
    unless match?({:var, _}, ii), do: char!(ii)
    unless match?({:var, _}, oo), do: char!(oo)

    for {c, d} <- Enum.sort(PrologEx.CharConversion.table()),
        do: {:unify, [{i, a(<<c::utf8>>)}, {o, a(<<d::utf8>>)}]}
  end

  defp char!({:atom, s} = x) do
    case String.to_charlist(s) do
      [c] -> c
      _ -> Error.type!("character", x)
    end
  end

  defp char!(other), do: Error.type!("character", other)

  defbuiltin "current_op", [p, t, op], nondet: true do
    pp = deref(p)
    tt = deref(t)
    oo = deref(op)

    case pp do
      {:var, _} -> :ok
      n when is_integer(n) and n >= 0 and n <= 1200 -> :ok
      other -> Error.domain!("operator_priority", resolve(other))
    end

    case tt do
      {:var, _} -> :ok
      {:atom, s} when s in @specs -> :ok
      other -> Error.domain!("operator_specifier", resolve(other))
    end

    case oo do
      {:var, _} -> :ok
      {:atom, _} -> :ok
      [] -> :ok
      other -> Error.type!("atom", resolve(other))
    end

    for {name, classes} <- Ops.table(),
        {_class, {prio, type}} <- classes,
        match?({:var, _}, pp) or pp == prio,
        match?({:var, _}, tt) or tt == {:atom, type},
        match?({:var, _}, oo) or oo == a(name),
        do: {:unify, [{p, prio}, {t, a(type)}, {op, a(name)}]}
  end
end
