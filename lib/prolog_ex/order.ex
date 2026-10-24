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

  import PrologEx, only: [walk: 2, uncons: 1, is_marked: 1]

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

  @doc """
  Sind a und b Varianten (gleich bis auf eine eineindeutige Umbenennung der
  Variablen)? Wie `=@=/2` in SWI.
  """
  def variant?(a, b, subst), do: variant(a, b, subst, {%{}, %{}}) != :no

  defp variant(a, b, subst, maps) do
    a = walk(a, subst)
    b = walk(b, subst)

    case {a, b} do
      {{:var, _}, {:var, _}} ->
        {ab, ba} = maps

        case {Map.fetch(ab, a), Map.fetch(ba, b)} do
          {{:ok, ^b}, {:ok, ^a}} -> maps
          {:error, :error} -> {Map.put(ab, a, b), Map.put(ba, b, a)}
          _ -> :no
        end

      {{:var, _}, _} ->
        :no

      {_, {:var, _}} ->
        :no

      _ ->
        variant_nonvar(a, b, subst, maps)
    end
  end

  defp variant_nonvar(a, b, subst, maps) do
    cond do
      # ground markiert: Variante heißt gleich
      is_marked(a) or is_marked(b) ->
        if compare(a, b, subst) == :eq, do: maps, else: :no

      class(a) == 3 and class(b) == 3 ->
        {fa, aa} = parts(a)
        {fb, ab} = parts(b)

        if fa == fb and length(aa) == length(ab),
          do: variant_args(aa, ab, subst, maps),
          else: :no

      class(a) == class(b) and same_class(class(a), a, b, subst) == :eq ->
        maps

      true ->
        :no
    end
  end

  defp variant_args([], [], _subst, maps), do: maps

  defp variant_args([x | xs], [y | ys], subst, maps) do
    case variant(x, y, subst, maps) do
      :no -> :no
      maps -> variant_args(xs, ys, subst, maps)
    end
  end

  @doc """
  Wie `compare/3`, aber nur, wenn das Ergebnis unter jeder weiteren Bindung
  dasselbe bliebe (library(si)): `:lt`, `:eq`, `:gt` oder `:undecided`.

  Verglichen wird wie in der Standardordnung von links; trifft der
  Vergleich auf zwei nicht identische Terme, von denen einer eine Variable
  ist, hängt das Ergebnis von deren späterer Bindung ab. Was vorher schon
  entschieden ist (Stelligkeit, Name, frühere Argumente), bleibt
  entschieden: `f(a, X)` gegen `f(b, Y)` ist `:lt`, `f(X, a)` gegen
  `f(Y, b)` unentschieden. Identische Variablen sind gleich.
  """
  def compare_si(a, b, subst) do
    a = walk(a, subst)
    b = walk(b, subst)

    case {a, b} do
      {{:var, _}, {:var, _}} -> if a == b, do: :eq, else: :undecided
      {{:var, _}, _} -> :undecided
      {_, {:var, _}} -> :undecided
      _ -> compare_si_nonvar(a, b, subst)
    end
  end

  defp compare_si_nonvar(a, b, subst) do
    case {class(a), class(b)} do
      # ground markierte Terme: gewöhnlicher Vergleich
      {3, 3} ->
        if is_marked(a) and is_marked(b) do
          same_class(3, a, b, subst)
        else
          {fx, ax} = parts(a)
          {fy, ay} = parts(b)

          case cmp(length(ax), length(ay)) do
            :eq ->
              case cmp(fx, fy) do
                :eq -> compare_args_si(ax, ay, subst)
                other -> other
              end

            other ->
              other
          end
        end

      {c, c} ->
        same_class(c, a, b, subst)

      {ca, cb} ->
        if ca < cb, do: :lt, else: :gt
    end
  end

  defp compare_args_si([x], [y], subst), do: compare_si(x, y, subst)

  defp compare_args_si([x | xs], [y | ys], subst) do
    case compare_si(x, y, subst) do
      :eq -> compare_args_si(xs, ys, subst)
      other -> other
    end
  end

  # ---------------------------------------------------------------------
  # Sortieren
  #
  # Tupel zu vergleichen ist auf der BEAM deutlich teurer als kleine Zahlen.
  # Deshalb zuerst Schnellwege für einheitliche Listen, in denen die
  # eingebaute Ordnung der BEAM genau der Standardordnung entspricht:
  #
  #   * nur Integer          -> nativ sortieren
  #   * nur Zahlen (gemischt) -> Zahlenvergleich mit "Float vor Integer"
  #   * nur Atome {:atom, _}  -> nativ sortieren (Namen bytewise)
  #
  # Sonst bekommt jedes Element EINMAL einen Sortierschlüssel (key/2): ein
  # Elixir-Term, dessen eingebaute Ordnung der Standardordnung entspricht.
  # Danach sortiert die BEAM ohne Rückruf in Elixir-Code. Jeder Termknoten
  # ist ein 4-Tupel – alle Schlüssel haben dieselbe Größe (die BEAM
  # vergleicht Tupel zuerst nach Größe):
  #
  #   Variable  -> {0, kennung, 0, 0}
  #   Zahl      -> {1, wert, 0 | 1, 0}         Float (0) vor Integer (1)
  #   Atom      -> {2, name, 0, 0}
  #   zusammen. -> {3, stelligkeit, name, {schlüssel der argumente ...}}
  # ---------------------------------------------------------------------

  @doc "Sortiert nach Standardordnung (stabil)."
  def sort(list, subst), do: do_sort(list, subst, false)

  @doc "Sortiert und entfernt Duplikate (gleich im Sinne von ==)."
  def sort_unique(list, subst), do: do_sort(list, subst, true)

  @doc "Sortiert Paare `{schlüsselterm, element}` stabil nach dem Schlüsselterm."
  def keysort(pairs, subst) do
    walked = Enum.map(pairs, fn {k, item} -> {walk(k, subst), item} end)

    keyed =
      case kind(Enum.map(walked, &elem(&1, 0)), :none) do
        # Schlüssel direkt vergleichbar (List.keysort ist stabil)
        k when k in [:integers, :atoms] -> walked
        _ -> Enum.map(walked, fn {k, item} -> {key(k, subst), item} end)
      end

    keyed |> List.keysort(0) |> Enum.map(&elem(&1, 1))
  end

  defp do_sort(list, subst, unique) do
    values = Enum.map(list, &walk(&1, subst))

    case kind(values, :none) do
      :integers ->
        if unique, do: :lists.usort(values), else: :lists.sort(values)

      :atoms ->
        if unique, do: :lists.usort(values), else: :lists.sort(values)

      :numbers ->
        sorted = Enum.sort(values, &number_le/2)
        if unique, do: dedup_numbers(sorted), else: sorted

      :mixed ->
        keyed = Enum.map(values, &{key(&1, subst), &1})
        sorted = List.keysort(keyed, 0)
        sorted = if unique, do: dedup_keyed(sorted), else: sorted
        Enum.map(sorted, &elem(&1, 1))
    end
  end

  # Einheitlichkeit der (dereferenzierten) Elemente feststellen
  defp kind([], k), do: if(k == :none, do: :integers, else: k)
  defp kind([x | xs], k) when is_integer(x) and k in [:none, :integers], do: kind(xs, :integers)

  defp kind([x | xs], k) when is_number(x) and k in [:none, :integers, :numbers],
    do: kind(xs, :numbers)

  defp kind([{:atom, _} | xs], k) when k in [:none, :atoms], do: kind(xs, :atoms)
  defp kind(_, _), do: :mixed

  defp number_le(x, y) when x < y, do: true
  defp number_le(x, y) when x > y, do: false
  # gleicher Wert: Float vor Integer
  defp number_le(x, y), do: is_float(x) or is_integer(y)

  defp dedup_numbers([x, y | rest]) when x == y and is_float(x) == is_float(y),
    do: dedup_numbers([x | rest])

  defp dedup_numbers([x | rest]), do: [x | dedup_numbers(rest)]
  defp dedup_numbers([]), do: []

  # == auf den Schlüsseln entspricht compare/3 == :eq (auch 0.0 / -0.0)
  defp dedup_keyed([{k1, _} = x, {k2, _} | rest]) when k1 == k2, do: dedup_keyed([x | rest])
  defp dedup_keyed([x | rest]), do: [x | dedup_keyed(rest)]
  defp dedup_keyed([]), do: []

  @doc "Sortierschlüssel eines Terms (siehe oben)."
  def key(t, subst) do
    case walk(t, subst) do
      {:var, n} ->
        {0, var_key(n), 0, 0}

      x when is_float(x) ->
        {1, x, 0, 0}

      x when is_integer(x) ->
        {1, x, 1, 0}

      [] ->
        {2, "[]", 0, 0}

      {:atom, n} ->
        {2, n, 0, 0}

      {:glist, _} = l ->
        list_key(l, subst)

      [_ | _] = l ->
        list_key(l, subst)

      {tag, f, args} when tag in [:struct, :gstruct] ->
        {3, length(args), f, args_key(args, subst)}
    end
  end

  defp list_key(l, subst) do
    {:cons, h, t} = uncons(l)
    {3, 2, ".", {key(h, subst), key(t, subst)}}
  end

  defp args_key(args, subst), do: args |> Enum.map(&key(&1, subst)) |> List.to_tuple()

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
