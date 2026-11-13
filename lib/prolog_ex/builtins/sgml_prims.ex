defmodule PrologEx.Builtins.SgmlPrims do
  @moduledoc """
  Kern von `library(sgml)` (`priv/library/sgml.pl`): Laden und Schreiben
  in `PrologEx.Sgml`.
  """
  use PrologEx.Builtin
  alias PrologEx.{Error, Sgml, Stream}
  import PrologEx.Builtins.IO, only: [input!: 2, output!: 2, current_out!: 1]

  # '$sgml_load'(+Art, +Quelle, -DOM, +Optionen): Art xml oder html,
  # Quelle text(Zeichen), stream(S) oder file(Name); scheitert, wenn XML
  # nicht wohlgeformt ist (wie Scryer)
  defbuiltin "$sgml_load", [kind, source, dom, opts] do
    kind = if deref(kind) == a("html"), do: :html, else: :xml

    text =
      case resolve(source) do
        {:struct, "text", [cs]} -> chars_text(cs)
        {:struct, "stream", [s]} -> read_rest(input!(s, :text))
        {:struct, "file", [f]} -> read_file(f)
      end

    case Sgml.load(kind, text, opt_list(resolve(opts))) do
      :fail -> :fail
      terms -> {:unify, [{dom, terms}]}
    end
  end

  # '$sgml_write'(+Dialekt, +Stream, +DOM, +Optionen): wie SWIs xml_write/3
  # bzw. html_write/3
  defbuiltin "$sgml_write", [dialect, stream, dom, opts] do
    dialect = if deref(dialect) == a("html"), do: :html, else: :xml

    id =
      case deref(stream) do
        {:atom, "user"} -> output!(a("user_output"), :text)
        {:atom, "current_output"} -> current_out!(:text)
        st -> output!(st, :text)
      end

    o =
      case resolve(opts) do
        l when is_list(l) -> l
        {:var, _} -> Error.instantiation!()
        other -> Error.type!("list", other)
      end

    case Sgml.write(dialect, resolve(dom), o, Stream.get(id).line_pos) do
      {:ok, out} ->
        Stream.put_text(id, IO.iodata_to_binary(out))
        :ok

      {:error, out, e, stack} ->
        Stream.put_text(id, IO.iodata_to_binary(out))
        reraise e, stack
    end
  end

  defp opt_list(l) when is_list(l), do: l
  defp opt_list(_), do: []

  defp chars_text(cs) do
    Enum.map_join(cs, fn
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

  defp read_file(f) do
    path =
      case f do
        {:atom, p} -> p
        l when is_list(l) -> chars_text(l)
      end

    case File.read(path) do
      {:ok, bin} ->
        if String.valid?(bin), do: bin, else: :unicode.characters_to_binary(bin, :latin1)

      {:error, :enoent} ->
        Error.existence!("source_sink", f)

      {:error, _} ->
        Error.permission!("open", "source_sink", f)
    end
  end
end
