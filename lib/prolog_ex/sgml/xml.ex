defmodule PrologEx.Sgml.Xml do
  @moduledoc """
  XML-Parser für `load_xml/3` (`library(sgml)`), mit dem Verhalten von
  Scryer Prolog (dort roxmltree): nur wohlgeformtes XML, sonst `:error`.

    * Ein Wurzelelement; davor die XML-Deklaration, Kommentare,
      Verarbeitungsanweisungen und Leerraum, danach Kommentare,
      Verarbeitungsanweisungen und Leerraum – im Ergebnis nur die Wurzel.
    * Keine DTD: `<!DOCTYPE …>` ist ein Fehler (roxmltree erlaubt sie
      nur auf Wunsch); daher nur die fünf vordefinierten Entitäten und
      Zeichenreferenzen.
    * Namensräume: Präfixe müssen erklärt sein; Element- und
      Attributnamen ohne Präfix, die `xmlns`-Attribute fallen weg.
    * Text, Zeichenreferenzen und CDATA-Abschnitte werden ein Textknoten;
      Kommentare und Verarbeitungsanweisungen im Element werden
      `{:other}` (bei Scryer `element('', [], [])`).
    * Zeilenenden werden `\\n`; in Attributwerten werden Tab, Zeilenwechsel
      und Wagenrücklauf (nicht aber Zeichenreferenzen darauf) ein
      Leerzeichen.

  Ergebnis: `{:ok, {:el, name, [{name, wert}], kinder}}` mit Kindern
  `{:el, …}`, `{:text, binary}` und `{:other}`.
  """

  @doc "Text (UTF-8) parsen"
  def parse(text) do
    text =
      text
      |> String.replace_prefix("﻿", "")
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")

    try do
      rest = xml_decl(text)
      rest = misc(rest)

      {root, rest} =
        case rest do
          "<!DOCTYPE" <> _ -> fail()
          "<" <> _ -> element(rest, %{"xml" => "http://www.w3.org/XML/1998/namespace"})
          _ -> fail()
        end

      if misc(rest) == "", do: {:ok, root}, else: :error
    catch
      :xml_error -> :error
    end
  end

  defp fail, do: throw(:xml_error)

  # <?xml version="1.0" ...?> nur ganz am Anfang
  defp xml_decl("<?xml" <> rest = all) do
    case rest do
      <<c, _::binary>> when c in [?\s, ?\t, ?\n] ->
        case :binary.split(rest, "?>") do
          [decl, after_decl] ->
            if String.contains?(decl, "version"), do: after_decl, else: fail()

          _ ->
            fail()
        end

      _ ->
        all
    end
  end

  defp xml_decl(text), do: text

  # Leerraum, Kommentare, Verarbeitungsanweisungen
  defp misc(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n], do: misc(rest)
  defp misc("<!--" <> rest), do: rest |> comment() |> misc()
  defp misc("<?" <> rest), do: rest |> pi() |> misc()
  defp misc(rest), do: rest

  defp comment(rest) do
    case :binary.split(rest, "-->") do
      [body, after_c] ->
        if String.contains?(body, "--") or String.ends_with?(body, "-"), do: fail()
        check_chars(body)
        after_c

      _ ->
        fail()
    end
  end

  defp pi(rest) do
    {target, rest} = name(rest)
    if String.downcase(target) == "xml", do: fail()

    case rest do
      "?>" <> after_pi ->
        after_pi

      <<c, _::binary>> when c in [?\s, ?\t, ?\n] ->
        case :binary.split(rest, "?>") do
          [body, after_pi] ->
            check_chars(body)
            after_pi

          _ ->
            fail()
        end

      _ ->
        fail()
    end
  end

  # --- Namen -----------------------------------------------------------------

  defp name(<<c::utf8, rest::binary>>) do
    if name_start?(c), do: name_rest(rest, <<c::utf8>>), else: fail()
  end

  defp name(_), do: fail()

  defp name_rest(<<c::utf8, rest::binary>> = all, acc) do
    if name_char?(c), do: name_rest(rest, <<acc::binary, c::utf8>>), else: {acc, all}
  end

  defp name_rest(<<>>, acc), do: {acc, <<>>}

  defp name_start?(c),
    do:
      c in ?a..?z or c in ?A..?Z or c == ?_ or c == ?: or c in 0xC0..0xD6 or c in 0xD8..0xF6 or
        c in 0xF8..0x2FF or c in 0x370..0x37D or c in 0x37F..0x1FFF or c in 0x200C..0x200D or
        c in 0x2070..0x218F or c in 0x2C00..0x2FEF or c in 0x3001..0xD7FF or
        c in 0xF900..0xFDCF or c in 0xFDF0..0xFFFD or c in 0x10000..0xEFFFF

  defp name_char?(c),
    do:
      name_start?(c) or c in ?0..?9 or c == ?- or c == ?. or c == 0xB7 or c in 0x300..0x36F or
        c in 0x203F..0x2040

  defp xml_char?(c),
    do: c in [0x9, 0xA, 0xD] or c in 0x20..0xD7FF or c in 0xE000..0xFFFD or c in 0x10000..0x10FFFF

  defp check_chars(text) do
    for <<c::utf8 <- text>>, not xml_char?(c), do: fail()
    :ok
  end

  defp skip_ws(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n], do: skip_ws(rest)
  defp skip_ws(rest), do: rest

  # --- Elemente ----------------------------------------------------------------

  # ns: Präfix => URI ("" Vorgabe-Namensraum)
  defp element("<" <> rest, ns) do
    {qname, rest} = name(rest)
    {raw_attrs, rest, empty?} = attributes(rest, [])
    ns = declare(raw_attrs, ns)
    elem_ns = resolve(qname, ns, true)

    attrs =
      for {an, av} <- raw_attrs, not xmlns?(an) do
        {resolve(an, ns, false), local(an), av}
      end

    keys = for {uri, l, _} <- attrs, do: {uri, l}
    if length(Enum.uniq(keys)) != length(keys), do: fail()
    _ = elem_ns
    attrs = for {_, l, v} <- attrs, do: {l, v}

    if empty? do
      {{:el, local(qname), attrs, []}, rest}
    else
      {kids, rest} = content(rest, ns, [], [])

      case rest do
        "</" <> rest2 ->
          {qname2, rest3} = name(rest2)
          if qname2 != qname, do: fail()

          case skip_ws(rest3) do
            ">" <> rest4 -> {{:el, local(qname), attrs, kids}, rest4}
            _ -> fail()
          end

        _ ->
          fail()
      end
    end
  end

  defp xmlns?("xmlns"), do: true
  defp xmlns?("xmlns:" <> _), do: true
  defp xmlns?(_), do: false

  defp declare(attrs, ns) do
    Enum.reduce(attrs, ns, fn
      {"xmlns", uri}, ns ->
        Map.put(ns, "", uri)

      {"xmlns:" <> p, uri}, ns ->
        cond do
          uri == "" -> fail()
          p == "xmlns" -> fail()
          p == "xml" and uri != "http://www.w3.org/XML/1998/namespace" -> fail()
          true -> Map.put(ns, p, uri)
        end

      _, ns ->
        ns
    end)
  end

  defp resolve(qname, ns, elem?) do
    case String.split(qname, ":") do
      [l] -> if elem?, do: Map.get(ns, "", ""), else: (_ = l) && ""
      [p, l] when p != "" and l != "" -> Map.get(ns, p) || fail()
      _ -> fail()
    end
  end

  defp local(qname) do
    case String.split(qname, ":") do
      [l] -> l
      [_, l] -> l
    end
  end

  defp attributes(rest, acc) do
    case rest do
      "/>" <> r ->
        {Enum.reverse(acc), r, true}

      ">" <> r ->
        {Enum.reverse(acc), r, false}

      <<c, _::binary>> when c in [?\s, ?\t, ?\n] ->
        case skip_ws(rest) do
          "/>" <> r ->
            {Enum.reverse(acc), r, true}

          ">" <> r ->
            {Enum.reverse(acc), r, false}

          r ->
            {an, r} = name(r)

            {av, r} =
              case skip_ws(r) do
                "=" <> r2 -> attr_value(skip_ws(r2))
                _ -> fail()
              end

            if List.keymember?(acc, an, 0), do: fail()
            attributes(r, [{an, av} | acc])
        end

      _ ->
        fail()
    end
  end

  defp attr_value(<<q, rest::binary>>) when q in [?", ?'] do
    case :binary.split(rest, <<q>>) do
      [raw, r] ->
        if String.contains?(raw, "<"), do: fail()
        check_chars(raw)
        {expand(raw, true), r}

      _ ->
        fail()
    end
  end

  defp attr_value(_), do: fail()

  # Referenzen auflösen; in Attributen Leerraum als Leerzeichen
  defp expand(raw, attr?) do
    raw
    |> expand_iter(attr?, [])
    |> IO.iodata_to_binary()
  end

  defp expand_iter(<<>>, _attr?, acc), do: Enum.reverse(acc)

  defp expand_iter("&" <> rest, attr?, acc) do
    {c, rest} = reference(rest)
    expand_iter(rest, attr?, [<<c::utf8>> | acc])
  end

  defp expand_iter(<<c, rest::binary>>, true, acc) when c in [?\t, ?\n, ?\r],
    do: expand_iter(rest, true, [" " | acc])

  defp expand_iter(<<c::utf8, rest::binary>>, attr?, acc),
    do: expand_iter(rest, attr?, [<<c::utf8>> | acc])

  defp reference(rest) do
    case :binary.split(rest, ";") do
      [ref, r] ->
        c =
          case ref do
            "lt" -> ?<
            "gt" -> ?>
            "amp" -> ?&
            "apos" -> ?'
            "quot" -> ?"
            "#x" <> hex -> char_ref(hex, 16)
            "#" <> dec -> char_ref(dec, 10)
            _ -> fail()
          end

        {c, r}

      _ ->
        fail()
    end
  end

  defp char_ref(digits, base) do
    case Integer.parse(digits, base) do
      {n, ""} when digits != "" -> if xml_char?(n), do: n, else: fail()
      _ -> fail()
    end
  end

  # Inhalt bis zum End-Tag: Kinder und das, was danach kommt (beginnt mit
  # "</"); text: gesammelte Textstücke des laufenden Textknotens (nil:
  # keiner offen)
  defp content(rest, ns, kids, text) do
    case rest do
      "</" <> _ ->
        {Enum.reverse(flush(kids, text)), rest}

      "<![CDATA[" <> r ->
        case :binary.split(r, "]]>") do
          [data, r2] ->
            check_chars(data)
            content(r2, ns, kids, [data | text || []])

          _ ->
            fail()
        end

      "<!--" <> r ->
        content(comment(r), ns, [{:other} | flush(kids, text)], nil)

      "<?" <> r ->
        content(pi(r), ns, [{:other} | flush(kids, text)], nil)

      "<!" <> _ ->
        fail()

      "<" <> _ ->
        {el, r} = element(rest, ns)
        content(r, ns, [el | flush(kids, text)], nil)

      "" ->
        fail()

      _ ->
        {chunk, r} = char_data(rest, [])
        content(r, ns, kids, [chunk | text || []])
    end
  end

  defp flush(kids, nil), do: kids
  defp flush(kids, []), do: kids
  defp flush(kids, text), do: [{:text, text |> Enum.reverse() |> IO.iodata_to_binary()} | kids]

  # Zeichen bis zum nächsten "<"
  defp char_data(rest, acc) do
    case :binary.match(rest, "<") do
      {pos, _} ->
        <<raw::binary-size(^pos), r::binary>> = rest
        {text_chunk(raw), r}

      :nomatch ->
        _ = acc
        fail()
    end
  end

  defp text_chunk(raw) do
    if String.contains?(raw, "]]>"), do: fail()
    check_chars(raw)
    expand(raw, false)
  end
end
