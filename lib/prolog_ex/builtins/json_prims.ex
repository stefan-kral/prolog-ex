defmodule PrologEx.Builtins.JsonPrims do
  @moduledoc """
  Kern von `library(http/json)` (`priv/library/http/json.pl`): Lesen und
  Schreiben in `PrologEx.Json`.
  """
  use PrologEx.Builtin
  alias PrologEx.{Json, Stream}
  import PrologEx.Builtins.IO, only: [input!: 2, output!: 2, current_in!: 1, current_out!: 1]

  # '$json_read'(+Stream, -Term, +Optionen); wie bei SWI darf Stream auch
  # current_input bzw. current_output sein
  defbuiltin "$json_read", [stream, t, opts] do
    st = deref(stream)
    id = if st == a("current_input"), do: current_in!(:text), else: input!(st, :text)
    {:unify, [{t, Json.read(id, st, Json.options(opt_list(resolve(opts))))}]}
  end

  # '$json_write'(+Stream, +Term, +Optionen)
  defbuiltin "$json_write", [stream, t, opts] do
    st = deref(stream)
    id = if st == a("current_output"), do: current_out!(:text), else: output!(st, :text)
    o = Json.options(opt_list(resolve(opts)))

    case Json.write(resolve(t), o, Stream.get(id).line_pos) do
      {:ok, out} ->
        Stream.put_text(id, IO.iodata_to_binary(out))
        :ok

      {:error, out, e, stack} ->
        Stream.put_text(id, IO.iodata_to_binary(out))
        reraise e, stack
    end
  end

  # '$json_read_text'(+Text, -Term, +Optionen): Text (Atom, Zahl, Code-
  # oder Zeichenliste) als JSON lesen, über einen Stream im Speicher
  defbuiltin "$json_read_text", [text, t, opts] do
    o = Json.options(opt_list(resolve(opts)))
    id = Stream.open_memory(text!(resolve(text)))

    try do
      {:unify, [{t, Json.read(id, Stream.term(id), o)}]}
    after
      Stream.close(id)
    end
  end

  # '$json_write_text'(+Term, +Typ, -Text, +Optionen): Term als JSON-Text
  # vom Typ atom, codes oder chars (string: nach double_quotes)
  defbuiltin "$json_write_text", [t, type, text, opts] do
    o = Json.options(opt_list(resolve(opts)))

    s =
      case Json.write(resolve(t), o, 0) do
        {:ok, out} -> IO.iodata_to_binary(out)
        {:error, _, e, stack} -> reraise e, stack
      end

    out =
      case deref(type) do
        {:atom, "atom"} -> a(s)
        {:atom, "codes"} -> String.to_charlist(s)
        {:atom, "chars"} -> for c <- String.codepoints(s), do: a(c)
        {:atom, "string"} -> PrologEx.Builtins.JsonPrims.dq_text(s)
      end

    {:unify, [{text, out}]}
  end

  @doc false
  def dq_text(s) do
    case PrologEx.Flags.get("double_quotes") do
      {:atom, "codes"} -> String.to_charlist(s)
      {:atom, "atom"} -> {:atom, s}
      _ -> for c <- String.codepoints(s), do: {:atom, c}
    end
  end

  defp opt_list(l) when is_list(l), do: l
  defp opt_list(_), do: []

  defp text!({:atom, s}), do: s
  defp text!(n) when is_number(n), do: PrologEx.Writer.format(n)
  defp text!([]), do: ""

  defp text!(l) when is_list(l) do
    Enum.map_join(l, fn
      {:atom, c} -> c
      c when is_integer(c) -> <<c::utf8>>
    end)
  end
end
