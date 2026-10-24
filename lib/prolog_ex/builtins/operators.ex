defmodule PrologEx.Builtins.Operators do
  @moduledoc """
  `op/3` und `current_op/3` (ISO 8.14.3, 8.14.4).

  Die Operatortabelle gehört dem Reader (gprolog liest alle Terme), also
  führt `op/3` die Änderung dort aus – gprolog prüft dabei wie ISO:
  instantiation_error, type_error(integer|atom|list),
  domain_error(operator_priority|operator_specifier),
  permission_error(modify, operator, ',') und permission_error(create,
  operator, Op) für `[]`, `{}`, `|` (außer als Infix mit Priorität ≥ 1001)
  und für Infix neben Postfix desselben Namens. Der Fehler kommt als
  error(Formal, _) zurück. Operatoren sind global (wie im Modulsystem
  festgelegt) und gelten ab dem nächsten gelesenen Term.

  `current_op(?P, ?Typ, ?Op)` zählt die aktuelle Tabelle auf (dazu gehören
  auch gprologs eigene Operatoren und die Deklarationen wie
  `dynamic`, `meta_predicate`).
  """
  use PrologEx.Builtin
  alias PrologEx.{Error, Reader, Writer}

  @specs ~w(xfx xfy yfx fy fx xf yf)
  # gprolog liest Ganzzahlen nur bis ±2^60
  @gp_max 576_460_752_303_423_488

  defbuiltin "op", [p, t, ops] do
    precheck(resolve(p), resolve(t), resolve(ops))
    args = Enum.map_join([p, t, ops], ", ", &Writer.format(resolve(&1), quoted: true))

    case Reader.op_call(Reader.current(), args) do
      :ok -> :ok
      {:error, formal} -> Error.error!(formal)
    end
  end

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

    for {prio, type, name} <- Reader.current_ops(Reader.current()),
        match?({:var, _}, pp) or pp == prio,
        match?({:var, _}, tt) or tt == {:atom, type},
        match?({:var, _}, oo) or oo == a(name),
        do: {:unify, [{p, prio}, {t, a(type)}, {op, a(name)}]}
  end

  # Ganzzahlen, die gprolog nicht lesen könnte: die Fehler hier melden
  defp precheck(p, t, ops) do
    if big?(p), do: Error.domain!("operator_priority", p)
    if big?(t), do: Error.type!("atom", t)
    if big?(ops), do: Error.type!("list", ops)
    each_elem(ops, fn e -> if big?(e), do: Error.type!("atom", e) end)
  end

  defp big?(n), do: is_integer(n) and abs(n) >= @gp_max

  defp each_elem([h | t], f) do
    f.(h)
    each_elem(t, f)
  end

  defp each_elem(_, _f), do: :ok
end
