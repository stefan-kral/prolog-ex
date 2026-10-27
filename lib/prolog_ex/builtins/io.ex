defmodule PrologEx.Builtins.IO do
  @moduledoc """
  Ein- und Ausgabe über Streams (ISO 8.11–8.14), siehe `PrologEx.Stream`.

  Streams: `open/3,4`, `close/1,2`, `current_input/1`, `current_output/1`,
  `set_input/1`, `set_output/1`, `flush_output/0,1`, `stream_property/2`,
  `at_end_of_stream/0,1`, `set_stream_position/2`; dazu `line_count/2`,
  `line_position/2`, `character_count/2` (SICStus/SWI).

  Zeichen und Bytes: `get_char/1,2`, `peek_char/1,2`, `put_char/1,2`,
  `get_code/1,2`, `peek_code/1,2`, `put_code/1,2`, `get_byte/1,2`,
  `peek_byte/1,2`, `put_byte/1,2`, `nl/1`.

  Terme: `read/1,2`, `read_term/2,3` (Optionen `variables/1`,
  `variable_names/1`, `singletons/1`), `write/2`, `writeq/2`, `print/2`,
  `write_canonical/2`, `write_term/3`.

  `open/4`-Optionen: `type(text|binary)`, `alias(A)`,
  `reposition(true|false)`, `eof_action(error|eof_code|reset)`,
  `encoding(utf8)`. Fehler wie ISO (instantiation, type, domain,
  existence, permission – z. B. permission_error(input, binary_stream, S),
  permission_error(input, past_end_of_stream, S)).
  """
  use PrologEx.Builtin
  alias PrologEx.{Error, Reader, Writer}
  alias PrologEx.Stream, as: S
  alias PrologEx.Builtins.Lists

  # ---------------------------------------------------------------------
  # Öffnen, Schließen, aktuelle Streams
  # ---------------------------------------------------------------------

  defbuiltin "open", [src, mode, stream] do
    open(src, mode, stream, [], subst())
  end

  defbuiltin "open", [src, mode, stream, opts] do
    open(src, mode, stream, opts, subst())
  end

  # Dateien wie SWI: exists_file/1, exists_directory/1, delete_file/1
  defbuiltin "exists_file", [f] do
    if File.regular?(fs_path!(f, subst())), do: :ok, else: :fail
  end

  defbuiltin "exists_directory", [f] do
    if File.dir?(fs_path!(f, subst())), do: :ok, else: :fail
  end

  defbuiltin "delete_file", [f] do
    case File.rm(fs_path!(f, subst())) do
      :ok -> :ok
      {:error, :enoent} -> Error.existence!("file", PrologEx.resolve(f, subst()))
      {:error, _} -> Error.permission!("delete", "file", PrologEx.resolve(f, subst()))
    end
  end

  # Dateiname: Atom oder Zeichen-/Codeliste
  defp fs_path!(f, s) do
    case PrologEx.walk(f, s) do
      {:var, _} ->
        Error.instantiation!()

      {:atom, p} ->
        p

      [_ | _] = l ->
        try do
          PrologEx.Builtins.Modules.file_name(PrologEx.resolve(l, s))
        rescue
          PrologEx.Error -> Error.type!("atom", PrologEx.resolve(l, s))
        end

      {:glist, _} = l ->
        PrologEx.Builtins.Modules.file_name(PrologEx.resolve(l, s))

      other ->
        Error.type!("atom", PrologEx.resolve(other, s))
    end
  end

  defbuiltin "close", [stream] do
    S.close(S.lookup!(deref(stream)))
    :ok
  end

  defbuiltin "close", [stream, opts] do
    id = S.lookup!(deref(stream))

    for o <- option_list!(opts, subst()) do
      case o do
        {:struct, "force", [{:atom, b}]} when b in ["true", "false"] -> :ok
        {:var, _} -> Error.instantiation!()
        other -> Error.domain!("close_option", other)
      end
    end

    S.close(id)
    :ok
  end

  defbuiltin "current_input", [stream] do
    check_stream_arg!(deref(stream))
    {:unify, [{stream, S.term(S.current_input())}]}
  end

  defbuiltin "current_output", [stream] do
    check_stream_arg!(deref(stream))
    {:unify, [{stream, S.term(S.current_output())}]}
  end

  defbuiltin "set_input", [stream] do
    S.set_input(input!(deref(stream), :any))
    :ok
  end

  defbuiltin "set_output", [stream] do
    S.set_output(output!(deref(stream), :any))
    :ok
  end

  defbuiltin "flush_output", [] do
    S.flush(S.current_output())
    :ok
  end

  defbuiltin "flush_output", [stream] do
    S.flush(output!(deref(stream), :any))
    :ok
  end

  defbuiltin "at_end_of_stream", [] do
    S.at_end?(S.current_input()) or S.end_of_stream(S.current_input()) == :past
  end

  defbuiltin "at_end_of_stream", [stream] do
    id = input!(deref(stream), :any)
    S.end_of_stream(id) == :past or S.at_end?(id)
  end

  defbuiltin "set_stream_position", [stream, pos] do
    st = deref(stream)
    id = S.lookup!(st)

    case PrologEx.unmark_top(deref(pos)) do
      {:var, _} ->
        Error.instantiation!()

      {:struct, "$stream_position", [c, l, lp, b]}
      when is_integer(c) and is_integer(l) and is_integer(lp) and is_integer(b) ->
        s = S.get(id)

        unless s.kind == :file and s.reposition and s.mode == :read,
          do: Error.permission!("reposition", "stream", st)

        S.set_position(id, c, l, lp, b)

      other ->
        Error.domain!("stream_position", resolve(other))
    end
  end

  defbuiltin "stream_property", [stream, prop], nondet: true do
    ids =
      case deref(stream) do
        {:var, _} ->
          S.all()

        {tag, "$stream", [id]} = st when tag in [:struct, :gstruct] and is_integer(id) ->
          if id in S.all(), do: [id], else: Error.existence!("stream", st)

        other ->
          Error.domain!("stream", other)
      end

    p = PrologEx.unmark_top(deref(prop))
    check_property!(p)

    for id <- ids,
        q <- properties(id),
        matches_property?(p, q),
        do: {:unify, [{stream, S.term(id)}, {prop, q}]}
  end

  defbuiltin "line_count", [stream, n] do
    {:unify, [{n, S.get(S.lookup!(deref(stream))).lines}]}
  end

  defbuiltin "line_position", [stream, n] do
    {:unify, [{n, S.get(S.lookup!(deref(stream))).line_pos}]}
  end

  defbuiltin "character_count", [stream, n] do
    {:unify, [{n, S.get(S.lookup!(deref(stream))).chars}]}
  end

  # ---------------------------------------------------------------------
  # Zeichen, Codes, Bytes
  # ---------------------------------------------------------------------

  defbuiltin "get_char", [c] do
    get_char(current_in!(:text), a("user_input"), c, deref(c), :char, false)
  end

  defbuiltin "get_char", [stream, c] do
    st = deref(stream)
    get_char(input!(st, :text), st, c, deref(c), :char, false)
  end

  defbuiltin "peek_char", [c] do
    get_char(current_in!(:text), a("user_input"), c, deref(c), :char, true)
  end

  defbuiltin "peek_char", [stream, c] do
    st = deref(stream)
    get_char(input!(st, :text), st, c, deref(c), :char, true)
  end

  defbuiltin "get_code", [c] do
    get_char(current_in!(:text), a("user_input"), c, deref(c), :code, false)
  end

  defbuiltin "get_code", [stream, c] do
    st = deref(stream)
    get_char(input!(st, :text), st, c, deref(c), :code, false)
  end

  defbuiltin "peek_code", [c] do
    get_char(current_in!(:text), a("user_input"), c, deref(c), :code, true)
  end

  defbuiltin "peek_code", [stream, c] do
    st = deref(stream)
    get_char(input!(st, :text), st, c, deref(c), :code, true)
  end

  defbuiltin "get_byte", [b] do
    get_byte(current_in!(:binary), a("user_input"), b, deref(b), false)
  end

  defbuiltin "get_byte", [stream, b] do
    st = deref(stream)
    get_byte(input!(st, :binary), st, b, deref(b), false)
  end

  defbuiltin "peek_byte", [b] do
    get_byte(current_in!(:binary), a("user_input"), b, deref(b), true)
  end

  defbuiltin "peek_byte", [stream, b] do
    st = deref(stream)
    get_byte(input!(st, :binary), st, b, deref(b), true)
  end

  defbuiltin "put_char", [c] do
    put_char(current_out!(:text), c, subst())
  end

  defbuiltin "put_char", [stream, c] do
    put_char(output!(deref(stream), :text), c, subst())
  end

  defbuiltin "put_code", [c] do
    put_code(current_out!(:text), c, subst())
  end

  defbuiltin "put_code", [stream, c] do
    put_code(output!(deref(stream), :text), c, subst())
  end

  defbuiltin "put_byte", [b] do
    put_byte(current_out!(:binary), b, subst())
  end

  defbuiltin "put_byte", [stream, b] do
    put_byte(output!(deref(stream), :binary), b, subst())
  end

  defbuiltin "nl", [stream] do
    S.put_text(output!(deref(stream), :text), "\n")
  end

  # ---------------------------------------------------------------------
  # Terme
  # ---------------------------------------------------------------------

  defbuiltin "read", [t] do
    read_term(current_in!(:text), a("user_input"), t, [], subst())
  end

  defbuiltin "read", [stream, t] do
    st = deref(stream)
    read_term(input!(st, :text), st, t, [], subst())
  end

  defbuiltin "read_term", [t, opts] do
    read_term(current_in!(:text), a("user_input"), t, opts, subst())
  end

  defbuiltin "read_term", [stream, t, opts] do
    st = deref(stream)
    read_term(input!(st, :text), st, t, opts, subst())
  end

  defbuiltin "write", [stream, x] do
    write_to(stream, x, [numbervars: true], subst())
  end

  defbuiltin "print", [stream, x] do
    id = output!(deref(stream), :text)
    S.put_text(id, PrologEx.Builtins.Core.print_text(x, subst()))
    :ok
  end

  defbuiltin "writeq", [stream, x] do
    write_to(stream, x, PrologEx.Builtins.Core.writeq_opts(), subst())
  end

  defbuiltin "write_canonical", [stream, x] do
    write_to(stream, x, [quoted: true, ignore_ops: true], subst())
  end

  defbuiltin "write_term", [stream, x, opts] do
    o = PrologEx.Builtins.Core.write_options(opts, subst())
    write_to(stream, x, o, subst())
  end

  # read_term_from_atom(+Atom, -T, +Optionen), term_to_atom(?T, ?Atom)
  # (SWI): Atom als Text lesen (ein Term, Punkt am Ende optional) bzw. T
  # wie writeq schreiben
  defbuiltin "read_term_from_atom", [atom, t, opts] do
    read_from_atom(deref(atom), t, opts, subst())
  end

  defbuiltin "term_to_atom", [t, atom] do
    case deref(atom) do
      {:var, _} ->
        text = Writer.format(resolve(t), quoted: true, ignore_ops: false)
        {:unify, [{atom, a(text)}]}

      at ->
        read_from_atom(at, t, [], subst())
    end
  end

  # ---------------------------------------------------------------------

  defp read_from_atom(at, t, opts, s) do
    text =
      case at do
        {:var, _} -> Error.instantiation!()
        {:atom, x} -> x
        [] -> "[]"
        n when is_number(n) -> Writer.format(n)
        other -> Error.type!("atom", PrologEx.resolve(other, s))
      end

    # Punkt anhängen, falls der Text keinen hat
    text =
      if Regex.match?(~r/(^|[^.#$&*+\-\/:<=>?@^~\\])\.\s*$/, text), do: text, else: text <> " ."

    id = S.open_memory(text)

    try do
      read_term(id, S.term(id), t, opts, s)
    after
      S.close(id)
    end
  end

  @doc "Text auf den aktuellen Ausgabestrom (write/1, nl/0, listing ...)"
  def out(text), do: S.put_text(current_out!(:text), text)

  defp write_to(stream, x, opts, s) do
    id = output!(PrologEx.walk(stream, s), :text)
    S.put_text(id, Writer.format(PrologEx.resolve(x, s), opts))
  end

  # --- open ---------------------------------------------------------------

  defp open(src, mode, stream, opts, s) do
    src = PrologEx.walk(src, s)
    mode = PrologEx.walk(mode, s)

    if match?({:var, _}, src) or match?({:var, _}, mode), do: Error.instantiation!()

    options = option_list!(opts, s)

    m =
      case mode do
        {:atom, m} when m in ["read", "write", "append"] -> String.to_atom(m)
        {:atom, _} -> Error.domain!("io_mode", mode)
        other -> Error.type!("atom", PrologEx.resolve(other, s))
      end

    case PrologEx.walk(stream, s) do
      {:var, _} -> :ok
      other -> Error.uninstantiation!(PrologEx.resolve(other, s))
    end

    open_opts = Enum.map(options, &open_option!/1)

    # Atom, oder Zeichen-/Codeliste ("datei" mit double_quotes=chars/codes,
    # wie Strings in SWI)
    path =
      case PrologEx.unmark_top(src) do
        {:atom, p} ->
          p

        [_ | _] = l ->
          try do
            PrologEx.Builtins.Modules.file_name(PrologEx.resolve(l, s))
          rescue
            PrologEx.Error -> Error.domain!("source_sink", PrologEx.resolve(l, s))
          end

        other ->
          Error.domain!("source_sink", PrologEx.resolve(other, s))
      end

    case Keyword.get(open_opts, :alias) do
      nil ->
        :ok

      al ->
        if S.alias_taken?(al),
          do: Error.permission!("open", "source_sink", mk("alias", [a(al)]))
    end

    case S.open_file(path, m, open_opts) do
      {:ok, id} ->
        {:unify, [{stream, S.term(id)}]}

      {:error, :enoent} ->
        Error.existence!("source_sink", src)

      {:error, _} ->
        Error.permission!("open", "source_sink", src)
    end
  end

  defp open_option!({:struct, "type", [{:atom, t}]}) when t in ["text", "binary"],
    do: {:type, String.to_atom(t)}

  defp open_option!({:struct, "reposition", [{:atom, b}]}) when b in ["true", "false"],
    do: {:reposition, b == "true"}

  defp open_option!({:struct, "alias", [{:atom, al}]}), do: {:alias, al}

  defp open_option!({:struct, "eof_action", [{:atom, e}]})
       when e in ["error", "eof_code", "reset"],
       do: {:eof_action, String.to_atom(e)}

  defp open_option!({:struct, "encoding", [{:atom, e}]}) when e in ["utf8", "UTF-8"],
    do: {:encoding, :utf8}

  defp open_option!({:var, _}), do: Error.instantiation!()

  # bekannte Option mit ungebundenem Wert: instantiation_error (ISO 8.11.5.3)
  defp open_option!({:struct, name, [{:var, _}]})
       when name in ~w(type reposition alias eof_action encoding),
       do: Error.instantiation!()

  defp open_option!(other), do: Error.domain!("stream_option", other)

  # Optionenliste: Elemente aufgelöst; Teilliste oder Variable darin:
  # instantiation_error; keine Liste: type_error(list, ...)
  defp option_list!(opts, s) do
    case Lists.skip_list(opts, s) do
      {_, []} -> :ok
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(opts, s))
    end

    for o <- Lists.items(opts, s) do
      case PrologEx.unmark(PrologEx.resolve(o, s)) do
        {:var, _} -> Error.instantiation!()
        t -> t
      end
    end
  end

  defp check_stream_arg!({:var, _}), do: :ok

  # ein geschlossener Stream ist kein Stream mehr (ISO 8.11.1.3)
  defp check_stream_arg!({tag, "$stream", [id]} = t)
       when tag in [:struct, :gstruct] and is_integer(id) do
    if id in S.all(), do: :ok, else: Error.domain!("stream", t)
  end

  defp check_stream_arg!(other), do: Error.domain!("stream", other)

  # --- Eingabe- und Ausgabestreams prüfen ------------------------------------

  # kind: :text, :binary oder :any
  @doc false
  def input!(st, kind) do
    id = S.lookup!(st)
    s = S.get(id)
    unless s.mode == :read, do: Error.permission!("input", "stream", st)
    check_type!(s, kind, "input", st)
    id
  end

  @doc false
  def output!(st, kind) do
    id = S.lookup!(st)
    s = S.get(id)
    if s.mode == :read, do: Error.permission!("output", "stream", st)
    check_type!(s, kind, "output", st)
    id
  end

  @doc false
  def current_in!(kind), do: input!(S.term(S.current_input()), kind)
  @doc false
  def current_out!(kind), do: output!(S.term(S.current_output()), kind)

  defp check_type!(%{type: :binary}, :text, dir, st),
    do: Error.permission!(dir, "binary_stream", st)

  defp check_type!(%{type: :text}, :binary, dir, st),
    do: Error.permission!(dir, "text_stream", st)

  defp check_type!(_, _, _, _), do: :ok

  # --- Dateiende ----------------------------------------------------------------

  # vor dem Lesen: Stream schon hinter dem Ende? Dann nach eof_action
  defp pre_read(id, st) do
    s = S.get(id)

    cond do
      not s.past -> :ok
      s.eof_action == :error -> Error.permission!("input", "past_end_of_stream", st)
      s.eof_action == :reset -> S.reset_eof(id)
      true -> :eof
    end
  end

  # --- Zeichen ----------------------------------------------------------------

  defp get_char(id, st, c, cw, how, peek?) do
    check_in_char!(cw, how)

    result =
      case pre_read(id, st) do
        :eof ->
          :eof

        :ok ->
          case S.peek_char(id) do
            :eof ->
              unless peek?, do: S.mark_past(id)
              :eof

            {ch, _} ->
              unless peek?, do: S.get_char(id)
              ch
          end
      end

    value =
      case {result, how} do
        {:eof, :char} -> a("end_of_file")
        {:eof, :code} -> -1
        {ch, :char} -> a(<<ch::utf8>>)
        {ch, :code} -> ch
      end

    {:unify, [{c, value}]}
  end

  # get_char: C Variable oder Zeichen/end_of_file; get_code: Variable
  # oder Code/-1 (ISO: type_error(in_character, C),
  # representation_error(in_character_code))
  defp check_in_char!({:var, _}, _), do: :ok
  defp check_in_char!({:atom, "end_of_file"}, :char), do: :ok

  defp check_in_char!({:atom, ch} = t, :char),
    do: if(match?([_], String.to_charlist(ch)), do: :ok, else: Error.type!("in_character", t))

  defp check_in_char!(other, :char), do: Error.type!("in_character", PrologEx.unmark(other))
  defp check_in_char!(-1, :code), do: :ok

  defp check_in_char!(n, :code) when is_integer(n) do
    if n >= 0 and n <= 0x10FFFF and (n < 0xD800 or n > 0xDFFF),
      do: :ok,
      else: Error.representation!("in_character_code")
  end

  defp check_in_char!(other, :code), do: Error.type!("integer", PrologEx.unmark(other))

  defp get_byte(id, st, b, bw, peek?) do
    case bw do
      {:var, _} -> :ok
      n when is_integer(n) and n >= -1 and n <= 255 -> :ok
      other -> Error.type!("in_byte", PrologEx.unmark(other))
    end

    result =
      case pre_read(id, st) do
        :eof ->
          :eof

        :ok ->
          case S.peek_byte(id) do
            :eof ->
              unless peek?, do: S.mark_past(id)
              :eof

            byte ->
              unless peek?, do: S.get_byte(id)
              byte
          end
      end

    {:unify, [{b, if(result == :eof, do: -1, else: result)}]}
  end

  defp put_char(id, c, s) do
    case PrologEx.walk(c, s) do
      {:var, _} ->
        Error.instantiation!()

      {:atom, ch} = t ->
        if match?([_], String.to_charlist(ch)),
          do: S.put_text(id, ch),
          else: Error.type!("character", t)

      other ->
        Error.type!("character", PrologEx.resolve(other, s))
    end
  end

  defp put_code(id, c, s) do
    case PrologEx.walk(c, s) do
      {:var, _} ->
        Error.instantiation!()

      n when is_integer(n) and n >= 0 and n <= 0x10FFFF and (n < 0xD800 or n > 0xDFFF) ->
        S.put_text(id, <<n::utf8>>)

      n when is_integer(n) ->
        Error.representation!("character_code")

      other ->
        Error.type!("integer", PrologEx.resolve(other, s))
    end
  end

  defp put_byte(id, b, s) do
    case PrologEx.walk(b, s) do
      {:var, _} -> Error.instantiation!()
      n when is_integer(n) and n >= 0 and n <= 255 -> S.put_byte(id, n)
      other -> Error.type!("byte", PrologEx.resolve(other, s))
    end
  end

  # --- read_term --------------------------------------------------------------

  defp read_term(id, st, t, opts, s) do
    options = option_list!(opts, s) |> Enum.map(&read_option!(&1, s))

    case pre_read(id, st) do
      :eof ->
        {:unify, [{t, a("end_of_file")} | read_results(options, [], [], [])]}

      :ok ->
        case S.read_term_text(id) do
          :eof ->
            S.mark_past(id)
            {:unify, [{t, a("end_of_file")} | read_results(options, [], [], [])]}

          {:incomplete, _text} ->
            Error.syntax!("end_of_file_in_term")

          {:term, text} ->
            parse(text, t, options)
        end
    end
  end

  # das Argument muss eine Variable oder eine (Teil-)Liste sein
  defp read_option!({:struct, name, [x]} = o, s)
       when name in ["variables", "variable_names", "singletons"] do
    case PrologEx.Builtins.Lists.skip_list(x, s) do
      {_, []} -> o
      {_, {:var, _}} -> o
      _ -> Error.domain!("read_option", PrologEx.resolve(o, s))
    end
  end

  defp read_option!(other, s), do: Error.domain!("read_option", PrologEx.resolve(other, s))

  # Text (Term samt Punkt) mit gprolog lesen. Verpackt als '$pure'((...)),
  # damit der Reader Direktiven wie ":- op(...)" nicht ausführt.
  defp parse(text, t, options) do
    body = text |> String.trim_trailing() |> String.trim_trailing(".")

    case Reader.read_terms(Reader.current(), "'$pure'((" <> body <> "\n)).\n") do
      [{:term, wrapped, names}] ->
        {:struct, "$pure", [term]} = PrologEx.unmark_top(wrapped)
        {term, vars, named, singles} = fresh(term, names)
        {:unify, [{t, term} | read_results(options, vars, named, singles)]}

      [{:error, msg} | _] ->
        Error.syntax!(syntax_text(msg))

      _ ->
        Error.syntax!("unreadable")
    end
  end

  defp syntax_text(msg) do
    msg |> String.replace_prefix("Syntaxfehler: ", "") |> String.trim()
  end

  # Variablen des gelesenen Terms durch frische ersetzen; Ergebnis:
  # {Term, alle Variablen, [{Name, Var}] der benannten, Singletons}
  defp fresh(term, names) do
    user_names = MapSet.new(Map.values(names))
    {order, counts} = var_occurrences(term, {[], %{}})
    order = Enum.reverse(order)
    map = Map.new(order, &{&1, fresh_var()})
    term = rename(term, map)
    vars = Enum.map(order, &Map.fetch!(map, &1))

    named = for {:var, n} = v <- order, MapSet.member?(user_names, n), do: {n, Map.fetch!(map, v)}

    singles = for {n, v} <- named, Map.fetch!(counts, {:var, n}) == 1, do: {n, v}
    {term, vars, named, singles}
  end

  defp var_occurrences(t, {order, counts} = acc) do
    case t do
      {:var, _} = v ->
        if Map.has_key?(counts, v),
          do: {order, Map.update!(counts, v, &(&1 + 1))},
          else: {[v | order], Map.put(counts, v, 1)}

      {tag, _, args} when tag in [:struct, :gstruct] ->
        Enum.reduce(args, acc, &var_occurrences/2)

      [h | tl] ->
        var_occurrences(tl, var_occurrences(h, acc))

      _ ->
        acc
    end
  end

  defp rename({:var, _} = v, map), do: Map.fetch!(map, v)
  defp rename({:struct, f, args}, map), do: mk(f, Enum.map(args, &rename(&1, map)))
  defp rename([h | t], map), do: PrologEx.cons(rename(h, map), rename(t, map))
  defp rename(t, _map), do: t

  defp read_results(options, vars, named, singles) do
    for {:struct, name, [arg]} <- options do
      value =
        case name do
          "variables" -> list(vars)
          "variable_names" -> list(for {n, v} <- named, do: mk("=", [a(n), v]))
          "singletons" -> list(for {n, v} <- singles, do: mk("=", [a(n), v]))
        end

      {arg, value}
    end
  end

  # --- stream_property --------------------------------------------------------

  @props ~w(file_name mode input output alias position end_of_stream eof_action reposition type)

  defp check_property!({:var, _}), do: :ok
  defp check_property!({:atom, p}) when p in ["input", "output"], do: :ok

  defp check_property!({tag, p, [_]}) when tag in [:struct, :gstruct] and p in @props,
    do: :ok

  defp check_property!(other), do: Error.domain!("stream_property", resolve_term(other))

  defp resolve_term(t), do: PrologEx.unmark(t)

  defp matches_property?({:var, _}, _), do: true
  defp matches_property?({:atom, p}, {:atom, p}), do: true
  defp matches_property?({tag, p, _}, {:struct, p, _}) when tag in [:struct, :gstruct], do: true
  defp matches_property?({tag, p, _}, {:gstruct, p, _}) when tag in [:struct, :gstruct], do: true
  defp matches_property?(_, _), do: false

  defp properties(id) do
    s = S.get(id)

    ([
       if(s.file_name, do: mk("file_name", [a(s.file_name)])),
       mk("mode", [a(Atom.to_string(s.mode))]),
       a(if s.mode == :read, do: "input", else: "output")
     ] ++
       Enum.map(s.aliases, &mk("alias", [a(&1)])) ++
       [
         mk("position", [S.position(id)]),
         if(s.mode == :read, do: mk("end_of_stream", [a(Atom.to_string(S.end_of_stream(id)))])),
         if(s.mode == :read, do: mk("eof_action", [a(Atom.to_string(s.eof_action))])),
         mk("reposition", [a(to_string(s.reposition and s.kind == :file))]),
         mk("type", [a(Atom.to_string(s.type))])
       ])
    |> Enum.reject(&is_nil/1)
  end
end
