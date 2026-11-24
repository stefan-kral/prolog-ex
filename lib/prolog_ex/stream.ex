defmodule PrologEx.Stream do
  @moduledoc """
  Streams der Sitzung (ISO 7.10). Ein Stream ist in Prolog `'$stream'(N)`;
  die Tabelle liegt im Sitzungsprozess (wie Operatoren und Datenbank) und
  ist nicht backtrackbar.

  Vorhanden ab Start: `user_input` (0, stdin), `user_output` (1, stdout),
  `user_error` (2, stderr) – mit diesen Aliasen.

  Eingabe wird gepuffert (Dateien in Blöcken von 64 KB, stdin zeilenweise);
  Textstreams sind UTF-8; ein ungültiges Byte ist kein Zeichen:
  `representation_error(character)` (Neumerkel stc #76), beim Lesen mit
  get_char/get_code wird es dabei verbraucht, bei peek_char nicht. Die
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
    # UTF-8-BOM am Anfang gelesen und übersprungen (open/4, bom(true))
    bom: false,
    eof: false,
    past: false,
    chars: 0,
    lines: 1,
    line_pos: 0,
    bytes: 0,
    # library(pio): gelesene Blöcke der faulen Liste, Nr. => {Zeichen,
    # Zeile, Spalte am Anfang, Text}; verschwindet mit dem Stream
    lazy: %{},
    # Speicher-Stream, im Bereich ohne Seiteneffekte auf dieser Tiefe
    # geöffnet (with_output_to/2, portray): dort darf hinein geschrieben
    # werden (PrologEx.Effects)
    nse_depth: nil
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

  @doc """
  Steht Stream id am Zeilenanfang? Ohne die Tabelle anzulegen (eine Abfrage
  von außen, etwa der Kreisel des Toplevels, darf den Zustand nicht
  ändern – sonst gälte das Vorausrechnen als Seiteneffekt): ein Stream,
  den es noch nicht gibt, hat noch nichts geschrieben.
  """
  def line_start?(id) do
    case Process.get({@key, id}) do
      nil -> true
      s -> s.line_pos == 0
    end
  end

  def get(id) do
    case Process.get({@key, id}) do
      nil ->
        table()
        Process.get({@key, id}) || raise ArgumentError, "kein Stream #{id}"

      s ->
        s
    end
  end

  @doc "Den Stream als im Bereich ohne Seiteneffekte auf Tiefe d geöffnet vermerken"
  def set_nse_depth(id, d), do: update(%{get(id) | nse_depth: d})

  @doc """
  Die Dateien schließen, die ein Bereich ohne Seiteneffekte geöffnet und
  offen gelassen hat (Ende eines Elements von library(concurrent))
  """
  def close_scoped_files do
    case Process.get(@key) do
      nil ->
        :ok

      t ->
        for id <- t.streams,
            match?(%__MODULE__{kind: :file, nse_depth: d} when d != nil, Process.get({@key, id})),
            do: close(id, true)

        :ok
    end
  end

  @doc "Tiefe, auf der der Stream im Bereich ohne Seiteneffekte geöffnet wurde (oder nil)"
  def nse_depth(id) do
    case Process.get({@key, id}) do
      %__MODULE__{nse_depth: d} -> d
      _ -> nil
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

  @doc "Kennung zu einem Alias (oder nil), ohne die Tabelle anzulegen"
  def alias_id(a) do
    case Process.get(@key) do
      nil -> nil
      t -> Map.get(t.aliases, a)
    end
  end

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

    # pipe: true – eine benannte Pipe (library(process)): ungepuffert, ohne
    # Dateinamen, nicht positionierbar
    pipe? = Keyword.get(opts, :pipe, false)
    buffer = if pipe?, do: [], else: write_buffer(mode)

    case :file.open(path, [:raw, :binary | flags] ++ buffer) do
      {:ok, dev} ->
        t = table()
        id = t.next
        alias = Keyword.get(opts, :alias)

        s = %__MODULE__{
          id: id,
          kind: :file,
          dev: dev,
          mode: mode,
          file_name: if(pipe?, do: nil, else: Path.expand(path)),
          type: Keyword.get(opts, :type, :text),
          aliases: if(alias, do: [alias], else: []),
          reposition: Keyword.get(opts, :reposition, not pipe?),
          eof_action: Keyword.get(opts, :eof_action, :eof_code)
        }

        s = if pipe?, do: s, else: skip_bom(s, Keyword.get(opts, :bom, true))
        aliases = if alias, do: Map.put(t.aliases, alias, id), else: t.aliases
        Process.put({@key, id}, s)
        put_table(%{t | next: id + 1, streams: MapSet.put(t.streams, id), aliases: aliases})
        {:ok, id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Wie SWI (open/4, bom(Bool), beim Lesen Vorgabe true) und Scryer: ein
  # UTF-8-BOM am Anfang einer Textdatei gehört nicht zum Text. Die
  # Byte-Position zählt es mit (sie ist der Versatz in der Datei); was
  # kein BOM ist, kommt in den Puffer.
  defp skip_bom(%{mode: :read, type: :text} = s, true) do
    case :file.read(s.dev, 3) do
      {:ok, <<0xEF, 0xBB, 0xBF>>} -> %{s | bom: true, bytes: 3}
      {:ok, data} -> %{s | buf: data}
      _ -> s
    end
  end

  defp skip_bom(s, _), do: s

  @doc """
  Lesendes Ende einer benannten Pipe (library(process)): ein Port liest sie
  mit cat; seine Daten kommen, sobald sie da sind (eine rohe Datei würde
  auf volle Blöcke warten). Der Name wird gelöscht, sobald beide Enden
  offen sind.
  """
  def open_pipe_reader(fifo) do
    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        args: ["-c", "exec <\"$0\"; rm -f \"$0\"; exec cat", fifo]
      ])

    t = table()
    id = t.next
    s = %__MODULE__{id: id, kind: :port_in, dev: port, mode: :read, reposition: false}
    Process.put({@key, id}, s)
    put_table(%{t | next: id + 1, streams: MapSet.put(t.streams, id)})
    id
  end

  defp write_buffer(:read), do: []
  defp write_buffer(_), do: [{:delayed_write, @chunk, 2000}]

  @doc "Ist der Alias schon vergeben?"
  def alias_taken?(name), do: Map.has_key?(table().aliases, name)

  defp close_port(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

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

      case s do
        # der Port kann sich zwischen Prüfen und Schließen selbst beenden
        # (Kindprozess fertig): badarg ist dann kein Fehler
        %{kind: :port_in, dev: port} -> close_port(port)
        %{kind: :socket, dev: sock} -> transport(sock).close(sock)
        %{kind: :http_out, dev: on_close, buf: buf} -> on_close.(IO.iodata_to_binary(buf))
        %{dev: dev} when dev != nil -> :file.close(dev)
        _ -> :ok
      end

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
  def input?(id), do: get(id).mode in [:read, :read_write]

  @doc """
  Nächstes Zeichen ansehen, ohne es zu lesen: {codepoint, bytes} | :eof,
  bei ungültigem UTF-8 `{:invalid, 1}`. Liest bei Bedarf nach (stdin: eine
  Zeile).
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
        if s.buf == b, do: {:invalid, 1}, else: peek_char(id)

      <<_, _::binary>> ->
        # ungültiges UTF-8: kein Zeichen
        {:invalid, 1}
    end
  end

  @doc "Fehler für ein ungültiges Byte im Textstream"
  def invalid_char!, do: Error.representation!("character")

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

      {:invalid, n} ->
        # das Byte wird verbraucht, damit es danach weitergeht
        s = get(id)
        {_, rest} = :erlang.split_binary(s.buf, n)
        update(advance(%{s | buf: rest}, 0xFFFD, n))
        invalid_char!()

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
  PrologEx.Parser.scan_end/2): {:term, text} | :eof | {:incomplete, text} (Datei
  endet mitten im Term).
  """
  def read_term_text(id) do
    s = get(id)

    case PrologEx.Parser.scan_end(s.buf, s.eof) do
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
    PrologEx.Shell.quiet()

    # im Terminal: Prompt weiß, die Eingabe in der Farbe von :input
    prompt =
      if PrologEx.Terminal.terminal?(), do: PrologEx.Terminal.input_prompt("|: "), else: ""

    # mit dem eigenen Editor (PrologEx.Shell): Ctrl-D auf leerer Zeile ist
    # Dateiende nur dieses Lesens; dort und mit SIGTERM als Ctrl-C
    # (--no-edit, rlwrap -I) bricht Ctrl-C die Anfrage ab
    data =
      if PrologEx.Shell.active?() or PrologEx.Shell.sigterm?(),
        do: PrologEx.Shell.gets(prompt, true),
        else: IO.gets(:stdio, prompt)

    if prompt != "", do: PrologEx.Terminal.end_input()

    case data do
      data when is_binary(data) ->
        %{s | buf: s.buf <> data}

      {:error, :interrupted} ->
        PrologEx.Error.throw!(PrologEx.Shell.abort_ball())

      _ ->
        %{s | eof: true}
    end
  end

  defp fill(%{kind: :port_in, dev: port} = s) do
    receive do
      {^port, {:data, data}} -> %{s | buf: s.buf <> data}
      {^port, {:exit_status, _}} -> %{s | eof: true}
    end
  end

  # Socket (library(sockets)): was gerade da ist; Lesen ist eine äußere
  # Wirkung (nicht im Vorausrechnen des Toplevels)
  defp fill(%{kind: :socket, dev: sock} = s) do
    PrologEx.Effects.external!()

    case transport(sock).recv(sock, 0) do
      {:ok, data} -> %{s | buf: s.buf <> data}
      {:error, _} -> %{s | eof: true}
    end
  end

  defp fill(%{kind: :memory} = s), do: %{s | eof: true}
  defp fill(s), do: %{s | eof: true}

  @doc """
  Den ganzen Rest eines Textstreams lesen (library(csv), library(sgml)):
  Text oder `:invalid`, wenn er kein gültiges UTF-8 ist (dann ist nichts
  gelesen). Position wird nachgeführt.
  """
  def read_rest(id) do
    s = fill_all(get(id))
    text = s.buf

    if String.valid?(text) do
      nl = length(:binary.matches(text, "\n"))

      line_pos =
        case :binary.matches(text, "\n") do
          [] ->
            s.line_pos + String.length(text)

          ms ->
            {pos, _} = List.last(ms)
            String.length(binary_part(text, pos + 1, byte_size(text) - pos - 1))
        end

      update(%{
        s
        | buf: "",
          chars: s.chars + String.length(text),
          lines: s.lines + nl,
          line_pos: line_pos,
          bytes: s.bytes + byte_size(text)
      })

      text
    else
      update(s)
      :invalid
    end
  end

  defp fill_all(%{eof: true} = s), do: s
  defp fill_all(s), do: s |> fill() |> fill_all()

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

  @doc """
  Eingabestream aus Text (für term_to_atom, read_term_from_atom ...);
  `type: :binary` liest Bytes (HTTP-Rümpfe)
  """
  def open_memory(text, type \\ :text) do
    t = table()
    id = t.next
    s = %__MODULE__{id: id, kind: :memory, mode: :read, buf: text, eof: true, type: type}
    Process.put({@key, id}, s)
    put_table(%{t | next: id + 1, streams: MapSet.put(t.streams, id)})
    id
  end

  @doc """
  Ausgabestream in den Speicher (für format/2 mit portray/1, später
  with_output_to/2): sammelt den Text; `memory_text/1` liefert ihn.
  """
  def open_memory_out(nse_depth \\ nil) do
    t = table()
    id = t.next
    s = %__MODULE__{id: id, kind: :memory_out, mode: :write, buf: [], nse_depth: nse_depth}
    Process.put({@key, id}, s)
    put_table(%{t | next: id + 1, streams: MapSet.put(t.streams, id)})
    id
  end

  @doc """
  Ausgabestream für eine HTTP-Antwort (library(http/http_server)): sammelt
  den Rumpf; `close/1` ruft `on_close.(rumpf)` (schickt die Antwort an den
  Verbindungsprozess). type: :binary wie Scryer oder :text (UTF-8).
  """
  def open_http_out(on_close, type) do
    t = table()
    id = t.next
    s = %__MODULE__{id: id, kind: :http_out, dev: on_close, mode: :write, buf: [], type: type}
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
        :stdout -> tap(s, fn _ -> quiet_write(fn -> IO.write(text) end) end)
        :stderr -> tap(s, fn _ -> quiet_write(fn -> IO.write(:stderr, text) end) end)
        :file -> tap(s, fn _ -> :file.write(s.dev, text) end)
        :socket -> tap(s, fn _ -> socket_send!(s, text) end)
        k when k in [:memory_out, :http_out] -> %{s | buf: [s.buf | text]}
      end

    update(out_position(s, text))
    :ok
  end

  # Ausgabe aufs Terminal: erst den Kreisel des Toplevels löschen
  # (PrologEx.Shell.busy/1; ohne Kreisel nur ein Process.get)
  defp quiet_write(f) do
    PrologEx.Shell.quiet()
    f.()
  end

  # Senden auf einem Socket; Gegenseite weg: error(socket_error(Grund), _)
  # (wie SWI)
  defp socket_send!(s, data) do
    PrologEx.Effects.external!()

    case transport(s.dev).send(s.dev, data) do
      :ok ->
        :ok

      {:error, reason} ->
        PrologEx.Error.error!(PrologEx.mk("socket_error", [{:atom, Atom.to_string(reason)}]))
    end
  end

  @doc """
  Modul für einen Socket: `:gen_tcp` (ein Port) oder `:ssl` (nach
  library(tls)); beide haben recv/2,3, send/2, close/1
  """
  def transport(sock) when is_port(sock), do: :gen_tcp
  def transport(_sock), do: :ssl

  @doc "Optionen eines Sockets setzen (`:inet` bzw. `:ssl`)"
  def setopts(sock, opts) when is_port(sock), do: :inet.setopts(sock, opts)
  def setopts(sock, opts), do: :ssl.setopts(sock, opts)

  @doc """
  Den Socket eines Socket-Streams herausnehmen (library(tls)): der Stream
  ist danach geschlossen, der Socket bleibt offen. Ergebnis
  `{socket, opts}` mit den Optionen für `open_socket/2` (Typ, eof_action;
  ohne Alias).
  """
  def take_socket(id) do
    %{kind: :socket, dev: sock} = s = get(id)
    update(%{s | dev: nil, kind: :taken})
    close(id)
    {sock, [type: s.type, eof_action: s.eof_action]}
  end

  @doc """
  Für `socket_select/7`: `{:wait, socket}`, wenn ein Socket-Stream nichts
  im Puffer hat und nicht am Ende ist (Lesen würde blockieren), sonst
  `:ready` (auch alle anderen Arten: Datei, Speicher, Standardeingabe, Pipe).
  """
  def read_wait(id) do
    case get(id) do
      %{kind: :socket, buf: "", eof: false, past: false, dev: sock} -> {:wait, sock}
      _ -> :ready
    end
  end

  @doc "Für `socket_select/7`: empfangene Daten in den Puffer, `:closed` → Ende"
  def socket_received(id, :closed), do: update(%{get(id) | eof: true})

  def socket_received(id, data) do
    s = get(id)
    update(%{s | buf: s.buf <> data})
  end

  @doc """
  Socket-Stream (library(sockets)): ein Stream für beide Richtungen
  (`mode: :read_write`), nicht positionierbar. opts wie bei open_file
  (type, alias, eof_action).
  """
  def open_socket(sock, opts) do
    t = table()
    id = t.next
    alias = Keyword.get(opts, :alias)

    s = %__MODULE__{
      id: id,
      kind: :socket,
      dev: sock,
      mode: :read_write,
      type: Keyword.get(opts, :type, :text),
      aliases: if(alias, do: [alias], else: []),
      reposition: false,
      eof_action: Keyword.get(opts, :eof_action, :eof_code)
    }

    aliases = if alias, do: Map.put(t.aliases, alias, id), else: t.aliases
    Process.put({@key, id}, s)
    put_table(%{t | next: id + 1, streams: MapSet.put(t.streams, id), aliases: aliases})
    id
  end

  @doc "Byte ausgeben"
  def put_byte(id, b) do
    s = get(id)

    s =
      case s.kind do
        :stdout -> tap(s, fn _ -> quiet_write(fn -> IO.binwrite(<<b>>) end) end)
        :stderr -> tap(s, fn _ -> quiet_write(fn -> IO.binwrite(:stderr, <<b>>) end) end)
        :file -> tap(s, fn _ -> :file.write(s.dev, <<b>>) end)
        :socket -> tap(s, fn _ -> socket_send!(s, <<b>>) end)
        k when k in [:memory_out, :http_out] -> %{s | buf: [s.buf | <<b>>]}
      end

    update(%{s | bytes: s.bytes + 1})
    :ok
  end

  @doc "Bytes (Binary) auf einmal ausgeben"
  def put_bytes(id, bin) do
    s = get(id)

    s =
      case s.kind do
        :stdout -> tap(s, fn _ -> quiet_write(fn -> IO.binwrite(bin) end) end)
        :stderr -> tap(s, fn _ -> quiet_write(fn -> IO.binwrite(:stderr, bin) end) end)
        :file -> tap(s, fn _ -> :file.write(s.dev, bin) end)
        :socket -> tap(s, fn _ -> socket_send!(s, bin) end)
        k when k in [:memory_out, :http_out] -> %{s | buf: [s.buf | bin]}
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

  defp ascii?(<<c, rest::binary>>) when c < 128, do: ascii?(rest)
  defp ascii?(<<>>), do: true
  defp ascii?(_), do: false

  # --- Eigenschaften und Position -------------------------------------------

  @doc """
  library(pio): Block `k` der faulen Liste (bis zu `max` Zeichen); einmal
  gelesen, bleibt er im Stream gemerkt (Rücksetzen liest ihn nicht neu).
  `{start, text}` mit Startposition `{zeichen, zeile, spalte}`; `""` am Ende.
  """
  def lazy_block(id, k, max) do
    case Map.fetch(get(id).lazy, k) do
      {:ok, {c, l, p, text}} ->
        {{c, l, p}, text}

      :error ->
        s = get(id)
        start = {s.chars, s.lines, s.line_pos}
        text = read_chars(id, max, [])
        {c, l, p} = start
        s = get(id)
        update(%{s | lazy: Map.put(s.lazy, k, {c, l, p, text})})
        {start, text}
    end
  end

  defp read_chars(_id, 0, acc), do: acc |> Enum.reverse() |> List.to_string()

  defp read_chars(id, n, acc) do
    case peek_char(id) do
      :eof -> read_chars(id, 0, acc)
      {_, _} -> read_chars(id, n - 1, [get_char(id) | acc])
    end
  end

  @doc "library(pio): gemerkte Blöcke und die Position danach"
  def lazy_blocks(id) do
    s = get(id)
    {s.lazy, {s.chars, s.lines, s.line_pos}}
  end

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

  @doc """
  Datei-Offset, an dem als Nächstes geschrieben wird (bei append das Ende:
  die Zähler des Streams beginnen dort bei 0)
  """
  def write_offset(id) do
    s = get(id)
    {:ok, off} = :file.position(s.dev, if(s.mode == :append, do: :eof, else: :cur))
    off
  end

  @doc "Zurück an den Offset off, dort abschneiden; die Zähler wie angegeben"
  def truncate_at(id, chars, lines, line_pos, bytes, off) do
    s = get(id)
    {:ok, _} = :file.position(s.dev, off)
    :ok = :file.truncate(s.dev)

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
