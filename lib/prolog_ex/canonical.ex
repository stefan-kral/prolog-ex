defmodule PrologEx.Canonical do
  @moduledoc """
  Parser für Terme in kanonischer Schreibweise (`write_canonical/1`):
  keine Operatoren, Listen als `'.'(H, T)` oder `[a, b | T]`.

      term   := var | number | atom ['(' term {',' term} ')']
              | '[' [term {',' term} ['|' term]] ']' | '{' term '}'
      atom   := name | 'quoted' | symbolzeichen | ! | ; | [] | {}

  Terme werden über `PrologEx.mk/2`, `a/1` und `cons/2` gebaut, sind also
  kanonisch und ground-markiert.

  Variablen behalten ihren Namen aus dem Text (bei gprolog z. B. `_14`).
  `rename_vars/2` ersetzt sie anschließend durch die Originalnamen aus
  `variable_names`.
  """

  import PrologEx, only: [a: 1, mk: 2, cons: 2, v: 1]

  @symbol_chars ~c"+-*/\\^<>=~:.?@#&$"

  @doc "Liest genau einen Term, optional mit abschließendem Punkt."
  def parse(text) do
    with {:ok, t, rest} <- term(skip_ws(text)) do
      case skip_ws(rest) do
        "" -> {:ok, t}
        "." <> r -> if skip_ws(r) == "", do: {:ok, t}, else: {:error, {:trailing, r}}
        r -> {:error, {:trailing, r}}
      end
    end
  end

  def parse!(text) do
    case parse(text) do
      {:ok, t} -> t
      {:error, e} -> raise ArgumentError, "kanonischer Term nicht lesbar: #{inspect(e)}"
    end
  end

  @doc """
  Ersetzt Variablennamen anhand einer `variable_names`-Liste
  (`['X' = _14, ...]` als Prolog-Term). Liefert auch die Zuordnung
  `%{"_14" => "X"}` zurück.
  """
  def rename_vars(term, var_names) do
    map =
      var_names
      |> PrologEx.unmark()
      |> prolog_list()
      |> Map.new(fn {:struct, "=", [{:atom, name}, {:var, internal}]} -> {internal, name} end)

    {rename(term, map), map}
  end

  defp prolog_list([]), do: []
  defp prolog_list([h | t]), do: [h | prolog_list(t)]

  defp rename({:var, n} = var, map) do
    case Map.fetch(map, n) do
      {:ok, name} -> v(name)
      :error -> var
    end
  end

  defp rename(t, map) do
    case t do
      {tag, f, args} when tag in [:struct, :gstruct] ->
        mk(f, Enum.map(args, &rename(&1, map)))

      [h | tl] ->
        cons(rename(h, map), rename(tl, map))

      {:glist, _} ->
        t

      _ ->
        t
    end
  end

  # ---------------------------------------------------------------------
  # Terme
  # ---------------------------------------------------------------------

  defp term(<<c, _::binary>> = s) when c in ?A..?Z or c == ?_, do: variable(s)
  defp term(<<c, _::binary>> = s) when c in ?0..?9, do: number(s, "")

  defp term(<<?-, c, _::binary>> = s) when c in ?0..?9,
    do: number(binary_part(s, 1, byte_size(s) - 1), "-")

  defp term("[" <> rest), do: list_or_nil(skip_ws(rest))
  defp term("{" <> rest), do: curly(skip_ws(rest))
  defp term(""), do: {:error, :unexpected_end}

  defp term(s) do
    with {:ok, name, rest} <- atom_name(s) do
      case rest do
        "(" <> r -> compound(name, skip_ws(r))
        _ -> {:ok, a(name), rest}
      end
    end
  end

  defp compound(name, s) do
    with {:ok, args, rest} <- args(s, []) do
      {:ok, mk(name, args), rest}
    end
  end

  defp args(s, acc) do
    with {:ok, t, rest} <- term(s) do
      case skip_ws(rest) do
        "," <> r -> args(skip_ws(r), [t | acc])
        ")" <> r -> {:ok, Enum.reverse([t | acc]), r}
        r -> {:error, {:expected, ", or )", r}}
      end
    end
  end

  defp list_or_nil("]" <> rest), do: name_tail("[]", rest)

  defp list_or_nil(s) do
    with {:ok, items, tail, rest} <- list_items(s, []) do
      {:ok, PrologEx.list(items, tail), rest}
    end
  end

  defp list_items(s, acc) do
    with {:ok, t, rest} <- term(s) do
      case skip_ws(rest) do
        "," <> r ->
          list_items(skip_ws(r), [t | acc])

        "|" <> r ->
          with {:ok, tail, rest} <- term(skip_ws(r)) do
            case skip_ws(rest) do
              "]" <> r -> {:ok, Enum.reverse([t | acc]), tail, r}
              r -> {:error, {:expected, "]", r}}
            end
          end

        "]" <> r ->
          {:ok, Enum.reverse([t | acc]), [], r}

        r ->
          {:error, {:expected, ", | or ]", r}}
      end
    end
  end

  defp curly("}" <> rest), do: name_tail("{}", rest)

  defp curly(s) do
    with {:ok, t, rest} <- term(s) do
      case skip_ws(rest) do
        "}" <> r -> {:ok, mk("{}", [t]), r}
        r -> {:error, {:expected, "}", r}}
      end
    end
  end

  # '[]' bzw. '{}' als Atom, ggf. als Funktor: {}(x), [](x)
  defp name_tail(name, "(" <> r), do: compound(name, skip_ws(r))
  defp name_tail(name, rest), do: {:ok, a(name), rest}

  # ---------------------------------------------------------------------
  # Token
  # ---------------------------------------------------------------------

  defp variable(s) do
    {name, rest} = take_while(s, &alnum?/1)
    {:ok, v(name), rest}
  end

  defp number(s, sign) do
    {int, rest} = take_while(s, &(&1 in ?0..?9))

    case rest do
      <<?', c, r::binary>> when int == "0" ->
        # 0'c Zeichencode (kommt bei write_canonical kaum vor)
        {:ok, if(sign == "-", do: -c, else: c), r}

      <<?., d, _::binary>> when d in ?0..?9 ->
        <<?., r::binary>> = rest
        {frac, r} = take_while(r, &(&1 in ?0..?9))
        {exp, r} = exponent(r)
        {:ok, String.to_float(sign <> int <> "." <> frac <> exp), r}

      _ ->
        {:ok, String.to_integer(sign <> int), rest}
    end
  end

  defp exponent(<<e, rest::binary>>) when e in [?e, ?E] do
    {sgn, rest} =
      case rest do
        <<s, r::binary>> when s in [?+, ?-] -> {<<s>>, r}
        _ -> {"", rest}
      end

    case take_while(rest, &(&1 in ?0..?9)) do
      {"", _} -> {"", <<e, rest::binary>>}
      {digits, r} -> {"e" <> sgn <> digits, r}
    end
  end

  defp exponent(rest), do: {"", rest}

  defp atom_name("'" <> rest), do: quoted(rest, [])
  defp atom_name("!" <> rest), do: {:ok, "!", rest}
  defp atom_name(";" <> rest), do: {:ok, ";", rest}
  defp atom_name("," <> rest), do: {:ok, ",", rest}
  defp atom_name("|" <> rest), do: {:ok, "|", rest}

  # Kleinbuchstabe oder Nicht-ASCII (UTF-8-Bytes >= 128) am Anfang
  defp atom_name(<<c, _::binary>> = s) when c in ?a..?z or c >= 128 do
    {name, rest} = take_while(s, &alnum?/1)
    {:ok, name, rest}
  end

  defp atom_name(<<c, _::binary>> = s) when c in @symbol_chars do
    {name, rest} = take_while(s, &(&1 in @symbol_chars))
    {:ok, name, rest}
  end

  defp atom_name(s), do: {:error, {:unexpected, String.slice(s, 0, 20)}}

  defp quoted("''" <> rest, acc), do: quoted(rest, [?' | acc])
  defp quoted("'" <> rest, acc), do: {:ok, acc |> Enum.reverse() |> List.to_string(), rest}
  defp quoted("\\" <> rest, acc), do: escape(rest, acc)
  defp quoted(<<c::utf8, rest::binary>>, acc), do: quoted(rest, [c | acc])
  defp quoted("", _), do: {:error, :unterminated_quote}

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

  # \xHH..\ hexadezimal, \NNN\ oktal, \<Zeilenumbruch> = Fortsetzung
  defp escape("x" <> rest, acc) do
    {hex, r} = take_while(rest, &hex?/1)
    "\\" <> r = r
    quoted(r, [String.to_integer(hex, 16) | acc])
  end

  defp escape(<<d, _::binary>> = rest, acc) when d in ?0..?7 do
    case take_while(rest, &(&1 in ?0..?7)) do
      {oct, "\\" <> r} -> quoted(r, [String.to_integer(oct, 8) | acc])
      {_, _} -> quoted(binary_part(rest, 1, byte_size(rest) - 1), [0 | acc])
    end
  end

  defp escape("\n" <> rest, acc), do: quoted(rest, acc)

  defp escape(<<c, rest::binary>>, acc) do
    case Map.fetch(@escapes, c) do
      {:ok, ch} -> quoted(rest, [ch | acc])
      :error -> {:error, {:bad_escape, <<c>>}}
    end
  end

  defp alnum?(c), do: c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c >= 128
  defp hex?(c), do: c in ?0..?9 or c in ?a..?f or c in ?A..?F

  defp take_while(s, pred), do: take_while(s, pred, 0)

  defp take_while(s, pred, n) do
    case s do
      <<_::binary-size(n), c, _::binary>> ->
        if pred.(c), do: take_while(s, pred, n + 1), else: split(s, n)

      _ ->
        split(s, n)
    end
  end

  defp split(s, n), do: {binary_part(s, 0, n), binary_part(s, n, byte_size(s) - n)}

  defp skip_ws(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: skip_ws(rest)
  defp skip_ws(s), do: s
end
