defmodule PrologEx.Sgml do
  @moduledoc """
  Kern von `library(sgml)` (`priv/library/sgml.pl`): Dokumente als Terme
  wie bei Scryer Prolog (Parser in `PrologEx.Sgml.Xml` und
  `PrologEx.Sgml.Html`) und `xml_write/3`, `html_write/3` wie SWI-Prologs
  `library(sgml_write)`.

  Terme: `element(Name, [Attr=Wert, …], Kinder)`, Text, bei HTML auch
  `comment(T)` und `doctype(T)`. Text und Attributwerte sind wie bei
  Scryer Zeichenlisten; die Optionen `cdata(Typ)` und
  `attribute_value(Typ)` (wie SWI) wählen `atom`, `chars`, `codes` oder
  `string` (ohne eigenen Stringtyp: nach `double_quotes`). `space(Modus)`
  wie SWI: `preserve` (Vorgabe, wie Scryer), `sgml` (leere Texte fallen
  weg, ein Zeilenwechsel direkt nach dem Start- und vor dem End-Tag
  auch), `default` (dazu Leerraum zu einem Leerzeichen) und `remove`
  (dazu am Anfang und Ende weg).
  """
  import PrologEx, only: [a: 1, mk: 2]
  alias PrologEx.{Error, Sgml}

  # --- Laden ---------------------------------------------------------------------

  @doc "Text laden: Liste von Termen oder :fail (XML nicht wohlgeformt)"
  def load(kind, text, opts) do
    o = load_options(opts)

    nodes =
      case kind do
        :xml ->
          case Sgml.Xml.parse(text) do
            {:ok, root} -> [root]
            :error -> :fail
          end

        :html ->
          Sgml.Html.parse(text)
      end

    case nodes do
      :fail -> :fail
      _ -> nodes |> space(o.space, false) |> Enum.map(&term(&1, o))
    end
  end

  defp load_options(opts) do
    Enum.reduce(opts, %{cdata: :chars, attr: :chars, space: :preserve}, fn
      {:struct, "cdata", [{:atom, t}]}, o ->
        %{o | cdata: text_type!(t, "cdata")}

      {:struct, "attribute_value", [{:atom, t}]}, o ->
        %{o | attr: text_type!(t, "attribute_value")}

      {:struct, "space", [{:atom, m}]}, o ->
        %{o | space: space_mode!(m)}

      _, o ->
        o
    end)
  end

  defp text_type!(t, _) when t in ~w(atom chars codes), do: String.to_atom(t)

  defp text_type!("string", _) do
    case PrologEx.Flags.get("double_quotes") do
      {:atom, "codes"} -> :codes
      {:atom, "atom"} -> :atom
      _ -> :chars
    end
  end

  defp text_type!(t, opt), do: Error.domain!(opt, a(t))

  defp space_mode!(m) when m in ~w(preserve sgml default remove), do: String.to_atom(m)
  defp space_mode!(m), do: Error.domain!("space", a(m))

  defp text(:chars, ""), do: []
  defp text(:chars, s), do: for(c <- String.codepoints(s), do: {:atom, c})
  defp text(:codes, s), do: String.to_charlist(s)
  defp text(:atom, s), do: {:atom, s}

  defp term({:el, name, attrs, kids}, o) do
    mk("element", [
      a(name),
      for({k, v} <- attrs, do: mk("=", [a(k), text(o.attr, v)])),
      Enum.map(kids, &term(&1, o))
    ])
  end

  defp term({:text, t}, o), do: text(o.cdata, t)
  defp term({:comment, t}, o), do: mk("comment", [text(o.cdata, t)])
  defp term({:doctype, t}, o), do: mk("doctype", [text(o.cdata, t)])
  defp term({:other}, _o), do: mk("element", [a(""), [], []])

  # Leerraum wie SWIs space/1 (in Elementen)
  defp space(nodes, :preserve, _in_el?), do: nodes

  defp space(nodes, mode, in_el?) do
    nodes =
      Enum.map(nodes, fn
        {:el, n, at, kids} -> {:el, n, at, space(kids, mode, true)}
        other -> other
      end)

    nodes = if in_el?, do: trim_edge_newlines(nodes), else: nodes

    Enum.flat_map(nodes, fn
      {:text, t} ->
        cond do
          blank?(t) -> []
          mode == :sgml -> [{:text, t}]
          mode == :default -> [{:text, collapse(t)}]
          mode == :remove -> [{:text, t |> collapse() |> String.trim()}]
        end

      other ->
        [other]
    end)
  end

  defp trim_edge_newlines(nodes) do
    nodes =
      case nodes do
        [{:text, "\n" <> t} | rest] -> [{:text, t} | rest]
        _ -> nodes
      end

    case Enum.reverse(nodes) do
      [{:text, t} | rest] -> Enum.reverse([{:text, String.replace_suffix(t, "\n", "")} | rest])
      _ -> nodes
    end
  end

  defp collapse(t), do: String.replace(t, ~r/[ \t\n\r]+/, " ")

  # --- Schreiben (SWIs sgml_write) --------------------------------------------------

  @doc """
  DOM schreiben wie SWIs `xml_write/3` (dialect :xml) bzw. `html_write/3`
  (:html); col0: Spalte des Streams. `{:ok, iodata}` oder
  `{:error, bis_dahin, ausnahme, stacktrace}`
  """
  def write(dialect, dom, opts, col0) do
    st = write_options(dialect, opts)
    out = {[], col0 == 0}

    try do
      out =
        if dialect == :xml and st.header,
          do: emit_raw(out, ~s(<?xml version="1.0" encoding="UTF-8"?>\n\n)),
          else: out

      out = doctype(out, dom, opts)
      out = if st.indent > 0, do: emit_indent(out, st.indent), else: out
      {acc, _} = emit(dom, out, st)
      {:ok, acc}
    rescue
      e in Error ->
        {acc, _} = Process.delete(:prolog_ex_sgml_partial) || {[], true}
        {:error, acc, e, __STACKTRACE__}
    after
      Process.delete(:prolog_ex_sgml_partial)
    end
  end

  defp partial(out), do: Process.put(:prolog_ex_sgml_partial, out)

  defp write_options(dialect, opts) do
    st0 = %{
      dialect: dialect,
      indent: 0,
      layout: true,
      header: true,
      cleanns: true,
      nsmap: [],
      net: dialect == :xml
    }

    Enum.reduce(opts, st0, fn
      {:struct, "indent", [n]}, st when is_integer(n) ->
        %{st | indent: n}

      {:struct, "layout", [{:atom, b}]}, st when b in ["true", "false"] ->
        %{st | layout: b == "true"}

      {:struct, "header", [{:atom, b}]}, st when b in ["true", "false"] ->
        %{st | header: b == "true"}

      {:struct, "cleanns", [{:atom, b}]}, st when b in ["true", "false"] ->
        %{st | cleanns: b == "true"}

      {:struct, "net", [{:atom, b}]}, st when b in ["true", "false"] ->
        %{st | net: b == "true"}

      {:struct, "nsmap", [m]}, st ->
        %{st | nsmap: nsmap_list(m)}

      {:struct, n, [_]}, st when n in ~w(dtd doctype public system) ->
        st

      o, _ ->
        Error.domain!("xml_write_option", o)
    end)
  end

  defp nsmap_list(l) when is_list(l) do
    for {:struct, "=", [ns, uri]} <- l, do: {ns, uri}
  end

  defp nsmap_list(_), do: []

  defp doctype(out, dom, opts) do
    html_version =
      Enum.find_value(List.wrap(top_list(dom)), fn
        {:struct, "element", [{:atom, "html"}, atts, _]} when is_list(atts) ->
          Enum.find_value(atts, fn
            {:struct, "=", [{:atom, "version"}, v]} -> v
            _ -> nil
          end)

        _ ->
          nil
      end)

    opt = fn name ->
      Enum.find_value(opts, fn
        {:struct, ^name, [v]} -> v
        _ -> nil
      end)
    end

    cond do
      html_version ->
        emit_raw(out, "<!DOCTYPE HTML PUBLIC \"#{plain(html_version)}\">\n\n")

      opt.("public") || opt.("system") || opt.("doctype") ->
        dt =
          case top_list(dom) do
            {:struct, "element", [n, _, _]} ->
              n

            l when is_list(l) ->
              Enum.find_value(l, fn
                {:struct, "element", [n, _, _]} -> n
                _ -> nil
              end) || opt.("doctype")

            _ ->
              opt.("doctype")
          end

        case dt do
          nil ->
            out

          dt ->
            dt = plain(dt)

            text =
              case {opt.("public"), opt.("system")} do
                {nil, nil} -> "<!DOCTYPE #{dt} []>"
                {nil, s} -> "<!DOCTYPE #{dt} SYSTEM \"#{plain(s)}\">"
                {p, nil} -> "<!DOCTYPE #{dt} PUBLIC \"#{plain(p)}\">"
                {p, s} -> "<!DOCTYPE #{dt} PUBLIC \"#{plain(p)}\" \"#{plain(s)}\">"
              end

            emit_raw(out, text <> "\n\n")
        end

      true ->
        out
    end
  end

  defp top_list(dom), do: dom

  # Ausgabe {iodata, am Zeilenanfang?}
  defp emit_raw(out, ""), do: out
  defp emit_raw({acc, _}, text), do: {[acc | text], String.ends_with?(text, "\n")}

  defp emit_indent({_, bol} = out, indent) do
    out = if bol, do: out, else: emit_raw(out, "\n")
    emit_raw(out, String.duplicate("\t", div(indent, 8)) <> String.duplicate(" ", rem(indent, 8)))
  end

  defp write_indent(out, %{layout: false}), do: out
  defp write_indent(out, st), do: emit_indent(out, st.indent)

  defp emit({:var, _}, out, _st) do
    partial(out)
    Error.instantiation!()
  end

  defp emit([], out, _st), do: out

  defp emit([h | t], out, st) do
    if text?([h | t]) do
      content_text(out, [h | t], st)
    else
      out = emit(h, out, st)
      emit(t, out, st)
    end
  end

  defp emit({:atom, _} = t, out, st), do: content_text(out, t, st)
  defp emit(n, out, _st) when is_number(n), do: emit_raw(out, plain(n))

  defp emit({:struct, "element", [name, atts, kids]}, out, st),
    do: element(name, atts, kids, out, st)

  defp emit({:struct, "pi", [pi]}, out, st) do
    out = emit_raw(out, "<?" <> escape(text_of(pi), ""))
    emit_raw(out, if(st.dialect == :xml, do: "?>", else: ">"))
  end

  defp emit(e, out, _st) do
    partial(out)
    Error.type!("xml_dom", e)
  end

  defp element(name, atts, kids, out, st) do
    atts = list!(atts, out)
    kids = list!(kids, out)

    {write_atts, st} =
      if st.dialect == :xml do
        {clean, map} = update_nsmap(atts, st.nsmap)
        {if(st.cleanns, do: clean, else: atts), %{st | nsmap: map}}
      else
        {atts, st}
      end

    alen = Enum.reduce(write_atts, 0, fn at, acc -> acc + 1 + att_len(at, st) end)

    {sep, att_st} =
      if alen > 60 and st.layout, do: {:nl, %{st | indent: st.indent + 4}}, else: {:sp, st}

    out = emit_raw(out, "<" <> name_text(name, st))

    out =
      Enum.reduce(write_atts, out, fn at, out ->
        out = if sep == :nl, do: write_indent(out, att_st), else: emit_raw(out, " ")
        attribute(at, out, st)
      end)

    content(kids, out, name, st)
  end

  defp list!(l, out) when is_list(l) do
    if proper?(l), do: l, else: list_err(l, out)
  end

  defp list!(l, out), do: list_err(l, out)

  defp list_err({:var, _}, out) do
    partial(out)
    Error.instantiation!()
  end

  defp list_err(l, out) do
    partial(out)
    Error.type!("list", l)
  end

  defp proper?([]), do: true
  defp proper?([_ | t]), do: proper?(t)
  defp proper?(_), do: false

  defp attribute({:struct, "=", [n, v]}, out, st) do
    out = emit_raw(out, name_text(n, st) <> "=")

    val =
      cond do
        text?(v) -> escape(text_of(v), "\"<&\r\n\t")
        is_list(v) -> Enum.map_join(v, " ", &escape(text_of(&1), "\"<&\r\n\t"))
        is_number(v) -> plain(v)
        true -> attr_type_error(v, out)
      end

    emit_raw(out, "\"" <> val <> "\"")
  end

  defp attribute(a, out, _st) do
    partial(out)
    Error.type!("xml_dom", a)
  end

  defp attr_type_error(v, out) do
    partial(out)
    Error.type!("sgml_attribute_value", v)
  end

  defp att_len({:struct, "=", [n, v]}, st) do
    nl =
      case n do
        {:struct, ":", [{:struct, "ns", [ns, _]}, l]} ->
          String.length(plain(ns)) + String.length(plain(l))

        {:struct, ":", [uri, l]} ->
          ns_len(uri, st) + String.length(plain(l))

        _ ->
          String.length(plain(n))
      end

    vl =
      cond do
        text?(v) ->
          String.length(text_of(v))

        is_list(v) ->
          v
          |> Enum.map(&String.length(text_of(&1)))
          |> Enum.sum()
          |> Kernel.+(max(length(v) - 1, 0))

        true ->
          String.length(plain(v))
      end

    nl + vl + 3
  end

  defp att_len(_, _), do: 0

  defp ns_len(uri, st) do
    case Enum.find(st.nsmap, fn {_, u} -> u == uri end) do
      {ns, _} -> String.length(plain(ns))
      nil -> String.length(plain(uri))
    end
  end

  defp content([], out, name, st) do
    cond do
      st.net and st.dialect == :xml -> emit_raw(out, "/>")
      st.net and empty_element?(name, st) -> emit_raw(out, ">")
      st.net -> emit_raw(out, "//")
      empty_element?(name, st) -> emit_raw(out, ">")
      true -> out |> emit_raw(">") |> close(name, st)
    end
  end

  defp content([single], out, name, st) when not is_tuple(single) or elem(single, 0) == :atom do
    if atomic_text?(single) do
      if verbatim?(name, st) do
        out |> emit_raw(">") |> emit_raw(text_of(single)) |> close(name, st)
      else
        out |> emit_raw(">") |> content_text(single, st) |> close(name, st)
      end
    else
      content_general([single], out, name, st)
    end
  end

  defp content(kids, out, name, st), do: content_general(kids, out, name, st)

  defp content_general(kids, out, name, st) do
    if st.layout and element_content?(kids) and not preserve_space?(kids) do
      out = emit_raw(out, ">")
      inner = %{st | indent: st.indent + 2}

      out =
        kids
        |> Enum.filter(&match?({:struct, "element", _}, &1))
        |> Enum.reduce(out, fn k, out ->
          out |> write_indent(inner) |> then(&emit(k, &1, inner))
        end)

      out |> write_indent(st) |> close(name, st)
    else
      out = emit_raw(out, ">")

      out =
        Enum.reduce(kids, out, fn k, out ->
          cond do
            text?(k) -> content_text(out, k, st)
            match?({:struct, "element", [_, _, _]}, k) -> emit(k, out, st)
            match?({:struct, "pi", [_]}, k) -> emit(k, out, st)
            match?({:var, _}, k) -> emit(k, out, st)
            match?({:struct, "sdata", [_]}, k) -> content_text(out, hd(elem(k, 2)), st)
            true -> type_error_content(k, out)
          end
        end)

      close(out, name, st)
    end
  end

  # xml:space=preserve: Leerraum nicht anfassen (wie SWI, das hier das
  # Element statt seiner Attribute prüft – dort nie wahr; hier auch nicht)
  defp preserve_space?(_kids), do: false

  defp type_error_content(k, out) do
    partial(out)
    Error.type!("sgml_content", k)
  end

  defp element_content?(kids) do
    Enum.all?(kids, fn
      {:struct, "element", [_, _, _]} -> true
      k -> text?(k) and blank?(text_of(k))
    end)
  end

  defp blank?(s),
    do: s |> String.to_charlist() |> Enum.all?(&(&1 in [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]))

  defp close(out, name, st), do: emit_raw(out, "</" <> name_text(name, st) <> ">")

  defp content_text(out, t, _st) do
    if is_number(t), do: emit_raw(out, plain(t)), else: emit_raw(out, escape(text_of(t), "<&>\r"))
  end

  @html_empty ~w(area base basefont br col frame hr img input isindex link meta param)

  defp empty_element?({:atom, n}, %{dialect: :html}), do: n in @html_empty
  defp empty_element?(_, _), do: false

  defp verbatim?({:atom, n}, %{dialect: :html}), do: n in ["script", "style"]
  defp verbatim?(_, _), do: false

  # Text: Atom, Zeichen- oder Codeliste (wie SWIs Strings)
  defp text?({:atom, _}), do: true
  defp text?([]), do: false

  defp text?(l) when is_list(l) do
    proper?(l) and
      (Enum.all?(l, &match?({:atom, <<_::utf8>>}, &1)) or
         Enum.all?(l, &(is_integer(&1) and &1 >= 0 and &1 <= 0x10FFFF)))
  end

  defp text?(_), do: false

  defp atomic_text?(t), do: text?(t) or is_number(t) or t == []

  defp text_of({:atom, s}), do: s
  defp text_of([]), do: ""
  defp text_of(n) when is_number(n), do: plain(n)

  defp text_of(l) when is_list(l) do
    Enum.map_join(l, fn
      {:atom, c} -> c
      c -> <<c::utf8>>
    end)
  end

  defp text_of(t), do: plain(t)

  defp plain({:atom, s}), do: s
  defp plain(t), do: PrologEx.Writer.format(t)

  defp name_text({:atom, n}, _st), do: n

  defp name_text({:struct, ":", [{:struct, "ns", [ns, _uri]}, n]}, _st) do
    if ns == {:atom, ""}, do: plain(n), else: plain(ns) <> ":" <> plain(n)
  end

  defp name_text({:struct, ":", [uri, n]} = t, st) do
    case Enum.find(st.nsmap, fn {_, u} -> u == uri end) do
      {[], _} -> plain(n)
      {ns, _} -> plain(ns) <> ":" <> plain(n)
      nil -> plain(t)
    end
  end

  defp name_text(t, _st), do: plain(t)

  defp update_nsmap(atts, map) do
    {clean, map} =
      Enum.reduce(atts, {[], map}, fn
        {:struct, "=", [{:struct, ":", [{:atom, "xmlns"}, ns]}, uri]} = at, {acc, map} ->
          if {ns, uri} in map, do: {acc, map}, else: {[at | acc], set_ns(map, ns, uri)}

        {:struct, "=", [{:atom, "xmlns"}, uri]} = at, {acc, map} ->
          if {[], uri} in map, do: {acc, map}, else: {[at | acc], set_ns(map, [], uri)}

        at, {acc, map} ->
          {[at | acc], map}
      end)

    {Enum.reverse(clean), map}
  end

  defp set_ns(map, ns, uri), do: [{ns, uri} | Enum.reject(map, fn {n, _} -> n == ns end)]

  # wie SWIs writeq/4 in sgml_write: die Zeichen aus esc als Entität
  defp escape(text, esc) do
    cps = String.codepoints(esc)

    if cps != [] and String.contains?(text, cps) do
      for <<c::utf8 <- text>>, into: "" do
        if <<c::utf8>> in cps, do: entity(c), else: <<c::utf8>>
      end
    else
      text
    end
  end

  defp entity(?<), do: "&lt;"
  defp entity(?>), do: "&gt;"
  defp entity(?&), do: "&amp;"
  defp entity(?"), do: "&quot;"
  defp entity(?'), do: "&apos;"
  defp entity(c), do: "&#x" <> Integer.to_string(c, 16) <> ";"
end
