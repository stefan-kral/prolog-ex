defmodule PrologEx.Order do
  @moduledoc """
  Standardordnung der Terme (ISO 7.2):

      Variable < Zahl < Atom < zusammengesetzter Term

    * Variablen: nach interner Kennung (stabil innerhalb einer Anfrage)
    * Zahlen: alle Floats vor allen Integern (ISO 7.2.2: `7.0 @< 1`),
      innerhalb nach Wert
    * Atome: alphabetisch nach Codepoints (UTF-8 bytewise = Codepoints)
    * zusammengesetzt: Stelligkeit, dann Name, dann Argumente von links;
      Listen sind '.'/2

  Gebundene Variablen werden über die Substitution verfolgt;
  Ground-Markierungen spielen keine Rolle.
  """

  import PrologEx, only: [walk: 2, uncons: 1, is_marked: 1]

  @doc """
  `:lt`, `:eq` oder `:gt`, direkt auf dem Paar: Klassen, Zahlen, Atome und
  Funktoren in Klauseln statt über Klassennummern; Listen ohne Umweg über
  `'.'/2`, Markierungen ohne `unmark_top`. Kein `===` vorweg (anders als
  `equal?/3`): bei den üblichen ungleichen kleinen Termen kostete es rund
  20 %, und innen wiederholt wäre es quadratisch.
  """
  def compare(a, b, subst), do: c(walk(a, subst), walk(b, subst), subst)

  @st [:struct, :gstruct]

  # Variable < Zahl < Atom < zusammengesetzt
  defp c({:var, x}, {:var, y}, _), do: var_cmp(x, y)
  defp c({:var, _}, _, _), do: :lt
  defp c(_, {:var, _}, _), do: :gt
  defp c(x, y, _) when is_integer(x) and is_integer(y), do: cmp(x, y)
  defp c(x, y, _) when is_float(x) and is_float(y), do: cmp(x, y)
  # ISO: Float vor Integer, unabhängig vom Wert
  defp c(x, y, _) when is_float(x) and is_integer(y), do: :lt
  defp c(x, y, _) when is_integer(x) and is_float(y), do: :gt
  defp c(x, _, _) when is_number(x), do: :lt
  defp c(_, y, _) when is_number(y), do: :gt
  defp c({:atom, x}, {:atom, y}, _), do: cmp(x, y)
  defp c([], [], _), do: :eq
  defp c([], {:atom, y}, _), do: cmp("[]", y)
  defp c({:atom, x}, [], _), do: cmp(x, "[]")
  defp c({:atom, _}, _, _), do: :lt
  defp c([], _, _), do: :lt
  defp c(_, {:atom, _}, _), do: :gt
  defp c(_, [], _), do: :gt

  # zusammengesetzt: Stelligkeit, Name, Argumente; Listen sind '.'/2.
  # Markierungen ({:gstruct, ...}, {:glist, ...}) direkt, ohne unmark_top
  defp c({:glist, l}, y, subst), do: c(l, y, subst)
  defp c(x, {:glist, l}, subst), do: c(x, l, subst)

  defp c([x | xs], [y | ys], subst) do
    case compare(x, y, subst) do
      :eq -> compare(xs, ys, subst)
      other -> other
    end
  end

  defp c({tx, f, xs}, {ty, g, ys}, subst) when tx in @st and ty in @st,
    do: c_struct(f, xs, g, ys, subst)

  defp c({tx, f, xs}, [y | ys], subst) when tx in @st, do: c_struct(f, xs, ".", [y, ys], subst)
  defp c([x | xs], {ty, g, ys}, subst) when ty in @st, do: c_struct(".", [x, xs], g, ys, subst)

  defp c_struct(f, xs, g, ys, subst) do
    case cmp(length(xs), length(ys)) do
      :eq ->
        case cmp(f, g) do
          :eq -> c_args(xs, ys, subst)
          other -> other
        end

      other ->
        other
    end
  end

  # letztes Argument per Tail Call
  defp c_args([x], [y], subst), do: compare(x, y, subst)

  defp c_args([x | xs], [y | ys], subst) do
    case compare(x, y, subst) do
      :eq -> c_args(xs, ys, subst)
      other -> other
    end
  end

  defp var_cmp(x, y) when is_integer(x) and is_integer(y), do: cmp(x, y)
  defp var_cmp(x, y), do: cmp(var_key(x), var_key(y))

  @doc """
  `==/2`: gleich in der Standardordnung, ohne die Ordnung zu bestimmen.
  Oben einmal `===` (in C; geteilte Terme in O(1)); sonst strukturell mit
  billigen Blättern, die letzte Stelle (Listenrest) per Tail Call. Innen
  kein `===` mehr: auf jeder Ebene wiederholt, wäre es bei spät
  verschiedenen Termen quadratisch. Was sich nicht billig entscheiden lässt
  – Floats (`-0.0`), `'.'/2` gegen Liste, verschiedene Klassen oder
  Funktoren – entscheidet `compare/3`.
  """
  def equal?(a, b, subst) do
    a = walk(a, subst)
    b = walk(b, subst)
    a === b or eq(PrologEx.unmark_top(a), PrologEx.unmark_top(b), subst)
  end

  defp same(a, b, subst),
    do: eq(PrologEx.unmark_top(walk(a, subst)), PrologEx.unmark_top(walk(b, subst)), subst)

  defp eq({:struct, f, xs}, {:struct, f, ys}, subst), do: eq_args(xs, ys, subst)
  defp eq([x | xs], [y | ys], subst), do: same(x, y, subst) and same(xs, ys, subst)
  defp eq({:var, v}, {:var, w}, _), do: v === w
  defp eq({:var, _}, _, _), do: false
  defp eq(_, {:var, _}, _), do: false
  defp eq({:atom, x}, {:atom, y}, _), do: x === y
  defp eq(x, y, _) when is_integer(x) and is_integer(y), do: x === y
  defp eq([], [], _), do: true
  defp eq(x, y, subst), do: compare(x, y, subst) == :eq

  defp eq_args([x], [y], subst), do: same(x, y, subst)
  defp eq_args([x | xs], [y | ys], subst), do: same(x, y, subst) and eq_args(xs, ys, subst)
  defp eq_args(_, _, _), do: false

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
  #   * nur Zahlen (gemischt) -> alle Floats vor allen Integern, sonst Wert
  #   * nur Atome {:atom, _}  -> nativ sortieren (Namen bytewise)
  #
  # Sonst bekommt jedes Element EINMAL einen Sortierschlüssel (key/2): ein
  # Elixir-Term, dessen eingebaute Ordnung der Standardordnung entspricht.
  # Danach sortiert die BEAM ohne Rückruf in Elixir-Code. Jeder Termknoten
  # ist ein 4-Tupel – alle Schlüssel haben dieselbe Größe (die BEAM
  # vergleicht Tupel zuerst nach Größe):
  #
  #   Variable  -> {0, kennung, 0, 0}
  #   Zahl      -> {1, 0 | 1, wert, 0}         Float (0) vor Integer (1)
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

  # ISO: Float vor Integer, sonst nach Wert
  defp number_le(x, y) when is_float(x) and is_integer(y), do: true
  defp number_le(x, y) when is_integer(x) and is_float(y), do: false
  defp number_le(x, y), do: x <= y

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
        {1, 0, x, 0}

      x when is_integer(x) ->
        {1, 1, x, 0}

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
  # ISO: Float vor Integer, unabhängig vom Wert
  defp same_class(1, x, y, _) when is_float(x) and is_integer(y), do: :lt
  defp same_class(1, x, y, _) when is_integer(x) and is_float(y), do: :gt
  defp same_class(1, x, y, _) when x < y, do: :lt
  defp same_class(1, x, y, _) when x > y, do: :gt
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
