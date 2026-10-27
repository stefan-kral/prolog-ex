defmodule PrologEx.Stream do
  @moduledoc """
  Streams der Sitzung (ISO 7.10). Ein Stream ist in Prolog `'$stream'(N)`;
  die Tabelle liegt im Sitzungsprozess (wie Operatoren und Datenbank) und
  ist nicht backtrackbar.

  Vorhanden ab Start: `user_input` (0, stdin), `user_output` (1, stdout),
  `user_error` (2, stderr) – mit diesen Aliasen.

  Eingabe wird gepuffert (Dateien in Blöcken von 64 KB, stdin zeilenweise);
  Textstreams sind UTF-8 (ungültige Bytes gelten als Latin-1-Zeichen). Die
  Position zählt Zeichen, Zeilen (ab 1), Spalte und Bytes:
  `'$stream_position'(Zeichen, Zeile, Spalte, Bytes)`.

  Dateiende: der erste Leseversuch am Ende liefert end_of_file (-1) und
  setzt den Stream auf "past"; danach je nach `eof_action`: `error`
  (permission_error(input, past_end_of_stream, S)), `eof_code` (wieder
  end_of_file) oder `reset` (neu lesen – Standard für user_input).
  """

  alias PrologEx.Error

  @key :prolog_ex_streams
  @chunk 65_536

  defstruct [
    :id,
    :kind,
    :dev,
    :mode,
    :file_name,
    type: :text,
    aliases: [],
    reposition: false,
    eof_action: :eof_code,
    buf: "",
    eof: false,
    past: false,
    chars: 0,
    lines: 1,
    line_pos: 0,
    bytes: 0
  ]

  # --- Tabelle --------------------------------------------------------------

  defp table do
    case Process.get(@key) do
      nil ->
        t = initial()
        Process.put(@key, t)
        t

      t ->
        t
    end
  end

  defp put_table(t), do: Process.put(@key, t)

  # Jeder Stream liegt unter einem eigenen Schlüssel {@key, id} (ein
  # Zugriff je Zeichen, ohne die Tabelle neu zu bauen); die Tabelle hält
  # die Kennungen, Aliase und die aktuellen Streams.
  defp initial do
    for s <- [
          %__MODULE__{
            id: 0,
            kind: :stdin,
            mode: :read,
            aliases: ["user_input"],
            eof_action: :reset
          },
          %__MODULE__{id: 1, kind: :stdout, mode: :append, aliases: ["user_output"]},
          %__MODULE__{id: 2, kind: :stderr, mode: :append, aliases: ["user_error"]}
        ],
        do: Process.put({@key, s.id}, s)

    %{
      next: 3,
      streams: MapSet.new([0, 1, 2]),
      aliases: %{"user_input" => 0, "user_output" => 1, "user_error" => 2},
      input: 0,
      output: 1
    }
  end

  @doc "Zurück auf die Standardstreams (offene Dateien werden geschlossen)"
  def reset do
    case Process.get(@key) do
      nil ->
        :ok

      t ->
        for id <- t.streams, id > 2, do: close(id, true)
        for id <- [0, 1, 2], do: Process.delete({@key, id})
    end

    Process.delete(@key)
  end

  @doc "Prolog-Term eines Streams"
  def term(id), do: PrologEx.mk("$stream", [id])

  def get(id) do
    case Process.get({@key, id}) do
      nil ->
        table()
        Process.get({@key, id}) || raise ArgumentError, "kein Stream #{id}"

      s ->
        s
    end
  end

  defp update(%__MODULE__{id: id} = s) do
    Process.put({@key, id}, s)
    s
  end

  def current_input, do: table().input
  def current_output, do: table().output

  def set_input(id), do: put_table(%{table() | input: id})
  def set_output(id), do: put_table(%{table() | output: id})

  @doc "Alle offenen Streams (Kennungen, aufsteigend)"
  def all, do: table().streams |> Enum.sort()

  @doc """
  Stream aus einem Prolog-Term (dereferenziert): Kennung oder Fehler wie
  ISO – Variable: instantiation_error; weder Stream noch Alias:
  domain_error(stream_or_alias, S); nicht (mehr) offen:
  existence_error(stream, S).
  """
  def lookup!(t) do
    case t do
      {:var, _} ->
        Error.instantiation!()

      {tag, "$stream", [id]} when tag in [:struct, :gstruct] and is_integer(id) ->
        if MapSet.member?(table().streams, id), do: id, else: Error.existence!("stream", t)

      {:atom, a} ->
        case Map.fetch(table().aliases, a) do
          {:ok, id} -> id
          :error -> Error.existence!("stream", t)
        end

      other ->
        Error.domain!("stream_or_alias", other)
    end
  end

  # --- Öffnen und Schließen ---------------------------------------------------

  @doc """
  Datei öffnen. `mode`: :read | :write | :append; opts: type (:text |
  :binary), alias (Name oder nil), reposition (bool), eof_action.
  Ergebnis {:ok, id} | {:error, :enoent | :eacces | ...}.
  """
  def open_file(path, mode, opts) do
    flags =
      case mode do
        :read -> [:read]
        :write -> [:write]
        :append -> [:append]
      end

    case :file.open(path, [:raw, :binary | flags] ++ write_buffer(mode)) do
      {:ok, dev} ->
        t = table()
        id = t.next
        alias = Keyword.get(opts, :alias)

        s = %__MODULE__{
          id: id,
          kind: :file,
          dev: dev,
          mode: mode,
          file_name: Path.expand(path),
          type: Keyword.get(opts, :type, :text),
          aliases: if(alias, do: [alias], else: []),
          reposition: Keyword.get(opts, :reposition, true),
          eof_action: Keyword.get(opts, :eof_action, :eof_code)
        }

        aliases = if alias, do: Map.put(t.aliases, alias, id), else: t.aliases
        Process.put({@key, id}, s)
        put_table(%{t | next: id + 1, streams: MapSet.put(t.streams, id), aliases: aliases})
        {:ok, id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_buffer(:read), do: []
  defp write_buffer(_), do: [{:delayed_write, @chunk, 2000}]

  @doc "Ist der Alias schon vergeben?"
  def alias_taken?(name), do: Map.has_key?(table().aliases, name)

  @doc """
  Stream schließen. Standardstreams bleiben offen (ISO: close auf ihnen
  tut nichts); war er aktueller Ein-/Ausgabestrom, gilt wieder user_input
  bzw. user_output.
  """
  def close(id, _force \\ false) do
    t = table()

    if id <= 2 do
      :ok
    else
      s = get(id)
      if s.dev, do: :file.close(s.dev)
      Process.delete({@key, id})

      put_table(%{
        t
        | streams: MapSet.delete(t.streams, id),
          aliases: Map.reject(t.aliases, fn {_, v} -> v == id end),
          input: if(t.input == id, do: 0, else: t.input),
          output: if(t.output == id, do: 1, else: t.output)
      })

      :ok
    end
  end

  # --- Eingabe ----------------------------------------------------------------

  @doc "Ist der Stream ein Eingabestream?"
  def input?(id), do: get(id).mode == :read

  @doc """
  Nächstes Zeichen ansehen, ohne es zu lesen: {codepoint, bytes} | :eof.
  Liest bei Bedarf nach (stdin: eine Zeile).
  """
  def peek_char(id) do
    s = ensure(get(id), 1)

    case s.buf do
      "" ->
        :eof

      <<c::utf8, _::binary>> ->
        {c, size_of(c)}

      <<b0, _::binary>> = b when b0 >= 0xC0 and byte_size(b) < 4 and not s.eof ->
        # angefangenes UTF-8-Zeichen am Pufferende: nachlesen
        s = ensure(s, byte_size(b) + 1)
        if s.buf == b, do: {b0, 1}, else: peek_char(id)

      <<b0, _::binary>> ->
        # ungültiges UTF-8: als Latin-1
        {b0, 1}
    end
  end

  defp size_of(c), do: byte_size(<<c::utf8>>)

  @doc "Nächstes Zeichen lesen: codepoint | :eof (Position wird nachgeführt)"
  def get_char(id) do
    s = get(id)

    # Schnellweg: ein vollständiges Zeichen liegt im Puffer
    case s.buf do
      <<c, rest::binary>> when c < 128 ->
        update(advance(%{s | buf: rest}, c, 1))
        c

      <<c::utf8, rest::binary>> ->
        update(advance(%{s | buf: rest}, c, size_of(c)))
        c

      _ ->
        get_char_slow(id)
    end
  end

  defp get_char_slow(id) do
    case peek_char(id) do
      :eof ->
        :eof

      {c, n} ->
        s = get(id)
        {_, rest} = :erlang.split_binary(s.buf, n)
        update(advance(%{s | buf: rest}, c, n))
        c
    end
  end

  @doc "Nächstes Byte ansehen: 0..255 | :eof"
  def peek_byte(id) do
    case ensure(get(id), 1).buf do
      "" -> :eof
      <<b, _::binary>> -> b
    end
  end

  @doc "Nächstes Byte lesen: 0..255 | :eof"
  def get_byte(id) do
    case peek_byte(id) do
      :eof ->
        :eof

      b ->
        s = get(id)
        <<_, rest::binary>> = s.buf
        update(%{s | buf: rest, bytes: s.bytes + 1})
        b
    end
  end

  @doc """
  Liest den Text bis zum Ende des nächsten Terms (siehe
  PrologEx.TermScanner): {:term, text} | :eof | {:incomplete, text} (Datei
  endet mitten im Term).
  """
  def read_term_text(id) do
    s = get(id)

    case PrologEx.TermScanner.scan(s.buf, s.eof) do
      {:end, n} ->
        {text, rest} = :erlang.split_binary(s.buf, n)
        update(consume(%{s | buf: rest}, text))
        {:term, text}

      :empty ->
        # nur Leerraum/Kommentare bis zum Dateiende
        update(consume(%{s | buf: ""}, s.buf))
        :eof

      {:eof_inside, _} ->
        text = s.buf
        update(consume(%{s | buf: ""}, text))
        {:incomplete, text}

      :more ->
        s = fill(s)
        update(s)
        read_term_text(id)
    end
  end

  @doc "Am Dateiende angekommen (es kommt nichts mehr)?"
  def at_end?(id) do
    s = ensure(get(id), 1)
    s.buf == "" and s.eof
  end

  @doc "Lesen am Ende: der Stream steht jetzt hinter dem Ende (past)"
  def mark_past(id), do: update(%{get(id) | past: true})

  @doc "eof_action(reset): wieder lesen (stdin: auf neue Eingabe warten)"
  def reset_eof(id) do
    s = get(id)
    update(%{s | past: false, eof: s.kind in [:file, :memory] and s.eof})
    :ok
  end

  # mindestens n Bytes im Puffer, oder Dateiende
  defp ensure(s, n) do
    if byte_size(s.buf) >= n or s.eof do
      s
    else
      s |> fill() |> update() |> ensure(n)
    end
  end

  defp fill(%{eof: true} = s), do: s

  defp fill(%{kind: :file} = s) do
    case :file.read(s.dev, @chunk) do
      {:ok, data} -> %{s | buf: s.buf <> data}
      :eof -> %{s | eof: true}
      {:error, _} -> %{s | eof: true}
    end
  end

  defp fill(%{kind: :stdin} = s) do
    prompt = if PrologEx.Terminal.terminal?(), do: "|: ", else: ""

    case IO.gets(:stdio, prompt) do
      data when is_binary(data) -> %{s | buf: s.buf <> data}
      _ -> %{s | eof: true}
    end
  end

  defp fill(%{kind: :memory} = s), do: %{s | eof: true}
  defp fill(s), do: %{s | eof: true}

  # Position nach gelesenem Text
  defp consume(s, text) do
    for <<c::utf8 <- text>>, reduce: s do
      s -> advance(s, c, size_of(c))
    end
    |> then(&%{&1 | bytes: s.bytes + byte_size(text)})
  end

  defp advance(s, ?\n, n),
    do: %{s | chars: s.chars + 1, lines: s.lines + 1, line_pos: 0, bytes: s.bytes + n}

  defp advance(s, _c, n),
    do: %{s | chars: s.chars + 1, line_pos: s.line_pos + 1, bytes: s.bytes + n}

  @doc "Eingabestream aus Text (für term_to_atom, read_term_from_atom ...)"
  def open_memory(text) do
    t = table()
    id = t.next
    s = %__MODULE__{id: id, kind: :memory, mode: :read, buf: text, eof: true}
    Process.put({@key, id}, s)
    put_table(%{t | next: id + 1, streams: MapSet.put(t.streams, id)})
    id
  end

  @doc """
  Ausgabestream in den Speicher (für format/2 mit portray/1, später
  with_output_to/2): sammelt den Text; `memory_text/1` liefert ihn.
  """
  def open_memory_out do
    t = table()
    id = t.next
    s = %__MODULE__{id: id, kind: :memory_out, mode: :write, buf: []}
    Process.put({@key, id}, s)
    put_table(%{t | next: id + 1, streams: MapSet.put(t.streams, id)})
    id
  end

  @doc "Bisher in einen Speicher-Ausgabestream geschriebener Text"
  def memory_text(id), do: IO.iodata_to_binary(get(id).buf)

  # --- Ausgabe ----------------------------------------------------------------

  @doc "Text (UTF-8) ausgeben; Position wird nachgeführt"
  def put_text(id, text) do
    s = get(id)
    text = IO.iodata_to_binary(text)

    s =
      case s.kind do
        :stdout -> tap(s, fn _ -> IO.write(text) end)
        :stderr -> tap(s, fn _ -> IO.write(:stderr, text) end)
        :file -> tap(s, fn _ -> :file.write(s.dev, text) end)
        :memory_out -> %{s | buf: [s.buf | text]}
      end

    update(out_position(s, text))
    :ok
  end

  @doc "Byte ausgeben"
  def put_byte(id, b) do
    s = get(id)

    s =
      case s.kind do
        :stdout -> tap(s, fn _ -> IO.binwrite(<<b>>) end)
        :stderr -> tap(s, fn _ -> IO.binwrite(:stderr, <<b>>) end)
        :file -> tap(s, fn _ -> :file.write(s.dev, <<b>>) end)
        :memory_out -> %{s | buf: [s.buf | <<b>>]}
      end

    update(%{s | bytes: s.bytes + 1})
    :ok
  end

  @doc "Bytes (Binary) auf einmal ausgeben"
  def put_bytes(id, bin) do
    s = get(id)

    s =
      case s.kind do
        :stdout -> tap(s, fn _ -> IO.binwrite(bin) end)
        :stderr -> tap(s, fn _ -> IO.binwrite(:stderr, bin) end)
        :file -> tap(s, fn _ -> :file.write(s.dev, bin) end)
        :memory_out -> %{s | buf: [s.buf | bin]}
      end

    update(%{s | bytes: s.bytes + byte_size(bin)})
    :ok
  end

  @doc "Bis zu n Bytes lesen (weniger nur am Dateiende); Binary"
  def get_bytes(id, n) do
    s = ensure(get(id), n)
    k = min(n, byte_size(s.buf))
    {data, rest} = :erlang.split_binary(s.buf, k)
    update(%{s | buf: rest, bytes: s.bytes + k})
    data
  end

  @doc "Ausgabepuffer leeren"
  def flush(id) do
    s = get(id)

    # delayed_write leert jede weitere Dateioperation
    if s.kind == :file and s.mode != :read, do: :file.position(s.dev, :cur)
    :ok
  end

  defp out_position(s, text) do
    case :binary.matches(text, "\n") do
      [] ->
        n = char_count(text)
        %{s | chars: s.chars + n, line_pos: s.line_pos + n, bytes: s.bytes + byte_size(text)}

      matches ->
        {last, 1} = List.last(matches)
        tail = binary_part(text, last + 1, byte_size(text) - last - 1)

        %{
          s
          | chars: s.chars + char_count(text),
            lines: s.lines + length(matches),
            line_pos: char_count(tail),
            bytes: s.bytes + byte_size(text)
        }
    end
  end

  defp char_count(text) do
    if ascii?(text), do: byte_size(text), else: length(String.to_charlist(text))
  end

  defp ascii?(text), do: not String.match?(text, ~r/[^\x00-\x7f]/)

  # --- Eigenschaften und Position -------------------------------------------

  @doc "Position als Prolog-Term"
  def position(id) do
    s = get(id)
    PrologEx.mk("$stream_position", [s.chars, s.lines, s.line_pos, s.bytes])
  end

  @doc "end_of_stream: :at | :past | :not (ohne zu blockieren)"
  def end_of_stream(id) do
    s = get(id)

    cond do
      s.past -> :past
      s.buf == "" and s.eof -> :at
      s.buf == "" and s.kind in [:file, :memory] and at_file_end?(s) -> :at
      true -> :not
    end
  end

  defp at_file_end?(%{kind: :memory}), do: true

  defp at_file_end?(%{kind: :file, dev: dev}) do
    with {:ok, cur} <- :file.position(dev, :cur),
         {:ok, last} <- :file.position(dev, :eof),
         {:ok, _} <- :file.position(dev, cur) do
      cur >= last
    else
      _ -> false
    end
  end

  @doc "Position setzen (nur Dateien mit reposition(true))"
  def set_position(id, chars, lines, line_pos, bytes) do
    s = get(id)
    {:ok, _} = :file.position(s.dev, bytes)

    update(%{
      s
      | buf: "",
        eof: false,
        past: false,
        chars: chars,
        lines: lines,
        line_pos: line_pos,
        bytes: bytes
    })

    :ok
  end
end
