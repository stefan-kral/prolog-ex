defmodule PrologEx.Order do
  @moduledoc """
  Standardordnung der Terme (ISO 7.2):

      Variable < Zahl < Atom < zusammengesetzter Term

    * Variablen: nach interner Kennung (stabil innerhalb einer Anfrage)
    * Zahlen: nach Wert; bei gleichem Wert Float vor Integer (1.0 @< 1)
    * Atome: alphabetisch nach Codepoints (UTF-8 bytewise = Codepoints)
    * zusammengesetzt: Stelligkeit, dann Name, dann Argumente von links;
      Listen sind '.'/2

  Gebundene Variablen werden über die Substitution verfolgt;
  Ground-Markierungen spielen keine Rolle.
  """

  import PrologEx, only: [walk: 2, uncons: 1]

  @doc "`:lt`, `:eq` oder `:gt`"
  def compare(a, b, subst) do
    a = walk(a, subst)
    b = walk(b, subst)

    case {class(a), class(b)} do
      {c, c} -> same_class(c, a, b, subst)
      {ca, cb} -> if ca < cb, do: :lt, else: :gt
    end
  end

  def equal?(a, b, subst), do: compare(a, b, subst) == :eq

  @doc "Sortiert nach Standardordnung (stabil)."
  def sort(list, subst), do: Enum.sort(list, &(compare(&1, &2, subst) != :gt))

  @doc "Entfernt aufeinanderfolgende gleiche Elemente."
  def dedup([], _subst), do: []
  def dedup([x], _subst), do: [x]

  def dedup([x, y | rest], subst) do
    if equal?(x, y, subst), do: dedup([x | rest], subst), else: [x | dedup([y | rest], subst)]
  end

  defp class({:var, _}), do: 0
  defp class(n) when is_number(n), do: 1
  defp class([]), do: 2
  defp class({:atom, _}), do: 2
  defp class(_compound), do: 3

  defp same_class(0, {:var, x}, {:var, y}, _), do: cmp(var_key(x), var_key(y))
  defp same_class(1, x, y, _) when x < y, do: :lt
  defp same_class(1, x, y, _) when x > y, do: :gt
  defp same_class(1, x, y, _) when is_float(x) and is_integer(y), do: :lt
  defp same_class(1, x, y, _) when is_integer(x) and is_float(y), do: :gt
  defp same_class(1, _, _, _), do: :eq
  defp same_class(2, x, y, _), do: cmp(atom_name(x), atom_name(y))

  defp same_class(3, x, y, subst) do
    {fx, ax} = parts(x)
    {fy, ay} = parts(y)

    case cmp(length(ax), length(ay)) do
      :eq ->
        case cmp(fx, fy) do
          :eq -> compare_args(ax, ay, subst)
          other -> other
        end

      other ->
        other
    end
  end

  # letztes Argument (z. B. Listenrest) per Tail Call: keine Rekursionstiefe
  # entlang langer Listen
  defp compare_args([x], [y], subst), do: compare(x, y, subst)

  defp compare_args([x | xs], [y | ys], subst) do
    case compare(x, y, subst) do
      :eq -> compare_args(xs, ys, subst)
      other -> other
    end
  end

  defp parts({tag, f, args}) when tag in [:struct, :gstruct], do: {f, args}

  defp parts(list) do
    {:cons, h, t} = uncons(list)
    {".", [h, t]}
  end

  defp atom_name([]), do: "[]"
  defp atom_name({:atom, n}), do: n

  defp var_key(n) when is_integer(n), do: {0, n}
  defp var_key(n) when is_binary(n), do: {1, n}
  defp var_key(n), do: {2, n}

  defp cmp(x, y) when x < y, do: :lt
  defp cmp(x, y) when x > y, do: :gt
  defp cmp(_, _), do: :eq
end
