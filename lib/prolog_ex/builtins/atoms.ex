defmodule PrologEx.Builtins.Atoms do
  @moduledoc """
  Atome, Zahlen und Zeichen (ISO 8.16): `atom_length/2`, `atom_concat/3`,
  `sub_atom/5`, `atom_chars/2`, `atom_codes/2`, `char_code/2`,
  `number_chars/2`, `number_codes/2`, dazu `atom_number/2` (SWI).

  Wie ISO (und SICStus) streng getypt: wo ein Atom verlangt ist, ergibt
  eine Zahl `type_error(atom, …)` (SWI wäre großzügiger). `[]` zählt als
  Atom `'[]'`. Längen und Positionen zählen Zeichen (Unicode-Codepoints),
  nicht Bytes.

  `atom_chars(A, L)` / `atom_codes(A, L)`: Ist L eine vollständige Liste,
  wird daraus das Atom gebaut und mit A unifiziert; sonst muss A ein Atom
  sein. Die Elemente von L werden immer geprüft (type_error(character, …)
  bzw. representation_error), wie bei number_chars nach Cor.2.

  `atom_concat/3` und `sub_atom/5` zählen nichtdeterministisch auf, in der
  ISO-Reihenfolge (B aufsteigend, dann L aufsteigend); die letzte Lösung
  hinterlässt keinen Choice Point. Ist `Sub` bei sub_atom/5 gebunden, wird
  direkt nach Vorkommen gesucht (überlappend).

  `atom_number(A, N)`: A ein Atom → als Zahl lesen, scheitert, wenn es
  keine ist; A ungebunden → N muss eine Zahl sein.

  ## number_chars, number_codes

  `number_chars(N, L)`:

    * Ist L eine vollständige Liste von Zeichen, wird sie als Zahl gelesen
      (Syntax wie im Quelltext) und mit N unifiziert – auch wenn N schon
      gebunden ist (`number_chars(1, ['0', '1'])` gelingt). Vor der Zahl
      darf Leerraum stehen, auch Kommentare; danach nichts mehr.
    * Sonst muss N eine Zahl sein; ihre Zeichen werden mit L unifiziert
      (L darf eine teilweise Liste sein).

  Gelesen werden: Ganzzahlen (beliebig groß, auch mit Zifferngruppen
  `1_000`), `0'c` (Zeichencode, mit Escapes; `0'''` für das Hochkomma),
  `0x..`, `0o..`, `0b..`, Floats mit Nachkommastellen und optionalem
  Exponenten (`1.5e10`, `1.0E-3`; ohne Nachkommastellen wie ISO kein
  Float), davor optional ein `-`, danach Leerzeichen erlaubt, aber keine
  Kommentare (wie ISO, Cor.2).

  Fehler wie ISO: instantiation_error, type_error(number|list|character),
  representation_error(character_code), syntax_error(illegal_number).
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.Lists
  alias PrologEx.Error

  # ---------------------------------------------------------------------
  # atom_length, atom_chars, atom_codes, char_code, atom_number
  # ---------------------------------------------------------------------

  defbuiltin "atom_length", [x, len] do
    name = atom_name!(deref(x), :required)

    case deref(len) do
      {:var, _} -> :ok
      n when is_integer(n) and n >= 0 -> :ok
      n when is_integer(n) -> Error.domain!("not_less_than_zero", n)
      other -> Error.type!("integer", other)
    end

    {:unify, [{len, cp_length(name)}]}
  end

  defbuiltin "atom_chars", [x, l] do
    atom_text(x, l, subst(), :chars)
  end

  defbuiltin "atom_codes", [x, l] do
    atom_text(x, l, subst(), :codes)
  end

  defbuiltin "char_code", [c, code] do
    case deref(c) do
      {:var, _} ->
        case deref(code) do
          {:var, _} ->
            Error.instantiation!()

          n when is_integer(n) ->
            check_elem(n, :codes)
            {:unify, [{c, a(<<n::utf8>>)}]}

          other ->
            Error.type!("integer", other)
        end

      cc ->
        check_elem(cc, :chars)

        case deref(code) do
          {:var, _} -> :ok
          n when is_integer(n) -> check_elem(n, :codes)
          other -> Error.type!("integer", other)
        end

        <<n::utf8>> = atom_name!(cc, :required)
        {:unify, [{code, n}]}
    end
  end

  defbuiltin "atom_number", [x, n] do
    case deref(x) do
      {:var, _} ->
        case deref(n) do
          {:var, _} -> Error.instantiation!()
          num when is_number(num) -> {:unify, [{x, a(number_string(num))}]}
          other -> Error.type!("number", other)
        end

      xx ->
        case parse_number(atom_name!(xx, :required)) do
          {:ok, num} -> {:unify, [{n, num}]}
          :error -> :fail
        end
    end
  end

  defp atom_text(x, l, s, kind) do
    name = atom_name!(PrologEx.walk(x, s), :optional)

    case text(l, s, kind) do
      {:ok, str} -> {:unify, [{x, a(str)}]}
      :partial when name != nil -> {:unify, [{l, encode(name, kind)}]}
      :partial -> Error.instantiation!()
    end
  end

  # Name eines Atoms; :optional: Variable ergibt nil, :required: Fehler
  defp atom_name!([], _), do: "[]"
  defp atom_name!({:atom, name}, _), do: name
  defp atom_name!({:var, _}, :optional), do: nil
  defp atom_name!({:var, _}, :required), do: Error.instantiation!()
  defp atom_name!(other, _), do: Error.type!("atom", other)

  # Atom-Argument, das ungebunden sein darf (atom_concat, sub_atom)
  defp opt_atom!(t), do: atom_name!(t, :optional)

  defp cp_length(name) do
    if ascii?(name), do: byte_size(name), else: length(String.to_charlist(name))
  end

  defp ascii?(name), do: not String.match?(name, ~r/[^\x00-\x7f]/)

  # ---------------------------------------------------------------------
  # atom_concat/3
  # ---------------------------------------------------------------------

  defbuiltin "atom_concat", [x, y, z], nondet: true do
    a1 = opt_atom!(deref(x))
    a2 = opt_atom!(deref(y))
    a3 = opt_atom!(deref(z))

    cond do
      a1 != nil and a2 != nil ->
        [{:unify, [{z, a(a1 <> a2)}]}]

      a3 == nil ->
        Error.instantiation!()

      a1 != nil ->
        if String.starts_with?(a3, a1),
          do: [{:unify, [{y, a(binary_part(a3, byte_size(a1), byte_size(a3) - byte_size(a1)))}]}],
          else: []

      a2 != nil ->
        if String.ends_with?(a3, a2),
          do: [{:unify, [{x, a(binary_part(a3, 0, byte_size(a3) - byte_size(a2)))}]}],
          else: []

      true ->
        splits(a3, 0, x, y)
    end
  end

  # alle Zerlegungen an Zeichengrenzen, ab Byte-Position i
  defp splits(name, i, x, y) do
    r =
      {:unify,
       [{x, a(binary_part(name, 0, i))}, {y, a(binary_part(name, i, byte_size(name) - i))}]}

    case binary_part(name, i, byte_size(name) - i) do
      "" -> [r]
      <<c::utf8, _::binary>> -> [r | fn -> splits(name, i + byte_size(<<c::utf8>>), x, y) end]
    end
  end

  # ---------------------------------------------------------------------
  # sub_atom/5
  # ---------------------------------------------------------------------

  defbuiltin "sub_atom", [x, b, l, af, sub], nondet: true do
    name = atom_name!(deref(x), :required)
    bb = opt_int!(deref(b))
    ll = opt_int!(deref(l))
    aa = opt_int!(deref(af))
    sa = opt_atom!(deref(sub))

    at = text_index(name)
    n = at.len
    out = {b, l, af, sub}

    cond do
      # negative Werte: keine Lösung (ISO 8.16.3.3 sieht keinen Fehler vor;
      # SICStus wirft domain_error(not_less_than_zero, _))
      Enum.any?([bb, ll, aa], &(&1 != nil and &1 < 0)) ->
        []

      sa == "" and ll not in [nil, 0] ->
        []

      sa == "" ->
        # leeres Sub: an jeder Position (wie Sub ungebunden mit L = 0)
        lookahead(
          fn st -> enum_next(n, bb, 0, aa, st) end,
          enum_first(n, bb, 0, aa),
          &emit_sub(at, &1, out)
        )

      sa != nil ->
        m = cp_length(sa)

        cond do
          m > n -> []
          ll != nil and ll != m -> []
          bb != nil -> check_at(at, bb, m, aa, sa, out)
          aa != nil -> check_at(at, n - m - aa, m, aa, sa, out)
          true -> occurrences(at, sa, out)
        end

      true ->
        first = enum_first(n, bb, ll, aa)
        lookahead(fn st -> enum_next(n, bb, ll, aa, st) end, first, &emit_sub(at, &1, out))
    end
  end

  defp opt_int!({:var, _}), do: nil
  defp opt_int!(n) when is_integer(n), do: n
  defp opt_int!(other), do: Error.type!("integer", other)

  # Zugriff auf Zeichenpositionen: bei ASCII Byte = Zeichen, sonst ein
  # Tupel der Byte-Offsets (Index i -> Byte-Offset von Zeichen i, plus Ende)
  defp text_index(name) do
    if ascii?(name) do
      %{name: name, len: byte_size(name), offs: nil}
    else
      offs = offsets(name, 0, [0]) |> Enum.reverse() |> List.to_tuple()
      %{name: name, len: tuple_size(offs) - 1, offs: offs}
    end
  end

  defp offsets(<<c::utf8, rest::binary>>, pos, acc) do
    pos = pos + byte_size(<<c::utf8>>)
    offsets(rest, pos, [pos | acc])
  end

  defp offsets(<<>>, _pos, acc), do: acc

  defp off(%{offs: nil}, i), do: i
  defp off(%{offs: o}, i), do: elem(o, i)

  defp slice(at, b, l) do
    from = off(at, b)
    binary_part(at.name, from, off(at, b + l) - from)
  end

  # Byte-Offset -> Zeichenindex (nur für Offsets an Zeichengrenzen)
  defp index_of(%{offs: nil}, byte), do: byte
  defp index_of(%{offs: o}, byte), do: bsearch(o, byte, 0, tuple_size(o) - 1)

  defp bsearch(o, byte, lo, hi) do
    mid = div(lo + hi, 2)

    case elem(o, mid) do
      ^byte -> mid
      v when v < byte -> bsearch(o, byte, mid + 1, hi)
      _ -> bsearch(o, byte, lo, mid - 1)
    end
  end

  defp emit_sub(at, {bi, li}, {b, l, af, sub}),
    do: {:unify, [{b, bi}, {l, li}, {af, at.len - bi - li}, {sub, a(slice(at, bi, li))}]}

  defp check_at(at, bi, m, aa, sa, out) do
    if bi >= 0 and bi + m <= at.len and (aa == nil or at.len - bi - m == aa) and
         slice(at, bi, m) == sa,
       do: [emit_sub(at, {bi, m}, out)],
       else: []
  end

  # alle (auch überlappenden) Vorkommen von sa, über :binary.match
  defp occurrences(at, sa, out) do
    m = cp_length(sa)
    first = next_occurrence(at, sa, 0)
    lookahead(&next_occurrence(at, sa, &1), first, fn {bi, _} -> emit_sub(at, {bi, m}, out) end)
  end

  # nächstes Vorkommen ab Byte-Position pos: {{b, nächste_pos}, zustand}
  defp next_occurrence(at, sa, pos) do
    size = byte_size(at.name)

    if pos > size do
      nil
    else
      case :binary.match(at.name, sa, scope: {pos, size - pos}) do
        :nomatch -> nil
        {p, _} -> next_after(at, p)
      end
    end
  end

  defp next_after(at, p) do
    bi = index_of(at, p)
    # überlappend: weiter ab dem nächsten Zeichen
    step = off(at, bi + 1) - p
    {{bi, p + step}, p + step}
  end

  # sub_atom ohne Sub: Paare {B, L}, B aufsteigend, dann L aufsteigend
  defp enum_first(n, bb, ll, aa) do
    b0 =
      cond do
        bb != nil -> bb
        ll != nil and aa != nil -> n - ll - aa
        true -> 0
      end

    valid_from(n, bb, ll, aa, b0, l_min(n, ll, aa, b0))
  end

  defp enum_next(n, bb, ll, aa, {b, l}), do: valid_from(n, bb, ll, aa, b, l + 1)

  defp l_min(n, ll, aa, b) do
    cond do
      ll != nil -> ll
      aa != nil -> n - b - aa
      true -> 0
    end
  end

  # erstes gültiges Paar ab (b, l): {{b, l}, {b, l}} oder nil
  defp valid_from(n, bb, ll, aa, b, l) do
    cond do
      b > n or (bb != nil and b != bb) or b < 0 ->
        nil

      l < 0 or b + l > n or (ll != nil and l != ll) or (aa != nil and n - b - l != aa) ->
        # nächstes B (wenn B frei ist)
        if bb != nil or (ll != nil and aa != nil),
          do: nil,
          else: valid_from(n, bb, ll, aa, b + 1, l_min(n, ll, aa, b + 1))

      true ->
        {{b, l}, {b, l}}
    end
  end

  # Lazy Lösungsliste mit einer Lösung Vorlauf: die letzte ohne Choice Point.
  # next.(zustand) -> {lösung, zustand} | nil
  defp lookahead(_next, nil, _emit), do: []

  defp lookahead(next, {sol, st}, emit) do
    case next.(st) do
      nil -> [emit.(sol)]
      more -> [emit.(sol) | fn -> lookahead(next, more, emit) end]
    end
  end

  # ---------------------------------------------------------------------
  # number_chars, number_codes
  # ---------------------------------------------------------------------

  defbuiltin "number_chars", [n, l] do
    number_text(n, l, subst(), :chars)
  end

  defbuiltin "number_codes", [n, l] do
    number_text(n, l, subst(), :codes)
  end

  # ---------------------------------------------------------------------

  defp number_text(n, l, s, kind) do
    nn = PrologEx.walk(n, s)

    unless match?({:var, _}, nn) or is_number(nn),
      do: Error.type!("number", PrologEx.resolve(nn, s))

    case text(l, s, kind) do
      {:ok, str} ->
        {:unify, [{n, parse_number!(str)}]}

      :partial when is_number(nn) ->
        {:unify, [{l, encode(number_string(nn), kind)}]}

      :partial ->
        Error.instantiation!()
    end
  end

  # Elemente einer vollständigen, ground Liste als String; :partial, wenn
  # die Liste offen ist oder Variablen enthält (Typfehler sofort)
  defp text(l, s, kind) do
    case Lists.skip_list(l, s) do
      {_, []} ->
        elems = Enum.map(Lists.items(l, s), &PrologEx.walk(&1, s))
        Enum.each(elems, &check_elem(&1, kind))

        if Enum.any?(elems, &match?({:var, _}, &1)),
          do: :partial,
          else: {:ok, elems |> Enum.map(&elem_char(&1, kind)) |> Enum.join()}

      {_, {:var, _}} ->
        # offene Liste: Elemente trotzdem prüfen (ISO: type_error zuerst)
        Lists.items_prefix(l, s) |> Enum.each(&check_elem(PrologEx.walk(&1, s), kind))
        :partial

      _ ->
        Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  defp check_elem({:var, _}, _), do: :ok

  defp check_elem({:atom, c} = a, :chars) do
    if String.length(c) == 1 and length(String.to_charlist(c)) == 1,
      do: :ok,
      else: Error.type!("character", a)
  end

  defp check_elem(c, :codes) when is_integer(c) do
    if c >= 0 and c <= 0x10FFFF and (c < 0xD800 or c > 0xDFFF),
      do: :ok,
      else: Error.representation!("character_code")
  end

  defp check_elem(other, :chars), do: Error.type!("character", other)
  defp check_elem(other, :codes), do: Error.type!("integer", other)

  defp elem_char({:atom, c}, :chars), do: c
  defp elem_char(c, :codes), do: <<c::utf8>>

  defp encode(str, :chars), do: str |> String.codepoints() |> Enum.map(&a/1) |> list()
  defp encode(str, :codes), do: str |> String.to_charlist() |> list()

  @doc "Textform einer Zahl (wie write/1)"
  def number_string(n) when is_integer(n), do: Integer.to_string(n)
  def number_string(f) when is_float(f), do: PrologEx.format_float(f)

  # ---------------------------------------------------------------------
  # Zahlensyntax
  # ---------------------------------------------------------------------

  @doc "Liest eine Zahl aus einem String (ganzer String, Leerraum davor erlaubt)."
  def parse_number!(str) do
    case parse_number(str) do
      {:ok, n} -> n
      :error -> Error.syntax!("illegal_number")
    end
  end

  def parse_number(str) do
    rest = skip_layout(str)

    {sign, rest} =
      case rest do
        # nach dem Minus nur Leerraumzeichen, keine Kommentare (ISO-
        # Konformitätstests 21 und 24)
        "-" <> r -> {-1, skip_blanks(r)}
        r -> {1, r}
      end

    case unsigned(rest) do
      {:ok, n, ""} -> {:ok, sign * n}
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp skip_blanks(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r, ?\f, ?\v],
    do: skip_blanks(rest)

  defp skip_blanks(s), do: s

  # Leerraum und Kommentare
  defp skip_layout(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r, ?\f, ?\v],
    do: skip_layout(rest)

  defp skip_layout("%" <> rest) do
    case String.split(rest, "\n", parts: 2) do
      [_, more] -> skip_layout(more)
      [_] -> ""
    end
  end

  defp skip_layout("/*" <> rest) do
    case String.split(rest, "*/", parts: 2) do
      [_, more] -> skip_layout(more)
      # unbeendeter Kommentar: bleibt stehen und ergibt einen Syntaxfehler
      [_] -> "/*" <> rest
    end
  end

  defp skip_layout(s), do: s

  defp unsigned("0'" <> rest) do
    case rest do
      "''" <> r -> {:ok, ?', r}
      "\\" <> r -> escape(r)
      <<c::utf8, r::binary>> when c != ?\n and c != ?' -> {:ok, c, r}
      _ -> :error
    end
  end

  defp unsigned("0x" <> rest), do: radix(rest, 16)
  defp unsigned("0o" <> rest), do: radix(rest, 8)
  defp unsigned("0b" <> rest), do: radix(rest, 2)

  defp unsigned(<<d, _::binary>> = s) when d in ?0..?9 do
    {int, rest} = digits(s)

    case rest do
      <<".", f, r::binary>> when f in ?0..?9 ->
        {frac, r} = span(<<f, r::binary>>, &(&1 in ?0..?9))

        case exponent(r) do
          {:ok, exp, r} -> {:ok, String.to_float(int <> "." <> frac <> exp), r}
          :error -> :error
        end

      _ ->
        {:ok, String.to_integer(int), rest}
    end
  end

  defp unsigned(_), do: :error

  # Ziffern mit Gruppen: "_" zwischen Ziffern
  defp digits(s) do
    {d, rest} = span(s, &(&1 in ?0..?9))

    case rest do
      <<"_", c, r::binary>> when c in ?0..?9 ->
        {more, rest} = digits(<<c, r::binary>>)
        {d <> more, rest}

      _ ->
        {d, rest}
    end
  end

  defp exponent(<<e, rest::binary>>) when e in [?e, ?E] do
    {sign, rest} =
      case rest do
        <<x, r::binary>> when x in [?+, ?-] -> {<<x>>, r}
        _ -> {"", rest}
      end

    case span(rest, &(&1 in ?0..?9)) do
      {"", _} -> :error
      {ds, r} -> {:ok, "e" <> sign <> ds, r}
    end
  end

  defp exponent(rest), do: {:ok, "", rest}

  defp radix(s, base) do
    {ds, rest} = span(s, &digit_in_base?(&1, base))
    if ds == "", do: :error, else: {:ok, String.to_integer(ds, base), rest}
  end

  defp digit_in_base?(c, 16), do: c in ?0..?9 or c in ?a..?f or c in ?A..?F
  defp digit_in_base?(c, 8), do: c in ?0..?7
  defp digit_in_base?(c, 2), do: c in ?0..?1

  # Escapes in 0'\.. wie in quotierten Atomen
  @escapes %{
    ?n => ?\n,
    ?t => ?\t,
    ?r => ?\r,
    ?a => 7,
    ?b => ?\b,
    ?f => ?\f,
    ?v => ?\v,
    ?0 => 0,
    ?\\ => ?\\,
    ?' => ?',
    ?" => ?",
    ?` => ?`,
    ?e => 27,
    ?s => ?\s
  }

  defp escape("x" <> rest) do
    case span(rest, &digit_in_base?(&1, 16)) do
      {hex, "\\" <> r} when hex != "" -> {:ok, String.to_integer(hex, 16), r}
      _ -> :error
    end
  end

  defp escape(<<d, _::binary>> = rest) when d in ?0..?7 do
    case span(rest, &(&1 in ?0..?7)) do
      {oct, "\\" <> r} -> {:ok, String.to_integer(oct, 8), r}
      _ -> :error
    end
  end

  defp escape(<<c, rest::binary>>) do
    case Map.fetch(@escapes, c) do
      {:ok, code} -> {:ok, code, rest}
      :error -> :error
    end
  end

  defp escape(_), do: :error

  defp span(s, pred), do: span(s, pred, 0)

  defp span(s, pred, n) do
    if n < byte_size(s) and pred.(:binary.at(s, n)),
      do: span(s, pred, n + 1),
      else: {binary_part(s, 0, n), binary_part(s, n, byte_size(s) - n)}
  end
end
