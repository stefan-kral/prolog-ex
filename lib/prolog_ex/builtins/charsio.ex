defmodule PrologEx.Builtins.Charsio do
  @moduledoc """
  Grundlagen für `library(charsio)` (priv/library/charsio.pl, aus Scryer
  Prolog): die `$`-Prädikate, die dort die Scryer-Maschine liefert.

  Zeichenklassen wie Scryer (`'$char_type'/2`): die ISO-Klassen des Lesers
  (`graphic`, `solo`, `layout`, ...) genau; die Unicode-Klassen
  (`alphabetic`, `lower`, `upper`, `numeric`, `control`, `whitespace`) über
  die allgemeinen Unicode-Kategorien:

    * `alphabetic`: Buchstaben (L) und Buchstabenzahlen (Nl)
    * `lower`/`upper`: Ll bzw. Lu
    * `numeric`: N; `control`: Cc; `whitespace`: die Unicode-Eigenschaft
      White_Space (fest, 25 Zeichen)

  Rust (Scryer) nimmt für die ersten drei die abgeleiteten Eigenschaften
  Alphabetic, Lowercase, Uppercase, die ein paar Zeichen mehr enthalten
  (z. B. kombinierende Vokalzeichen, ª, Ⓐ).
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.IO, as: PIO
  alias PrologEx.Error
  alias PrologEx.Stream, as: S

  @graphic ~c"#$&*+-./:<=>?@^~"
  @solo ~c"!(),;[]{}|%"
  @layout [?\s, ?\r, ?\n, ?\t, 0x0B, 0x0C]
  @meta ~c"\\'\"`"
  @whitespace [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680] ++
                Enum.to_list(0x2000..0x200A) ++ [0x2028, 0x2029, 0x202F, 0x205F, 0x3000]

  defp cat?(c, re), do: Regex.match?(re, <<c::utf8>>)

  defp alphabetic?(c), do: cat?(c, ~r/^[\p{L}\p{Nl}]$/u)
  defp numeric?(c), do: cat?(c, ~r/^\p{N}$/u)
  defp lower?(c), do: cat?(c, ~r/^\p{Ll}$/u)
  defp upper?(c), do: cat?(c, ~r/^\p{Lu}$/u)
  defp control?(c), do: cat?(c, ~r/^\p{Cc}$/u)
  defp whitespace?(c), do: c in @whitespace

  defp graphic_token?(c), do: c in @graphic or c == ?\\

  # Scryers alpha_char!: kein Zeichen einer anderen Klasse, oder _
  defp alpha?(c) do
    (not numeric?(c) and not whitespace?(c) and not control?(c) and not graphic_token?(c) and
       c not in @layout and c not in @meta and c not in @solo) or c == ?_
  end

  defp alnum?(c), do: alpha?(c) or numeric?(c)

  @doc false
  def type?(c, type) do
    case type do
      "alpha" -> alpha?(c)
      "alphabetic" -> alphabetic?(c)
      "alphanumeric" -> alphabetic?(c) or numeric?(c)
      "alnum" -> alnum?(c)
      "ascii" -> c < 128
      "ascii_punctuation" -> c in ~c"!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
      "ascii_graphic" -> c in 0x21..0x7E
      "binary_digit" -> c in ~c"01"
      "control" -> control?(c)
      "decimal_digit" -> c in ?0..?9
      "exponent" -> c in ~c"eE"
      "graphic" -> c in @graphic
      "graphic_token" -> graphic_token?(c)
      "hexadecimal_digit" -> c in ?0..?9 or c in ?a..?f or c in ?A..?F
      "layout" -> c in @layout
      "lower" -> lower?(c)
      "meta" -> c in @meta
      "numeric" -> numeric?(c)
      "octal_digit" -> c in ?0..?7
      "octet" -> c in 0..255
      "prolog" -> c in @graphic or alnum?(c) or c in @solo or c in @layout or c in @meta
      "sign" -> c in ~c"+-"
      "solo" -> c in @solo
      "symbolic_control" -> c in ~c"abfnrtv0"
      "symbolic_hexadecimal" -> c == ?x
      "upper" -> upper?(c)
      "whitespace" -> whitespace?(c)
    end
  end

  # '$char_type'(C, Typ): C ein Zeichen, Typ gültig (siehe charsio.pl)
  defbuiltin "$char_type", [c, type] do
    {:atom, <<ch::utf8>>} = deref(c)

    case deref(type) do
      {:atom, t} ->
        type?(ch, t)

      # wie in Scryers Doku: upper(U) mit U = Großschreibung von C als
      # Zeichenliste (ß → "SS"), lower(L) ebenso klein; ohne Klassenprüfung
      {:struct, "upper", [u]} ->
        {:unify, [{u, chars(String.upcase(<<ch::utf8>>))}]}

      {:struct, "lower", [l]} ->
        {:unify, [{l, chars(String.downcase(<<ch::utf8>>))}]}
    end
  end

  defp chars(text), do: list(for(<<c::utf8 <- text>>, do: a(<<c::utf8>>)))

  defp text_of(cs, s) do
    cs
    |> PrologEx.Builtins.Lists.items(s)
    |> Enum.map_join(fn t ->
      {:atom, c} = PrologEx.walk(t, s)
      c
    end)
  end

  # '$chars_input'(Cs, S): S liest den Text Cs (Speicherstream)
  defbuiltin "$chars_input", [cs, stream] do
    id = S.open_memory(text_of(cs, subst()))
    {:unify, [{stream, S.term(id)}]}
  end

  # '$write_term_chars'(T, Optionen, Cs): wie write_term/2, als Zeichen
  defbuiltin "$write_term_chars", [t, opts, cs] do
    o = PrologEx.Builtins.Core.write_options(opts, subst())
    text = PrologEx.Writer.format(resolve(t), o)
    {:unify, [{cs, chars(text)}]}
  end

  # '$get_n_chars'(S, N, Cs): bis zu N Zeichen (Binärstream: Bytes als
  # Zeichen); am Ende weniger, [] ganz am Ende
  defbuiltin "$get_n_chars", [stream, n, cs] do
    st = deref(stream)
    id = S.lookup!(st)

    read =
      case S.get(id) do
        %{type: :binary} ->
          id = PIO.input!(st, :binary)
          take(n_of(deref(n)), fn -> S.get_byte(id) end)

        _ ->
          id = PIO.input!(st, :text)

          take(n_of(deref(n)), fn ->
            if S.peek_char(id) == :eof, do: :eof, else: S.get_char(id)
          end)
      end

    {:unify, [{cs, list(for(c <- read, do: a(<<c::utf8>>)))}]}
  end

  defp n_of(n) do
    case n do
      i when is_integer(i) and i >= 0 -> i
      other -> Error.type!("integer", other)
    end
  end

  defp take(0, _next), do: []

  defp take(n, next) do
    case next.() do
      :eof -> []
      c -> [c | take(n - 1, next)]
    end
  end

  # '$chars_base64'(Cs, Bs, Padding, Charset): Cs offen → Bs dekodieren
  # (ungültig: scheitert), sonst Cs (Oktette) kodieren
  defbuiltin "$chars_base64", [cs, bs, padding, charset] do
    s = subst()
    pad = deref(padding) == {:atom, "true"}
    url = deref(charset) == {:atom, "url"}

    case deref(cs) do
      {:var, _} ->
        text = text_of(bs, s)

        decoded =
          if url,
            do: Base.url_decode64(text, padding: pad),
            else: Base.decode64(text, padding: pad)

        case decoded do
          {:ok, bytes} -> {:unify, [{cs, list(for(<<b <- bytes>>, do: a(<<b::utf8>>)))}]}
          :error -> :fail
        end

      _ ->
        bytes =
          for t <- PrologEx.Builtins.Lists.items(cs, s), into: <<>> do
            {:atom, <<c::utf8>>} = PrologEx.walk(t, s)
            <<c>>
          end

        enc =
          if url,
            do: Base.url_encode64(bytes, padding: pad),
            else: Base.encode64(bytes, padding: pad)

        {:unify, [{bs, chars(enc)}]}
    end
  end
end
