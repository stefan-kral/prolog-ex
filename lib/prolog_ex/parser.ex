defmodule PrologEx.Parser do
  @moduledoc """
  Prolog-Reader in Elixir nach ISO/IEC 13211-1: Tokenizer (6.4) und
  Operator-Präzedenz-Parser (6.3). Liefert dasselbe Format wie
  `PrologEx.Reader.read_terms/2`:

    * `{:term, term, names}` – Variablen tragen ihre Namen aus dem Text
      (`names`: `%{name => name}` der benannten), jede anonyme Variable `_`
      einen eigenen Namen `_N`, der im Term nicht schon vorkommt
    * `{:error, meldung}` – Syntaxfehler; gelesen wird nach dem nächsten
      Endezeichen weiter

  Optionen: `ops:` (Operatortabelle wie `PrologEx.Ops.table/0`, Standard
  die der Sitzung), `double_quotes:` (`"codes"`, `"chars"`, `"atom"`;
  Standard das Flag), `back_quotes:` (wie `double_quotes`; Standard `"atom"` wie gprolog).

  Wie der gprolog-Reader führt `read_terms/2` Direktiven `:- op/3`,
  `:- module/2` (Operatoren der Exportliste) und
  `:- set_prolog_flag(double_quotes, _)` für die folgenden Terme desselben
  Textes aus – hier nur für diesen Text, nicht für die Sitzung.

  Erweiterungen gegenüber ISO: Zifferngruppen `1_000_000` (nach `_` darf
  Leerraum folgen), Unicode-Buchstaben in Namen und Variablen
  (Großbuchstabe am Anfang: Variable), Unicode-Symbole als Symbolzeichen.
  """

  import PrologEx, only: [a: 1, mk: 2]

  @graphic ~c"#$&*+-./:<=>?@^~\\"
  @layout [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]
  @punct %{?( => "(", ?) => ")", ?[ => "[", ?] => "]", ?{ => "{", ?} => "}", ?, => ",", ?| => "|"}

  # ---------------------------------------------------------------------
  # Schnittstelle

  def read_terms(text, opts \\ []) do
    ctx = context(text, opts)
    lc = if Keyword.get(opts, :lines), do: {1, 0}

    # Byte-Order-Mark am Anfang überspringen
    case text do
      <<0xEF, 0xBB, 0xBF, rest::binary>> -> read_all(rest, 3, ctx, [], lc)
      _ -> read_all(text, 0, ctx, [], lc)
    end
  end

  @doc """
  Lesekontext für `read_term/3`: Operatortabelle und double_quotes (aus
  den Optionen, sonst die der Sitzung zu diesem Zeitpunkt), `text` ist
  der ganze Text (für Zeile/Spalte in Fehlermeldungen).
  """
  def context(text, opts \\ []) do
    %{
      ops: Keyword.get_lazy(opts, :ops, &PrologEx.Ops.table/0),
      dq: Keyword.get_lazy(opts, :double_quotes, &flag_dq/0),
      bq: Keyword.get(opts, :back_quotes, "atom"),
      conv: Keyword.get_lazy(opts, :char_conversion, &PrologEx.CharConversion.active/0),
      text: text
    }
  end

  @doc """
  Genau einen Term (für read_term/2,3): `{:term, t, names}`,
  `{:error, meldung}` oder `:eof`. Anders als `read_terms/2` ist
  `end_of_file` hier ein gewöhnlicher Term, und Direktiven wirken nicht.
  """
  def read_one(text) do
    case read_term(text, 0, context(text)) do
      {:term, t, names, _, _, _} -> {:term, t, names}
      {:error, msg, _, _} -> {:error, msg}
      :eof -> :eof
    end
  end

  defp flag_dq do
    case PrologEx.Flags.get("double_quotes") do
      {:atom, v} -> v
      _ -> "codes"
    end
  end

  # lc: {Zeile, Byte-Position} für die Zeilennummern (inkrementell), oder
  # nil ohne Option lines:
  defp read_all(rest, pos, ctx, acc, lc) do
    case read_term(rest, pos, ctx) do
      :eof ->
        Enum.reverse(acc)

      # wie beim Laden in ISO-Systemen: der Term end_of_file beendet den Text
      {:term, {:atom, "end_of_file"}, _, _, _, _} ->
        Enum.reverse(acc)

      {:term, t, names, rest, pos, start} when lc != nil ->
        {line, _} = lc = line_at(ctx.text, lc, start)
        read_all(rest, pos, directive(t, ctx), [{:term, t, names, line} | acc], lc)

      {:term, t, names, rest, pos, _} ->
        read_all(rest, pos, directive(t, ctx), [{:term, t, names} | acc], lc)

      {:error, msg, rest, pos} ->
        read_all(rest, pos, ctx, [{:error, msg} | acc], lc)
    end
  end

  @doc """
  Ende des nächsten Terms in `text` (für read/1 von einem Stream, der
  stückweise gefüllt wird), mit demselben Tokenizer wie beim Lesen:

    * `{:end, n}` – die ersten n Bytes sind der Term samt Endepunkt; das
      folgende Layoutzeichen bleibt im Stream (ISO 8.14.1.4),
    * `:empty` – bis zum Dateiende nur Leerraum und Kommentare,
    * `{:eof_inside, n}` – Dateiende mitten in einem Term,
    * `:more` – der Text reicht nicht (`eof?` falsch), nachlesen.

  Bei einem Fehler im Term (etwa einer unbekannten Escape-Sequenz) endet
  er wie beim Wiederaufsetzen am nächsten Endepunkt; den Fehler meldet
  dann das Lesen.
  """
  def scan_end(text, eof?) do
    size = byte_size(text)

    case tokens(text, 0, []) do
      :eof ->
        if eof?, do: :empty, else: :more

      # am Pufferende kann der Punkt noch zu einer Symbolfolge gehören
      {:ok, _toks, _rest, pos} when pos >= size and not eof? ->
        :more

      {:ok, _toks, _rest, pos} ->
        {:end, pos}

      {:lex_error, _msg, _at, _rest, pos} when pos >= size ->
        cond do
          not eof? -> :more
          size > 0 and :binary.last(text) == ?. -> {:end, size}
          true -> {:eof_inside, size}
        end

      {:lex_error, _msg, _at, _rest, pos} ->
        {:end, pos}
    end
  end

  @doc """
  Zeilennummer an Byte-Position `pos` von `text`, ausgehend von einer
  bekannten `{zeile, position}` davor: `{zeile, pos}`.
  """
  def line_at(text, {line, from}, pos) when pos >= from do
    n = length(:binary.matches(text, "\n", scope: {from, pos - from}))
    {line + n, pos}
  end

  @doc """
  Liest einen Term ab `rest` (Byte-Position `pos` in `ctx.text`):
  `{:term, t, names, rest, pos, start}` (start: Byte-Position des ersten
  Tokens), `{:error, meldung, rest, pos}` oder
  `:eof` (nur noch Leerraum und Kommentare).
  """
  def read_term(rest, pos, %{conv: conv} = ctx) when conv != nil do
    # Zeichenumsetzung: den Text eines Terms umsetzen und lesen; Zeile und
    # Spalte in Meldungen bleiben die des Originals (davor steht der
    # Originaltext), weiter geht es im Original hinter dem Term
    {chunk, used} = PrologEx.CharConversion.convert_term(rest, conv)
    prefix = binary_part(ctx.text, 0, pos)
    sub = %{ctx | conv: nil, text: prefix <> chunk}
    rest2 = binary_part(rest, used, byte_size(rest) - used)

    case read_term(chunk, pos, sub) do
      {:term, t, names, _, _, start} -> {:term, t, names, rest2, pos + used, start}
      {:error, msg, _, _} -> {:error, msg, rest2, pos + used}
      :eof -> :eof
    end
  end

  def read_term(rest, pos, ctx) do
    case tokens(rest, pos, []) do
      :eof ->
        :eof

      {:ok, toks, rest, pos} ->
        try do
          vars =
            toks
            |> Enum.flat_map(fn
              {{:var, n}, _, _} -> [n]
              _ -> []
            end)
            |> MapSet.new()

          Process.put(:prolog_ex_parser_anon, {0, vars})
          {t, _p, [{:end, _, _}]} = whole(toks, ctx)
          names = for n <- vars, n != "_", into: %{}, do: {n, n}
          [{_, _, start} | _] = toks
          {:term, t, names, rest, pos, start}
        catch
          {:syntax, msg, at} ->
            {rest, pos} = skip_to_end(binary_part(ctx.text, at, byte_size(ctx.text) - at), at)
            {:error, message(ctx, msg, at), rest, pos}
        after
          Process.delete(:prolog_ex_parser_anon)
        end

      {:lex_error, msg, at, rest, pos} ->
        {:error, message(ctx, msg, at), rest, pos}
    end
  end

  defp message(ctx, msg, at) do
    before = binary_part(ctx.text, 0, min(at, byte_size(ctx.text)))
    line = 1 + length(:binary.matches(before, "\n"))

    col = before |> String.split("\n") |> List.last() |> String.length() |> Kernel.+(1)

    "Syntaxfehler: Zeile #{line}, Spalte #{col}: #{msg}"
  end

  # Direktiven, die das Lesen des restlichen Textes betreffen
  defp directive(t, ctx) do
    case PrologEx.unmark(t) do
      {:struct, ":-", [{:struct, "op", [p, ty, names]}]} ->
        add_ops(ctx, p, ty, names)

      {:struct, ":-", [{:struct, "module", [_, exports]}]} ->
        exports
        |> plist()
        |> Enum.reduce(ctx, fn
          {:struct, "op", [p, ty, names]}, ctx -> add_ops(ctx, p, ty, names)
          _, ctx -> ctx
        end)

      {:struct, ":-", [{:struct, "set_prolog_flag", [{:atom, "double_quotes"}, {:atom, v}]}]}
      when v in ["codes", "chars", "atom"] ->
        %{ctx | dq: v}

      _ ->
        ctx
    end
  end

  defp add_ops(ctx, p, {:atom, ty}, names)
       when is_integer(p) and p >= 0 and p <= 1200 and
              ty in ~w(xfx xfy yfx fy fx xf yf) do
    names = if is_list(names), do: plist(names), else: [names]

    if Enum.all?(names, &match?({:atom, n} when n != ",", &1)) do
      Enum.reduce(names, ctx, fn {:atom, n}, ctx -> %{ctx | ops: op_put(ctx.ops, p, ty, n)} end)
    else
      ctx
    end
  end

  defp add_ops(ctx, _, _, _), do: ctx

  defp op_put(table, p, ty, n) do
    c = PrologEx.Ops.class(ty)
    entry = Map.get(table, n, %{})
    entry = if p == 0, do: Map.delete(entry, c), else: Map.put(entry, c, {p, ty})
    if entry == %{}, do: Map.delete(table, n), else: Map.put(table, n, entry)
  end

  defp plist([h | t]), do: [h | plist(t)]
  defp plist(_), do: []

  # ---------------------------------------------------------------------
  # Tokenizer: Tokens eines Terms bis einschließlich Endezeichen
  # Token: {art, leerraum_davor?, byte_position}

  defp tokens(rest, pos, acc) do
    case token(rest, pos) do
      {:eof, _, _, _, _} when acc == [] ->
        :eof

      {:eof, _lay, at, _rest, _pos} ->
        {:lex_error, "Dateiende im Term", at, "", pos_end(rest, pos)}

      {:end, lay, at, rest, pos} ->
        {:ok, Enum.reverse([{:end, lay, at} | acc]), rest, pos}

      {:error, msg, at, _rest, _pos} ->
        {rest, pos} = skip_to_end(rest, pos)
        {:lex_error, msg, at, rest, pos}

      {tok, lay, at, rest, pos} ->
        tokens(rest, pos, [{tok, lay, at} | acc])
    end
  end

  defp pos_end(rest, pos), do: pos + byte_size(rest)

  # nach einem Syntaxfehler (wie gprolog): ab der Fehlerstelle Zeichen
  # überspringen bis hinter einen Punkt vor Leerraum, % oder Dateiende.
  # Quotes, 0'c und Kommentare zählen dabei als Ganzes; ein Punkt vor einem
  # anderen Zeichen nimmt dieses mit (in "=.. [" endet nichts, in
  # "x :- ?????." schon)
  defp skip_to_end(r, pos) do
    case r do
      "" ->
        {"", pos}

      <<?., c, _::binary>> when c in @layout or c == ?% ->
        <<_, rest::binary>> = r
        {rest, pos + 1}

      "." ->
        {"", pos + 1}

      <<"0'\\", c::utf8, rest::binary>> ->
        skip_to_end(rest, pos + 3 + byte_size(<<c::utf8>>))

      <<"0'", c::utf8, rest::binary>> ->
        skip_to_end(rest, pos + 2 + byte_size(<<c::utf8>>))

      <<q, rest::binary>> when q in [?', ?", ?`] ->
        {rest, pos} = skip_quoted(rest, q, pos + 1)
        skip_to_end(rest, pos)

      <<?%, _::binary>> ->
        case :binary.match(r, "\n") do
          {i, 1} -> skip_to_end(binary_part(r, i, byte_size(r) - i), pos + i)
          :nomatch -> {"", pos + byte_size(r)}
        end

      <<"/*", _::binary>> ->
        case :binary.match(r, "*/") do
          {i, 2} -> skip_to_end(binary_part(r, i + 2, byte_size(r) - i - 2), pos + i + 2)
          :nomatch -> {"", pos + byte_size(r)}
        end

      <<?., _, rest::binary>> ->
        skip_to_end(rest, pos + 2)

      <<_, rest::binary>> ->
        skip_to_end(rest, pos + 1)
    end
  end

  defp skip_quoted(r, q, pos) do
    case r do
      <<^q, ^q, rest::binary>> -> skip_quoted(rest, q, pos + 2)
      <<^q, rest::binary>> -> {rest, pos + 1}
      <<?\\, _, rest::binary>> -> skip_quoted(rest, q, pos + 2)
      <<_, rest::binary>> -> skip_quoted(rest, q, pos + 1)
      "" -> {"", pos}
    end
  end

  defp token(rest, pos) do
    case layout(rest, pos, false) do
      {:error, msg, at} -> {:error, msg, at, "", pos_end(rest, pos)}
      {rest, pos, lay} -> token1(rest, pos, lay)
    end
  end

  # Leerraum und Kommentare
  defp layout(<<c, rest::binary>>, pos, _) when c in @layout, do: layout(rest, pos + 1, true)

  defp layout(<<?%, rest::binary>>, pos, _) do
    case :binary.match(rest, "\n") do
      {i, 1} -> layout(binary_part(rest, i + 1, byte_size(rest) - i - 1), pos + i + 2, true)
      :nomatch -> {"", pos + 1 + byte_size(rest), true}
    end
  end

  defp layout(<<"/*", rest::binary>>, pos, _) do
    case :binary.match(rest, "*/") do
      {i, 2} -> layout(binary_part(rest, i + 2, byte_size(rest) - i - 2), pos + i + 4, true)
      :nomatch -> {:error, "Kommentar nicht abgeschlossen", pos}
    end
  end

  defp layout(rest, pos, lay), do: {rest, pos, lay}

  defp token1("", pos, lay), do: {:eof, lay, pos, "", pos}

  # Endezeichen: Punkt vor Leerraum, % oder Dateiende
  defp token1(<<?., c, _::binary>> = r, pos, lay) when c in @layout or c == ?% do
    <<_, rest::binary>> = r
    {:end, lay, pos, rest, pos + 1}
  end

  defp token1(".", pos, lay), do: {:end, lay, pos, "", pos + 1}

  defp token1(<<c, _::binary>> = r, pos, lay) when c in ?0..?9, do: number(r, pos, lay)

  defp token1(<<c, _::binary>> = r, pos, lay) when c == ?_ or c in ?A..?Z do
    {name, rest} = alnum(r, 0)
    {{:var, name}, lay, pos, rest, pos + byte_size(name)}
  end

  defp token1(<<c, _::binary>> = r, pos, lay) when c in ?a..?z do
    {name, rest} = alnum(r, 0)
    {{:name, name}, lay, pos, rest, pos + byte_size(name)}
  end

  defp token1(<<q, rest::binary>>, pos, lay) when q in [?', ?", ?`] do
    case quoted(rest, q, pos + 1, []) do
      {:ok, s, rest, npos} ->
        kind = %{?' => :qname, ?" => :str, ?` => :bq}[q]
        {{kind, s}, lay, pos, rest, npos}

      {:error, msg, at} ->
        {:error, msg, at, rest, pos + 1}
    end
  end

  defp token1(<<c, rest::binary>>, pos, lay) when is_map_key(@punct, c),
    do: {{:p, Map.fetch!(@punct, c)}, lay, pos, rest, pos + 1}

  defp token1(<<c, rest::binary>>, pos, lay) when c in [?!, ?;],
    do: {{:name, <<c>>}, lay, pos, rest, pos + 1}

  defp token1(<<c, _::binary>> = r, pos, lay) when c in @graphic do
    {name, rest} = graphic(r, 0)
    {{:name, name}, lay, pos, rest, pos + byte_size(name)}
  end

  defp token1(<<c::utf8, _::binary>> = r, pos, lay) do
    s = <<c::utf8>>

    cond do
      String.match?(s, ~r/^[\p{Lu}\p{Lt}]$/u) ->
        {name, rest} = alnum(r, 0)
        {{:var, name}, lay, pos, rest, pos + byte_size(name)}

      String.match?(s, ~r/^\p{L}$/u) ->
        {name, rest} = alnum(r, 0)
        {{:name, name}, lay, pos, rest, pos + byte_size(name)}

      String.match?(s, ~r/^[\p{Sm}\p{So}]$/u) ->
        {name, rest} = graphic(r, 0)
        {{:name, name}, lay, pos, rest, pos + byte_size(name)}

      true ->
        {:error, "unerlaubtes Zeichen #{inspect(s)}", pos, r, pos}
    end
  end

  defp token1(<<_, _::binary>> = r, pos, _lay),
    do: {:error, "unerlaubtes Byte", pos, r, pos}

  # Länge des alphanumerischen Namens ab Anfang
  defp alnum(r, i) do
    case from(r, i) do
      <<c, _::binary>>
      when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ ->
        alnum(r, i + 1)

      <<c::utf8, _::binary>> when c > 127 ->
        if String.match?(<<c::utf8>>, ~r/^[\p{L}\p{N}\p{M}]$/u),
          do: alnum(r, i + byte_size(<<c::utf8>>)),
          else: split(r, i)

      _ ->
        split(r, i)
    end
  end

  defp graphic(r, i) do
    case from(r, i) do
      <<c, _::binary>> when c in @graphic ->
        graphic(r, i + 1)

      <<c::utf8, _::binary>> when c > 127 ->
        if String.match?(<<c::utf8>>, ~r/^[\p{Sm}\p{So}]$/u),
          do: graphic(r, i + byte_size(<<c::utf8>>)),
          else: split(r, i)

      _ ->
        split(r, i)
    end
  end

  # ab Byte i (ohne Kopie: Teilbinary)
  defp from(r, i), do: binary_part(r, i, byte_size(r) - i)

  defp split(r, i), do: {binary_part(r, 0, i), binary_part(r, i, byte_size(r) - i)}

  # --- Zahlen -------------------------------------------------------------

  # 0'c; folgt kein gültiges Zeichen (0'' ohne drittes Quote, 0'\ vor
  # Zeilenumbruch, ...), ist 0 eine Zahl für sich und das Quote beginnt
  # ein neues Token (ISO 6.4.4; so liest "0''1" sich als 0 '' 1)
  defp number(<<"0'", rest::binary>> = r, pos, lay) do
    case char_code(rest, pos + 2) do
      {:ok, c, rest, npos} ->
        {{:num, c}, lay, pos, rest, npos}

      {:error, _msg, _at} ->
        <<_, quote_on::binary>> = r
        {{:num, 0}, lay, pos, quote_on, pos + 1}
    end
  end

  defp number(<<"0", x, d, _::binary>> = r, pos, lay)
       when (x == ?x and (d in ?0..?9 or d in ?a..?f or d in ?A..?F)) or
              (x == ?o and d in ?0..?7) or (x == ?b and d in ?0..?1) do
    base = %{?x => 16, ?o => 8, ?b => 2}[x]
    <<_, _, digits::binary>> = r
    {ds, rest} = radix_digits(digits, base, 0)
    {{:num, String.to_integer(ds, base)}, lay, pos, rest, pos + 2 + byte_size(ds)}
  end

  defp number(r, pos, lay) do
    {int, rest, used} = decimal(r, [], 0)

    case rest do
      <<?., d, _::binary>> when d in ?0..?9 ->
        <<_, frac_r::binary>> = rest
        {frac, rest2} = digits(frac_r, 0)
        {exp, rest3} = exponent(rest2)
        len = used + 1 + byte_size(frac) + byte_size(exp)

        case float(int <> "." <> frac <> exp) do
          {:ok, f} -> {{:num, f}, lay, pos, rest3, pos + len}
          :error -> {:error, "Gleitkommazahl nicht darstellbar", pos, rest3, pos + len}
        end

      _ ->
        {{:num, String.to_integer(int)}, lay, pos, rest, pos + used}
    end
  end

  defp float(s) do
    case Float.parse(s) do
      {f, ""} -> {:ok, f}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  # Ziffern mit Gruppen (1_000_000, auch 1_000_ 000): {ziffern, rest, bytes}
  defp decimal(r, acc, used) do
    {ds, rest} = digits(r, 0)
    acc = [acc, ds]
    used = used + byte_size(ds)

    case rest do
      <<?_, more::binary>> ->
        {skipped, more2} = blank(more, 0)

        case more2 do
          <<d, _::binary>> when d in ?0..?9 -> decimal(more2, acc, used + 1 + skipped)
          _ -> {IO.iodata_to_binary(acc), rest, used}
        end

      _ ->
        {IO.iodata_to_binary(acc), rest, used}
    end
  end

  defp blank(<<c, rest::binary>>, n) when c in @layout, do: blank(rest, n + 1)
  defp blank(rest, n), do: {n, rest}

  defp digits(r, i) do
    case from(r, i) do
      <<c, _::binary>> when c in ?0..?9 -> digits(r, i + 1)
      _ -> split(r, i)
    end
  end

  defp radix_digits(r, base, i) do
    case from(r, i) do
      <<c, _::binary>> ->
        if digit_value(c) < base, do: radix_digits(r, base, i + 1), else: split(r, i)

      _ ->
        split(r, i)
    end
  end

  defp digit_value(c) when c in ?0..?9, do: c - ?0
  defp digit_value(c) when c in ?a..?z, do: c - ?a + 10
  defp digit_value(c) when c in ?A..?Z, do: c - ?A + 10
  defp digit_value(_), do: 99

  defp exponent(<<e, s, d, _::binary>> = r)
       when e in [?e, ?E] and s in [?+, ?-] and d in ?0..?9 do
    <<_, _, more::binary>> = r
    {ds, rest} = digits(more, 0)
    {<<e, s>> <> ds, rest}
  end

  defp exponent(<<e, d, _::binary>> = r) when e in [?e, ?E] and d in ?0..?9 do
    <<_, more::binary>> = r
    {ds, rest} = digits(more, 0)
    {<<e>> <> ds, rest}
  end

  defp exponent(r), do: {"", r}

  # 0'c: ein Zeichen wie in Quotes ('' für ', Escapes)
  defp char_code(<<"''", rest::binary>>, pos), do: {:ok, ?', rest, pos + 2}

  defp char_code(<<?\\, rest::binary>>, pos) do
    case escape(rest, pos + 1) do
      {:ok, :continuation, _, _} -> {:error, "0'\\ mit Zeilenumbruch", pos}
      {:ok, c, rest, npos} -> {:ok, c, rest, npos}
      {:error, msg, at} -> {:error, msg, at}
    end
  end

  defp char_code(<<?', _::binary>>, pos), do: {:error, "0'' statt 0''' ", pos}

  defp char_code(<<c::utf8, rest::binary>>, pos) when c >= 32 and c != 127,
    do: {:ok, c, rest, pos + byte_size(<<c::utf8>>)}

  defp char_code(_, pos), do: {:error, "Zeichen nach 0' fehlt", pos}

  # --- Quotes ---------------------------------------------------------------

  defp quoted(r, q, pos, acc) do
    case r do
      <<^q, ^q, rest::binary>> ->
        quoted(rest, q, pos + 2, [acc, q])

      <<^q, rest::binary>> ->
        {:ok, IO.iodata_to_binary(acc), rest, pos + 1}

      <<?\\, rest::binary>> ->
        case escape(rest, pos + 1) do
          {:ok, :continuation, rest, npos} -> quoted(rest, q, npos, acc)
          {:ok, c, rest, npos} -> quoted(rest, q, npos, [acc, <<c::utf8>>])
          {:error, msg, at} -> {:error, msg, at}
        end

      <<?\n, _::binary>> ->
        {:error, "Zeilenumbruch in Quotes", pos}

      # ISO 6.4.2.1: von den Steuerzeichen nur das Leerzeichen direkt
      <<c, _::binary>> when c < 32 or c == 127 ->
        {:error, "Steuerzeichen in Quotes (nur als Escape-Sequenz)", pos}

      <<c::utf8, rest::binary>> ->
        quoted(rest, q, pos + byte_size(<<c::utf8>>), [acc, <<c::utf8>>])

      <<_, _::binary>> ->
        {:error, "ungültiges UTF-8", pos}

      "" ->
        {:error, "Dateiende in Quotes", pos}
    end
  end

  @escapes %{
    ?a => 7,
    ?b => 8,
    ?f => 12,
    ?n => 10,
    ?r => 13,
    ?t => 9,
    ?v => 11,
    ?\\ => ?\\,
    ?' => ?',
    ?" => ?",
    ?` => ?`
  }

  # nach dem Backslash
  defp escape(<<?\n, rest::binary>>, pos), do: {:ok, :continuation, rest, pos + 1}

  defp escape(<<c, rest::binary>>, pos) when is_map_key(@escapes, c),
    do: {:ok, Map.fetch!(@escapes, c), rest, pos + 1}

  defp escape(<<?x, rest::binary>>, pos), do: numeric_escape(rest, 16, pos + 1)
  defp escape(<<c, _::binary>> = r, pos) when c in ?0..?7, do: numeric_escape(r, 8, pos)
  defp escape(_, pos), do: {:error, "unbekannte Escape-Sequenz", pos - 1}

  defp numeric_escape(r, base, pos) do
    {ds, rest} = radix_digits(r, base, 0)

    case rest do
      <<?\\, rest::binary>> when ds != "" ->
        c = String.to_integer(ds, base)

        if c <= 0x10FFFF and (c < 0xD800 or c > 0xDFFF),
          do: {:ok, c, rest, pos + byte_size(ds) + 1},
          else: {:error, "Zeichencode außerhalb von Unicode", pos}

      _ ->
        {:error, "Escape-Sequenz ohne abschließenden Backslash", pos}
    end
  end

  # ---------------------------------------------------------------------
  # Parser (ISO 6.3)

  # ein Operator allein ist ein ganzer Term (wie gprolog: "- ." liest -,
  # als Operand in "x :- - ." nicht)
  defp whole([{{kind, name}, _, _}, {:end, _, _} = e], _ctx) when kind in [:name, :qname],
    do: {a(name), 0, [e]}

  defp whole(toks, ctx), do: parse(toks, 1200, ctx) |> expect_end(ctx)

  defp expect_end({t, p, [{:end, _, _}] = rest}, _ctx), do: {t, p, rest}
  defp expect_end({_t, _p, [{tok, _, at} | _]}, _ctx), do: syntax!("Operator erwartet", at, tok)

  defp syntax!(msg, at, tok \\ nil) do
    msg = if tok, do: "#{msg} (bei #{show(tok)})", else: msg
    throw({:syntax, msg, at})
  end

  defp show({:p, s}), do: s
  defp show({:name, s}), do: s
  defp show({:qname, s}), do: "'#{s}'"
  defp show({:var, s}), do: s
  defp show({:num, n}), do: inspect(n)
  defp show({:str, s}), do: inspect(s)
  defp show({:bq, s}), do: "`#{s}`"
  defp show(:end), do: "Endezeichen"
  defp show(other), do: inspect(other)

  defp parse(toks, max, ctx) do
    {left, lp, rest} = primary(toks, max, ctx)

    if lp > max do
      [{_, _, at} | _] = toks
      syntax!("Priorität #{lp} zu hoch (höchstens #{max})", at)
    end

    infix(left, lp, rest, max, ctx)
  end

  # Argument (999); ein Operator als Atom ist hier erlaubt (ISO 6.3.3)
  defp arg([{{kind, name}, _, _}, {{:p, p}, _, _} | rest] = toks, ctx)
       when kind in [:name, :qname] and p in [",", ")", "|", "]", "}"] do
    if op?(ctx, name) do
      {a(name), tl(toks)}
    else
      _ = rest
      {t, _, rest} = parse(toks, 999, ctx)
      {t, rest}
    end
  end

  defp arg(toks, ctx) do
    {t, _, rest} = parse(toks, 999, ctx)
    {t, rest}
  end

  defp op?(ctx, name), do: Map.has_key?(ctx.ops, name)

  defp primary([{tok, _lay, at} | rest], max, ctx) do
    case tok do
      {:num, n} ->
        {n, 0, rest}

      {:var, "_"} ->
        {anon(), 0, rest}

      {:var, name} ->
        {{:var, name}, 0, rest}

      {:str, s} ->
        {text(s, ctx.dq), 0, rest}

      {:bq, s} ->
        {text(s, ctx.bq), 0, rest}

      # in Klammern auch ein Operator als Atom (Priorität 1201)
      {:p, "("} ->
        {t, _, rest} = parse(rest, 1201, ctx)
        {t, 0, close(rest, ")")}

      {:p, "["} ->
        case rest do
          [{{:p, "]"}, _, _} | rest] -> name_term("[]", rest, max, ctx, at)
          _ -> list(rest, ctx, [])
        end

      {:p, "{"} ->
        case rest do
          [{{:p, "}"}, _, _} | rest] ->
            name_term("{}", rest, max, ctx, at)

          _ ->
            {t, _, rest} = parse(rest, 1201, ctx)
            {mk("{}", [t]), 0, close(rest, "}")}
        end

      {kind, "-"} when kind in [:name, :qname] ->
        case rest do
          # ISO 6.3.4.1: "- 1" ist die Zahl -1 (wie gprolog), "-(1)" nicht
          [{{:num, n}, _, _} | rest] -> {neg(n), 0, rest}
          _ -> name_term("-", rest, max, ctx, at)
        end

      {kind, name} when kind in [:name, :qname] ->
        name_term(name, rest, max, ctx, at)

      {:p, _} ->
        syntax!("Term erwartet", at, tok)

      :end ->
        syntax!("Term erwartet", at, tok)
    end
  end

  defp primary([], _max, _ctx), do: syntax!("Term erwartet", 0)

  defp neg(n) when is_integer(n), do: -n
  defp neg(f), do: -f

  defp anon do
    {n, used} = Process.get(:prolog_ex_parser_anon)
    {name, n} = fresh_anon(n, used)
    Process.put(:prolog_ex_parser_anon, {n, used})
    {:var, name}
  end

  defp fresh_anon(n, used) do
    name = "_" <> Integer.to_string(n)
    if MapSet.member?(used, name), do: fresh_anon(n + 1, used), else: {name, n + 1}
  end

  defp close([{{:p, p}, _, _} | rest], p), do: rest
  defp close([{tok, _, at} | _], p), do: syntax!("#{p} erwartet", at, tok)

  # Name: Funktionsschreibweise, Präfixoperator oder Atom
  defp name_term(name, [{{:p, "("}, false, _} | rest], _max, ctx, _at) do
    {args, rest} = args(rest, ctx, [])
    {mk(name, args), 0, rest}
  end

  defp name_term(name, rest, max, ctx, at) do
    case PrologEx.Ops.lookup(ctx.ops, name, :prefix) do
      nil ->
        atom_term(name, rest, max, ctx, at)

      {p, type} ->
        if terminator?(rest) do
          atom_term(name, rest, max, ctx, at)
        else
          argmax = if type == "fy", do: p, else: p - 1

          try do
            {arg, _, rest2} = parse(rest, argmax, ctx)
            {mk(name, [arg]), p, rest2}
          catch
            {:syntax, _, _} = e ->
              if infix_next?(rest, ctx), do: atom_term(name, rest, max, ctx, at), else: throw(e)
          end
        end
    end
  end

  # Atom; ist es ein Operator, hat es Priorität 1201 (ISO 6.3.1.3) – außer
  # als Argument (siehe arg/2) oder in Klammern
  defp atom_term(name, rest, _max, ctx, _at) do
    p = if op?(ctx, name), do: 1201, else: 0
    {a(name), p, rest}
  end

  defp terminator?([{tok, _, _} | _]),
    do: tok == :end or tok in [{:p, ")"}, {:p, ","}, {:p, "|"}, {:p, "]"}, {:p, "}"}]

  defp infix_next?([{{kind, n}, _, _} | _], ctx) when kind in [:name, :qname],
    do:
      PrologEx.Ops.lookup(ctx.ops, n, :infix) != nil or
        PrologEx.Ops.lookup(ctx.ops, n, :postfix) != nil

  defp infix_next?([{{:p, p}, _, _} | _], _ctx), do: p in [",", "|"]
  defp infix_next?(_, _), do: false

  defp args(toks, ctx, acc) do
    {t, rest} = arg(toks, ctx)

    case rest do
      [{{:p, ","}, _, _} | rest] -> args(rest, ctx, [t | acc])
      [{{:p, ")"}, _, _} | rest] -> {Enum.reverse([t | acc]), rest}
      [{tok, _, at} | _] -> syntax!(", oder ) erwartet", at, tok)
    end
  end

  defp list(toks, ctx, acc) do
    {t, rest} = arg(toks, ctx)

    case rest do
      [{{:p, ","}, _, _} | rest] ->
        list(rest, ctx, [t | acc])

      [{{:p, "|"}, _, _} | rest] ->
        {tail, rest} = arg(rest, ctx)
        {PrologEx.list(Enum.reverse([t | acc]), tail), 0, close(rest, "]")}

      [{{:p, "]"}, _, _} | rest] ->
        {PrologEx.list(Enum.reverse([t | acc])), 0, rest}

      [{tok, _, at} | _] ->
        syntax!(", | oder ] erwartet", at, tok)
    end
  end

  defp text(s, "codes"), do: PrologEx.list(String.to_charlist(s))
  defp text(s, "chars"), do: PrologEx.list(for(c <- String.codepoints(s), do: a(c)))
  defp text(s, "atom"), do: a(s)

  # Infix- und Postfixoperatoren nach einem Term der Priorität lp
  defp infix(left, lp, [{tok, _, _} | after_op] = toks, max, ctx) do
    case tok do
      {kind, name} when kind in [:name, :qname] ->
        inf = PrologEx.Ops.lookup(ctx.ops, name, :infix)
        post = PrologEx.Ops.lookup(ctx.ops, name, :postfix)
        try_infix(left, lp, name, inf, post, after_op, toks, max, ctx)

      {:p, ","} when max >= 1000 and lp <= 999 ->
        {right, _, rest} = parse(after_op, 1000, ctx)
        infix(mk(",", [left, right]), 1000, rest, max, ctx)

      {:p, "|"} ->
        case PrologEx.Ops.lookup(ctx.ops, "|", :infix) do
          {p, type} when p <= max ->
            {la, ra} = sides(p, type)

            if lp <= la do
              {right, _, rest} = parse(after_op, ra, ctx)
              infix(mk("|", [left, right]), p, rest, max, ctx)
            else
              {left, lp, toks}
            end

          _ ->
            {left, lp, toks}
        end

      _ ->
        {left, lp, toks}
    end
  end

  defp try_infix(left, lp, name, inf, post, after_op, toks, max, ctx) do
    infix_ok =
      case inf do
        {p, type} ->
          {la, ra} = sides(p, type)
          if p <= max and lp <= la, do: {p, ra}, else: nil

        nil ->
          nil
      end

    post_ok =
      case post do
        {p, type} ->
          la = if type == "yf", do: p, else: p - 1
          if p <= max and lp <= la, do: p, else: nil

        nil ->
          nil
      end

    cond do
      infix_ok ->
        {p, ra} = infix_ok

        try do
          {right, _, rest} = parse(after_op, ra, ctx)
          infix(mk(name, [left, right]), p, rest, max, ctx)
        catch
          {:syntax, _, _} = e ->
            if post_ok, do: infix(mk(name, [left]), post_ok, after_op, max, ctx), else: throw(e)
        end

      post_ok ->
        infix(mk(name, [left]), post_ok, after_op, max, ctx)

      true ->
        {left, lp, toks}
    end
  end

  defp sides(p, "xfx"), do: {p - 1, p - 1}
  defp sides(p, "xfy"), do: {p - 1, p}
  defp sides(p, "yfx"), do: {p, p - 1}
end
