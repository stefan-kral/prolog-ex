defmodule PrologEx.Builtins.Atoms do
  @moduledoc """
  Zahlen und Zeichen: `number_chars/2`, `number_codes/2` (ISO).

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
