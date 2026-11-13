defmodule PrologEx.Builtins.CsvPrims do
  @moduledoc """
  Kern von SWIs Teil von `library(csv)` (`priv/library/csv.pl`): Lesen
  und Schreiben in `PrologEx.Csv`.
  """
  use PrologEx.Builtin
  alias PrologEx.{Csv, Error, Stream}
  import PrologEx.Builtins.IO, only: [input!: 2, output!: 2, current_in!: 1, current_out!: 1]

  # '$csv_parse'(+Quelle, +Record, -Zeilen): Quelle text(Codes|Zeichen)
  # oder stream(S); bindet die Stelligkeit im Record an die der ersten
  # Zeile (wie SWI); scheitert, wenn der Text kein CSV ist
  defbuiltin "$csv_parse", [source, record, rows] do
    rec = resolve(record)
    o = Csv.opts(rec)

    text =
      case resolve(source) do
        {:struct, "text", [l]} -> list_text(l)
        {:struct, "stream", [s]} -> read_rest(in_stream(s))
      end

    {:struct, _, rargs} = rec

    arity =
      case Enum.at(rargs, 6) do
        n when is_integer(n) -> n
        _ -> nil
      end

    match? = Enum.at(rargs, 7) == a("true")

    {status, field_rows} = Csv.parse(text, o)

    # wie SWI Zeile für Zeile: eine falsche Stelligkeit vor der Stelle, an
    # der der Text kein CSV mehr ist, ist ein Fehler
    case Csv.rows_terms(field_rows, o.functor, arity, match?) do
      {:arity, expected, actual} ->
        raise_arity(expected, actual)

      _ when status == :fail ->
        :fail

      {:ok, terms, nil} ->
        {:unify, [{rows, terms}]}

      {:ok, terms, first} ->
        {_, _, [_, _, _, _, _, _, ar, _, _]} = PrologEx.unmark_top(deref(record))
        {:unify, [{rows, terms}, {ar, first}]}
    end
  end

  # '$csv_read_record'(+Stream, +Record, -Felder): ein Datensatz wie
  # csv_read_row/3 (end_of_file am Ende); scheitert, wenn er kein CSV ist
  defbuiltin "$csv_read_record", [stream, record, fields] do
    id = in_stream(deref(stream))
    o = Csv.opts(resolve(record))

    case Csv.read_record(id, o) do
      :eof ->
        {:unify, [{fields, a("end_of_file")}]}

      :fail ->
        :fail

      text ->
        case Csv.parse_row(text, o) do
          {:ok, fs} -> {:unify, [{fields, fs}]}
          :fail -> :fail
        end
    end
  end

  # '$csv_value'(+Codes, +Record, -Wert): Feldwert wie make_value/3
  defbuiltin "$csv_value", [codes, record, value] do
    {:unify, [{value, Csv.value(list_text(resolve(codes)), Csv.opts(resolve(record)))}]}
  end

  # '$csv_emit'(+Zeilen, +Trenner, -Codes)
  defbuiltin "$csv_emit", [rows, sep, codes] do
    {:unify, [{codes, String.to_charlist(Csv.emit(list!(resolve(rows)), deref(sep)))}]}
  end

  # '$csv_write'(+Stream, +Zeilen, +Trenner)
  defbuiltin "$csv_write", [stream, rows, sep] do
    id = out_stream(deref(stream))
    Stream.put_text(id, Csv.emit(list!(resolve(rows)), deref(sep)))
    :ok
  end

  defp raise_arity(expected, actual),
    do: Error.error!(mk("domain_error", [mk("row_arity", [expected]), actual]))

  defp list!(l) when is_list(l), do: l
  defp list!({:var, _}), do: Error.instantiation!()
  defp list!(t), do: Error.type!("list", t)

  defp list_text(l) do
    Enum.map_join(l, fn
      {:atom, c} -> c
      c when is_integer(c) -> <<c::utf8>>
    end)
  end

  defp read_rest(id) do
    case Stream.read_rest(id) do
      :invalid -> read_rest(id, [])
      text -> text
    end
  end

  defp read_rest(id, acc) do
    case Stream.get_char(id) do
      :eof -> acc |> Enum.reverse() |> List.to_string()
      c when is_integer(c) -> read_rest(id, [c | acc])
      _ -> read_rest(id, acc)
    end
  end

  # wie bei SWI auch current_input bzw. current_output
  defp in_stream({:atom, "current_input"}), do: current_in!(:text)
  defp in_stream(st), do: input!(st, :text)

  defp out_stream({:atom, "current_output"}), do: current_out!(:text)
  defp out_stream(st), do: output!(st, :text)
end
