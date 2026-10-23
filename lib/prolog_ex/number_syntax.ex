defmodule PrologEx.NumberSyntax do
  @moduledoc """
  Zahlen-Schreibweisen, die gprolog (unser Reader) nicht kennt, vor dem
  Lesen umschreiben:

    * Zifferngruppen wie in SWI: `1_000_000`, auch `1_000_<Zeilenumbruch>000`
      (nach `_` darf Leerraum folgen). Gilt für Ganzzahlen und den
      ganzzahligen Teil von Floats.
    * Ganzzahlen über gprologs `max_integer` (2^60 - 1) werden zu
      `'$bigint'('…')` und nach dem Lesen wieder zur Zahl (`unwrap/1`);
      ein unäres Minus davor ergibt die negative Zahl.

  Quoted Atome, Strings, Backquotes, Kommentare, `0'c` und Bezeichner wie
  `x_1_000` bleiben unverändert. Beim Entfernen von Leerraum nach `_`
  werden die Zeilenumbrüche hinter der Zahl wieder eingefügt, damit die
  Zeilennummern in Fehlermeldungen stimmen.
  """

  import PrologEx, only: [mk: 2]

  @max_int 1_152_921_504_606_846_975
  @big "$bigint"

  @doc "Text umschreiben; liefert `{text, enthält_bigint?}`."
  def rewrite(text) do
    # schneller Vorab-Test: ohne "Ziffer_" und ohne ≥ 19 Ziffern am Stück
    # (max_integer hat 19) gibt es nichts zu tun
    if Regex.match?(~r/[0-9]_|[0-9]{19}/, text) do
      {out, big?} = scan(text, false, [], false)
      {IO.iodata_to_binary(out), big?}
    else
      {text, false}
    end
  end

  # prev_word?: das vorige Zeichen gehört zu einem Bezeichner oder einer
  # Zahl (dann beginnt hier kein neues Zahltoken)
  defp scan(<<>>, _pw, acc, big), do: {Enum.reverse(acc), big}

  defp scan("%" <> _ = s, _pw, acc, big) do
    {c, rest} = until_incl(s, "\n")
    scan(rest, false, [c | acc], big)
  end

  defp scan("/*" <> _ = s, _pw, acc, big) do
    {c, rest} = until_incl(s, "*/")
    scan(rest, false, [c | acc], big)
  end

  defp scan(<<q, _::binary>> = s, _pw, acc, big) when q in [?', ?", ?`] do
    {c, rest} = quoted(s)
    scan(rest, false, [c | acc], big)
  end

  # 0'c Zeichencode: das Zeichen nach 0' unverändert übernehmen
  defp scan(<<"0'", rest::binary>>, false, acc, big) do
    {c, rest} =
      case rest do
        <<"\\", ch::utf8, r::binary>> -> {<<"0'\\", ch::utf8>>, r}
        <<"''", r::binary>> -> {"0'''", r}
        <<ch::utf8, r::binary>> -> {<<"0'", ch::utf8>>, r}
        "" -> {"0'", ""}
      end

    scan(rest, true, [c | acc], big)
  end

  # 0x.. 0o.. 0b..: unverändert
  defp scan(<<"0", b, d, rest::binary>>, false, acc, big)
       when (b in [?x, ?o, ?b] and d in ?0..?9) or
              (b == ?x and d in ?a..?f) or
              (b == ?x and d in ?A..?F) do
    {w, rest} = span(<<d, rest::binary>>, &word?/1)
    scan(rest, true, [w, <<?0, b>> | acc], big)
  end

  defp scan(<<d, _::binary>> = s, false, acc, big) when d in ?0..?9 do
    {digits, nls, rest} = digits(s, [], [])

    case rest do
      # Float: Bruchteil und Exponent unverändert
      <<".", f, _::binary>> when f in ?0..?9 ->
        {frac, rest} = span(binary_part(rest, 1, byte_size(rest) - 1), &(&1 in ?0..?9))
        {exp, rest} = exponent(rest)
        scan(rest, true, [nls, exp, frac, ".", digits | acc], big)

      # Radix wie 16'FF (SWI): unverändert weiterreichen
      <<"'", c, _::binary>> when c in ?0..?9 or c in ?a..?z or c in ?A..?Z ->
        {w, rest} = span(binary_part(rest, 1, byte_size(rest) - 1), &word?/1)
        scan(rest, true, [nls, w, "'", digits | acc], big)

      _ ->
        if String.to_integer(digits) > @max_int,
          do: scan(rest, true, [nls, "'#{@big}'('#{digits}')" | acc], true),
          else: scan(rest, true, [nls, digits | acc], big)
    end
  end

  defp scan(<<c::utf8, rest::binary>>, _pw, acc, big),
    do: scan(rest, word?(c), [<<c::utf8>> | acc], big)

  # ungültiges UTF-8: Byte übernehmen
  defp scan(<<c, rest::binary>>, _pw, acc, big), do: scan(rest, false, [<<c>> | acc], big)

  # Ziffern mit Gruppen "_" (+ optional Leerraum) zwischen Ziffern;
  # liefert {ziffern, entfernte_zeilenumbrüche, rest}
  defp digits(<<d, rest::binary>>, acc, nls) when d in ?0..?9, do: digits(rest, [d | acc], nls)

  defp digits(<<"_", rest::binary>> = s, acc, nls) do
    {ws, after_ws} = span(rest, &(&1 in [?\s, ?\t, ?\n, ?\r]))

    case after_ws do
      <<d, _::binary>> when d in ?0..?9 ->
        newlines = for <<c <- ws>>, c == ?\n, do: "\n"
        digits(after_ws, acc, [newlines | nls])

      _ ->
        {acc |> Enum.reverse() |> List.to_string(), nls, s}
    end
  end

  defp digits(rest, acc, nls), do: {acc |> Enum.reverse() |> List.to_string(), nls, rest}

  defp exponent(<<e, rest::binary>> = s) when e in [?e, ?E] do
    {sign, r} =
      case rest do
        <<x, r::binary>> when x in [?+, ?-] -> {<<x>>, r}
        _ -> {"", rest}
      end

    case span(r, &(&1 in ?0..?9)) do
      {"", _} -> {"", s}
      {ds, r} -> {<<e>> <> sign <> ds, r}
    end
  end

  defp exponent(s), do: {"", s}

  defp word?(c), do: c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c >= 128

  defp span(s, pred), do: span(s, pred, 0)

  defp span(s, pred, n) do
    if n < byte_size(s) and pred.(:binary.at(s, n)),
      do: span(s, pred, n + 1),
      else: {binary_part(s, 0, n), binary_part(s, n, byte_size(s) - n)}
  end

  # bis einschließlich Endmarke (oder Textende)
  defp until_incl(s, mark) do
    case :binary.match(s, mark, scope: {1, byte_size(s) - 1}) do
      {pos, len} ->
        {binary_part(s, 0, pos + len), binary_part(s, pos + len, byte_size(s) - pos - len)}

      :nomatch ->
        {s, ""}
    end
  end

  # Quotiertes Token mit \-Escapes und verdoppeltem Anführungszeichen
  defp quoted(<<q, rest::binary>>), do: quoted(rest, q, [<<q>>])

  defp quoted(<<>>, _q, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}

  defp quoted(<<"\\", c::utf8, rest::binary>>, q, acc),
    do: quoted(rest, q, [<<"\\", c::utf8>> | acc])

  defp quoted(<<q, q, rest::binary>>, q, acc), do: quoted(rest, q, [<<q, q>> | acc])

  defp quoted(<<q, rest::binary>>, q, acc),
    do: {[<<q>> | acc] |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp quoted(<<c::utf8, rest::binary>>, q, acc), do: quoted(rest, q, [<<c::utf8>> | acc])
  defp quoted(<<c, rest::binary>>, q, acc), do: quoted(rest, q, [<<c>> | acc])

  # ---------------------------------------------------------------------

  @doc "`'$bigint'('…')` im gelesenen Term wieder durch die Zahl ersetzen."
  def unwrap({tag, "-", [{tag2, @big, [{:atom, ds}]}]})
      when tag in [:struct, :gstruct] and tag2 in [:struct, :gstruct],
      do: -String.to_integer(ds)

  def unwrap({tag, @big, [{:atom, ds}]}) when tag in [:struct, :gstruct],
    do: String.to_integer(ds)

  def unwrap({tag, f, args}) when tag in [:struct, :gstruct], do: mk(f, Enum.map(args, &unwrap/1))
  def unwrap({:glist, _} = l), do: l |> PrologEx.unmark_top() |> unwrap()
  def unwrap([h | t]), do: PrologEx.cons(unwrap(h), unwrap(t))
  def unwrap(t), do: t
end
