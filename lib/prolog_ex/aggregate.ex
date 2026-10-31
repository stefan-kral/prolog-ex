defmodule PrologEx.Aggregate do
  @moduledoc """
  Kern von `library(aggregate)`: Templates prüfen und Lösungen falten.

  Ein Template ist `count`, `sum(E)`, `min(E)`, `max(E)`, `min(E, W)`,
  `max(E, W)`, `bag(X)`, `set(X)` oder ein zusammengesetzter Term, dessen
  Argumente selbst Templates sind (`r(count, max(X))`, auch geschachtelt).
  `spec!/2` macht daraus die Form (ohne die Ausdrücke), `step/5` faltet
  eine Lösung hinein, `result/2` baut das Ergebnis.

  Arithmetik wie `is/2`: `sum` addiert, `min`/`max` vergleichen
  numerisch; ein Wert, der keine Zahl ergibt, wirft wie `is/2`
  (`type_error(evaluable, a/0)`). Beim Zeugen (`max(E, W)`) gewinnt bei
  Gleichstand der erste. Ohne Lösung: `count` und `sum` 0, `bag` und `set`
  `[]`, `min` und `max` keine (das Falten scheitert, auch im
  zusammengesetzten Template).

  Fehler wie SWI: freies Template `instantiation_error`, unbekanntes Atom
  oder unbekannte Struktur ohne Template-Argumente
  `domain_error(aggregate_template, T)`, nicht aufrufbar
  `type_error(aggregate_template, T)`.
  """
  import PrologEx, only: [mk: 2, list: 1]
  alias PrologEx.{Arith, Error}

  @doc "Form des Templates (wirft bei ungültigem Template)"
  def spec!(t, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:var, _} -> Error.instantiation!()
      {:atom, "count"} -> :count
      {:struct, "sum", [_]} -> :sum
      {:struct, "max", [_]} -> :max
      {:struct, "min", [_]} -> :min
      {:struct, "max", [_, _]} -> :max_w
      {:struct, "min", [_, _]} -> :min_w
      {:struct, "bag", [_]} -> :bag
      {:struct, "set", [_]} -> :set
      {:struct, f, args} -> {:comp, f, Enum.map(args, &spec!(&1, s))}
      [h | tl] -> {:comp, ".", [spec!(h, s), spec!(tl, s)]}
      {:atom, _} = a -> Error.domain!("aggregate_template", a)
      [] -> Error.domain!("aggregate_template", [])
      other -> Error.type!("aggregate_template", PrologEx.resolve(other, s))
    end
  end

  @doc "Anfangswert des Akkumulators"
  def init(:count), do: 0
  def init(:sum), do: 0
  def init(k) when k in [:bag, :set], do: []
  def init({:comp, _, specs}), do: Enum.map(specs, &init/1)
  def init(_minmax), do: nil

  @doc """
  Eine Lösung falten: `t` ist das Template (bzw. eine Instanz davon),
  `s` die Substitution der Lösung; `copy` macht aus einem Teilterm eine
  Kopie, die die Lösung überdauert (`bag`, `set`, Zeuge).
  """
  def step(:count, _t, _s, n, _copy), do: n + 1

  def step(:sum, t, s, acc, _copy) do
    v = value(arg(t, s, 0), s)
    Arith.eval(mk("+", [acc, v]), %{})
  end

  def step(k, t, s, acc, _copy) when k in [:max, :min] do
    v = value(arg(t, s, 0), s)

    if acc == nil,
      do: v,
      else: Arith.eval(mk(if(k == :max, do: "max", else: "min"), [acc, v]), %{})
  end

  def step(k, t, s, acc, copy) when k in [:max_w, :min_w] do
    v = value(arg(t, s, 0), s)

    better =
      case acc do
        nil -> true
        {best, _} -> if k == :max_w, do: v > best, else: v < best
      end

    if better, do: {v, copy.(arg(t, s, 1), s)}, else: acc
  end

  def step(k, t, s, acc, copy) when k in [:bag, :set], do: [copy.(arg(t, s, 0), s) | acc]

  def step({:comp, _, specs}, t, s, accs, copy) do
    args = args(t, s)

    [specs, args, accs]
    |> Enum.zip()
    |> Enum.map(fn {sp, a, acc} -> step(sp, a, s, acc, copy) end)
  end

  @doc "Ergebnis: `{:ok, term}` oder `:fail` (min/max ohne Lösung)"
  def result(k, n) when k in [:count, :sum], do: {:ok, n}
  def result(k, nil) when k in [:max, :min, :max_w, :min_w], do: :fail
  def result(k, v) when k in [:max, :min], do: {:ok, v}
  def result(:max_w, {v, w}), do: {:ok, mk("max", [v, w])}
  def result(:min_w, {v, w}), do: {:ok, mk("min", [v, w])}
  def result(:bag, acc), do: {:ok, list(Enum.reverse(acc))}
  def result(:set, acc), do: {:ok, list(PrologEx.Order.sort_unique(Enum.reverse(acc), %{}))}

  def result({:comp, f, specs}, accs) do
    results = Enum.zip_with(specs, accs, &result/2)

    if Enum.all?(results, &match?({:ok, _}, &1)),
      do: {:ok, mk(f, Enum.map(results, &elem(&1, 1)))},
      else: :fail
  end

  # Ausdruck auswerten wie is/2
  defp value(e, s), do: Arith.eval(e, s)

  defp arg(t, s, i), do: Enum.at(args(t, s), i)

  defp args(t, s) do
    case PrologEx.unmark_top(PrologEx.walk(t, s)) do
      {:struct, _, args} -> args
      [h | tl] -> [h, tl]
    end
  end
end
