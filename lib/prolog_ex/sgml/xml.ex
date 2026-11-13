defmodule PrologEx.Sgml.Xml do
  @moduledoc """
  XML-Parser für `load_xml/3` (`library(sgml)`), Schritt für Schritt wie
  roxmltree 0.20 (das Scryer Prolog nimmt, ohne DTD): nur wohlgeformtes XML,
  sonst `:error`.

    * Ein Wurzelelement; davor `<?xml version=… ?>` (nur mit Leerzeichen
      nach `xml`), Kommentare, Verarbeitungsanweisungen und Leerraum,
      danach Kommentare, Verarbeitungsanweisungen und Leerraum – im
      Ergebnis nur die Wurzel. `<!DOCTYPE` ist ein Fehler.
    * Nur die fünf vordefinierten Entitäten; Zeichenreferenzen auf
      Ersatzzeichen oder über U+10FFFF werden U+FFFD, `&#0;` ist ein
      Fehler.
    * Namensräume wie roxmltree: Präfixe müssen erklärt sein (`xml` nur
      bei Attributen), `xmlns:p=""` ist erlaubt, ein Element darf kein
      Präfix `xmlns` haben; Element- und Attributnamen ohne Präfix, die
      `xmlns`-Attribute fallen weg; doppelte Attribute (gleicher
      Namensraum und Name) sind ein Fehler.
    * Text, Zeichenreferenzen und CDATA-Abschnitte werden ein Textknoten;
      Kommentare und Verarbeitungsanweisungen im Element werden
      `{:other}` (bei Scryer `element('', [], [])`).
    * Zeilenenden: `\\r\\n` und `\\r` werden `\\n` (nicht in
      Zeichenreferenzen); in Attributwerten werden Tab, Zeilenwechsel und
      Wagenrücklauf ein Leerzeichen.

  Ergebnis: `{:ok, {:el, name, [{name, wert}], kinder}}` mit Kindern
  `{:el, …}`, `{:text, binary}` und `{:other}`.
  """

  @xml_uri "http://www.w3.org/XML/1998/namespace"
  @xmlns_uri "http://www.w3.org/2000/xmlns/"

  @doc "Text (UTF-8) parsen"
  def parse(text) do
    text = String.replace_prefix(text, "﻿", "")
    rest = if String.starts_with?(text, "<?xml "), do: declaration(text), else: text
    rest = misc(rest)
    rest = skip_spaces(rest)
    if String.starts_with?(rest, "<!DOCTYPE"), do: fail()
    rest = skip_spaces(rest)

    {root, rest} =
      case rest do
        "<" <> _ -> element(rest, %{})
        _ -> {nil, rest}
      end

    if root != nil and misc(rest) == "", do: {:ok, root}, else: :error
  catch
    :xml_error -> :error
  end

  defp fail, do: throw(:xml_error)

  # --- Zeichen ---------------------------------------------------------------

  defp space?(c), do: c in [?\s, ?\t, ?\n, ?\r]

  defp skip_spaces(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: skip_spaces(rest)
  defp skip_spaces(rest), do: rest

  defp xml_char?(c) when c < 0x20, do: space?(c)
  defp xml_char?(c), do: c != 0xFFFE and c != 0xFFFF

  defp name_start?(c) when c <= 128, do: c in ?A..?Z or c in ?a..?z or c == ?: or c == ?_

  defp name_start?(c),
    do:
      c in 0xC0..0xD6 or c in 0xD8..0xF6 or c in 0xF8..0x2FF or c in 0x370..0x37D or
        c in 0x37F..0x1FFF or c in 0x200C..0x200D or c in 0x2070..0x218F or
        c in 0x2C00..0x2FEF or c in 0x3001..0xD7FF or c in 0xF900..0xFDCF or
        c in 0xFDF0..0xFFFD or c in 0x10000..0xEFFFF

  defp name_char?(c) when c <= 128,
    do: c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c in [?:, ?_, ?-, ?.]

  defp name_char?(c),
    do:
      c == 0xB7 or c in 0xC0..0xD6 or c in 0xD8..0xF6 or c in 0xF8..0x2FF or
        c in 0x300..0x36F or c in 0x370..0x37D or c in 0x37F..0x1FFF or
        c in 0x200C..0x200D or c in 0x203F..0x2040 or c in 0x2070..0x218F or
        c in 0x2C00..0x2FEF or c in 0x3001..0xD7FF or c in 0xF900..0xFDCF or
        c in 0xFDF0..0xFFFD or c in 0x10000..0xEFFFF

  # Zeichen bis zum Muster stop (das bleibt stehen); alle müssen
  # XML-Zeichen sein; {text, rest} – ohne Muster bis zum Ende
  defp chars_until(text, stop) do
    {pos, rest_from} =
      case :binary.match(text, stop) do
        {pos, _} -> {pos, pos}
        :nomatch -> {byte_size(text), byte_size(text)}
      end

    <<chunk::binary-size(^pos), _::binary>> = text
    check_chars(chunk)
    <<_::binary-size(^rest_from), rest::binary>> = text
    {chunk, rest}
  end

  defp check_chars(text) do
    if valid_chars?(text), do: :ok, else: fail()
  end

  defp valid_chars?(<<>>), do: true
  defp valid_chars?(<<c, r::binary>>) when c >= 0x20 and c < 0x80, do: valid_chars?(r)
  defp valid_chars?(<<c::utf8, r::binary>>), do: xml_char?(c) and valid_chars?(r)

  defp skip_string(text, s) do
    if String.starts_with?(text, s),
      do: binary_part(text, byte_size(s), byte_size(text) - byte_size(s)),
      else: fail()
  end

  # --- Prolog ---------------------------------------------------------------

  defp declaration("<?xml" <> rest) do
    rest = decl_spaces(rest)
    unless String.starts_with?(rest, "version"), do: fail()
    {_, _, _, rest} = attribute(rest)
    rest = decl_spaces(rest)

    rest =
      if String.starts_with?(rest, "encoding") do
        {_, _, _, r} = attribute(rest)
        decl_spaces(r)
      else
        rest
      end

    rest =
      if String.starts_with?(rest, "standalone") do
        {_, _, _, r} = attribute(rest)
        r
      else
        rest
      end

    rest |> skip_spaces() |> skip_string("?>")
  end

  defp decl_spaces(<<c, _::binary>> = rest) when c in [?\s, ?\t, ?\n, ?\r], do: skip_spaces(rest)
  defp decl_spaces("?>" <> _ = rest), do: rest
  defp decl_spaces(""), do: ""
  defp decl_spaces(_), do: fail()

  # Leerraum, Kommentare, Verarbeitungsanweisungen
  defp misc(""), do: ""

  defp misc(text) do
    case skip_spaces(text) do
      "<!--" <> _ = r -> r |> comment() |> elem(1) |> misc()
      "<?" <> _ = r -> r |> pi() |> misc()
      r -> r
    end
  end

  defp comment("<!--" <> rest) do
    {body, rest} = chars_until(rest, "-->")
    rest = skip_string(rest, "-->")
    if String.contains?(body, "--") or String.ends_with?(body, "-"), do: fail()
    {body, rest}
  end

  defp pi("<?xml " <> _), do: fail()

  defp pi("<?" <> rest) do
    {_target, rest} = name(rest)
    rest = skip_spaces(rest)
    {_content, rest} = chars_until(rest, "?>")
    skip_string(rest, "?>")
  end

  # Name (wie consume_name: erstes Zeichen NameStartChar, auch ":")
  defp name(<<c::utf8, rest::binary>>) do
    if name_start?(c), do: name_rest(rest, <<c::utf8>>), else: fail()
  end

  defp name(_), do: fail()

  defp name_rest(<<c::utf8, rest::binary>> = all, acc) do
    if name_char?(c), do: name_rest(rest, <<acc::binary, c::utf8>>), else: {acc, all}
  end

  defp name_rest(<<>>, acc), do: {acc, <<>>}

  # QName: {präfix, lokal, rest}; ein ":" trennt, ein zweites ist ein Fehler
  defp qname(text), do: qname(text, nil, "")

  defp qname(<<?:, rest::binary>>, nil, acc), do: qname(rest, acc, "")
  defp qname(<<?:, _::binary>>, _prefix, _acc), do: fail()

  defp qname(<<c::utf8, rest::binary>> = all, prefix, acc) do
    if name_char?(c) and c != ?:,
      do: qname(rest, prefix, <<acc::binary, c::utf8>>),
      else: qname_done(prefix, acc, all)
  end

  defp qname(<<>>, prefix, acc), do: qname_done(prefix, acc, <<>>)

  defp qname_done(prefix, local, rest) do
    prefix = prefix || ""

    case prefix do
      <<c::utf8, _::binary>> -> unless name_start?(c), do: fail()
      _ -> :ok
    end

    case local do
      <<c::utf8, _::binary>> -> unless name_start?(c), do: fail()
      _ -> fail()
    end

    {prefix, local, rest}
  end

  # Attribut: {präfix, lokal, roher Wert, rest}
  defp attribute(text) do
    {prefix, local, rest} = qname(text)
    rest = rest |> skip_spaces() |> skip_string("=") |> skip_spaces()

    case rest do
      <<q, r::binary>> when q in [?", ?'] ->
        {value, r} = attr_chars(r, q, 0)
        {prefix, local, value, r}

      _ ->
        fail()
    end
  end

  # Wert bis zum Anführungszeichen (kein "<"), Zeichen geprüft
  defp attr_chars(text, q, i) do
    case text do
      <<_::binary-size(^i), ^q, _::binary>> ->
        <<v::binary-size(^i), _, r::binary>> = text
        {v, r}

      <<_::binary-size(^i), ?<, _::binary>> ->
        fail()

      <<_::binary-size(^i), c::utf8, _::binary>> ->
        if xml_char?(c), do: attr_chars(text, q, i + byte_size(<<c::utf8>>)), else: fail()

      _ ->
        fail()
    end
  end

  # --- Elemente ------------------------------------------------------------------

  # ns: Präfix (nil: Vorgabe) => URI, geerbt
  defp element("<" <> rest, ns) do
    {prefix, local, rest} = qname(rest)
    if prefix == "xmlns", do: fail()
    {raw_attrs, decls, rest, empty?} = attributes(rest, [], [])
    ns = Enum.reduce(Enum.reverse(decls), ns, fn {p, uri}, acc -> Map.put(acc, p, uri) end)
    attrs = resolve_attributes(Enum.reverse(raw_attrs), ns)

    if prefix != "" and not Map.has_key?(ns, prefix), do: fail()

    if empty? do
      {{:el, local, attrs, []}, rest}
    else
      {kids, rest} = content(rest, ns, [], false)
      {prefix2, local2, rest} = qname(skip_string(rest, "</"))
      if prefix2 != prefix or local2 != local, do: fail()
      rest = rest |> skip_spaces() |> skip_string(">")
      {{:el, local, attrs, kids}, rest}
    end
  end

  # Attribute bis "/>" bzw. ">": {attrs, erklärte Namensräume, rest, leer?}
  defp attributes(text, attrs, decls) do
    has_space = match?(<<c, _::binary>> when c in [?\s, ?\t, ?\n, ?\r], text)

    case skip_spaces(text) do
      "" ->
        fail()

      "/" <> r ->
        {attrs, decls, skip_string(r, ">"), true}

      ">" <> r ->
        {attrs, decls, r, false}

      r ->
        unless has_space, do: fail()
        {prefix, local, raw, r} = attribute(r)
        value = normalize_attribute(raw)

        cond do
          prefix == "xmlns" ->
            if value == @xmlns_uri, do: fail()
            xml? = value == @xml_uri
            if local == "xml" and not xml?, do: fail()
            if local != "xml" and xml?, do: fail()
            if Enum.any?(decls, fn {p, _} -> p == local end), do: fail()
            decls = if xml?, do: decls, else: [{local, value} | decls]
            attributes(r, attrs, decls)

          local == "xmlns" ->
            if value == @xml_uri or value == @xmlns_uri, do: fail()
            attributes(r, attrs, [{nil, value} | decls])

          true ->
            attributes(r, [{prefix, local, value} | attrs], decls)
        end
    end
  end

  defp resolve_attributes(attrs, ns) do
    resolved =
      for {prefix, local, value} <- attrs do
        uri =
          cond do
            prefix == "xml" -> @xml_uri
            prefix == "" -> nil
            true -> Map.get(ns, prefix) || fail()
          end

        {{uri, local}, local, value}
      end

    keys = for {k, _, _} <- resolved, do: k
    if length(Enum.uniq(keys)) != length(keys), do: fail()
    for {_, local, value} <- resolved, do: {local, value}
  end

  # Inhalt bis zum End-Tag (der Rest beginnt mit "</"); after_text: der
  # letzte Knoten ist Text, an den neuer Text angehängt wird
  defp content("", _ns, _kids, _after), do: fail()

  defp content(text, ns, kids, after_text) do
    case text do
      "</" <> _ ->
        {Enum.reverse(kids), text}

      "<!--" <> _ ->
        {_, r} = comment(text)
        content(r, ns, [{:other} | kids], false)

      "<![CDATA[" <> r ->
        {data, r} = chars_until(r, "]]>")
        r = skip_string(r, "]]>")
        data = if String.contains?(data, "\r"), do: newlines(data, true), else: data
        content(r, ns, append_text(kids, data, after_text), true)

      "<!" <> _ ->
        fail()

      "<?" <> _ ->
        content(pi(text), ns, [{:other} | kids], false)

      "<" <> "" ->
        fail()

      "<" <> _ ->
        {el, r} = element(text, ns)
        content(r, ns, [el | kids], false)

      _ ->
        {raw, r} = chars_until(text, "<")
        if String.contains?(raw, "]]>"), do: fail()
        content(r, ns, append_text(kids, text_value(raw), after_text), true)
    end
  end

  defp append_text([{:text, prev} | kids], text, true), do: [{:text, prev <> text} | kids]
  defp append_text(kids, text, _), do: [{:text, text} | kids]

  # Text wie roxmltrees process_text: Referenzen auflösen, Zeilenenden
  # (nicht aus Zeichenreferenzen, und nicht das Byte direkt danach)
  defp text_value(raw) do
    if String.contains?(raw, ["&", "\r"]), do: text_chunks(raw, [], false), else: raw
  end

  defp text_chunks(<<>>, buf, _as_is), do: buf |> Enum.reverse() |> IO.iodata_to_binary()

  defp text_chunks("&" <> _ = text, buf, _as_is) do
    {c, rest} = reference(text)
    text_chunks(rest, [<<c::utf8>> | buf], true)
  end

  defp text_chunks(<<c, rest::binary>>, buf, true), do: text_chunks(rest, [<<c>> | buf], false)

  defp text_chunks(<<c, rest::binary>>, buf, false),
    do: text_chunks(rest, push_from_text(buf, c, rest == ""), false)

  # roxmltrees TextBuffer::push_from_text (buf umgekehrt, Byte-Stücke)
  defp push_from_text(["\r" | buf], c, at_end) do
    buf = ["\n" | buf]

    cond do
      at_end and c == ?\r -> ["\n" | buf]
      c != ?\n -> [<<c>> | buf]
      true -> buf
    end
  end

  defp push_from_text(buf, ?\r, true), do: ["\n" | buf]
  defp push_from_text(buf, c, _at_end), do: [<<c>> | buf]

  # CDATA mit "\r": nur Zeilenenden (wie process_cdata, zeichenweise)
  defp newlines(data, _), do: newlines_bytes(data, [])

  defp newlines_bytes(<<>>, buf), do: buf |> Enum.reverse() |> IO.iodata_to_binary()

  defp newlines_bytes(<<c::utf8, rest::binary>>, buf) do
    last = rest == ""

    buf =
      Enum.reduce(:binary.bin_to_list(<<c::utf8>>), buf, fn b, acc ->
        push_from_text(acc, b, last)
      end)

    newlines_bytes(rest, buf)
  end

  # Attributwert normalisieren (roxmltrees _normalize_attribute)
  defp normalize_attribute(raw) do
    if String.contains?(raw, ["&", "\t", "\n", "\r"]), do: attr_bytes(raw, []), else: raw
  end

  defp attr_bytes(<<>>, buf), do: buf |> Enum.reverse() |> IO.iodata_to_binary()

  defp attr_bytes("&" <> _ = text, buf) do
    {c, rest} = reference(text)
    attr_bytes(rest, [<<c::utf8>> | buf])
  end

  defp attr_bytes(<<?\r, ?\n, _::binary>> = text, buf),
    do: attr_bytes(binary_part(text, 1, byte_size(text) - 1), buf)

  defp attr_bytes(<<c, rest::binary>>, buf) when c in [?\n, ?\r, ?\t],
    do: attr_bytes(rest, [" " | buf])

  defp attr_bytes(<<c, rest::binary>>, buf), do: attr_bytes(rest, [<<c>> | buf])

  # Referenz ab "&": {codepoint, rest}; sonst Fehler
  defp reference("&#x" <> rest) do
    {digits, r} = take_while(rest, &(&1 in ?0..?9 or &1 in ?a..?f or &1 in ?A..?F))
    char_ref(digits, 16, r)
  end

  defp reference("&#" <> rest) do
    {digits, r} = take_while(rest, &(&1 in ?0..?9))
    char_ref(digits, 10, r)
  end

  defp reference("&" <> rest) do
    {n, r} = name(rest)

    c =
      case n do
        "quot" -> ?"
        "amp" -> ?&
        "apos" -> ?'
        "lt" -> ?<
        "gt" -> ?>
        _ -> fail()
      end

    {c, skip_string(r, ";")}
  end

  defp char_ref("", _base, _r), do: fail()

  defp char_ref(digits, base, r) do
    n = String.to_integer(digits, base)
    if n > 0xFFFFFFFF, do: fail()
    c = if n > 0x10FFFF or n in 0xD800..0xDFFF, do: 0xFFFD, else: n
    unless xml_char?(c), do: fail()
    {c, skip_string(r, ";")}
  end

  defp take_while(bin, pred), do: take_while(bin, pred, 0)

  defp take_while(bin, pred, i) do
    case bin do
      <<_::binary-size(^i), c, _::binary>> ->
        if pred.(c), do: take_while(bin, pred, i + 1), else: split_at(bin, i)

      _ ->
        split_at(bin, i)
    end
  end

  defp split_at(bin, i) do
    <<a::binary-size(^i), b::binary>> = bin
    {a, b}
  end
end
