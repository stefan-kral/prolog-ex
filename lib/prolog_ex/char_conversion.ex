defmodule PrologEx.CharConversion do
  @moduledoc """
  Zeichenumsetzung beim Lesen (ISO 8.14.5, 8.14.6, Flag `char_conversion`).

  Die Tabelle gehört der Sitzung (Prozess-Dictionary, wie Flags und
  Operatoren): `%{zeichen => zeichen}` als Codepoints. Ist das Flag
  `char_conversion` `on`, setzt der Reader jedes Zeichen außerhalb von
  Quotes (`'…'`, `"…"`, `` `…` ``), `0'c` und Kommentaren um, bevor er den
  Term zerlegt – wie SWI und SICStus („unquoted“); gprolog setzt auch in
  Strings und `0'c` um.

  `convert_term/2` liefert den umgesetzten Text genau eines Terms (bis
  einschließlich des Endepunkts, so wie der Tokenizer ihn erkennt) und die
  Anzahl der dafür gelesenen Bytes des Originals.
  """

  @key :prolog_ex_char_conversion
  @layout [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]
  @graphic ~c"#$&*+-./:<=>?@^~\\"

  def table, do: Process.get(@key, %{})

  @doc "In → Out eintragen; In → In entfernt den Eintrag"
  def put(c, c), do: Process.put(@key, Map.delete(table(), c))
  def put(c, d), do: Process.put(@key, Map.put(table(), c, d))

  @doc "Tabelle, wenn das Flag an ist und sie nicht leer ist, sonst nil"
  def active do
    t = table()

    if t != %{} and PrologEx.Flags.get("char_conversion") == {:atom, "on"},
      do: t,
      else: nil
  end

  @doc "Umgesetzter Text eines Terms und verbrauchte Bytes des Originals"
  def convert_term(text, table), do: conv(text, table, :start, [], 0)

  # prev: :graphic (letztes Zeichen ein Symbolzeichen: "." gehört dazu,
  # "/*" ist kein Kommentar), :alnum (davor Buchstabe/Ziffer: "0'" ist
  # kein Zeichencode), :other
  defp conv("", _t, _prev, acc, n), do: {IO.iodata_to_binary(acc), n}

  defp conv(<<q, rest::binary>>, t, _prev, acc, n) when q in [?', ?", ?`] do
    {quoted, rest, len} = quoted(rest, q, [q], 1)
    conv(rest, t, :other, [acc, quoted], n + len)
  end

  defp conv(<<"0'", rest::binary>>, t, prev, acc, n) when prev != :alnum do
    {code, rest, len} = char_code(rest)
    conv(rest, t, :other, [acc, "0'", code], n + 2 + len)
  end

  defp conv(<<?%, _::binary>> = r, t, _prev, acc, n) do
    case :binary.match(r, "\n") do
      {i, 1} ->
        conv(binary_part(r, i, byte_size(r) - i), t, :other, [acc, binary_part(r, 0, i)], n + i)

      :nomatch ->
        {IO.iodata_to_binary([acc, r]), n + byte_size(r)}
    end
  end

  defp conv(<<"/*", _::binary>> = r, t, prev, acc, n) when prev != :graphic do
    case :binary.match(r, "*/") do
      {i, 2} ->
        conv(
          binary_part(r, i + 2, byte_size(r) - i - 2),
          t,
          :other,
          [acc, binary_part(r, 0, i + 2)],
          n + i + 2
        )

      :nomatch ->
        {IO.iodata_to_binary([acc, r]), n + byte_size(r)}
    end
  end

  defp conv(<<c::utf8, rest::binary>>, t, prev, acc, n) do
    d = Map.get(t, c, c)
    n = n + byte_size(<<c::utf8>>)

    cond do
      d == ?. and prev != :graphic and end_follows?(rest, t) ->
        {IO.iodata_to_binary([acc, ?.]), n}

      # ein umgesetztes % beginnt einen Kommentar, ein umgesetztes Quote
      # ein Quote (der Rest bleibt dann unverändert)
      d == ?% ->
        conv(<<?%, rest::binary>>, t, prev, acc, n - 1)

      d in [?', ?", ?`] ->
        conv(<<d, rest::binary>>, t, prev, acc, n - 1)

      true ->
        conv(rest, t, class(d), [acc, <<d::utf8>>], n)
    end
  end

  # ungültiges UTF-8: unverändert (der Tokenizer meldet es)
  defp conv(<<b, rest::binary>>, t, _prev, acc, n), do: conv(rest, t, :other, [acc, b], n + 1)

  defp end_follows?("", _t), do: true

  defp end_follows?(<<c::utf8, _::binary>>, t) do
    d = Map.get(t, c, c)
    d in @layout or d == ?%
  end

  defp end_follows?(_, _t), do: false

  defp class(d) when d in @graphic, do: :graphic
  defp class(d) when d in ?a..?z or d in ?A..?Z or d in ?0..?9 or d == ?_, do: :alnum
  defp class(d) when d > 127, do: :alnum
  defp class(_), do: :other

  # bis einschließlich des schließenden Quotes, unverändert
  defp quoted(r, q, acc, len) do
    case r do
      <<^q, ^q, rest::binary>> -> quoted(rest, q, [acc, q, q], len + 2)
      <<^q, rest::binary>> -> {IO.iodata_to_binary([acc, q]), rest, len + 1}
      <<?\\, c, rest::binary>> -> quoted(rest, q, [acc, ?\\, c], len + 2)
      <<c, rest::binary>> -> quoted(rest, q, [acc, c], len + 1)
      "" -> {IO.iodata_to_binary(acc), "", len}
    end
  end

  # das Zeichen nach 0' (auch '' und Escapes), unverändert
  defp char_code(<<"''", rest::binary>>), do: {"''", rest, 2}
  # \x41\ und \101\ ganz, sonst \ und ein Zeichen
  defp char_code(<<?\\, c, _::binary>> = r) when c == ?x or c in ?0..?7 do
    case :binary.match(r, "\\", scope: {1, min(byte_size(r) - 1, 12)}) do
      {i, 1} -> {binary_part(r, 0, i + 1), binary_part(r, i + 1, byte_size(r) - i - 1), i + 1}
      :nomatch -> {<<?\\, c>>, binary_part(r, 2, byte_size(r) - 2), 2}
    end
  end

  defp char_code(<<?\\, c, rest::binary>>), do: {<<?\\, c>>, rest, 2}
  defp char_code(<<c::utf8, rest::binary>>), do: {<<c::utf8>>, rest, byte_size(<<c::utf8>>)}
  defp char_code(rest), do: {"", rest, 0}
end
