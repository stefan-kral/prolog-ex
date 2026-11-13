defmodule PrologEx.Json do
  @moduledoc """
  JSON lesen und schreiben wie SWI-Prologs `library(http/json)` in der
  klassischen Darstellung (`json_read/2,3`, `json_write/2,3`,
  `atom_json_term/3`; `priv/library/http/json.pl`):

    * Objekt: `json([Name=Wert, …])`, Name ein Atom (beim Schreiben auch
      `Name-Wert` und `Name(Wert)`);
    * Array: Liste; Zahl: Zahl; String: Atom (Option
      `value_string_as(Typ)`: `atom`, `string` – hier, ohne eigenen
      Stringtyp, eine Zeichen- oder Codeliste wie `"…"` nach dem Flag
      `double_quotes` –, `codes`, `chars`);
    * `true`, `false`, `null`: `@(true)`, `@(false)`, `@(null)` (Optionen
      `true(T)`, `false(T)`, `null(T)`).

  Gelesen wird Zeichen für Zeichen vom Stream wie bei SWI 9.0.4 (danach
  steht der Stream hinter dem Wert – aneinandergereihtes JSON geht, mit
  `end_of_file(Term)` auch bis zum Ende): Leerraum nur Leerzeichen, Tab,
  Zeilenwechsel; ein Komma vor `]` bzw. `}` ist erlaubt; Zahlen wie SWI
  (`01` ist 1, `2.` ist 2, `1e5` ein Float); Fehler
  `syntax_error(json(Grund))` bzw. `syntax_error(illegal_number)` mit
  `stream(S, Zeile, Spalte, Zeichen)`. Anders als SWI 9.0.4: ein
  UTF-16-Ersatzpaar `\\ud83d\\ude00` wird ein Zeichen (😀), ein einzelnes
  Ersatzzeichen U+FFFD.

  Geschrieben wird mit SWIs Layout (Breite 72, Schritt 2, Tabulator 8:
  passt ein Wert in die Zeile, waagrecht – `[1, 2, 3 ]`, `{"a":1, "b":2}`
  –, sonst senkrecht eingerückt, Tabs ab Spalte 8).
  """
  import PrologEx, only: [a: 1, mk: 2]
  alias PrologEx.{Error, Stream, Writer}

  # --- Lesen -----------------------------------------------------------------

  @doc "Optionen für Lesen und Schreiben aus einer Prolog-Optionsliste"
  def options(list) do
    Enum.reduce(list, default_opts(), fn
      {tag, "null", [t]}, o when tag in [:struct, :gstruct] ->
        %{o | null: t}

      {tag, "true", [t]}, o when tag in [:struct, :gstruct] ->
        %{o | true: t}

      {tag, "false", [t]}, o when tag in [:struct, :gstruct] ->
        %{o | false: t}

      {tag, "end_of_file", [{:atom, "error"}]}, o when tag in [:struct, :gstruct] ->
        %{o | eof: :error}

      {tag, "end_of_file", [t]}, o when tag in [:struct, :gstruct] ->
        %{o | eof: {:term, t}}

      {tag, "value_string_as", [{:atom, ty}]}, o when tag in [:struct, :gstruct] ->
        %{o | str: str_type!(ty)}

      {tag, "width", [n]}, o when tag in [:struct, :gstruct] and is_integer(n) and n >= 0 ->
        %{o | width: n}

      {tag, "step", [n]}, o when tag in [:struct, :gstruct] and is_integer(n) and n > 0 ->
        %{o | step: n}

      {tag, "tab", [n]}, o when tag in [:struct, :gstruct] and is_integer(n) and n > 0 ->
        %{o | tab: n}

      {tag, "indent", [n]}, o when tag in [:struct, :gstruct] and is_integer(n) and n >= 0 ->
        %{o | indent: n}

      {tag, "serialize_unknown", [{:atom, b}]}, o when tag in [:struct, :gstruct] ->
        %{o | unknown: b == "true"}

      _, o ->
        o
    end)
  end

  defp default_opts do
    # ohne Ground-Markierung, wie aufgelöste Terme (Vergleich mit ==)
    %{
      null: {:struct, "@", [a("null")]},
      true: {:struct, "@", [a("true")]},
      false: {:struct, "@", [a("false")]},
      eof: :error,
      str: :atom,
      width: 72,
      step: 2,
      tab: 8,
      indent: 0,
      unknown: false
    }
  end

  defp str_type!("atom"), do: :atom
  defp str_type!("codes"), do: :codes
  defp str_type!("chars"), do: :chars

  defp str_type!("string") do
    case PrologEx.Flags.get("double_quotes") do
      {:atom, "codes"} -> :codes
      {:atom, "atom"} -> :atom
      _ -> :chars
    end
  end

  defp str_type!(t), do: Error.domain!("value_string_as", a(t))

  @doc "Den nächsten JSON-Wert vom Stream id lesen (st: der Stream-Term für Fehler)"
  def read(id, st, opts) do
    c = ws(get(id), id)

    if c == :eof do
      case opts.eof do
        :error -> syntax!(id, st, "unexpected_end_of_file")
        {:term, t} -> t
      end
    else
      case term_top(c, id, st, opts) do
        :fail -> syntax!(id, st, "illegal_json")
        {:ok, t} -> t
      end
    end
  end

  defp get(id), do: Stream.get_char(id)

  defp peek(id) do
    case Stream.peek_char(id) do
      {c, _} when is_integer(c) -> c
      _ -> :eof
    end
  end

  # Leerraum wie SWI 9.0.4: Leerzeichen, Tab, Zeilenwechsel, Wagenrücklauf
  defp ws(c, id) when c in [?\s, ?\t, ?\n, ?\r], do: ws(get(id), id)
  defp ws(c, _id), do: c

  defp ws_next(id), do: ws(get(id), id)

  # {:ok, Term} oder :fail (dann illegal_json, wie SWIs Scheitern)
  defp term_top(?{, id, st, o) do
    pairs(ws_next(id), id, st, o, [])
  end

  defp term_top(?[, id, st, o), do: array(ws_next(id), id, st, o, [])

  defp term_top(?", id, st, o) do
    cs = string_codes(get(id), id, st, [])
    {:ok, as_type(o.str, cs)}
  end

  defp term_top(c, id, st, _o) when c == ?- or c in ?0..?9, do: {:ok, number(c, id, st)}

  defp term_top(?t, id, st, o), do: constant(~c"rue", "true", o.true, id, st)
  defp term_top(?f, id, st, o), do: constant(~c"alse", "false", o.false, id, st)
  defp term_top(?n, id, st, o), do: constant(~c"ull", "null", o.null, id, st)
  defp term_top(_, _id, _st, _o), do: :fail

  defp constant([], _name, t, _id, _st), do: {:ok, t}

  defp constant([h | rest], name, t, id, st) do
    if get(id) == h,
      do: constant(rest, name, t, id, st),
      else: syntax!(id, st, mk("json_expected", [a(name)]))
  end

  defp pairs(?}, _id, _st, _o, []), do: {:ok, mk("json", [[]])}

  defp pairs(c0, id, st, o, acc) do
    with ?" <- c0,
         name <- {:atom, codes_text(string_codes(get(id), id, st, []))},
         ?: <- ws_next(id),
         {:ok, v, next} <- value(id, st, o) do
      acc = [mk("=", [name, v]) | acc]

      case ws(next, id) do
        ?, ->
          case ws_next(id) do
            ?} -> {:ok, mk("json", [Enum.reverse(acc)])}
            c2 -> pairs(c2, id, st, o, acc)
          end

        ?} ->
          {:ok, mk("json", [Enum.reverse(acc)])}

        _ ->
          syntax!(id, st, "illegal_object")
      end
    else
      _ -> :fail
    end
  end

  defp array(?], _id, _st, _o, []), do: {:ok, []}

  defp array(c0, id, st, o, acc) do
    case term_top(c0, id, st, o) do
      {:ok, v} ->
        acc = [v | acc]

        case ws(get(id), id) do
          ?, ->
            case ws_next(id) do
              ?] -> {:ok, Enum.reverse(acc)}
              c1 -> array(c1, id, st, o, acc)
            end

          ?] ->
            {:ok, Enum.reverse(acc)}

          _ ->
            syntax!(id, st, "illegal_array")
        end

      :fail ->
        :fail
    end
  end

  # Wert nach ':' samt dem Zeichen danach
  defp value(id, st, o) do
    case ws_next(id) do
      :eof ->
        syntax!(id, st, "unexpected_end_of_file")

      c ->
        case term_top(c, id, st, o) do
          {:ok, v} -> {:ok, v, get(id)}
          :fail -> :fail
        end
    end
  end

  defp string_codes(?", _id, _st, acc), do: Enum.reverse(acc)
  defp string_codes(:eof, id, st, _acc), do: syntax!(id, st, "eof_in_string")

  defp string_codes(?\\, id, st, acc) do
    c =
      case get(id) do
        ?" -> ?"
        ?\\ -> ?\\
        ?/ -> ?/
        ?b -> ?\b
        ?f -> ?\f
        ?n -> ?\n
        ?r -> ?\r
        ?t -> ?\t
        ?u -> hex4(id, st)
        _ -> syntax!(id, st, "illegal_string_escape")
      end

    string_codes(get(id), id, st, [c | acc])
  end

  defp string_codes(c, id, st, acc), do: string_codes(get(id), id, st, [c | acc])

  defp hex4(id, st) do
    ds = for _ <- 1..4, do: get(id)

    if Enum.all?(ds, &(is_integer(&1) and hex?(&1))),
      do: List.to_integer(ds, 16),
      else: syntax!(id, st, "illegal_string_escape")
  end

  defp hex?(c), do: c in ?0..?9 or c in ?a..?f or c in ?A..?F

  # UTF-16-Ersatzpaare zusammenfügen, einzelne Ersatzzeichen: U+FFFD
  defp fix_surrogates([h, l | t]) when h in 0xD800..0xDBFF and l in 0xDC00..0xDFFF,
    do: [0x10000 + Bitwise.bsl(h - 0xD800, 10) + (l - 0xDC00) | fix_surrogates(t)]

  defp fix_surrogates([s | t]) when s in 0xD800..0xDFFF, do: [0xFFFD | fix_surrogates(t)]
  defp fix_surrogates([c | t]), do: [c | fix_surrogates(t)]
  defp fix_surrogates([]), do: []

  defp codes_text(cs), do: cs |> fix_surrogates() |> List.to_string()

  defp as_type(:atom, cs), do: {:atom, codes_text(cs)}
  defp as_type(:codes, cs), do: fix_surrogates(cs)
  defp as_type(:chars, cs), do: for(c <- fix_surrogates(cs), do: {:atom, <<c::utf8>>})

  # Zahl wie SWI 9.0.4: gierig Zeichen aus -+0-9.eE, dann deuten (ein
  # Punkt am Ende zählt nicht: "2." ist 2)
  defp number(c0, id, st) do
    text = number_chars(id, [c0]) |> List.to_string()
    t = if String.ends_with?(text, "."), do: String.slice(text, 0..-2//1), else: text

    case Regex.run(~r/^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/, t) do
      [_] ->
        String.to_integer(t)

      [_ | _] ->
        try do
          t =
            if String.contains?(t, "."),
              do: t,
              else: String.replace(t, ~r/[eE]/, ".0e", global: false)

          String.to_float(t)
        rescue
          ArgumentError -> syntax_number!(id, st)
        end

      nil ->
        syntax_number!(id, st)
    end
  end

  defp number_chars(id, acc) do
    c = peek(id)

    if is_integer(c) and (c in ?0..?9 or c in [?-, ?+, ?., ?e, ?E]) do
      get(id)
      number_chars(id, [c | acc])
    else
      Enum.reverse(acc)
    end
  end

  defp syntax!(id, st, msg) do
    m = if is_binary(msg), do: a(msg), else: msg
    throw_syntax(mk("json", [m]), id, st)
  end

  defp syntax_number!(id, st), do: throw_syntax(a("illegal_number"), id, st)

  defp throw_syntax(what, id, st) do
    s = Stream.get(id)
    ctx = mk("stream", [st, s.lines, s.line_pos, s.chars])
    Error.throw!(mk("error", [mk("syntax_error", [what]), ctx]))
  end

  # --- Schreiben -----------------------------------------------------------------

  # bei einem Fehler: was bis dahin geschrieben ist (wie bei SWI, das
  # direkt auf den Stream schreibt)
  @partial :prolog_ex_json_partial
  defp partial(out), do: Process.put(@partial, out)

  @doc """
  Term (aufgelöst, ohne Markierungen) als JSON: `{:ok, iodata}` oder
  `{:error, bis_dahin, ausnahme, stacktrace}`; col0 die Spalte des Streams
  am Anfang
  """
  def write(term, opts, col0) do
    st = %{indent: opts.indent, step: opts.step, tab: opts.tab, width: opts.width}

    try do
      {out, _col} = w_term(term, st, opts, {[], col0})
      {:ok, out}
    rescue
      e in Error ->
        {out, _} = Process.delete(@partial) || {[], 0}
        {:error, out, e, __STACKTRACE__}
    after
      Process.delete(@partial)
    end
  end

  # Ausgabe mitsamt Spalte (Tab: nächste Achterstelle, wie SWIs Streams)
  defp emit({acc, col}, text), do: {[acc | text], advance(text, col)}

  defp advance(text, col) do
    case :binary.split(text, "\n", [:global]) do
      [one] -> cols(one, col)
      parts -> cols(List.last(parts), 0)
    end
  end

  defp cols(<<>>, col), do: col
  defp cols(<<?\t, rest::binary>>, col), do: cols(rest, Bitwise.bor(col, 7) + 1)
  defp cols(<<_::utf8, rest::binary>>, col), do: cols(rest, col + 1)
  defp cols(<<_, rest::binary>>, col), do: cols(rest, col + 1)

  defp w_term({:var, _}, _st, _o, out) do
    partial(out)
    Error.instantiation!()
  end

  defp w_term({:struct, "json", [pairs]}, st, o, out), do: w_object(pairs, st, o, out)

  defp w_term(l, st, o, out) when is_list(l) do
    if proper?(l), do: w_array(l, st, o, out), else: w_other(l, st, o, out)
  end

  defp w_term(t, st, o, out), do: w_other(t, st, o, out)

  defp w_other(t, _st, o, out) do
    cond do
      is_number(t) -> emit(out, number_text(t))
      match?({:rat, _, _}, t) -> emit(out, number_text(PrologEx.Rational.to_float(t)))
      t == o.true -> emit(out, "true")
      t == o.false -> emit(out, "false")
      t == o.null -> emit(out, "null")
      match?({:struct, "#", [_]}, t) -> stringify(elem(t, 2) |> hd(), out)
      match?({:atom, _}, t) -> emit(out, json_string(elem(t, 1)))
      o.unknown -> emit(out, json_string(Writer.format(t, quoted: true)))
      true -> type_error(out, t)
    end
  end

  defp type_error(out, t) do
    partial(out)
    Error.type!("json_term", t)
  end

  defp stringify({:atom, s}, out), do: emit(out, json_string(s))
  defp stringify(t, out), do: emit(out, json_string(Writer.format(t, quoted: true)))

  defp number_text(n), do: Writer.format(n)

  defp proper?([]), do: true
  defp proper?([_ | t]), do: proper?(t)
  defp proper?(_), do: false

  defp w_array(l, st, o, out) do
    out = space_if(st, out) |> emit("[")
    partial(out)

    if st.width == 0 or print_len(l, o, st.width, st.indent) != :no do
      out = arr_hor(l, %{st | width: 0}, o, out)
      emit(out, "]")
    else
      st2 = %{st | indent: st.indent + st.step}
      out = arr_ver(l, st2, o, out)
      out |> indent(st) |> emit("]")
    end
  end

  defp arr_hor([], _st, _o, out), do: out

  defp arr_hor([h | t], st, o, out) do
    out = w_term(h, st, o, out)
    if t == [], do: emit(out, " "), else: arr_hor(t, st, o, emit(out, ", "))
  end

  defp arr_ver([], _st, _o, out), do: out

  defp arr_ver([h | t], st, o, out) do
    out = out |> indent(st) |> then(&w_term(h, st, o, &1))
    if t == [], do: out, else: arr_ver(t, st, o, emit(out, ","))
  end

  defp w_object(pairs, st, o, out) do
    out = space_if(st, out) |> emit("{")
    partial(out)

    if st.width == 0 or obj_len(pairs, o, st.width, st.indent) != :no do
      out = pairs_hor(pairs!(pairs), %{st | width: 0}, o, out)
      emit(out, "}")
    else
      st2 = %{st | indent: st.indent + st.step}
      out = pairs_ver(pairs!(pairs), st2, o, out)
      out |> indent(st) |> emit("}")
    end
  end

  defp pairs!({:var, _}), do: Error.instantiation!()
  defp pairs!(l) when is_list(l), do: if(proper?(l), do: l, else: Error.type!("list", l))
  defp pairs!(t), do: Error.type!("list", t)

  defp pairs_hor([], _st, _o, out), do: out

  defp pairs_hor([h | t], st, o, out) do
    partial(out)
    {name, value} = pair!(h)
    out = out |> emit(json_string(text!(name))) |> emit(":")
    out = w_term(value, st, o, out)
    if t == [], do: out, else: pairs_hor(t, st, o, emit(out, ", "))
  end

  defp pairs_ver([], _st, _o, out), do: out

  defp pairs_ver([h | t], st, o, out) do
    out = indent(out, st)
    partial(out)
    {name, value} = pair!(h)
    out = out |> emit(json_string(text!(name))) |> emit(":")
    out = w_term(value, st, o, out)
    if t == [], do: out, else: pairs_ver(t, st, o, emit(out, ","))
  end

  defp pair!({:var, _}), do: Error.instantiation!()
  defp pair!({:struct, op, [n, v]}) when op in ["=", "-"], do: {n, v}
  defp pair!({:struct, n, [v]}), do: {{:atom, n}, v}
  defp pair!(p), do: Error.type!("json_pair", p)

  # Text eines Namens: Atom (auch [] und Zeichen-/Codelisten)
  defp text!({:atom, s}), do: s
  defp text!([]), do: "[]"

  defp text!(l) when is_list(l) do
    if proper?(l) and Enum.all?(l, &text_elem?/1),
      do: Enum.map_join(l, &elem_text/1),
      else: Error.type!("text", l)
  end

  defp text!(t), do: Error.type!("text", t)

  defp name_text({:atom, s}), do: s

  defp name_text(l) when is_list(l) and l != [] do
    if proper?(l) and Enum.all?(l, &text_elem?/1), do: Enum.map_join(l, &elem_text/1)
  end

  defp name_text(_), do: nil

  defp text_elem?({:atom, <<_::utf8>>}), do: true
  defp text_elem?(c) when is_integer(c) and c >= 0, do: true
  defp text_elem?(_), do: false

  defp elem_text({:atom, s}), do: s
  defp elem_text(c), do: <<c::utf8>>

  # Zeilenwechsel (wenn nicht schon am Zeilenanfang) und Einrückung:
  # Indent // Tab Tabs, der Rest Leerzeichen
  defp indent({_, col} = out, st) do
    out = if col != 0, do: emit(out, "\n"), else: out
    tabs = String.duplicate("\t", div(st.indent, st.tab))
    emit(out, tabs <> String.duplicate(" ", rem(st.indent, st.tab)))
  end

  defp space_if(st, {_, col} = out) do
    if col == 0 or col == st.indent, do: out, else: emit(out, " ")
  end

  # --- Länge in einer Zeile (wie json_print_length/5): Len oder :no -------

  defp print_len({:var, _}, _o, _max, _len0), do: Error.instantiation!()

  defp print_len({:struct, "json", [pairs]}, o, max, len0), do: obj_len(pairs, o, max, len0)

  defp print_len(l, o, max, len0) when is_list(l) do
    if proper?(l) do
      len1 = len0 + 2
      if len1 > max, do: :no, else: arr_len(l, o, max, len1)
    else
      other_len(l, o, max, len0)
    end
  end

  defp print_len(t, o, max, len0), do: other_len(t, o, max, len0)

  defp obj_len(pairs, o, max, len0) do
    len1 = len0 + 2

    if len1 > max do
      :no
    else
      pairs_len(pairs!(pairs), o, max, len1)
    end
  end

  defp other_len(t, o, max, len0) do
    len =
      cond do
        t == o.null -> len0 + 4
        t == o.false -> len0 + 5
        t == o.true -> len0 + 4
        is_number(t) or match?({:rat, _, _}, t) -> len0 + String.length(number_text(t))
        match?({:struct, "@", [{:atom, _}]}, t) -> len0 + String.length(elem(hd(elem(t, 2)), 1))
        match?({:atom, _}, t) -> len0 + String.length(elem(t, 1)) + 2
        true -> len0 + String.length(Writer.format(t)) + 2
      end

    if len <= max, do: len, else: :no
  end

  defp pairs_len([], _o, _max, len), do: len

  defp pairs_len([h | t], o, max, len0) do
    with len1 when len1 != :no <- pair_len(h, o, max, len0) do
      cond do
        t == [] -> len1
        len1 + 2 > max -> :no
        true -> pairs_len(t, o, max, len1 + 2)
      end
    end
  end

  defp pair_len(p, o, max, len0) do
    {n, v} =
      case p do
        {tag, op, [n, v]} when tag in [:struct, :gstruct] and op in ["=", "-"] -> {n, v}
        {tag, n, [v]} when tag in [:struct, :gstruct] -> {{:atom, n}, v}
        _ -> Error.type!("pair", p)
      end

    # Name: Atom oder (für SWIs String) Zeichen-/Codeliste
    case name_text(n) do
      nil ->
        :no

      s ->
        len2 = len0 + String.length(s) + 2 + 2
        if len2 > max, do: :no, else: print_len(v, o, max, len2)
    end
  end

  defp arr_len([], _o, _max, len), do: len

  defp arr_len([h | t], o, max, len0) do
    with len1 when len1 != :no <- print_len(h, o, max, len0) do
      cond do
        t == [] -> len1
        len1 + 2 > max -> :no
        true -> arr_len(t, o, max, len1 + 2)
      end
    end
  end

  @doc "Text als JSON-String (wie SWIs json_write_string/2)"
  def json_string(text) do
    ["\"", escape(text, []), "\""] |> IO.iodata_to_binary()
  end

  defp escape(<<>>, acc), do: Enum.reverse(acc)
  defp escape(<<?", r::binary>>, acc), do: escape(r, ["\\\"" | acc])
  defp escape(<<?\\, r::binary>>, acc), do: escape(r, ["\\\\" | acc])
  defp escape(<<"</", r::binary>>, acc), do: escape(r, ["<\\/" | acc])
  defp escape(<<?\n, r::binary>>, acc), do: escape(r, ["\\n" | acc])
  defp escape(<<?\r, r::binary>>, acc), do: escape(r, ["\\r" | acc])
  defp escape(<<?\t, r::binary>>, acc), do: escape(r, ["\\t" | acc])
  defp escape(<<?\b, r::binary>>, acc), do: escape(r, ["\\b" | acc])
  defp escape(<<?\f, r::binary>>, acc), do: escape(r, ["\\f" | acc])

  defp escape(<<c, r::binary>>, acc) when c < 0x20,
    do:
      escape(r, [
        "\\u" <> String.pad_leading(Integer.to_string(c, 16) |> String.downcase(), 4, "0") | acc
      ])

  defp escape(<<c::utf8, r::binary>>, acc), do: escape(r, [<<c::utf8>> | acc])
  defp escape(<<c, r::binary>>, acc), do: escape(r, [<<c>> | acc])
end
