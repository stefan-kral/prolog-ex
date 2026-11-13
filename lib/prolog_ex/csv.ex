defmodule PrologEx.Csv do
  @moduledoc """
  CSV lesen und schreiben wie SWI-Prologs `library(csv)` (`csv//1,2`,
  `csv_read_file/2,3`, `csv_read_stream/3`, `csv_read_row/3`,
  `csv_write_file/2,3`, `csv_write_stream/3` in `priv/library/csv.pl`).

  Optionen als SWIs Record `csv_options(Trenner, Strip, IgnoreQuotes,
  Convert, Case, Functor, Arity, MatchArity, SkipHeader)`.

  Lesen wie SWI 9: Felder bis zum Trenner oder Zeilenende (`\\n`, `\\r\\n`,
  `\\r`); ein Feld in `"…"` mit `""` für `"`, danach muss Trenner oder
  Zeilenende folgen, sonst scheitert das Lesen; eine leere Zeile ist eine
  Zeile mit einem leeren Feld. `strip(true)` entfernt Leerzeichen und Tabs
  am Rand (Anführungszeichen nach Leerraum bleiben, wie bei SWI, Teil des
  Feldes). `convert(true)` macht aus Zahlen Zahlen (ohne Leerraum, auch
  `+5`, `0x1A`, `1e10`), sonst Atome; `case(down|up)` ändert die
  Schreibung.
  """
  import PrologEx, only: [a: 1, mk: 2]

  @doc "Optionen aus dem Record (aufgelöst)"
  def opts({:struct, "csv_options", [sep, strip, iq, conv, cas, fun, _ar, _ma, skip]}) do
    %{
      sep: sep,
      strip: strip == a("true"),
      ignore_quotes: iq == a("true"),
      convert: conv == a("true"),
      case: elem(cas, 1),
      functor: elem(fun, 1),
      skip_header:
        case skip do
          {:atom, s} -> s
          _ -> nil
        end
    }
  end

  # --- Lesen ---------------------------------------------------------------------

  @doc """
  Ganzen Text lesen: `{:ok, [felder]}` oder `:fail` (wie SWIs csv//2 auf
  einer Liste)
  """
  def parse(text, o) do
    text = if o.skip_header, do: skip_header(text, o.skip_header), else: text
    rows(text, o, [])
  catch
    :csv_fail -> :fail
  end

  defp rows("", _o, acc), do: {:ok, Enum.reverse(acc)}

  defp rows(text, o, acc) do
    {fields, rest} = row(text, o, [])
    rows(rest, o, [fields | acc])
  end

  @doc "Eine Zeile (schon ohne Zeilenende-Fortsetzung): Felder oder :fail"
  def parse_row(text, o) do
    case row(text, o, []) do
      {fields, ""} -> {:ok, fields}
      _ -> :fail
    end
  catch
    :csv_fail -> :fail
  end

  # Felder einer Zeile bis einschließlich Zeilenende
  defp row(text, o, acc) do
    {v, rest} = field(text, o)
    acc = [v | acc]

    case rest do
      <<c::utf8, r::binary>> when c == o.sep -> row(r, o, acc)
      _ -> {Enum.reverse(acc), end_of_record(rest)}
    end
  end

  defp end_of_record("\n" <> r), do: r
  defp end_of_record("\r\n" <> r), do: r
  defp end_of_record("\r" <> r), do: r
  defp end_of_record(""), do: ""
  defp end_of_record(_), do: throw(:csv_fail)

  defp field("\"" <> rest, %{ignore_quotes: false} = o) do
    {s, r} = quoted(rest, [])
    {value(s, o), r}
  end

  defp field(text, %{strip: true} = o) do
    text = trim_ws(text)
    {s, r} = field_codes(text, o.sep)
    {value(trim_trailing_ws(s), o), r}
  end

  defp field(text, o) do
    {s, r} = field_codes(text, o.sep)
    {value(s, o), r}
  end

  defp trim_ws(<<c, r::binary>>) when c in [?\s, ?\t], do: trim_ws(r)
  defp trim_ws(t), do: t

  defp trim_trailing_ws(s), do: String.replace(s, ~r/[ \t]+\z/, "")

  defp quoted(text, acc) do
    case :binary.match(text, "\"") do
      {pos, 1} ->
        <<part::binary-size(^pos), "\"", r::binary>> = text

        case r do
          "\"" <> r2 -> quoted(r2, [acc, part, "\""])
          _ -> {IO.iodata_to_binary([acc, part]), r}
        end

      :nomatch ->
        throw(:csv_fail)
    end
  end

  defp field_codes(text, sep) do
    pat = Process.get({__MODULE__, sep}) || compile_pattern(sep)

    case :binary.match(text, pat) do
      {pos, _} ->
        <<f::binary-size(^pos), r::binary>> = text
        {f, r}

      :nomatch ->
        {text, ""}
    end
  end

  defp compile_pattern(sep) do
    pat = :binary.compile_pattern([<<sep::utf8>>, "\n", "\r"])
    Process.put({__MODULE__, sep}, pat)
    pat
  end

  defp skip_header(text, prefix) do
    if text != "" and String.starts_with?(text, prefix) do
      case :binary.match(text, ["\n", "\r"]) do
        {_, _} -> text |> drop_line() |> skip_header(prefix)
        :nomatch -> ""
      end
    else
      skip_blank_lines(text)
    end
  end

  defp drop_line(text) do
    [_, rest] = String.split(text, ~r/\r\n|\n|\r/, parts: 2)
    rest
  end

  defp skip_blank_lines("\r\n" <> r), do: skip_blank_lines(r)
  defp skip_blank_lines("\n" <> r), do: skip_blank_lines(r)
  defp skip_blank_lines("\r" <> r), do: skip_blank_lines(r)
  defp skip_blank_lines(t), do: t

  @doc "Wert eines Feldes (wie SWIs make_value/3)"
  def value(s, o) do
    n = if o.convert, do: number(s), else: nil

    cond do
      n != nil -> n
      o.case == "down" -> a(String.downcase(s))
      o.case == "up" -> a(String.upcase(s))
      true -> a(s)
    end
  end

  # Zahl wie SWIs name/2: ganzer Text, ohne Leerraum am Rand; "+" davor
  # erlaubt
  defp number(<<c, _::binary>> = s) when c in ?0..?9 or c == ?+ or c == ?- do
    t =
      case s do
        "+" <> r -> r
        _ -> s
      end

    cond do
      t == "" -> nil
      :binary.last(s) in [?\s, ?\t, ?\n, ?\r, ?\f, ?\v] -> nil
      match?(<<?-, w, _::binary>> when w in [?\s, ?\t, ?\n, ?\r, ?\f, ?\v], t) -> nil
      true -> parse_num(t)
    end
  end

  defp number(_), do: nil

  defp parse_num(t) do
    case simple_num(t) do
      nil -> parse_num_general(t)
      n -> n
    end
  end

  # Schnellweg: -?Ziffern bzw. -?Ziffern.Ziffern (dann wie Erlang)
  defp simple_num(t) do
    {body, _neg} =
      case t do
        "-" <> r -> {r, true}
        r -> {r, false}
      end

    case digits(body, 0) do
      {n, ""} when n > 0 ->
        String.to_integer(t)

      {n, "." <> frac} when n > 0 ->
        case digits(frac, 0) do
          {m, ""} when m > 0 and m + n < 300 -> :erlang.binary_to_float(t)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp digits(<<c, r::binary>>, n) when c in ?0..?9, do: digits(r, n + 1)
  defp digits(r, n), do: {n, r}

  defp parse_num_general(t) do
    case PrologEx.Builtins.Atoms.parse_number(t) do
      {:ok, n} ->
        n

      _ ->
        # wie SWI auch 1e10 (ohne Nachkommastellen) als Float
        case Regex.run(~r/\A(-?\d+)([eE][+-]?\d+)\z/, t) do
          [_, m, e] ->
            case PrologEx.Builtins.Atoms.parse_number(m <> ".0" <> e) do
              {:ok, n} -> n
              _ -> nil
            end

          nil ->
            nil
        end
    end
  end

  @doc """
  Einen Datensatz vom Stream lesen wie SWIs csv_read_row/3: Zeilen (ohne
  Zeilenende), bis die Zahl der `"` gerade ist; `:eof` am Ende
  """
  def read_record(id, o) do
    case read_line(id) do
      :eof -> :eof
      line -> more_lines(id, line, o)
    end
  end

  defp more_lines(id, text, o) do
    if o.ignore_quotes or even_quotes?(text) do
      text
    else
      case read_line(id) do
        :eof -> text
        line -> more_lines(id, text <> "\n" <> line, o)
      end
    end
  end

  defp even_quotes?(text), do: rem(length(:binary.matches(text, "\"")), 2) == 0

  # wie read_line_to_codes/2: ohne "\n" (und "\r" davor); :eof am Ende
  defp read_line(id) do
    case PrologEx.Stream.get_char(id) do
      :eof -> :eof
      c -> read_line(id, [c])
    end
  end

  defp read_line(_id, [?\n | acc]),
    do: acc |> Enum.reverse() |> List.to_string() |> String.replace_suffix("\r", "")

  defp read_line(id, acc) do
    case PrologEx.Stream.get_char(id) do
      :eof -> acc |> Enum.reverse() |> List.to_string()
      c -> read_line(id, [c | acc])
    end
  end

  @doc "Zeilen zu Termen, Stelligkeit prüfen: {:ok, rows, erste} | {:arity, erwartet, ist}"
  def rows_terms(field_rows, functor, arity, match?) do
    Enum.reduce_while(field_rows, {:ok, [], arity}, fn fields, {:ok, acc, ar} ->
      n = length(fields)

      cond do
        ar == nil or ar == n -> {:cont, {:ok, [mk(functor, fields) | acc], n}}
        not match? -> {:cont, {:ok, [mk(functor, fields) | acc], ar}}
        true -> {:halt, {:arity, ar, n}}
      end
    end)
    |> case do
      {:ok, acc, ar} -> {:ok, Enum.reverse(acc), ar}
      err -> err
    end
  end

  # --- Schreiben -------------------------------------------------------------------

  @doc "Zeilen als CSV-Text wie SWIs emit_csv//2 (jede Zeile mit \\r\\n)"
  def emit(rows, sep) do
    for row <- rows, into: "" do
      fields =
        case row do
          {tag, _, args} when tag in [:struct, :gstruct] -> args
          {:atom, _} -> []
          _ -> PrologEx.Error.type!("compound", row)
        end

      Enum.map_join(fields, <<sep::utf8>>, &emit_field(&1, sep)) <> "\r\n"
    end
  end

  defp emit_field({:atom, s}, sep), do: emit_text(s, sep)
  defp emit_field([], _sep), do: "[]"
  defp emit_field(n, _sep) when is_number(n), do: PrologEx.Builtins.Atoms.number_string(n)
  defp emit_field({:rat, _, _} = r, _sep), do: PrologEx.Builtins.Atoms.number_string(r)

  defp emit_field(l, sep) when is_list(l) do
    if Enum.all?(l, &(match?({:atom, <<_::utf8>>}, &1) or (is_integer(&1) and &1 >= 0))),
      do:
        emit_text(
          Enum.map_join(l, fn
            {:atom, c} -> c
            c -> <<c::utf8>>
          end),
          sep
        ),
      else: PrologEx.Error.type!("number", l)
  end

  defp emit_field({:var, _}, _sep), do: PrologEx.Error.instantiation!()
  defp emit_field(t, _sep), do: PrologEx.Error.type!("number", t)

  defp emit_text(s, sep) do
    esc = String.replace(s, "\"", "\"\"")

    if String.contains?(s, ["\"", "\n", "\r", <<sep::utf8>>]),
      do: "\"" <> esc <> "\"",
      else: esc
  end
end
