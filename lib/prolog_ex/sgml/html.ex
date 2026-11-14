defmodule PrologEx.Sgml.Html do
  @moduledoc """
  HTML-Parser für `load_html/3` (`library(sgml)`), tolerant wie ein
  Browser: eine vereinfachte Fassung des HTML5-Algorithmus (Scryer Prolog
  nimmt html5ever). Für wohlgeformtes und das übliche „schlampige“ HTML
  derselbe Baum wie Scryer, bei stark kaputtem Markup sind Abweichungen
  möglich.

    * Tokenizer nach HTML5: Tags und Attribute (Namen klein), Kommentare,
      `<!DOCTYPE>`, `<?…>` und `<!…>` als Kommentar, alle 2231 benannten
      Zeichenreferenzen (`priv/html_entities.txt`), auch ohne `;` wie im
      Standard; Rohtext in `script`, `style`, `xmp`, `iframe`,
      `noembed`, `noframes`, `noscript`, Text mit Referenzen in `title`
      und `textarea`, `plaintext`.
    * Baum: `html`, `head` und `body` werden ergänzt; Kopf-Elemente in
      `head`; leere Elemente (`br`, `img`, …); implizites Schließen (`p`,
      `li`, `dt`/`dd`, `option`, Überschriften, Tabellenzellen, …);
      `tbody`/`tr` in Tabellen, fremder Inhalt vor die Tabelle (foster
      parenting); Formatierungselemente mit Wiederherstellen und
      Adoption-Agency-Algorithmus; SVG und MathML mit `/>` und den
      gemischten Groß-/Kleinschreibungen von SVG (`viewBox`,
      `foreignObject`).
    * Ohne Doctype `html` gilt der Quirks-Modus: `<p><table>` lässt die
      Tabelle im Absatz.

  Ergebnis: Liste von `{:el, name, attrs, kinder}`, `{:text, t}`,
  `{:comment, t}`, `{:doctype, name}`; Attribute nach Namen sortiert (wie
  Scryer), das erste von mehreren gleichnamigen gilt.
  """

  # --- Zeichenreferenzen -------------------------------------------------------

  @entities_file Path.join([__DIR__, "..", "..", "..", "priv", "html_entities.txt"])
  @external_resource @entities_file
  @entities (for line <-
                   File.read!(@entities_file)
                   |> String.split("\n", trim: true),
                 not String.starts_with?(line, "#"),
                 into: %{} do
               [name, cps] = String.split(line, "\t")

               {name,
                cps
                |> String.split(" ")
                |> Enum.map(&String.to_integer(&1, 16))
                |> List.to_string()}
             end)

  @win1252 %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }

  @doc false
  # Text mit Zeichenreferenzen auflösen (attr?: Regeln für Attributwerte)
  def decode(text, attr?) do
    if String.contains?(text, "&"), do: decode(text, attr?, []), else: text
  end

  defp decode(<<>>, _attr?, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp decode("&" <> rest, attr?, acc) do
    case char_ref(rest, attr?) do
      {s, rest2} -> decode(rest2, attr?, [s | acc])
      nil -> decode(rest, attr?, ["&" | acc])
    end
  end

  defp decode(text, attr?, acc) do
    case :binary.match(text, "&") do
      {pos, _} ->
        <<plain::binary-size(^pos), rest::binary>> = text
        decode(rest, attr?, [plain | acc])

      :nomatch ->
        decode(<<>>, attr?, [text | acc])
    end
  end

  defp char_ref(<<"#", x, rest::binary>>, _attr?) when x in [?x, ?X] do
    case take_while(rest, &hex?/1) do
      {"", _} -> nil
      {digits, r} -> {num_char(String.to_integer(digits, 16)), drop_semi(r)}
    end
  end

  defp char_ref("#" <> rest, _attr?) do
    case take_while(rest, &(&1 in ?0..?9)) do
      {"", _} -> nil
      {digits, r} -> {num_char(String.to_integer(digits)), drop_semi(r)}
    end
  end

  defp char_ref(rest, attr?) do
    {alnum, r} = take_while(rest, &alnum?/1)
    alnum = binary_part(alnum, 0, min(byte_size(alnum), 40))
    cand = if String.starts_with?(r, ";"), do: alnum <> ";", else: alnum
    named(cand, byte_size(cand), rest, attr?)
  end

  defp named(_cand, 0, _rest, _attr?), do: nil

  defp named(cand, n, rest, attr?) do
    key = binary_part(cand, 0, n)

    case Map.fetch(@entities, key) do
      {:ok, s} ->
        <<_::binary-size(^n), after_ref::binary>> = rest

        if attr? and not String.ends_with?(key, ";") and
             match?(
               <<c, _::binary>> when c == ?= or c in ?0..?9 or c in ?a..?z or c in ?A..?Z,
               after_ref
             ),
           do: nil,
           else: {s, after_ref}

      :error ->
        named(cand, n - 1, rest, attr?)
    end
  end

  defp num_char(n) do
    cond do
      n == 0 or n > 0x10FFFF or n in 0xD800..0xDFFF -> "�"
      Map.has_key?(@win1252, n) -> <<@win1252[n]::utf8>>
      true -> <<n::utf8>>
    end
  end

  defp drop_semi(";" <> r), do: r
  defp drop_semi(r), do: r

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

  defp hex?(c), do: c in ?0..?9 or c in ?a..?f or c in ?A..?F
  defp alnum?(c), do: c in ?0..?9 or c in ?a..?z or c in ?A..?Z
  defp alpha?(c), do: c in ?a..?z or c in ?A..?Z

  # --- Tokenizer -----------------------------------------------------------------

  @ws [?\s, ?\t, ?\n, ?\f]

  # {token, rest} oder :eof; Token {:start, name, attrs, selbstschließend},
  # {:end, name}, {:text, t}, {:comment, t}, {:doctype, name}
  defp token(""), do: :eof

  defp token("<!--" <> rest) do
    case rest do
      ">" <> r ->
        {{:comment, ""}, r}

      "->" <> r ->
        {{:comment, ""}, r}

      _ ->
        case :binary.match(rest, ["-->", "--!>"]) do
          {pos, len} ->
            <<c::binary-size(^pos), _::binary-size(^len), r::binary>> = rest
            {{:comment, c}, r}

          :nomatch ->
            # Dateiende: angefangene Endmarke weg ("-", "--", "--!")
            c =
              cond do
                String.ends_with?(rest, "--!") -> String.slice(rest, 0..-4//1)
                String.ends_with?(rest, "--") -> String.slice(rest, 0..-3//1)
                String.ends_with?(rest, "-") -> String.slice(rest, 0..-2//1)
                true -> rest
              end

            {{:comment, c}, ""}
        end
    end
  end

  defp token(<<"<!", d, o, c, t, y, p, e, rest::binary>> = all) do
    if String.downcase(<<d, o, c, t, y, p, e>>) == "doctype" do
      {body, r} = until_gt(rest)
      name = body |> String.trim_leading() |> String.split(~r/[\t\n\f ]/, parts: 2) |> hd()
      {{:doctype, String.downcase(name, :ascii)}, r}
    else
      bogus_comment(binary_part(all, 2, byte_size(all) - 2))
    end
  end

  defp token("<!" <> rest), do: bogus_comment(rest)
  defp token("<?" <> _ = all), do: bogus_comment(binary_part(all, 1, byte_size(all) - 1))

  defp token(<<"</", c, _::binary>> = all) do
    rest = binary_part(all, 2, byte_size(all) - 2)

    cond do
      alpha?(c) ->
        {name, r} = tag_name(rest)
        {_attrs, _self, r} = attrs(r, [])
        if r == :eof, do: {{:text, ""}, ""}, else: {{:end, name}, r}

      c == ?> ->
        {{:text, ""}, binary_part(rest, 1, byte_size(rest) - 1)}

      true ->
        bogus_comment(rest)
    end
  end

  defp token("</"), do: {{:text, "</"}, ""}

  defp token(<<"<", c, _::binary>> = all) when c in ?a..?z or c in ?A..?Z do
    {name, r} = tag_name(binary_part(all, 1, byte_size(all) - 1))
    {attrs, self?, r} = attrs(r, [])
    if r == :eof, do: {{:text, ""}, ""}, else: {{:start, name, attrs, self?}, r}
  end

  defp token("<" <> rest), do: {{:text, "<"}, rest}

  defp token(text) do
    case :binary.match(text, "<") do
      {pos, _} ->
        <<t::binary-size(^pos), r::binary>> = text
        {{:text, decode(t, false)}, r}

      :nomatch ->
        {{:text, decode(text, false)}, ""}
    end
  end

  defp bogus_comment(rest) do
    {body, r} = until_gt(rest)
    {{:comment, body}, r}
  end

  defp until_gt(rest) do
    case :binary.split(rest, ">") do
      [body, r] -> {body, r}
      [body] -> {body, ""}
    end
  end

  defp tag_name(bin) do
    {name, r} = take_while(bin, &(&1 not in [?\s, ?\t, ?\n, ?\f, ?/, ?>]))
    {String.downcase(name, :ascii), r}
  end

  # Attribute bis ">": {attrs (erstes gilt), selbstschließend?, rest | :eof}
  defp attrs(<<c, r::binary>>, acc) when c in @ws, do: attrs(r, acc)
  defp attrs("/>" <> r, acc), do: {Enum.reverse(acc), true, r}
  defp attrs(">" <> r, acc), do: {Enum.reverse(acc), false, r}
  defp attrs("/" <> r, acc), do: attrs(r, acc)
  defp attrs("", acc), do: {Enum.reverse(acc), false, :eof}

  defp attrs(<<c, r0::binary>> = bin, acc) do
    {name, r} =
      if c == ?= do
        {n, r} = take_while(r0, &(&1 not in [?\s, ?\t, ?\n, ?\f, ?/, ?>, ?=]))
        {"=" <> n, r}
      else
        take_while(bin, &(&1 not in [?\s, ?\t, ?\n, ?\f, ?/, ?>, ?=]))
      end

    name = String.downcase(name, :ascii)
    {_, r} = take_while(r, &(&1 in @ws))

    {value, r} =
      case r do
        "=" <> r2 ->
          {_, r2} = take_while(r2, &(&1 in @ws))
          attr_value(r2)

        _ ->
          {"", r}
      end

    acc = if List.keymember?(acc, name, 0), do: acc, else: [{name, value} | acc]
    if r == :eof, do: {Enum.reverse(acc), false, :eof}, else: attrs(r, acc)
  end

  defp attr_value(<<q, r::binary>>) when q in [?", ?'] do
    case :binary.split(r, <<q>>) do
      [v, r2] -> {decode(v, true), r2}
      [_] -> {"", :eof}
    end
  end

  defp attr_value(r) do
    {v, r2} = take_while(r, &(&1 not in [?\s, ?\t, ?\n, ?\f, ?>]))
    {decode(v, true), r2}
  end

  # Rohtext bis zum End-Tag `</name` (Groß/klein egal) vor Leerraum, / oder >
  defp raw_text(input, "script"), do: script_text(input, 0, :data)

  defp raw_text(input, name) do
    re = Regex.compile!("</" <> Regex.escape(name) <> "[\\t\\n\\f />]", "i")

    case Regex.run(re, input, return: :index) do
      [{pos, _}] -> split_at(input, pos)
      nil -> {input, ""}
    end
  end

  # Skriptdaten mit den Zuständen „escaped“ (nach <!--) und „double
  # escaped“ (nach <script darin): dort beendet </script> das Skript nicht
  # bzw. erst nach -->
  defp script_text(input, i, state) do
    case input do
      <<_::binary-size(^i)>> ->
        {input, ""}

      <<_::binary-size(^i), "</", rest::binary>> ->
        cond do
          script_tag?(rest) and state != :double -> split_at(input, i)
          script_tag?(rest) -> script_text(input, i + 8, :escaped)
          true -> script_text(input, i + 2, state)
        end

      <<_::binary-size(^i), "<!--", _::binary>> when state == :data ->
        # "<!-->" und "<!--->" kehren sofort zurück
        j = skip_dashes(input, i + 4)

        case input do
          <<_::binary-size(^j), ">", _::binary>> -> script_text(input, j + 1, :data)
          _ -> script_text(input, j, :escaped)
        end

      <<_::binary-size(^i), "<", rest::binary>> when state == :escaped ->
        if script_tag?(rest),
          do: script_text(input, i + 7, :double),
          else: script_text(input, i + 1, state)

      <<_::binary-size(^i), "-->", _::binary>> when state != :data ->
        script_text(input, i + 3, :data)

      _ ->
        script_text(input, i + 1, state)
    end
  end

  defp skip_dashes(input, j) do
    case input do
      <<_::binary-size(^j), "-", _::binary>> -> skip_dashes(input, j + 1)
      _ -> j
    end
  end

  defp script_tag?(<<s::binary-size(6), c, _::binary>>),
    do: String.downcase(s, :ascii) == "script" and c in [?\t, ?\n, ?\f, ?\s, ?/, ?>]

  defp script_tag?(_), do: false

  # --- Baum --------------------------------------------------------------------------

  @doc "HTML-Text parsen: Liste der Knoten auf oberster Ebene"
  def parse(text) do
    text =
      text
      |> String.replace_prefix("﻿", "")
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.replace("\0", "")

    st = %{
      nodes: %{0 => %{t: :doc, kids: []}},
      next: 1,
      stack: [0],
      afe: [],
      mode: :initial,
      html: nil,
      head: nil,
      body: nil,
      quirks: false,
      skip_nl: false,
      raw: nil,
      foster: false,
      form: nil,
      tmpl: [],
      frameset_ok: true,
      table_text: nil
    }

    st = run(text, st)
    st = finish(st)
    out(st, 0)
  end

  defp run(input, %{raw: {kind, name}} = st) do
    {t, rest} = raw_text(input, name)
    t = if kind == :rcdata, do: decode(t, false), else: t
    t = if st.skip_nl, do: String.replace_prefix(t, "\n", ""), else: t
    st = %{st | raw: nil, skip_nl: false}
    st = if t == "", do: st, else: insert_text(st, t, false)
    # das End-Tag schließt das Element
    rest =
      case token(rest) do
        {{:end, _}, r} -> r
        _ -> rest
      end

    run(rest, pop(st))
  end

  # plaintext: der Rest ist Text (mit Wiederherstellen der Formatierung)
  defp run(input, %{raw: :plaintext} = st),
    do: if(input == "", do: st, else: in_body({:text, input}, st))

  # CDATA-Abschnitt in SVG/MathML: Text
  defp run("<![CDATA[" <> rest = input, st) do
    if foreign?(cur_name(st)) do
      {data, r} =
        case :binary.split(rest, "]]>") do
          [d, r] -> {d, r}
          [d] -> {d, ""}
        end

      st = if data == "", do: st, else: handle({:text, data}, st)
      run(r, st)
    else
      run_token(input, st)
    end
  end

  defp run(input, st), do: run_token(input, st)

  defp run_token(input, st) do
    case token(input) do
      :eof ->
        flush_table_text(st)

      {{:text, ""}, rest} ->
        run(rest, st)

      {{:text, _} = tok, rest} ->
        run(rest, handle(tok, st))

      {tok, rest} ->
        # ein Zeilenwechsel nach <pre> zählt nur direkt danach
        st = %{flush_table_text(st) | skip_nl: false}
        run(rest, handle(tok, st))
    end
  end

  # Text in Tabellen wird gesammelt und als Ganzes entschieden: nur
  # Leerraum bleibt in der Tabelle, sonst kommt alles davor
  defp flush_table_text(%{table_text: nil} = st), do: st

  defp flush_table_text(st) do
    t = IO.iodata_to_binary(st.table_text)
    st = %{st | table_text: nil}
    if blank?(t), do: insert_text(st, t, false), else: foster({:text, t}, st)
  end

  # --- Knoten ---------------------------------------------------------------------

  defp node(st, id), do: Map.fetch!(st.nodes, id)
  defp put_node(st, id, n), do: %{st | nodes: Map.put(st.nodes, id, n)}

  defp new_node(st, n) do
    id = st.next
    {id, %{st | nodes: Map.put(st.nodes, id, Map.put(n, :kids, [])), next: id + 1}}
  end

  defp current(st), do: node(st, hd(st.stack))
  defp cur_name(st), do: name_of(current(st))

  defp name_of(%{t: :el, ns: :html, name: n}), do: n
  defp name_of(%{t: :el, ns: ns, name: n}), do: {ns, n}
  defp name_of(_), do: nil

  defp html_el?(st, id, names), do: name_of(node(st, id)) in names

  # Kind am Ende von parent anhängen (Text an vorherigen Text)
  defp append(st, parent, id) do
    p = node(st, parent)
    put_node(st, parent, %{p | kids: [id | p.kids]}) |> set_parent(id, parent)
  end

  defp set_parent(st, id, parent), do: put_node(st, id, Map.put(node(st, id), :parent, parent))

  defp detach(st, id) do
    case Map.get(node(st, id), :parent) do
      nil ->
        st

      p ->
        pn = node(st, p)
        put_node(st, p, %{pn | kids: List.delete(pn.kids, id)})
    end
  end

  # Kind in parent vor before einfügen
  defp insert_before(st, parent, before, id) do
    p = node(st, parent)
    # kids sind umgekehrt: „vor before“ heißt in der Liste dahinter
    {a, b} = Enum.split_while(p.kids, &(&1 != before))
    kids = a ++ [before, id | tl(b)]
    put_node(st, parent, %{p | kids: kids}) |> set_parent(id, parent)
  end

  # Einfügeort: {parent, before | nil}; foster: vor die Tabelle
  defp place(st, foster?) do
    cur = hd(st.stack)

    if (foster? or st.foster) and html_el?(st, cur, ~w(table tbody tfoot thead tr)) do
      tmpl = Enum.find_index(st.stack, &html_el?(st, &1, ["template"]))
      table_i = Enum.find_index(st.stack, &html_el?(st, &1, ["table"]))

      case if(tmpl != nil and (table_i == nil or tmpl < table_i),
             do: :template,
             else: table_i && Enum.at(st.stack, table_i)
           ) do
        :template ->
          {content(st, Enum.at(st.stack, tmpl)), nil}

        nil ->
          {content(st, cur), nil}

        table ->
          case Map.get(node(st, table), :parent) do
            nil ->
              [_ | above] = Enum.drop_while(st.stack, &(&1 != table))
              {hd(above), nil}

            p ->
              {p, table}
          end
      end
    else
      {content(st, cur), nil}
    end
  end

  # in ein template-Element kommt der Inhalt in sein Fragment
  defp content(st, id) do
    case node(st, id) do
      %{t: :el, name: "template", ns: :html, frag: f} -> f
      _ -> id
    end
  end

  defp insert_at(st, {parent, nil}, id), do: append(st, parent, id)
  defp insert_at(st, {parent, before}, id), do: insert_before(st, parent, before, id)

  defp insert_text(st, text, foster?) do
    {parent, before} = place(st, foster?)
    p = node(st, parent)

    prev =
      case before do
        nil -> List.first(p.kids)
        b -> p.kids |> Enum.drop_while(&(&1 != b)) |> Enum.at(1)
      end

    case prev && node(st, prev) do
      %{t: :text, text: t0} = n ->
        put_node(st, prev, %{n | text: t0 <> text})

      _ ->
        {id, st} = new_node(st, %{t: :text, text: text})
        insert_at(st, {parent, before}, id)
    end
  end

  defp insert_comment(st, parent, text) do
    {id, st} = new_node(st, %{t: :comment, text: text})
    append(st, content(st, parent), id)
  end

  defp create(st, name, attrs, ns), do: new_node(st, %{t: :el, name: name, attrs: attrs, ns: ns})

  # Element einfügen und auf den Stapel legen
  defp insert_el(st, name, attrs, ns \\ :html, foster? \\ false) do
    {id, st} = create(st, name, attrs, ns)
    st = insert_at(st, place(st, foster?), id)
    {id, %{st | stack: [id | st.stack]}}
  end

  defp insert_el!(st, name, attrs), do: st |> insert_el(name, attrs) |> elem(1)

  defp insert_void(st, name, attrs, foster? \\ false) do
    {id, st} = create(st, name, attrs, :html)
    insert_at(st, place(st, foster?), id)
  end

  defp pop(%{stack: [_ | rest]} = st) when rest != [], do: %{st | stack: rest}
  defp pop(st), do: st

  defp pop_until(st, names) do
    case st.stack do
      [0] ->
        st

      [id | _] ->
        st = pop(st)
        if html_el?(st, id, names), do: st, else: pop_until(st, names)
    end
  end

  defp merge_attrs(st, nil, _attrs), do: st

  defp merge_attrs(st, id, attrs) do
    n = node(st, id)
    new = for {k, v} <- attrs, not List.keymember?(n.attrs, k, 0), do: {k, v}
    put_node(st, id, %{n | attrs: n.attrs ++ new})
  end

  # --- Bereiche (scope) ----------------------------------------------------------

  @scope_base ~w(applet caption html table td th marquee object template) ++
                [
                  {:math, "mi"},
                  {:math, "mo"},
                  {:math, "mn"},
                  {:math, "ms"},
                  {:math, "mtext"},
                  {:svg, "foreignObject"},
                  {:svg, "desc"},
                  {:svg, "title"}
                ]

  defp in_scope?(st, targets, kind \\ :default) do
    boundary =
      case kind do
        :default -> @scope_base
        :button -> ["button" | @scope_base]
        :list -> ["ol", "ul" | @scope_base]
        :table -> ~w(html table template)
        :select -> :select
      end

    Enum.reduce_while(st.stack, false, fn id, _ ->
      n = name_of(node(st, id))

      cond do
        n in targets -> {:halt, true}
        boundary == :select and n not in ["optgroup", "option"] -> {:halt, false}
        is_list(boundary) and n in boundary -> {:halt, false}
        true -> {:cont, false}
      end
    end)
  end

  @implied ~w(dd dt li optgroup option p rb rp rt rtc)

  defp implied_end(st, except \\ nil) do
    n = cur_name(st)
    if n in @implied and n != except, do: st |> pop() |> implied_end(except), else: st
  end

  defp close_p(st) do
    if in_scope?(st, ["p"], :button), do: st |> implied_end("p") |> pop_until(["p"]), else: st
  end

  # wie html5ever nur HTML-Elemente (die Liste der Spezifikation hat auch
  # mi, mo, …, foreignObject, desc, title)
  @special ~w(address applet area article aside base basefont bgsound blockquote body br button
              caption center col colgroup dd details dir div dl dt embed fieldset figcaption figure
              footer form frame frameset h1 h2 h3 h4 h5 h6 head header hgroup hr html iframe img
              input isindex keygen li link listing main marquee menu meta nav noembed noframes noscript
              object ol p param plaintext pre script section select source style summary
              table tbody td template textarea tfoot th thead title tr track ul wbr xmp)

  defp special?(st, id), do: name_of(node(st, id)) in @special

  # --- Formatierungselemente ---------------------------------------------------

  @formatting ~w(a b big code em font i nobr s small strike strong tt u)

  # mit „Noah's Ark“: höchstens drei gleiche Einträge (Name und Attribute)
  # nach der letzten Marke, sonst fällt der früheste weg
  defp push_afe(st, id) do
    n = node(st, id)
    key = {n.name, Enum.sort(n.attrs)}
    {recent, older} = Enum.split_while(st.afe, &(&1 != :marker))

    same =
      for {{eid, name, attrs}, i} <- Enum.with_index(recent),
          {name, Enum.sort(attrs)} == key,
          do: {eid, i}

    recent =
      if length(same) >= 3 do
        {_, i} = List.last(same)
        List.delete_at(recent, i)
      else
        recent
      end

    %{st | afe: [{id, n.name, n.attrs} | recent ++ older]}
  end

  defp push_marker(st), do: %{st | afe: [:marker | st.afe]}

  defp clear_afe_to_marker(%{afe: [:marker | rest]} = st), do: %{st | afe: rest}
  defp clear_afe_to_marker(%{afe: [_ | rest]} = st), do: clear_afe_to_marker(%{st | afe: rest})
  defp clear_afe_to_marker(st), do: st

  # Eintrag mit Namen name nach der letzten Marke
  defp afe_find(st, name) do
    Enum.find_value(Enum.take_while(st.afe, &(&1 != :marker)), fn
      {id, ^name, _} -> id
      _ -> nil
    end)
  end

  defp afe_remove(st, id), do: %{st | afe: Enum.reject(st.afe, &match?({^id, _, _}, &1))}

  defp reconstruct(st) do
    todo =
      Enum.take_while(st.afe, fn
        :marker -> false
        {id, _, _} -> id not in st.stack
      end)

    if todo == [] do
      st
    else
      Enum.reduce(Enum.reverse(todo), st, fn {old, name, attrs}, st ->
        {id, st} = insert_el(st, name, attrs)

        afe =
          Enum.map(st.afe, fn
            {^old, n, a} -> {id, n, a}
            e -> e
          end)

        %{st | afe: afe}
      end)
    end
  end

  # Adoption-Agency-Algorithmus (HTML5 13.2.6.4.7, vereinfacht in der
  # äußeren Schleife)
  defp adoption(st, subject) do
    cur = hd(st.stack)

    if cur_name(st) == subject and not Enum.any?(st.afe, &match?({^cur, _, _}, &1)) do
      pop(st)
    else
      adoption_loop(st, subject, 0)
    end
  end

  defp adoption_loop(st, _subject, 8), do: st

  defp adoption_loop(st, subject, outer) do
    case afe_find(st, subject) do
      nil ->
        any_other_end(st, subject)

      fe ->
        cond do
          fe not in st.stack ->
            afe_remove(st, fe)

          not in_scope?(st, [subject]) ->
            st

          true ->
            # Stapel von oben bis fe (ohne): Kandidaten für furthest block
            above = Enum.take_while(st.stack, &(&1 != fe))
            fb = above |> Enum.reverse() |> Enum.find(&special?(st, &1))

            if fb == nil do
              st = %{st | stack: tl(Enum.drop_while(st.stack, &(&1 != fe)))}
              afe_remove(st, fe)
            else
              st |> adopt(fe, fb) |> adoption_loop(subject, outer + 1)
            end
        end
    end
  end

  defp adopt(st, fe, fb) do
    [_ | below_fe] = Enum.drop_while(st.stack, &(&1 != fe))
    common = hd(below_fe)
    bookmark = {:replace, fe}

    # innere Schleife: Knoten zwischen fb und fe
    fb_pos = Enum.find_index(st.stack, &(&1 == fb))
    {st, last, bookmark} = inner(st, fe, fb, fb, fb_pos + 1, 0, bookmark)

    st = detach(st, last)

    st =
      if html_el?(st, common, ~w(table tbody tfoot thead tr)),
        do: insert_at(st, place(%{st | stack: [common | st.stack]}, true), last),
        else: append(st, content(st, common), last)

    {_, name, attrs} = Enum.find(st.afe, &match?({^fe, _, _}, &1))
    {new, st} = create(st, name, attrs, :html)
    fbn = node(st, fb)
    kids = fbn.kids

    st =
      Enum.reduce(Enum.reverse(kids), put_node(st, fb, %{fbn | kids: []}), fn k, st ->
        append(st, new, k)
      end)

    st = append(st, fb, new)

    # Liste: new an die Lesezeichen-Stelle (statt fe oder neuer als der
    # Knoten), fe entfernen
    afe =
      case bookmark do
        {:replace, ^fe} ->
          Enum.map(st.afe, fn
            {^fe, _, _} -> {new, name, attrs}
            e -> e
          end)

        {:after, b} ->
          i = Enum.find_index(st.afe, &match?({^b, _, _}, &1))

          st.afe
          |> List.insert_at(i, {new, name, attrs})
          |> Enum.reject(&match?({^fe, _, _}, &1))
      end

    # Stapel: fe entfernen, new direkt über fb (tiefer im Baum)
    stack = List.delete(st.stack, fe)
    i = Enum.find_index(stack, &(&1 == fb))
    stack = List.insert_at(stack, i, new)
    %{st | afe: afe, stack: stack}
  end

  defp inner(st, fe, fb, last, pos, counter, bookmark) do
    node_id = Enum.at(st.stack, pos)

    if node_id == fe or node_id == nil do
      {st, last, bookmark}
    else
      counter = counter + 1
      in_afe = Enum.find(st.afe, &match?({^node_id, _, _}, &1))

      st = if counter > 3 and in_afe, do: afe_remove(st, node_id), else: st
      in_afe = if counter > 3, do: nil, else: in_afe

      if in_afe == nil do
        st = %{st | stack: List.delete(st.stack, node_id)}
        inner(st, fe, fb, last, pos, counter, bookmark)
      else
        {_, name, attrs} = in_afe
        {new, st} = create(st, name, attrs, :html)

        afe =
          Enum.map(st.afe, fn
            {^node_id, n, a} -> {new, n, a}
            e -> e
          end)

        stack = Enum.map(st.stack, &if(&1 == node_id, do: new, else: &1))
        st = %{st | afe: afe, stack: stack}

        bookmark = if last == fb, do: {:after, new}, else: bookmark

        st = st |> detach(last) |> append(new, last)
        inner(st, fe, fb, new, pos + 1, counter, bookmark)
      end
    end
  end

  defp any_other_end(st, name) do
    Enum.reduce_while(st.stack, st, fn id, st0 ->
      cond do
        id == 0 ->
          {:halt, st0}

        html_el?(st0, id, [name]) ->
          st1 = implied_end(st0, name)
          st1 = %{st1 | stack: tl(Enum.drop_while(st1.stack, &(&1 != id)))}
          {:halt, st1}

        special?(st0, id) ->
          {:halt, st0}

        true ->
          {:cont, st0}
      end
    end)
  end

  # --- Einfügemodi -------------------------------------------------------------------

  defp split_ws(t) do
    {ws, rest} = take_while(t, &(&1 in @ws or &1 == ?\r))
    {ws, rest}
  end

  defp ensure_html(%{html: nil} = st) do
    {id, st} = insert_el(st, "html", [])
    %{st | html: id}
  end

  defp ensure_html(st), do: st

  defp mode_handle(tok, %{mode: :initial} = st) do
    case tok do
      {:text, t} ->
        case split_ws(t) do
          {_, ""} -> st
          {_, rest} -> handle({:text, rest}, %{st | mode: :before_html, quirks: true})
        end

      {:comment, c} ->
        insert_comment(st, 0, c)

      {:doctype, name} ->
        {id, st} = new_node(st, %{t: :doctype, text: name})
        st = append(st, 0, id)
        %{st | mode: :before_html, quirks: name != "html"}

      _ ->
        handle(tok, %{st | mode: :before_html, quirks: true})
    end
  end

  defp mode_handle(tok, %{mode: :before_html} = st) do
    case tok do
      {:doctype, _} ->
        st

      {:comment, c} ->
        insert_comment(st, 0, c)

      {:text, t} ->
        case split_ws(t) do
          {_, ""} -> st
          {_, rest} -> handle({:text, rest}, %{ensure_html(st) | mode: :before_head})
        end

      {:start, "html", attrs, _} ->
        {id, st} = insert_el(st, "html", attrs)
        %{st | html: id, mode: :before_head}

      {:end, n} when n not in ~w(head body html br) ->
        st

      _ ->
        handle(tok, %{ensure_html(st) | mode: :before_head})
    end
  end

  defp mode_handle(tok, %{mode: :before_head} = st) do
    case tok do
      {:text, t} ->
        case split_ws(t) do
          {_, ""} -> st
          {_, rest} -> handle({:text, rest}, open_head(st, []))
        end

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:doctype, _} ->
        st

      {:start, "html", attrs, _} ->
        merge_attrs(st, st.html, attrs)

      {:start, "head", attrs, _} ->
        open_head(st, attrs)

      {:end, n} when n not in ~w(head body html br) ->
        st

      _ ->
        handle(tok, open_head(st, []))
    end
  end

  defp mode_handle(tok, %{mode: :in_head} = st) do
    case tok do
      {:text, t} ->
        case split_ws(t) do
          {ws, ""} ->
            insert_text(st, ws, false)

          {ws, rest} ->
            st = if ws == "", do: st, else: insert_text(st, ws, false)
            handle({:text, rest}, close_head(st))
        end

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:doctype, _} ->
        st

      {:start, "html", attrs, _} ->
        merge_attrs(st, st.html, attrs)

      {:start, n, attrs, _}
      when n in ~w(base basefont bgsound link meta title noscript noframes style script template) ->
        head_element(st, n, attrs)

      {:start, "head", _, _} ->
        st

      {:end, "head"} ->
        close_head(st)

      {:end, "template"} ->
        close_template(st)

      {:end, n} when n not in ~w(body html br) ->
        st

      _ ->
        handle(tok, close_head(st))
    end
  end

  defp mode_handle(tok, %{mode: :after_head} = st) do
    case tok do
      {:text, t} ->
        case split_ws(t) do
          {ws, ""} ->
            insert_text(st, ws, false)

          {ws, rest} ->
            st = if ws == "", do: st, else: insert_text(st, ws, false)
            handle({:text, rest}, open_body(st, []))
        end

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:doctype, _} ->
        st

      {:start, "html", attrs, _} ->
        merge_attrs(st, st.html, attrs)

      {:start, "body", attrs, _} ->
        open_body(st, attrs)

      {:start, "frameset", attrs, _} ->
        {_, st} = insert_el(st, "frameset", attrs)
        %{st | mode: :in_frameset}

      {:start, n, attrs, _}
      when n in ~w(base basefont bgsound link meta noframes script style template title) ->
        # in den schon geschlossenen Kopf
        in_head_of(st, n, attrs)

      {:start, "head", _, _} ->
        st

      {:end, n} when n not in ~w(body html br) ->
        st

      _ ->
        handle(tok, open_body(st, []))
    end
  end

  defp mode_handle(tok, %{mode: :in_frameset} = st) do
    case tok do
      {:text, t} ->
        ws = for <<c <- t>>, c in @ws, into: "", do: <<c>>
        if ws == "", do: st, else: insert_text(st, ws, false)

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:start, "frameset", attrs, _} ->
        insert_el!(st, "frameset", attrs)

      {:start, "frame", attrs, _} ->
        insert_void(st, "frame", attrs)

      {:start, "noframes", attrs, _} ->
        head_element(st, "noframes", attrs)

      {:start, "html", _, _} ->
        in_body(tok, st)

      {:end, "frameset"} ->
        if cur_name(st) == "html" do
          st
        else
          st = pop(st)
          if cur_name(st) == "frameset", do: st, else: %{st | mode: :after_frameset}
        end

      _ ->
        st
    end
  end

  defp mode_handle(tok, %{mode: mode} = st)
       when mode in [:after_frameset, :after_after_frameset] do
    case tok do
      {:text, t} ->
        ws = for <<c <- t>>, c in @ws, into: "", do: <<c>>

        cond do
          ws == "" -> st
          mode == :after_frameset -> insert_text(st, ws, false)
          true -> in_body({:text, ws}, st)
        end

      {:comment, c} ->
        insert_comment(st, if(mode == :after_frameset, do: hd(st.stack), else: 0), c)

      {:start, "html", _, _} ->
        in_body(tok, st)

      {:start, "noframes", attrs, _} ->
        head_element(st, "noframes", attrs)

      {:end, "html"} when mode == :after_frameset ->
        %{st | mode: :after_after_frameset}

      _ ->
        st
    end
  end

  defp mode_handle(tok, %{mode: :after_body} = st) do
    case tok do
      {:text, t} ->
        case split_ws(t) do
          {_, ""} -> in_body(tok, st)
          _ -> body(tok, %{st | mode: :in_body})
        end

      {:comment, c} ->
        insert_comment(st, st.html, c)

      {:doctype, _} ->
        st

      {:start, "html", attrs, _} ->
        merge_attrs(st, st.html, attrs)

      {:end, "html"} ->
        %{st | mode: :after_after_body}

      _ ->
        handle(tok, %{st | mode: :in_body})
    end
  end

  defp mode_handle(tok, %{mode: :after_after_body} = st) do
    case tok do
      {:comment, c} ->
        insert_comment(st, 0, c)

      {:doctype, _} ->
        st

      {:text, t} ->
        case split_ws(t) do
          {_, ""} -> in_body(tok, st)
          _ -> body(tok, %{st | mode: :in_body})
        end

      {:start, "html", attrs, _} ->
        merge_attrs(st, st.html, attrs)

      _ ->
        handle(tok, %{st | mode: :in_body})
    end
  end

  defp mode_handle(tok, st), do: by_mode(tok, st)

  # Verteiler (HTML5 13.2.6): ist der aktuelle Knoten fremd (SVG, MathML),
  # gelten – außer an Integrationspunkten – die Regeln für fremden Inhalt,
  # in jedem Einfügemodus
  defp handle(tok, st), do: body(tok, st)

  defp open_head(st, attrs) do
    {id, st} = insert_el(st, "head", attrs)
    %{st | head: id, mode: :in_head}
  end

  defp close_head(st) do
    st = if cur_name(st) == "head", do: pop(st), else: st
    %{st | mode: :after_head}
  end

  defp open_body(st, attrs) do
    {id, st} = insert_el(st, "body", attrs)
    %{st | body: id, mode: :in_body}
  end

  # Elemente des Kopfs (auch im Rumpf an der aktuellen Stelle)
  defp head_element(st, n, attrs) do
    cond do
      n in ~w(base basefont bgsound link meta) ->
        insert_void(st, n, attrs)

      n == "title" ->
        %{insert_el!(st, n, attrs) | raw: {:rcdata, n}}

      n in ~w(noscript noframes style script) ->
        %{insert_el!(st, n, attrs) | raw: {:rawtext, n}}

      n == "template" ->
        {id, st} = insert_el(st, n, attrs)
        open_template(st, id)

      true ->
        insert_el!(st, n, attrs)
    end
  end

  # template: Fragment für den Inhalt, Marke, eigener Einfügemodus
  defp open_template(st, id) do
    st = %{st | frameset_ok: false}
    {frag, st} = new_node(st, %{t: :fragment})
    st = append(st, id, frag)
    st = put_node(st, id, Map.put(node(st, id), :frag, frag))
    %{push_marker(st) | mode: :in_template, tmpl: [:in_template | st.tmpl]}
  end

  @thorough ~w(caption colgroup dd dt li optgroup option p rb rp rt rtc tbody td tfoot th thead tr)

  defp close_template(st) do
    if Enum.any?(st.stack, &html_el?(st, &1, ["template"])) do
      st = implied_thorough(st)
      st = pop_until(st, ["template"]) |> clear_afe_to_marker()
      reset_mode(%{st | tmpl: Enum.drop(st.tmpl, 1)})
    else
      st
    end
  end

  defp implied_thorough(st) do
    if cur_name(st) in @thorough, do: st |> pop() |> implied_thorough(), else: st
  end

  defp template_open?(st), do: Enum.any?(st.stack, &html_el?(st, &1, ["template"]))

  # Einfügemodus „in template“
  defp template(tok, st) do
    case tok do
      {tag, _} when tag in [:text, :comment, :doctype] ->
        in_body(tok, st)

      {:start, n, attrs, _}
      when n in ~w(base basefont bgsound link meta noframes script style template title) ->
        head_element(st, n, attrs)

      {:end, "template"} ->
        close_template(st)

      {:start, n, _, _} ->
        mode =
          cond do
            n in ~w(caption colgroup tbody tfoot thead) -> :in_table
            n == "col" -> :in_column_group
            n == "tr" -> :in_table_body
            n in ~w(td th) -> :in_row
            true -> :in_body
          end

        handle(tok, %{st | mode: mode, tmpl: [mode | Enum.drop(st.tmpl, 1)]})

      {:end, _} ->
        st
    end
  end

  defp in_head_of(st, n, attrs) do
    {id, st} = create(st, n, attrs, :html)
    st = append(st, st.head, id)

    cond do
      n == "template" -> open_template(%{st | stack: [id | st.stack]}, id)
      n in ~w(base basefont bgsound link meta) -> st
      n == "title" -> %{st | stack: [id | st.stack], raw: {:rcdata, n}}
      n in ~w(noframes style script) -> %{st | stack: [id | st.stack], raw: {:rawtext, n}}
      true -> %{st | stack: [id | st.stack]}
    end
  end

  # --- Rumpf ---------------------------------------------------------------------

  @p_closers ~w(address article aside blockquote center details dialog dir div dl fieldset
                figcaption figure footer header hgroup main menu nav ol p search section summary ul)
  @headings ~w(h1 h2 h3 h4 h5 h6)
  @table_ctx ~w(table tbody tfoot thead tr)
  @cells ~w(td th)

  defp body(tok, st) do
    cn = cur_name(st)

    html? =
      case html_rules_in_foreign?(cn, tok) do
        # scrapers TreeSink kennt keine annotation-xml-Integrationspunkte
        :annotation -> false
        b -> b
      end

    if foreign?(cn) and not html?,
      do: foreign(tok, st),
      else: mode_handle(tok, st)
  end

  # nach den Regeln des Einfügemodus (für HTML-Inhalt)
  defp by_mode(tok, st) do
    case st.mode do
      m when m in [:in_table, :in_table_body, :in_row] -> table(tok, st)
      :in_column_group -> colgroup(tok, st)
      :in_cell -> if cell_token?(tok), do: cell(tok, st), else: in_body(tok, st)
      :in_caption -> if caption_token?(tok), do: caption(tok, st), else: in_body(tok, st)
      m when m in [:in_select, :in_select_in_table] -> select(tok, st)
      :in_template -> template(tok, st)
      :in_body -> in_body(tok, st)
      _ -> mode_handle(tok, st)
    end
  end

  # Einfügemodus nach dem Stapel (HTML5: „reset the insertion mode
  # appropriately“)
  defp reset_mode(st), do: reset_mode(st, st.stack)

  defp reset_mode(st, [id | rest]) do
    last? = rest == [0] or rest == []

    case name_of(node(st, id)) do
      "select" ->
        if Enum.any?(rest, &html_el?(st, &1, ["table"])),
          do: %{st | mode: :in_select_in_table},
          else: %{st | mode: :in_select}

      n when n in ["td", "th"] and not last? ->
        %{st | mode: :in_cell}

      "tr" ->
        %{st | mode: :in_row}

      n when n in ~w(tbody thead tfoot) ->
        %{st | mode: :in_table_body}

      "caption" ->
        %{st | mode: :in_caption}

      "colgroup" ->
        %{st | mode: :in_column_group}

      "table" ->
        %{st | mode: :in_table}

      "body" ->
        %{st | mode: :in_body}

      "frameset" ->
        %{st | mode: :in_frameset}

      "template" ->
        %{st | mode: List.first(st.tmpl, :in_body)}

      "head" when not last? ->
        %{st | mode: :in_head}

      "html" ->
        %{st | mode: if(st.head == nil, do: :before_head, else: :after_head)}

      _ ->
        if last?, do: %{st | mode: :in_body}, else: reset_mode(st, rest)
    end
  end

  defp reset_mode(st, []), do: %{st | mode: :in_body}

  # wie im Rumpf, aber mit foster parenting
  defp foster(tok, st), do: %{in_body(tok, %{st | foster: true}) | foster: false}

  defp foreign?({_, _}), do: true
  defp foreign?(_), do: false

  # Integrationspunkte: darin gelten die HTML-Regeln
  # an HTML-Integrationspunkten: Start-Tags und Text nach HTML-Regeln,
  # End-Tags nach denen für fremden Inhalt
  defp html_rules_in_foreign?({:svg, n}, tok) when n in ["foreignObject", "desc", "title"],
    do: match?({:text, _}, tok) or match?({:start, _, _, _}, tok)

  defp html_rules_in_foreign?({:math, n}, tok) when n in ~w(mi mo mn ms mtext),
    do:
      match?({:text, _}, tok) or
        (match?({:start, _, _, _}, tok) and elem(tok, 1) not in ["mglyph", "malignmark"])

  defp html_rules_in_foreign?({:math, "annotation-xml"}, tok) do
    case tok do
      {:start, "svg", _, _} -> true
      {:start, _, _, _} -> :annotation
      {:text, _} -> :annotation
      _ -> false
    end
  end

  defp html_rules_in_foreign?(_, _), do: false

  defp cell_token?({:start, n, _, _}),
    do: n in ~w(caption col colgroup tbody td tfoot th thead tr)

  defp cell_token?({:end, n}),
    do: n in ~w(td th table tbody tfoot thead tr body caption col colgroup html)

  defp cell_token?(_), do: false

  defp caption_token?({:start, n, _, _}),
    do: n in ~w(caption col colgroup tbody td tfoot th thead tr)

  defp caption_token?({:end, n}),
    do: n in ~w(caption table body col colgroup html tbody td tfoot th thead tr)

  defp caption_token?(_), do: false

  defp blank?(t), do: t |> String.to_charlist() |> Enum.all?(&(&1 in @ws))

  defp hidden?(attrs),
    do: Enum.any?(attrs, fn {k, v} -> k == "type" and String.downcase(v, :ascii) == "hidden" end)

  defp in_body(tok, st) do
    case tok do
      {:text, t} ->
        {t, st} =
          if st.skip_nl and String.starts_with?(t, "\n"),
            do: {binary_part(t, 1, byte_size(t) - 1), %{st | skip_nl: false}},
            else: {t, %{st | skip_nl: false}}

        st = if blank?(t), do: st, else: %{st | frameset_ok: false}
        if t == "", do: st, else: st |> reconstruct() |> insert_text(t, false)

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:doctype, _} ->
        st

      {:start, n, attrs, self?} ->
        start(%{st | skip_nl: false}, n, attrs, self?)

      {:end, n} ->
        stop(%{st | skip_nl: false}, n)
    end
  end

  defp start(st, n, attrs, self?) do
    st =
      if n in ~w(pre listing li dd dt button applet marquee object table area br embed img
                  keygen wbr hr textarea xmp iframe select) or
           (n == "input" and not hidden?(attrs)),
         do: %{st | frameset_ok: false},
         else: st

    cond do
      n == "html" ->
        if template_open?(st), do: st, else: merge_attrs(st, st.html, attrs)

      n in ~w(base basefont bgsound link meta noframes script style template title) ->
        head_element(st, n, attrs)

      n == "body" ->
        body = Enum.at(st.stack, -3)

        if body != nil and html_el?(st, body, ["body"]) and not template_open?(st),
          do: %{merge_attrs(st, body, attrs) | frameset_ok: false},
          else: st

      n == "frameset" ->
        body = Enum.at(st.stack, -3)

        if st.frameset_ok and body != nil and html_el?(st, body, ["body"]) do
          st = detach(st, body)
          st = %{st | stack: Enum.take(st.stack, -2)}
          %{insert_el!(st, "frameset", attrs) | mode: :in_frameset}
        else
          st
        end

      n in @p_closers ->
        st |> close_p() |> insert_el!(n, attrs)

      n in @headings ->
        st = close_p(st)
        st = if cur_name(st) in @headings, do: pop(st), else: st
        insert_el!(st, n, attrs)

      n in ["pre", "listing"] ->
        %{(st |> close_p() |> insert_el!(n, attrs)) | skip_nl: true}

      n == "form" ->
        if st.form do
          st
        else
          {id, st} = st |> close_p() |> insert_el(n, attrs)
          %{st | form: id}
        end

      n == "li" ->
        st |> close_list_item(["li"]) |> close_p() |> insert_el!(n, attrs)

      n in ["dd", "dt"] ->
        st |> close_list_item(["dd", "dt"]) |> close_p() |> insert_el!(n, attrs)

      n == "plaintext" ->
        %{(st |> close_p() |> insert_el!(n, attrs)) | raw: :plaintext}

      n == "button" ->
        st =
          if in_scope?(st, ["button"]),
            do: st |> implied_end() |> pop_until(["button"]),
            else: st

        st |> reconstruct() |> insert_el!(n, attrs)

      n == "a" ->
        st =
          case afe_find(st, "a") do
            nil ->
              st

            old ->
              st = adoption(st, "a")
              st = afe_remove(st, old)
              %{st | stack: List.delete(st.stack, old)}
          end

        {id, st} = st |> reconstruct() |> insert_el(n, attrs)
        push_afe(st, id)

      n == "nobr" ->
        st = reconstruct(st)
        st = if in_scope?(st, ["nobr"]), do: st |> adoption("nobr") |> reconstruct(), else: st
        {id, st} = insert_el(st, n, attrs)
        push_afe(st, id)

      n in @formatting ->
        {id, st} = st |> reconstruct() |> insert_el(n, attrs)
        push_afe(st, id)

      n in ~w(applet marquee object) ->
        st |> reconstruct() |> insert_el!(n, attrs) |> push_marker()

      n == "table" ->
        st = if st.quirks, do: st, else: close_p(st)
        %{insert_el!(st, n, attrs) | mode: :in_table}

      n in ~w(area br embed img keygen wbr input) ->
        st |> reconstruct() |> insert_void(n, attrs)

      n in ~w(param source track) ->
        insert_void(st, n, attrs)

      n == "hr" ->
        st |> close_p() |> insert_void(n, attrs)

      n == "image" ->
        st |> reconstruct() |> insert_void("img", attrs)

      n == "textarea" ->
        %{insert_el!(st, n, attrs) | raw: {:rcdata, n}, skip_nl: true}

      n == "xmp" ->
        %{(st |> close_p() |> reconstruct() |> insert_el!(n, attrs)) | raw: {:rawtext, n}}

      n in ~w(iframe noembed noscript) ->
        %{insert_el!(st, n, attrs) | raw: {:rawtext, n}}

      n == "select" ->
        mode =
          if st.mode in [:in_table, :in_caption, :in_table_body, :in_row, :in_cell],
            do: :in_select_in_table,
            else: :in_select

        %{(st |> reconstruct() |> insert_el!(n, attrs)) | mode: mode}

      n in ["optgroup", "option"] ->
        st = if cur_name(st) == "option", do: pop(st), else: st
        st |> reconstruct() |> insert_el!(n, attrs)

      n in ["rb", "rtc"] ->
        st = if in_scope?(st, ["ruby"]), do: implied_end(st), else: st
        insert_el!(st, n, attrs)

      n in ["rp", "rt"] ->
        st = if in_scope?(st, ["ruby"]), do: implied_end(st, "rtc"), else: st
        insert_el!(st, n, attrs)

      n in ["svg", "math"] ->
        ns = String.to_atom(n)
        # wie html5ever: ohne Wiederherstellen der Formatierung
        {_, st} = insert_el(st, n, foreign_attrs(attrs, ns), ns)
        if self?, do: pop(st), else: st

      n in ~w(caption col colgroup frame head tbody td tfoot th thead tr) ->
        st

      true ->
        st |> reconstruct() |> insert_el!(n, attrs)
    end
  end

  defp close_list_item(st, names) do
    Enum.reduce_while(st.stack, st, fn id, st0 ->
      cond do
        id == 0 ->
          {:halt, st0}

        html_el?(st0, id, names) ->
          n = name_of(node(st0, id))
          {:halt, st0 |> implied_end(n) |> pop_until([n])}

        special?(st0, id) and not html_el?(st0, id, ~w(address div p)) ->
          {:halt, st0}

        true ->
          {:cont, st0}
      end
    end)
  end

  defp stop(st, n) do
    cond do
      n == "template" ->
        close_template(st)

      n in ["body", "html"] ->
        if in_scope?(st, ["body"]) do
          st = %{st | mode: :after_body}
          if n == "html", do: %{st | mode: :after_after_body}, else: st
        else
          st
        end

      n in ((@p_closers -- ["p"]) ++ ~w(button listing pre)) ->
        if in_scope?(st, [n]), do: st |> implied_end() |> pop_until([n]), else: st

      n == "form" ->
        form = st.form
        st = %{st | form: nil}

        if form != nil and form in st.stack and in_scope?(st, ["form"]) do
          st = implied_end(st)
          %{st | stack: List.delete(st.stack, form)}
        else
          st
        end

      n == "p" ->
        st = if in_scope?(st, ["p"], :button), do: st, else: insert_el!(st, "p", [])
        st |> implied_end("p") |> pop_until(["p"])

      n == "li" ->
        if in_scope?(st, ["li"], :list),
          do: st |> implied_end("li") |> pop_until(["li"]),
          else: st

      n in ["dd", "dt"] ->
        if in_scope?(st, [n]), do: st |> implied_end(n) |> pop_until([n]), else: st

      n in @headings ->
        if in_scope?(st, @headings), do: st |> implied_end() |> pop_until(@headings), else: st

      n in @formatting ->
        adoption(st, n)

      n in ~w(applet marquee object) ->
        if in_scope?(st, [n]),
          do: st |> implied_end() |> pop_until([n]) |> clear_afe_to_marker(),
          else: st

      n == "br" ->
        st |> reconstruct() |> insert_void("br", [])

      true ->
        any_other_end(st, n)
    end
  end

  # --- Tabellen --------------------------------------------------------------------

  # Einfügemodi „in table“, „in table body“, „in row“ (HTML5 13.2.6.4.9,
  # .13, .14)
  defp table(tok, %{mode: :in_table_body} = st) do
    case tok do
      {:start, "tr", attrs, _} ->
        %{(st |> clear_to(~w(tbody tfoot thead)) |> insert_el!("tr", attrs)) | mode: :in_row}

      {:start, n, _, _} when n in @cells ->
        st = st |> clear_to(~w(tbody tfoot thead)) |> insert_el!("tr", [])
        handle(tok, %{st | mode: :in_row})

      {:end, n} when n in ~w(tbody tfoot thead) ->
        if in_scope?(st, [n], :table),
          do: %{(st |> clear_to(~w(tbody tfoot thead)) |> pop()) | mode: :in_table},
          else: st

      {tag, n, _, _} when tag == :start and n in ~w(caption col colgroup tbody tfoot thead) ->
        close_section(tok, st)

      {:end, "table"} ->
        close_section(tok, st)

      {:end, n} when n in ~w(body caption col colgroup html td th tr) ->
        st

      _ ->
        in_table(tok, st)
    end
  end

  defp table(tok, %{mode: :in_row} = st) do
    case tok do
      {:start, n, attrs, _} when n in @cells ->
        st = st |> clear_to(["tr"]) |> insert_el!(n, attrs) |> push_marker()
        %{st | mode: :in_cell}

      {:end, "tr"} ->
        if in_scope?(st, ["tr"], :table), do: close_row(st), else: st

      {:start, n, _, _} when n in ~w(caption col colgroup tbody tfoot thead tr) ->
        if in_scope?(st, ["tr"], :table), do: handle(tok, close_row(st)), else: st

      {:end, "table"} ->
        if in_scope?(st, ["tr"], :table), do: handle(tok, close_row(st)), else: st

      {:end, n} when n in ~w(tbody tfoot thead) ->
        cond do
          not in_scope?(st, [n], :table) -> st
          not in_scope?(st, ["tr"], :table) -> st
          true -> handle(tok, close_row(st))
        end

      {:end, n} when n in ~w(body caption col colgroup html td th) ->
        st

      _ ->
        in_table(tok, st)
    end
  end

  defp table(tok, st), do: in_table(tok, st)

  defp close_section(tok, st) do
    if in_scope?(st, ~w(tbody thead tfoot), :table),
      do: handle(tok, %{(st |> clear_to(~w(tbody tfoot thead)) |> pop()) | mode: :in_table}),
      else: st
  end

  defp close_row(st), do: %{(st |> clear_to(["tr"]) |> pop()) | mode: :in_table_body}

  defp in_table(tok, st) do
    case tok do
      {:text, t} ->
        if cur_name(st) in @table_ctx or cur_name(st) == "template" do
          %{st | table_text: [st.table_text || [], t]}
        else
          foster(tok, st)
        end

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:doctype, _} ->
        st

      {:start, "caption", attrs, _} ->
        st = st |> clear_to(["table"]) |> insert_el!("caption", attrs) |> push_marker()
        %{st | mode: :in_caption}

      {:start, "colgroup", attrs, _} ->
        %{(st |> clear_to(["table"]) |> insert_el!("colgroup", attrs)) | mode: :in_column_group}

      {:start, "col", _, _} ->
        handle(tok, %{
          (st
           |> clear_to(["table"])
           |> insert_el!("colgroup", []))
          | mode: :in_column_group
        })

      {:start, n, attrs, _} when n in ~w(tbody tfoot thead) ->
        %{(st |> clear_to(["table"]) |> insert_el!(n, attrs)) | mode: :in_table_body}

      {:start, n, _, _} when n in ~w(td th tr) ->
        handle(tok, %{
          (st
           |> clear_to(["table"])
           |> insert_el!("tbody", []))
          | mode: :in_table_body
        })

      {:start, "table", _, _} ->
        if in_scope?(st, ["table"], :table),
          do: handle(tok, st |> pop_until(["table"]) |> reset_mode()),
          else: st

      {:start, n, attrs, _} when n in ~w(style script template) ->
        head_element(st, n, attrs)

      {:start, "input", attrs, _} ->
        if Enum.any?(attrs, fn {k, v} ->
             k == "type" and String.downcase(v, :ascii) == "hidden"
           end),
           do: insert_void(st, "input", attrs),
           else: foster(tok, st)

      {:start, "form", attrs, _} ->
        if st.form != nil or template_open?(st) do
          st
        else
          {id, st} = insert_el(st, "form", attrs)
          %{pop(st) | form: id}
        end

      {:start, _, _, _} ->
        foster(tok, st)

      {:end, "template"} ->
        close_template(st)

      {:end, "table"} ->
        if in_scope?(st, ["table"], :table),
          do: st |> pop_until(["table"]) |> reset_mode(),
          else: st

      {:end, n} when n in ~w(body caption col colgroup html tbody td tfoot th thead tr) ->
        st

      {:end, _} ->
        foster(tok, st)
    end
  end

  defp colgroup(tok, st) do
    case tok do
      {:text, t} ->
        case split_ws(t) do
          {ws, ""} ->
            insert_text(st, ws, false)

          {ws, rest} ->
            st = if ws == "", do: st, else: insert_text(st, ws, false)
            colgroup_else({:text, rest}, st)
        end

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:start, "col", attrs, _} ->
        insert_void(st, "col", attrs)

      {:start, "template", attrs, _} ->
        head_element(st, "template", attrs)

      {:end, "template"} ->
        close_template(st)

      {:end, "colgroup"} ->
        if cur_name(st) == "colgroup", do: %{pop(st) | mode: :in_table}, else: st

      {:end, "col"} ->
        st

      _ ->
        colgroup_else(tok, st)
    end
  end

  defp colgroup_else(tok, st) do
    if cur_name(st) == "colgroup", do: handle(tok, %{pop(st) | mode: :in_table}), else: st
  end

  # Tabellenkontext: bis eines der Elemente oben liegt
  defp clear_to(st, names) do
    if cur_name(st) in names or cur_name(st) in ["html", "template"] or hd(st.stack) == 0,
      do: st,
      else: clear_to(pop(st), names)
  end

  defp cell(tok, st) do
    case tok do
      {:end, n} when n in @cells ->
        if in_scope?(st, [n], :table), do: close_cell(st), else: st

      {:end, n} when n in ~w(table tbody tfoot thead tr) ->
        if in_scope?(st, [n], :table), do: handle(tok, close_cell(st)), else: st

      {:start, _, _, _} ->
        if in_scope?(st, @cells, :table), do: handle(tok, close_cell(st)), else: st

      {:end, _} ->
        st
    end
  end

  defp close_cell(st) do
    %{(st |> implied_end() |> pop_until(@cells) |> clear_afe_to_marker()) | mode: :in_row}
  end

  defp caption({:end, n}, st) when n not in ["caption", "table"], do: st

  defp caption(tok, st) do
    if in_scope?(st, ["caption"], :table) do
      st = st |> implied_end() |> pop_until(["caption"]) |> clear_afe_to_marker()
      st = %{st | mode: :in_table}

      case tok do
        {:end, "caption"} -> st
        _ -> handle(tok, st)
      end
    else
      st
    end
  end

  # --- select ------------------------------------------------------------------------

  defp select(tok, st) do
    case tok do
      {:text, t} ->
        insert_text(st, t, false)

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:start, "option", attrs, _} ->
        st = if cur_name(st) == "option", do: pop(st), else: st
        insert_el!(st, "option", attrs)

      {:start, "optgroup", attrs, _} ->
        st = if cur_name(st) == "option", do: pop(st), else: st
        st = if cur_name(st) == "optgroup", do: pop(st), else: st
        insert_el!(st, "optgroup", attrs)

      {:start, "hr", attrs, _} ->
        st = if cur_name(st) == "option", do: pop(st), else: st
        st = if cur_name(st) == "optgroup", do: pop(st), else: st
        insert_void(st, "hr", attrs)

      {:start, "select", _, _} ->
        close_select(st)

      {:start, n, _, _} when n in ~w(input keygen textarea) ->
        if in_scope?(st, ["select"], :select), do: handle(tok, close_select(st)), else: st

      {:start, n, _, _}
      when st.mode == :in_select_in_table and n in ~w(caption table tbody tfoot thead tr td th) ->
        handle(tok, close_select(st))

      {:end, n}
      when st.mode == :in_select_in_table and n in ~w(caption table tbody tfoot thead tr td th) ->
        if in_scope?(st, [n], :table), do: handle(tok, close_select(st)), else: st

      {:start, n, attrs, _} when n in ~w(script template) ->
        head_element(st, n, attrs)

      {:end, "optgroup"} ->
        st =
          case st.stack do
            [o, g | _] ->
              if html_el?(st, o, ["option"]) and html_el?(st, g, ["optgroup"]),
                do: pop(st),
                else: st

            _ ->
              st
          end

        if cur_name(st) == "optgroup", do: pop(st), else: st

      {:end, "option"} ->
        if cur_name(st) == "option", do: pop(st), else: st

      {:end, "template"} ->
        close_template(st)

      {:end, "select"} ->
        if in_scope?(st, ["select"], :select), do: close_select(st), else: st

      _ ->
        st
    end
  end

  defp close_select(st), do: st |> pop_until(["select"]) |> reset_mode()

  # --- SVG und MathML ------------------------------------------------------------

  @breakout ~w(b big blockquote body br center code dd div dl dt em embed h1 h2 h3 h4 h5 h6
               head hr i img li listing menu meta nobr ol p pre ruby s small span strong strike
               sub sup table tt u ul var)

  defp foreign(tok, st) do
    {ns, _} = cur_name(st)

    case tok do
      {:text, t} ->
        insert_text(st, t, false)

      {:comment, c} ->
        insert_comment(st, hd(st.stack), c)

      {:start, n, attrs, self?} ->
        if n in @breakout or
             (n == "font" and Enum.any?(attrs, fn {k, _} -> k in ~w(color face size) end)) do
          # nach den Regeln des Einfügemodus (HTML-Inhalt)
          by_mode(tok, pop_foreign(st))
        else
          name = if ns == :svg, do: svg_name(n), else: n
          # im fremden Inhalt gilt der Namensraum des aktuellen Knotens
          {_, st} = insert_el(st, name, foreign_attrs(attrs, ns), ns)
          if self?, do: pop(st), else: st
        end

      {:end, n} when n in ["br", "p"] ->
        by_mode(tok, pop_foreign(st))

      {:end, n} ->
        foreign_end(st, st.stack, n)

      _ ->
        st
    end
  end

  defp pop_foreign(st) do
    case current(st) do
      %{t: :el, ns: :html} ->
        st

      n ->
        if name_of(n) in [{:svg, "foreignObject"}, {:svg, "desc"}, {:svg, "title"}] or
             name_of(n) in [
               {:math, "mi"},
               {:math, "mo"},
               {:math, "mn"},
               {:math, "ms"},
               {:math, "mtext"}
             ],
           do: st,
           else: pop_foreign(pop(st))
    end
  end

  defp foreign_end(st, [id | rest], n) do
    case node(st, id) do
      %{t: :el, ns: :html} ->
        by_mode({:end, n}, st)

      %{t: :el, name: name} ->
        if String.downcase(name, :ascii) == n,
          do: %{st | stack: rest},
          else: foreign_end(st, rest, n)

      _ ->
        st
    end
  end

  defp foreign_end(st, [], _), do: st

  @svg_tags ~w(altGlyph altGlyphDef altGlyphItem animateColor animateMotion animateTransform
               clipPath feBlend feColorMatrix feComponentTransfer feComposite feConvolveMatrix
               feDiffuseLighting feDisplacementMap feDistantLight feDropShadow feFlood feFuncA
               feFuncB feFuncG feFuncR feGaussianBlur feImage feMerge feMergeNode feMorphology
               feOffset fePointLight feSpecularLighting feSpotLight feTile feTurbulence
               foreignObject glyphRef linearGradient radialGradient textPath)
            |> Map.new(&{String.downcase(&1), &1})

  @svg_attrs ~w(attributeName attributeType baseFrequency baseProfile calcMode clipPathUnits
                diffuseConstant edgeMode filterUnits glyphRef gradientTransform gradientUnits
                kernelMatrix kernelUnitLength keyPoints keySplines keyTimes lengthAdjust
                limitingConeAngle markerHeight markerUnits markerWidth maskContentUnits maskUnits
                numOctaves pathLength patternContentUnits patternTransform patternUnits pointsAtX
                pointsAtY pointsAtZ preserveAlpha preserveAspectRatio primitiveUnits refX refY
                repeatCount repeatDur requiredExtensions requiredFeatures specularConstant
                specularExponent spreadMethod startOffset stdDeviation stitchTiles surfaceScale
                systemLanguage tableValues targetX targetY textLength viewBox viewTarget
                xChannelSelector yChannelSelector zoomAndPan)
             |> Map.new(&{String.downcase(&1), &1})

  @ns_uri %{
    "xlink" => "http://www.w3.org/1999/xlink",
    "xml" => "http://www.w3.org/XML/1998/namespace",
    "xmlns" => "http://www.w3.org/2000/xmlns/"
  }

  defp svg_name(n), do: Map.get(@svg_tags, n, n)

  defp foreign_attrs(attrs, ns) do
    for {k, v} <- attrs do
      k =
        cond do
          ns == :svg and Map.has_key?(@svg_attrs, k) -> @svg_attrs[k]
          ns == :math and k == "definitionurl" -> "definitionURL"
          true -> k
        end

      # xlink:href, xml:lang, xmlns, xmlns:xlink: Namensraum und lokaler
      # Name wie html5ever (ausgegeben wird der lokale Name, sortiert nach
      # Präfix, Namensraum, Name)
      k =
        case String.split(k, ":", parts: 2) do
          [p, l] when p in ["xlink", "xml", "xmlns"] -> {:q, 1, p, @ns_uri[p], l}
          ["xmlns"] -> {:q, 0, "", @ns_uri["xmlns"], "xmlns"}
          _ -> k
        end

      {k, v}
    end
  end

  # --- Ende und Ausgabe --------------------------------------------------------------

  defp finish(st) do
    st = if st.html == nil, do: ensure_html(%{st | stack: [0]}), else: st

    st =
      if st.head == nil do
        {id, st} = create(st, "head", [], :html)
        st = %{st | head: id}
        html = node(st, st.html)
        put_node(st, st.html, %{html | kids: [id | html.kids]}) |> set_parent(id, st.html)
      else
        st
      end

    has_frameset =
      Enum.any?(node(st, st.html).kids, &match?(%{t: :el, name: "frameset"}, node(st, &1)))

    if st.body == nil and not has_frameset do
      {id, st} = create(st, "body", [], :html)
      append(%{st | body: id}, st.html, id)
    else
      st
    end
  end

  defp attr_key({:q, flag, p, ns, l}), do: {flag, p, ns, l}
  defp attr_key(k), do: {0, "", "", k}

  defp attr_name({:q, _, _, _, l}), do: l
  defp attr_name(k), do: k

  defp out(st, id) do
    node(st, id).kids
    |> Enum.reverse()
    |> Enum.map(fn k ->
      case node(st, k) do
        %{t: :el, name: n, attrs: a} ->
          attrs =
            a
            |> Enum.sort_by(&attr_key(elem(&1, 0)))
            |> Enum.map(fn {k, v} -> {attr_name(k), v} end)

          {:el, n, attrs, out(st, k)}

        %{t: :text, text: t} ->
          {:text, t}

        %{t: :fragment} ->
          {:fragment, out(st, k)}

        %{t: :comment, text: t} ->
          {:comment, t}

        %{t: :doctype, text: t} ->
          {:doctype, t}
      end
    end)
  end
end
