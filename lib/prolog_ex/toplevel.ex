defmodule PrologEx.Toplevel do
  @moduledoc """
  Interaktiver Toplevel und Kommandozeile.

      mix prolog [DATEI ...] [-] [-g ZIEL ...] [-q]

    * `DATEI` – wird geladen (`.pl` darf fehlen)
    * `-`     – Programm von stdin laden (bis Dateiende); danach kein
                interaktiver Toplevel, sondern nur die `-g`-Ziele
    * `-g Z`  – Ziel Z nach dem Laden ausführen (mehrfach möglich)
    * `-q`    – keine Begrüßung

  Im Toplevel:

      ?- [user].            Klauseln eintippen, Ende mit end_of_file. oder Ctrl-D
      ?- [datei].           Datei laden (auch consult(datei))
      ?- app(X, Y, [1,2]).  Anfrage; bei weiteren Lösungen ";" + Enter
      ?- halt.

  ## Antworten seitenweise

  Passiert beim Berechnen einer Antwort kein Seiteneffekt (Ausgabe,
  assert/retract, bb_put, Flags, op/3, Zufall, ...), rechnet der Toplevel
  die nächste schon voraus und zeigt sie gleich mit an – bis eine
  Bildschirmseite voll ist (Flag `answer_chunk`: `auto`, oder höchstens N
  Antworten; `1` = einzeln wie früher; ohne Terminal immer einzeln). Das
  Vorausrechnen läuft in einem eigenen Prozess mit Zeitgrenze (#{500} ms)
  und gefangener Ausgabe; gibt es dabei Seiteneffekte oder dauert es zu
  lange, wird es verworfen und wie früher nach ";" gefragt. (Nur äußere
  Wirkungen – eine Datei schreiben – lassen sich nicht verwerfen.)

  ## In iex: Ctrl-C bricht ab und führt zu iex

      bin/iprolog                         # oder:
      iex --erl "+Bc" -S mix
      iex> PrologEx.Toplevel.repl()

  Mit `+Bc` unterbricht Ctrl-C nur die laufende Anfrage (statt des
  BREAK-Menüs der BEAM) und man ist in iex; `PrologEx.Toplevel.repl()`
  macht mit derselben Sitzung weiter (Datenbank, Flags, Operatoren, ... –
  Stand nach der letzten fertigen Anfrage). `halt.` führt ebenfalls zurück
  zu iex; `reset_session/0` beginnt neu. Offene Datei-Streams überstehen
  den Abbruch nicht.
  """

  alias PrologEx.{Consult, Reader}

  def main(args) do
    {files, goals, quiet} = parse_args(args, [], [], false)
    {:ok, reader} = Reader.start_link()
    Reader.put_current(reader)
    PrologEx.put_db(%{})
    st = %{db: %{}, reader: reader, dq: "chars"}

    try do
      st = Enum.reduce(files, st, &load_source/2)
      st = Enum.reduce(goals, st, fn g, st -> run_text(g <> ".", st, :goal) end)

      cond do
        "-" in files -> 0
        goals != [] and quiet -> 0
        true -> interactive(st, quiet)
      end
    catch
      {:prolog_halt, code} -> code
    end
  end

  @session __MODULE__.Session

  @doc "Toplevel in iex mit Sitzung, die einen Abbruch (Ctrl-C mit +Bc) übersteht"
  def repl(args \\ []) do
    {files, goals, quiet} = parse_args(args, [], [], false)
    session = session()

    {st, resumed?} =
      case Agent.get(session, & &1) do
        nil ->
          {:ok, reader} = Reader.start()
          Reader.put_current(reader)
          PrologEx.put_db(%{})
          {%{db: %{}, reader: reader, dq: "chars"}, false}

        %{st: st, pdict: pdict} ->
          Enum.each(pdict, fn {k, v} -> Process.put(k, v) end)
          {st, true}
      end

    save = fn st -> Agent.update(session, fn _ -> %{st: st, pdict: state_snapshot()} end) end

    try do
      st = Enum.reduce(files, st, &load_source/2)
      st = Enum.reduce(goals, st, fn g, st -> run_text(g <> ".", st, :goal) end)
      save.(st)

      unless quiet do
        IO.puts(
          if resumed?,
            do: "PrologEx – weiter mit der Sitzung (Ctrl-C: zu iex, halt.: zu iex)\n",
            else: "PrologEx – Ctrl-C: zu iex (mit +Bc), weiter mit PrologEx.Toplevel.repl()\n"
        )
      end

      loop(st, save)
      :ok
    catch
      {:prolog_halt, _code} -> :ok
    end
  end

  @doc "Sitzung von repl/1 verwerfen (der nächste Aufruf beginnt neu)"
  def reset_session do
    case Process.whereis(@session) do
      nil ->
        :ok

      pid ->
        case Agent.get_and_update(pid, &{&1, nil}) do
          %{st: %{reader: r}} -> if Process.alive?(r), do: GenServer.stop(r)
          _ -> :ok
        end

        :ok
    end
  end

  # Agent mit der Sitzung, unverknüpft (überlebt den abgebrochenen Prozess)
  defp session do
    case Agent.start(fn -> nil end, name: @session) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  @doc false
  # Zustand des Interpreters im Prozess (Datenbank, Flags, Streams, ...)
  def state_snapshot do
    for {k, _} = e <- Process.get(), prolog_key?(k), do: e
  end

  defp prolog_key?(k) when is_atom(k), do: String.starts_with?(Atom.to_string(k), "prolog_ex_")
  defp prolog_key?(k) when is_tuple(k) and tuple_size(k) > 0, do: prolog_key?(elem(k, 0))
  defp prolog_key?(_), do: false

  defp parse_args([], files, goals, q), do: {Enum.reverse(files), Enum.reverse(goals), q}
  defp parse_args(["-g", g | rest], f, gs, q), do: parse_args(rest, f, [g | gs], q)
  defp parse_args(["-q" | rest], f, gs, _), do: parse_args(rest, f, gs, true)
  defp parse_args([file | rest], f, gs, q), do: parse_args(rest, [file | f], gs, q)

  # ---------------------------------------------------------------------
  # Laden
  # ---------------------------------------------------------------------

  defp load_source("-", st), do: load_text(IO.read(:stdio, :eof) |> eof_to_text(), "stdin", st)
  defp load_source("user", st), do: load_text(read_user(), "user", st)

  defp load_source(file, st) do
    PrologEx.put_db(st.db)
    Consult.load_file(file)
    sync_flags(%{st | db: PrologEx.current_db()})
  rescue
    e in PrologEx.Error -> err("#{file}: #{Exception.message(e)}", st)
  end

  defp eof_to_text(:eof), do: ""
  defp eof_to_text(text), do: text

  defp load_text(text, name, st) do
    items = Reader.read_terms(st.reader, text)
    {db, msgs} = Consult.load(st.db, items)
    PrologEx.put_db(db)
    Enum.each(msgs, &IO.puts(:stderr, "#{name}: #{&1}"))
    sync_flags(%{st | db: db})
  end

  # [user]: bis end_of_file., Ctrl-D oder Dateiende (siehe PrologEx.Terminal)
  defp read_user, do: PrologEx.Terminal.read_until_eof("|: ")

  # ---------------------------------------------------------------------
  # Interaktiv
  # ---------------------------------------------------------------------

  defp interactive(st, quiet) do
    unless quiet,
      do: IO.puts("PrologEx – Hilfe: siehe `mix help prolog`, Ende mit halt. oder Ctrl-D\n")

    loop(st, fn _ -> :ok end)
    0
  end

  # save: nach jeder Anfrage (Sitzung von repl/1)
  defp loop(st, save) do
    case read_query("?- ", []) do
      :eof ->
        IO.puts("")

      text ->
        st = run_text(text, st, :interactive)
        save.(st)
        loop(st, save)
    end
  end

  # Zeilen sammeln, bis eine mit "." endet
  defp read_query(prompt, acc) do
    case IO.gets(prompt) do
      :eof when acc == [] ->
        :eof

      :eof ->
        acc |> Enum.reverse() |> Enum.join()

      {:error, _} ->
        :eof

      line ->
        acc = [line | acc]

        if String.ends_with?(String.trim_trailing(line), "."),
          do: acc |> Enum.reverse() |> Enum.join(),
          else: read_query("|    ", acc)
    end
  end

  # Hat eine Anfrage double_quotes geändert, muss der Reader es wissen
  defp sync_flags(st) do
    {:atom, dq} = PrologEx.Flags.get("double_quotes")

    if dq != st.dq do
      Reader.set_double_quotes(st.reader, dq)
      %{st | dq: dq}
    else
      st
    end
  end

  defp run_text(text, st, mode) do
    Enum.reduce(Reader.read_terms(st.reader, text), st, fn
      {:error, msg}, st -> err(msg, st)
      {:term, t, _names}, st -> sync_flags(run_query(PrologEx.unmark(t), st, mode))
    end)
  end

  # [datei, ...] und consult(datei)
  defp run_query([_ | _] = files, st, _mode) do
    files
    |> prolog_list()
    |> Enum.map(&file_name/1)
    |> Enum.reduce(st, &load_source/2)
    |> tap(fn _ -> IO.puts("true.\n") end)
  end

  defp run_query({:struct, "consult", [f]}, st, mode), do: run_query([f], st, mode)

  defp run_query(goal, st, mode) do
    answers = PrologEx.solutions(st.db, PrologEx.Builtins.Expansion.expand_query(st.db, goal))

    try do
      show(answers, mode, PrologEx.query_var_names(goal))
    rescue
      e in [RuntimeError, PrologEx.Error] -> IO.puts("Fehler: #{Exception.message(e)}")
    end

    if mode != :goal, do: IO.puts("")
    # assert/retract während der Anfrage übernehmen
    %{st | db: PrologEx.current_db()}
  end

  # -g Ziele: still ausführen, nur Fehlschlag melden
  defp show(answers, :goal, _order) do
    if Enum.take(answers, 1) == [], do: IO.puts(:stderr, "Warnung: Ziel gescheitert")
  end

  defp show(answers, _mode, order) do
    page = page()
    first = fn -> Enumerable.reduce(answers, {:cont, nil}, fn x, _ -> {:suspend, x} end) end
    show_next(computed(first), order, page, 0)
  end

  # Nächste Lösung zeigen; die Suche wird FORTGESETZT (nicht neu gestartet),
  # Seiteneffekte früherer Lösungen wiederholen sich also nicht. Nur nach
  # ";" fragen, wenn noch Choice Points da sind (wie SWI). Ohne
  # Seiteneffekt seit der vorigen Antwort: die nächste vorausrechnen und
  # ohne Rückfrage zeigen, bis die Seite voll ist (siehe Moduldoku).
  # used: auf dieser Seite schon gezeigte Antworten bzw. Zeilen
  defp show_next({{:suspended, {ans, more?}, cont}, effects?}, order, page, used) do
    text = PrologEx.format_answer(ans, order)
    used = used + size(text, page)

    cond do
      not more? ->
        IO.puts(text <> ".")

      page != nil and not effects? and room?(page, used) ->
        case lookahead(cont) do
          {:ok, {{:suspended, _, _}, false} = next} ->
            IO.puts(text <> " ;")
            show_next(next, order, page, used)

          # keine weitere Lösung: gleich mit "." enden
          {:ok, {_done, false}} ->
            IO.puts(text <> ".")

          _ ->
            ask(text, cont, order, page)
        end

      true ->
        ask(text, cont, order, page)
    end
  end

  defp show_next({_done, _effects?}, _order, _page, _used), do: IO.puts("false.")

  defp ask(text, cont, order, page) do
    case IO.gets(text <> " ") do
      ";" <> _ -> show_next(computed(fn -> cont.({:cont, nil}) end), order, page, 0)
      _ -> IO.puts(".")
    end
  end

  # Ergebnis von f und ob dabei ein Seiteneffekt passiert ist (der Zustand
  # des Interpreters im Prozess hat sich geändert)
  defp computed(f) do
    before = state_snapshot()
    r = f.()
    {r, not same_state?(before, state_snapshot())}
  end

  defp same_state?(a, b), do: length(a) == length(b) and Enum.all?(a, &(&1 in b))

  @lookahead_ms 500

  # Nächste Lösung in einem eigenen Prozess vorausrechnen: mit dem Zustand
  # dieses Prozesses, gefangener Ausgabe und Zeitgrenze. {:ok, {r, false}}
  # nur, wenn dabei nichts passiert ist – sonst verwerfen (die Wirkungen
  # bleiben im anderen Prozess).
  defp lookahead(cont) do
    state = state_snapshot()
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Enum.each(state, fn {k, v} -> Process.put(k, v) end)
        {:ok, io} = StringIO.open("")
        Process.group_leader(self(), io)

        result =
          try do
            r = cont.({:cont, nil})
            {_, out} = StringIO.contents(io)

            if out == "" and same_state?(state, state_snapshot()),
              do: {:ok, {r, false}},
              else: :effects
          catch
            _, _ -> :effects
          end

        send(parent, {:lookahead, self(), result})
      end)

    receive do
      {:lookahead, ^pid, result} ->
        Process.demonitor(ref, [:flush])
        result
    after
      @lookahead_ms ->
        Process.exit(pid, :kill)
        Process.demonitor(ref, [:flush])
        :timeout
    end
  end

  # Seite: {:lines, n} (auto, Terminal mit n Zeilen), {:answers, n} oder nil
  defp page do
    case PrologEx.Flags.get("answer_chunk") do
      {:atom, "auto"} ->
        case :io.rows() do
          {:ok, rows} when rows > 3 -> {:lines, rows - 2}
          _ -> nil
        end

      1 ->
        nil

      # ohne Terminal einzeln (Eingabe aus Datei/Pipe erwartet das alte
      # Protokoll); :prolog_ex_force_chunk: für Tests
      n when is_integer(n) ->
        if match?({:ok, _}, :io.rows()) or Process.get(:prolog_ex_force_chunk),
          do: {:answers, n},
          else: nil
    end
  end

  defp size(text, {:lines, _}), do: length(String.split(text, "\n"))
  defp size(_text, _), do: 1

  # Platz für eine weitere Antwort auf der Seite?
  defp room?({:lines, n}, used), do: used + 1 <= n
  defp room?({:answers, n}, used), do: used < n

  defp prolog_list([]), do: []
  defp prolog_list([h | t]), do: [h | prolog_list(t)]

  defp file_name([]), do: "[]"

  defp file_name(t) do
    PrologEx.Builtins.Modules.file_name(t)
  rescue
    PrologEx.Error -> PrologEx.format(t)
  end

  defp err(msg, st) do
    IO.puts(:stderr, msg)
    st
  end
end
