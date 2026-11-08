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

  import PrologEx, only: [uncons: 1, is_marked: 1]
  import PrologEx.Store, only: [walk: 2]

  @doc """
  `:lt`, `:eq` oder `:gt`, direkt auf dem Paar: Klassen, Zahlen, Atome und
  Funktoren in Klauseln statt über Klassennummern; Listen ohne Umweg über
  `'.'/2`, Markierungen ohne `unmark_top`. Kein `===` vorweg: bei den
  üblichen ungleichen kleinen Termen kostete es rund 20 %, innen
  wiederholt wäre es quadratisch, und auf zwei verschiedenen DAGs läuft
  es (in C) Pfad für Pfad. Physisch derselbe Teilterm ist sofort `:eq`
  (`PrologEx.Share.same?/2`); Paare geteilter Teilterme werden nur einmal
  verglichen (Memo nach den ersten Strukturen).
  """
  def compare(a, b, subst) do
    {r, _memo} = c(walk(a, subst), walk(b, subst), subst, %{}, 0)
    r
  catch
    # ein Zyklus (siehe cm/5): zyklenfest von vorn
    :"$cyclic" -> PrologEx.Cyclic.compare(a, b, subst)
  end

  # mit Memo (PrologEx.Share): geteilte Teilterme-Paare (zwei DAGs) nur
  # einmal vergleichen; physisch derselbe Teilterm ist sofort :eq.
  # d: an wie vielen Stellen des Pfads eine Seite über eine Bindung lief;
  # mehr als doppelt so oft, wie es Bindungen gibt, heißt Zyklus
  defp cm(a0, b0, subst, m, d) do
    a = walk(a0, subst)
    b = walk(b0, subst)
    c(a, b, subst, m, cyc_step(a, a0, b, b0, d, subst))
  end

  @st [:struct, :gstruct]

  # Zähler der Bindungen auf dem Pfad (siehe PrologEx.Cyclic): +1, wenn eine
  # Seite über eine Bindung lief; mehr als 2 × Einträge: Zyklus
  @compile {:inline, cyc_step: 6}
  defp cyc_step(a, a0, b, b0, d, subst) do
    if a === a0 and b === b0 do
      d
    else
      d = d + 1
      if d > 2 * map_size(subst), do: throw(:"$cyclic"), else: d
    end
  end

  # Variable < Zahl < Atom < zusammengesetzt
  defp c({:var, x}, {:var, y}, _, m, _d), do: {var_cmp(x, y), m}
  defp c({:var, _}, _, _, m, _d), do: {:lt, m}
  defp c(_, {:var, _}, _, m, _d), do: {:gt, m}
  defp c(x, y, _, m, _d) when is_integer(x) and is_integer(y), do: {cmp(x, y), m}
  defp c(x, y, _, m, _d) when is_float(x) and is_float(y), do: {cmp(x, y), m}
  # ISO: Float vor Integer, unabhängig vom Wert
  defp c(x, y, _, m, _d) when is_float(x) and is_integer(y), do: {:lt, m}
  defp c(x, y, _, m, _d) when is_integer(x) and is_float(y), do: {:gt, m}
  defp c(x, _, _, m, _d) when is_number(x), do: {:lt, m}
  defp c(_, y, _, m, _d) when is_number(y), do: {:gt, m}
  defp c({:atom, x}, {:atom, y}, _, m, _d), do: {cmp(x, y), m}
  defp c([], [], _, m, _d), do: {:eq, m}
  defp c([], {:atom, y}, _, m, _d), do: {cmp("[]", y), m}
  defp c({:atom, x}, [], _, m, _d), do: {cmp(x, "[]"), m}
  defp c({:atom, _}, _, _, m, _d), do: {:lt, m}
  defp c([], _, _, m, _d), do: {:lt, m}
  defp c(_, {:atom, _}, _, m, _d), do: {:gt, m}
  defp c(_, [], _, m, _d), do: {:gt, m}

  # zusammengesetzt: Stelligkeit, Name, Argumente; Listen sind '.'/2.
  # Markierungen ({:gstruct, ...}, {:glist, ...}) direkt, ohne unmark_top
  defp c(x, y, subst, m, d) do
    cond do
      PrologEx.Share.same?(x, y) ->
        {:eq, m}

      true ->
        case PrologEx.Share.get2(m, x, y) do
          {:ok, r} ->
            {r, m}

          :error ->
            {r, m} = c_compound(x, y, subst, m, d)
            {r, PrologEx.Share.put2(m, x, y, r)}
        end
    end
  end

  defp c_compound({:glist, l}, y, subst, m, d), do: c(l, y, subst, m, d)
  defp c_compound(x, {:glist, l}, subst, m, d), do: c(x, l, subst, m, d)

  defp c_compound([x | xs], [y | ys], subst, m, d) do
    case cm(x, y, subst, m, d) do
      {:eq, m} -> cm(xs, ys, subst, m, d)
      other -> other
    end
  end

  defp c_compound({tx, f, xs}, {ty, g, ys}, subst, m, d) when tx in @st and ty in @st,
    do: c_struct(f, xs, g, ys, subst, m, d)

  defp c_compound({tx, f, xs}, [y | ys], subst, m, d) when tx in @st,
    do: c_struct(f, xs, ".", [y, ys], subst, m, d)

  defp c_compound([x | xs], {ty, g, ys}, subst, m, d) when ty in @st,
    do: c_struct(".", [x, xs], g, ys, subst, m, d)

  defp c_struct(f, xs, g, ys, subst, m, d) do
    case cmp(length(xs), length(ys)) do
      :eq ->
        case cmp(f, g) do
          :eq -> c_args(xs, ys, subst, m, d)
          other -> {other, m}
        end

      other ->
        {other, m}
    end
  end

  # letztes Argument per Tail Call
  defp c_args([x], [y], subst, m, d), do: cm(x, y, subst, m, d)

  defp c_args([x | xs], [y | ys], subst, m, d) do
    case cm(x, y, subst, m, d) do
      {:eq, m} -> c_args(xs, ys, subst, m, d)
      other -> other
    end
  end

  defp var_cmp(x, y) when is_integer(x) and is_integer(y), do: cmp(x, y)
  defp var_cmp(x, y), do: cmp(var_key(x), var_key(y))

  @doc """
  `==/2`: gleich in der Standardordnung, ohne die Ordnung zu bestimmen.
  Atomare Terme entscheidet `===`; bei zusammengesetzten ist physisch
  derselbe Teilterm sofort gleich (`PrologEx.Share.same?/2`, O(1)) –
  `===` selbst liefe auf zwei verschiedenen DAGs Pfad für Pfad. Sonst
  strukturell mit billigen Blättern und Memo für Paare geteilter
  Teilterme. Was sich nicht billig entscheiden lässt – Floats (`-0.0`),
  `'.'/2` gegen Liste, verschiedene Klassen oder Funktoren – entscheidet
  `compare/3`.
  """
  def equal?(a, b, subst) do
    a = walk(a, subst)
    b = walk(b, subst)

    cond do
      # atomar: === (strikt: 1 und 1.0 sind verschieden), sonst wie
      # compare/3 (-0.0 und 0.0 sind gleich)
      not is_tuple(a) and not is_list(a) -> a === b or elem(eq(a, b, subst, %{}, 0), 0)
      PrologEx.Share.same?(a, b) -> true
      true -> a |> eq(b, subst, %{}, 0) |> elem(0)
    end
  catch
    # ein Zyklus (d in same/5): zyklenfest von vorn
    :"$cyclic" -> PrologEx.Cyclic.compare(a, b, subst) == :eq
  end

  # Markierungen nicht aufheben (unmark_top baute jedes Mal ein neues Tupel,
  # und das Memo erkennt Teilterme an ihrer Identität): eq/4 nimmt
  # {:struct, ...} und {:gstruct, ...} gleich, {:glist, l} wie l
  defp same(a0, b0, subst, m, d) do
    a = walk(a0, subst)
    b = walk(b0, subst)
    d = cyc_step(a, a0, b, b0, d, subst)

    if (is_tuple(a) or is_list(a)) and PrologEx.Share.same?(a, b),
      do: {true, m},
      else: eq(a, b, subst, m, d)
  end

  # der Rest einer Liste (siehe eq/4 für Listen)
  defp same_tail(a0, b0, subst, m, d) do
    a = walk(a0, subst)
    b = walk(b0, subst)
    d = cyc_step(a, a0, b, b0, d, subst)

    if (is_tuple(a) or is_list(a)) and PrologEx.Share.same?(a, b),
      do: {true, m},
      else: eq_tail(a, b, subst, m, d)
  end

  defp eq_tail({:glist, l}, b, subst, m, d), do: eq_tail(l, b, subst, m, d)
  defp eq_tail(a, {:glist, l}, subst, m, d), do: eq_tail(a, l, subst, m, d)

  defp eq_tail([x | xs] = a, [y | ys] = b, subst, m, d) do
    if flat_head?(x) do
      case same(x, y, subst, m, d) do
        {true, m} -> same_tail(xs, ys, subst, m, d)
        other -> other
      end
    else
      eq(a, b, subst, m, d)
    end
  end

  defp eq_tail(a, b, subst, m, d), do: eq(a, b, subst, m, d)

  # zusammengesetzte Paare mit Memo (PrologEx.Share); Blätter billig
  defp eq({:glist, l}, b, subst, m, d), do: eq(l, b, subst, m, d)
  defp eq(a, {:glist, l}, subst, m, d), do: eq(a, l, subst, m, d)

  defp eq({ta, f, xs} = a, {tb, f, ys} = b, subst, m, d) when ta in @st and tb in @st,
    do: eq_memo(a, b, m, fn m -> eq_args(xs, ys, subst, m, d) end)

  # Listen: die erste Zelle mit Memo (sie kann über ein Argument, einen
  # Kopf oder eine Variable von mehreren Stellen her erreicht werden – f(L, L)
  # mit L als Variable kommt selbst nicht ins Memo, PrologEx.Share), die
  # Folgezellen über den Rest ohne, solange ihr Kopf flach ist: Eine solche
  # Zelle verzweigt nicht, jede Verzweigung darüber ist gemerkt, der
  # Mehraufwand also höchstens polynomiell. Lange Listen aus Zahlen oder
  # L..U (clpz-Domänen) zahlen so einen Memo-Eintrag statt einen je Zelle.
  defp eq([x | xs] = a, [y | ys] = b, subst, m, d) do
    eq_memo(a, b, m, fn m ->
      case same(x, y, subst, m, d) do
        {true, m} -> same_tail(xs, ys, subst, m, d)
        other -> other
      end
    end)
  end

  defp eq({:var, v}, {:var, w}, _, m, _d), do: {v === w, m}
  defp eq({:var, _}, _, _, m, _d), do: {false, m}
  defp eq(_, {:var, _}, _, m, _d), do: {false, m}
  defp eq({:atom, x}, {:atom, y}, _, m, _d), do: {x === y, m}
  defp eq(x, y, _, m, _d) when is_integer(x) and is_integer(y), do: {x === y, m}
  defp eq([], [], _, m, _d), do: {true, m}
  defp eq(x, y, subst, m, _d), do: {compare(x, y, subst) == :eq, m}

  # flach: atomar oder eine Struktur mit lauter atomaren Argumenten
  # (Variablen zählen nicht als atomar – gebunden könnten sie verzweigen)
  defp flat_head?(x) when is_number(x), do: true
  defp flat_head?({:atom, _}), do: true
  defp flat_head?([]), do: true
  defp flat_head?({tag, _, args}) when tag in [:struct, :gstruct], do: atomic_args?(args)
  defp flat_head?(_), do: false

  defp atomic_args?([]), do: true
  defp atomic_args?([x | xs]) when is_number(x), do: atomic_args?(xs)
  defp atomic_args?([{:atom, _} | xs]), do: atomic_args?(xs)
  defp atomic_args?([[] | xs]), do: atomic_args?(xs)
  defp atomic_args?(_), do: false

  defp eq_memo(a, b, m, f) do
    case PrologEx.Share.get2(m, a, b) do
      {:ok, r} ->
        {r, m}

      :error ->
        {r, m} = f.(m)
        {r, PrologEx.Share.put2(m, a, b, r)}
    end
  end

  defp eq_args([x], [y], subst, m, d), do: same(x, y, subst, m, d)

  defp eq_args([x | xs], [y | ys], subst, m, d) do
    case same(x, y, subst, m, d) do
      {true, m} -> eq_args(xs, ys, subst, m, d)
      other -> other
    end
  end

  defp eq_args(_, _, _, m, _d), do: {false, m}

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

    case kind(Enum.map(walked, &elem(&1, 0)), :none) do
      # Schlüssel direkt vergleichbar (List.keysort ist stabil)
      k when k in [:integers, :atoms] ->
        walked |> List.keysort(0) |> Enum.map(&elem(&1, 1))

      _ ->
        try do
          walked
          |> Enum.map(fn {k, item} -> {sort_key(k, subst), item} end)
          |> List.keysort(0)
          |> Enum.map(&elem(&1, 1))
        catch
          # geteilte Teilterme: über compare/3 (stabil), siehe do_sort/3
          :shared ->
            walked
            |> Enum.sort(fn {a, _}, {b, _} -> compare(a, b, subst) != :gt end)
            |> Enum.map(&elem(&1, 1))
        end
    end
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
        keyed =
          try do
            Enum.map(values, &{sort_key(&1, subst), &1})
          catch
            :shared -> :shared
          end

        if keyed == :shared do
          # Die Schlüssel geteilter Teilterme wären selbst DAGs, und der
          # native Vergleich zweier verschiedener DAGs läuft Pfad für Pfad –
          # dann über compare/3 mit Memo (Enum.sort ist stabil)
          sorted = Enum.sort(values, fn a, b -> compare(a, b, subst) != :gt end)
          if unique, do: dedup_compare(sorted, subst), else: sorted
        else
          sorted = List.keysort(keyed, 0)
          sorted = if unique, do: dedup_keyed(sorted), else: sorted
          Enum.map(sorted, &elem(&1, 1))
        end
    end
  end

  defp shared?(m), do: Map.has_key?(m, :"$shared")

  # Schlüssel eines Elements: erst wie früher ohne Memo, aber höchstens
  # @key_budget zusammengesetzte Knoten (gezählt in einem :atomics-Zähler,
  # damit der Schlüsselbau so schlank bleibt wie früher); größere Elemente
  # noch einmal mit Memo – wird dabei Teilung erkannt, throw(:shared): dann
  # sortieren die Aufrufer über compare/3
  @key_budget 256
  defp sort_key(t, subst) do
    case walk(t, subst) do
      # lauter atomare Argumente (etwa X-Y): nichts aufzublähen
      {tag, f, args} when tag in [:struct, :gstruct] ->
        if Enum.any?(args, &compound_arg?/1),
          do: budget_key(t, subst),
          else: {3, length(args), f, args |> Enum.map(&key_leaf_or(&1, subst)) |> List.to_tuple()}

      _ ->
        budget_key(t, subst)
    end
  end

  defp compound_arg?({:atom, _}), do: false
  defp compound_arg?({:var, _}), do: false
  defp compound_arg?(t) when is_tuple(t), do: true
  defp compound_arg?([_ | _]), do: true
  defp compound_arg?(_), do: false

  # ein atomares Argument (eine gebundene Variable kann noch auf eine
  # Struktur zeigen: dann der volle Schlüssel)
  defp key_leaf_or(a, subst) do
    case walk(a, subst) do
      {tag, _, _} when tag in [:struct, :gstruct] -> sort_key_full(a, subst)
      [_ | _] -> sort_key_full(a, subst)
      {:glist, _} -> sort_key_full(a, subst)
      other -> key_leaf(other)
    end
  end

  # (ein Zyklus: über compare/3 sortieren, siehe budget_key/2)
  defp sort_key_full(t, subst) do
    t |> key(subst, %{}, 0) |> elem(0)
  catch
    :"$cyclic" -> throw(:shared)
  end

  defp budget_key(t, subst) do
    ref = :atomics.new(1, signed: true)
    :atomics.put(ref, 1, @key_budget)
    key_b(t, subst, ref)
  catch
    :big ->
      # (ein Zyklus: dann sortieren die Aufrufer über compare/3, das ihn
      # verträgt – wie bei geteilten Teiltermen)
      {k, m} =
        try do
          key(t, subst, %{}, 0)
        catch
          :"$cyclic" -> throw(:shared)
        end

      if shared?(m), do: throw(:shared), else: k
  end

  defp key_b(t, subst, ref) do
    case walk(t, subst) do
      {tag, f, args} when tag in [:struct, :gstruct] ->
        if :atomics.sub_get(ref, 1, 1) < 0, do: throw(:big)
        {3, length(args), f, args |> Enum.map(&key_b(&1, subst, ref)) |> List.to_tuple()}

      l when is_list(l) and l != [] ->
        key_b_list(l, subst, ref)

      {:glist, _} = l ->
        key_b_list(l, subst, ref)

      other ->
        key_leaf(other)
    end
  end

  defp key_b_list(l, subst, ref) do
    if :atomics.sub_get(ref, 1, 1) < 0, do: throw(:big)
    {:cons, h, t} = uncons(l)
    {3, 2, ".", {key_b(h, subst, ref), key_b(t, subst, ref)}}
  end

  defp dedup_compare([x, y | rest], subst) do
    if compare(x, y, subst) == :eq,
      do: dedup_compare([x | rest], subst),
      else: [x | dedup_compare([y | rest], subst)]
  end

  defp dedup_compare(l, _subst), do: l

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
    t |> key(subst, %{}, 0) |> elem(0)
  catch
    # ein Schlüssel kann keinen Zyklus darstellen
    :"$cyclic" -> PrologEx.Cyclic.error!()
  end

  # mit Memo (PrologEx.Share): ein geteilter Teilterm bekommt seinen
  # Schlüssel nur einmal; ein Treffer setzt :"$shared" (dann sortiert
  # do_sort/3 über compare/3)
  defp key(t0, subst, m, d) do
    t = walk(t0, subst)
    d = cyc_step(t, t0, nil, nil, d, subst)

    case t do
      {tag, f, args} = st when tag in [:struct, :gstruct] ->
        case PrologEx.Share.get(m, st) do
          {:ok, k} ->
            {k, Map.put(m, :"$shared", true)}

          :error ->
            {ks, m} = Enum.map_reduce(args, m, &key(&1, subst, &2, d))
            k = {3, length(args), f, List.to_tuple(ks)}
            {k, PrologEx.Share.put(m, st, k)}
        end

      [h | _] = l when is_tuple(h) or is_list(h) ->
        case PrologEx.Share.get(m, l) do
          {:ok, k} ->
            {k, Map.put(m, :"$shared", true)}

          :error ->
            {:cons, h, t} = uncons(l)
            {kh, m} = key(h, subst, m, d)
            {kt, m} = key(t, subst, m, d)
            k = {3, 2, ".", {kh, kt}}
            {k, PrologEx.Share.put(m, l, k)}
        end

      l when is_list(l) and l != [] ->
        list_key(l, subst, m, d)

      {:glist, _} = l ->
        list_key(l, subst, m, d)

      other ->
        {key_leaf(other), m}
    end
  end

  defp list_key(l, subst, m, d) do
    {:cons, h, t} = uncons(l)
    {kh, m} = key(h, subst, m, d)
    {kt, m} = key(t, subst, m, d)
    {{3, 2, ".", {kh, kt}}, m}
  end

  defp key_leaf(t) do
    case t do
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
    end
  end

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

  # Kennungen sind Zahlen (PrologEx.Vars), auch in {name, n} und {:attv, n};
  # eine Binary ist ein von Hand gebauter Name (Tests)
  defp var_key(n) when is_integer(n), do: {0, n}
  defp var_key({_, n}) when is_integer(n), do: {0, n}
  defp var_key(n) when is_binary(n), do: {1, n}
  defp var_key(n), do: {2, n}

  defp cmp(x, y) when x < y, do: :lt
  defp cmp(x, y) when x > y, do: :gt
  defp cmp(_, _), do: :eq
end
