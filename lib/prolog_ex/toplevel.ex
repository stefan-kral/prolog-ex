defmodule PrologEx.Toplevel do
  @moduledoc """
  Interaktiver Toplevel und Kommandozeile.

      mix prolog [DATEI ...] [-] [-g ZIEL ...] [-q] [--no-jit]

    * `DATEI` – wird geladen (`.pl` darf fehlen)
    * `-`     – Programm von stdin laden (bis Dateiende); danach kein
                interaktiver Toplevel, sondern nur die `-g`-Ziele
    * `-g Z`  – Ziel Z nach dem Laden ausführen (mehrfach möglich)
    * `-q`    – keine Begrüßung
    * `--no-jit` – nichts übersetzen, alles interpretieren (wie
                `set_prolog_flag(jit, false)` vor dem Laden; für
                Vorher/nachher-Vergleiche)

  Im Toplevel:

      ?- [user].            Klauseln eintippen, Ende mit end_of_file. oder Ctrl-D
      ?- [datei].           Datei laden (auch consult(datei))
      ?- app(X, Y, [1,2]).  Anfrage; bei weiteren Lösungen ";" + Enter
      ?- halt.

  ## Antworten seitenweise

  Passiert beim Berechnen einer Antwort kein Seiteneffekt (Ausgabe,
  assert/retract, bb_put, Flags, op/3, Zufall, ...), rechnet der Toplevel
  die nächste schon voraus und zeigt sie gleich mit an – bis die halbe
  Höhe des Terminals voll ist (Flag `answer_chunk`: `auto`, oder höchstens N
  Antworten; `1` = einzeln wie früher; ohne Terminal immer einzeln). Das
  Vorausrechnen läuft in einem eigenen Prozess mit Zeitgrenze (#{500} ms)
  und gefangener Ausgabe; gibt es dabei Seiteneffekte oder dauert es zu
  lange, wird es verworfen und wie früher nach ";" gefragt. (Nur äußere
  Wirkungen – eine Datei schreiben – lassen sich nicht verwerfen.)

  ## In iex: Ctrl-C bricht ab und führt zu iex

      iex --erl "+Bc" -S mix
      iex> PrologEx.Toplevel.repl()

  Mit `+Bc` unterbricht Ctrl-C nur die laufende Anfrage (statt des
  BREAK-Menüs der BEAM) und man ist in iex; `PrologEx.Toplevel.repl()`
  macht mit derselben Sitzung weiter (Datenbank, Flags, Operatoren, ... –
  Stand nach der letzten fertigen Anfrage). `halt.` führt ebenfalls zurück
  zu iex; `reset_session/0` beginnt neu. Offene Datei-Streams überstehen
  den Abbruch nicht.
  """

  alias PrologEx.Terminal
  alias PrologEx.{Consult, Reader}

  def main(args) do
    Application.put_env(:prolog_ex, :argv, args)
    {files, goals, quiet, flags} = parse_args(args)
    edit = "--no-edit" not in args
    quiet_load(quiet)
    set_flags(flags)
    {:ok, reader} = Reader.start_link()
    Reader.put_current(reader)
    PrologEx.put_db(%{})
    st = %{db: %{}, reader: reader}

    try do
      st = Enum.reduce(files, st, &load_source/2)
      st = Enum.reduce(goals, st, fn g, st -> run_text(g <> ".", st, :goal) end)

      cond do
        "-" in files -> 0
        goals != [] and quiet -> 0
        true -> interactive(st, quiet, edit)
      end
    catch
      {:prolog_halt, code} -> code
    after
      Terminal.restore()
    end
  end

  @session __MODULE__.Session
  @banner "PrologEx – Hilfe: siehe `mix help prolog`, Ende mit halt. oder Ctrl-D"

  @doc "Toplevel in iex mit Sitzung, die einen Abbruch (Ctrl-C mit +Bc) übersteht"
  def repl(args \\ []) do
    Application.put_env(:prolog_ex, :argv, args)
    {files, goals, quiet, flags} = parse_args(args)
    quiet_load(quiet)
    session = session()

    {st, resumed?} =
      case Agent.get(session, & &1) do
        nil ->
          {:ok, reader} = Reader.start()
          Reader.put_current(reader)
          PrologEx.put_db(%{})
          {%{db: %{}, reader: reader}, false}

        %{st: st, pdict: pdict} ->
          Enum.each(pdict, fn {k, v} -> Process.put(k, v) end)
          {st, true}
      end

    # nach der Sitzung: die Schalter dieses Aufrufs gelten
    set_flags(flags)

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
    after
      Terminal.restore()
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

  # -q: auch das Laden still (wie SWI); das Programm kann verbose_load
  # wieder setzen
  defp quiet_load(true), do: PrologEx.Flags.set("verbose_load", {:atom, "silent"})
  defp quiet_load(false), do: :ok

  # Schalter, die ein Flag setzen
  @flag_switches %{"--no-jit" => {"jit", {:atom, "false"}}}

  defp set_flags(flags), do: Enum.each(flags, fn {k, v} -> PrologEx.Flags.set(k, v) end)

  defp parse_args(args) do
    {files, goals, q, flags} = parse_args(args, [], [], false, [])
    {Enum.reverse(files), Enum.reverse(goals), q, Enum.reverse(flags)}
  end

  defp parse_args([], f, gs, q, fl), do: {f, gs, q, fl}
  # dahinter: Argumente für das Programm (argv/1 aus library(os))
  defp parse_args(["--" | _], f, gs, q, fl), do: {f, gs, q, fl}
  defp parse_args(["-g", g | rest], f, gs, q, fl), do: parse_args(rest, f, [g | gs], q, fl)
  defp parse_args(["-q" | rest], f, gs, _, fl), do: parse_args(rest, f, gs, true, fl)
  defp parse_args(["--no-edit" | rest], f, gs, q, fl), do: parse_args(rest, f, gs, q, fl)

  defp parse_args([a | rest], f, gs, q, fl) when is_map_key(@flag_switches, a),
    do: parse_args(rest, f, gs, q, [@flag_switches[a] | fl])

  defp parse_args([file | rest], f, gs, q, fl), do: parse_args(rest, [file | f], gs, q, fl)

  # ---------------------------------------------------------------------
  # Laden
  # ---------------------------------------------------------------------

  defp load_source("-", st), do: load_text(IO.read(:stdio, :eof) |> eof_to_text(), "stdin", st)
  defp load_source("user", st), do: load_text(read_user(), "user", st)

  defp load_source(file, st) do
    PrologEx.put_db(st.db)
    Consult.load_file(file)
    %{st | db: PrologEx.current_db()}
  rescue
    e in PrologEx.Error -> err("#{file}: #{Exception.message(e)}", st)
  end

  defp eof_to_text(:eof), do: ""
  defp eof_to_text(text), do: text

  defp load_text(text, name, st) do
    items = Reader.read_terms(st.reader, text, lines: true)
    {db, msgs} = Consult.load(st.db, items)
    PrologEx.put_db(db)
    Enum.each(msgs, &IO.puts(:stderr, Terminal.paint(:error, "#{name}: #{&1}")))
    %{st | db: db}
  end

  # [user]: bis end_of_file., Ctrl-D oder Dateiende (siehe PrologEx.Terminal)
  defp read_user, do: PrologEx.Terminal.read_until_eof("|: ")

  # ---------------------------------------------------------------------
  # Interaktiv
  # ---------------------------------------------------------------------

  defp interactive(st, quiet, edit) do
    # am Terminal: eigener Zeileneditor im Rohmodus (Ctrl-D, Ctrl-C, TAB)
    shell? = edit and Terminal.terminal?() and PrologEx.Shell.start()
    # --no-edit am Terminal (start_ex: rlwrap -I schickt bei Ctrl-C ein
    # SIGTERM): SIGTERM bricht die laufende Anfrage ab
    if not edit and Terminal.terminal?(), do: PrologEx.Shell.trap_sigterm()
    Terminal.start()

    unless quiet do
      hint =
        cond do
          not shell? -> ""
          PrologEx.Shell.ctrl_c?() -> ", Ctrl-C bricht ab"
          true -> " (Ctrl-C bricht nur mit +Bc ab)"
        end

      IO.puts(@banner <> hint <> "\n")
    end

    loop(st, fn _ -> :ok end)
    0
  after
    PrologEx.Shell.stop()
  end

  # save: nach jeder Anfrage (Sitzung von repl/1)
  defp loop(st, save) do
    # TAB-Completion (eigener Editor): die sichtbaren Prädikate
    if PrologEx.Shell.active?(), do: PrologEx.Shell.Complete.publish(st.db)

    # im Trace- oder Debug-Modus (bleibt über Anfragen hinweg an) wie SWI
    prompt =
      case PrologEx.Trace.mode() do
        :trace -> "[trace] ?- "
        :debug -> "[debug] ?- "
        nil -> "?- "
      end

    case read_query(prompt, []) do
      # (der eigene Editor ist schon in der nächsten Zeile)
      :eof ->
        unless PrologEx.Shell.active?(), do: IO.puts("")

      text ->
        st = run_text(text, st, :interactive)
        save.(st)
        loop(st, save)
    end
  end

  # Zeilen sammeln, bis eine mit "." endet
  defp read_query(prompt, acc) do
    line = PrologEx.Shell.gets(Terminal.input_prompt(prompt))
    Terminal.end_input()

    case line do
      :eof when acc == [] ->
        :eof

      :eof ->
        acc |> Enum.reverse() |> Enum.join()

      # Ctrl-C (eigener Editor): angefangene Eingabe verwerfen
      {:error, :interrupted} ->
        PrologEx.Shell.clear_interrupt()
        read_query("?- ", [])

      {:error, _} ->
        :eof

      line ->
        acc = [line | acc]

        if String.ends_with?(String.trim_trailing(line), "."),
          do: acc |> Enum.reverse() |> Enum.join(),
          else: read_query("|    ", acc)
    end
  end

  defp run_text(text, st, mode) do
    Enum.reduce(Reader.read_terms(st.reader, text), st, fn
      {:error, msg}, st ->
        st = err(msg, st)
        for h <- op_hint(text), do: IO.puts(:stderr, Terminal.paint(:comment, h))
        st

      {:term, t, _names}, st ->
        run_query(PrologEx.unmark(t), st, mode)
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

  # ?- :- G. wie eine Direktive: G ausführen (z. B. op/3)
  defp run_query({:struct, ":-", [g]}, st, mode), do: run_query(g, st, mode)

  # Zahl der gezeigten Antworten der laufenden Anfrage (answer_count/1; nicht
  # prolog_ex_...: gehört nicht zum Zustand des Interpreters)
  @count_key :toplevel_answer_count

  defp run_query(goal, st, mode) do
    st = if mode == :interactive, do: autoload(goal, st), else: st
    answers = PrologEx.solutions(st.db, PrologEx.Builtins.Expansion.expand_query(st.db, goal))

    Process.put(@count_key, 0)

    try do
      show(answers, mode, PrologEx.query_var_names(goal))
    rescue
      # Ctrl-C (PrologEx.Shell)
      e in PrologEx.Error ->
        if e.term == PrologEx.Shell.abort_ball() do
          fresh_line()
          IO.puts(Terminal.paint(:comment, "% Ausführung abgebrochen"))
          if mode != :goal, do: answer_count(:aborted)
        else
          error_message(e)
          if mode != :goal, do: answer_count(:error)
        end

      e in RuntimeError ->
        error_message(e)
        if mode != :goal, do: answer_count(:error)
    end

    if mode != :goal, do: IO.puts("")
    # assert/retract während der Anfrage übernehmen
    %{st | db: PrologEx.current_db()}
  end

  # --- Autoload im Toplevel (Flag toplevel_autoload) -----------------------
  #
  # Vor dem Ausführen: Prädikate der Anfrage, die in user nicht sichtbar
  # sind, aber eindeutig in einer Bibliothek liegen (PrologEx.LibraryIndex.
  # choice/2), nach user importieren – nur sie (use_module/2 mit Liste),
  # mit einer Meldung. Durchgesehen werden die Steuerkonstrukte und die
  # Meta-Argumente (maplist(foo, ...) → foo/N); nach einem Import noch
  # einmal (die Meta-Argumente einer eben importierten Bibliothek). Was erst
  # zur Laufzeit entsteht (call(G) mit gebautem G), bleibt beim Fehler mit
  # Hinweis. Programme (consult) bleiben ohne: nur der Toplevel

  defp autoload(goal, st, rounds \\ 3)

  defp autoload(_goal, st, 0), do: st

  defp autoload(goal, st, rounds) do
    if PrologEx.Flags.get("toplevel_autoload") == {:atom, "true"} do
      case scan(goal, st.db, []) |> Enum.reverse() |> Enum.uniq() do
        [] ->
          st

        missing ->
          db =
            missing
            |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
            |> Enum.sort()
            |> Enum.reduce(st.db, &import_into_user/2)

          autoload(goal, %{st | db: db}, rounds - 1)
      end
    else
      st
    end
  end

  defp import_into_user({lib, keys}, db) do
    {:term, spec, _} = PrologEx.Parser.read_one("library(#{lib}).")
    pis = for {n, a} <- keys, do: {:struct, "/", [{:atom, n}, a]}
    goal = {:struct, "use_module", [PrologEx.unmark(spec), pis]}

    # still und am Tracer vorbei: der Import gehört nicht zur Anfrage
    # (sonst Call/Exit von use_module/2 im Trace und die Meldung von
    # verbose_load zusätzlich zu unserer)
    trace = Process.delete(:prolog_ex_trace)
    load = PrologEx.Flags.get("verbose_load")
    PrologEx.Flags.set("verbose_load", {:atom, "silent"})

    try do
      case Enum.take(PrologEx.solutions(db, goal), 1) do
        [_] ->
          what = Enum.map_join(pis, ", ", &PrologEx.Writer.format(&1, quoted: true))
          IO.puts(Terminal.paint(:comment, "% #{what} aus library(#{lib}) importiert"))
          PrologEx.current_db()

        [] ->
          db
      end
    rescue
      PrologEx.Error -> db
    after
      PrologEx.Flags.set("verbose_load", load)
      if trace, do: Process.put(:prolog_ex_trace, trace)
    end
  end

  # Steuerkonstrukte und eingebaute Meta-Prädikate ohne eigene Angabe
  @control_meta %{
    {"findall", 3} => ["?", 0, "?"],
    {"findall", 4} => ["?", 0, "?", "?"],
    {"once", 1} => [0],
    {"ignore", 1} => [0],
    {"catch", 3} => [0, "?", 0],
    {"phrase", 2} => ["//", "?"],
    {"phrase", 3} => ["//", "?", "?"]
  }

  defp scan({:var, _}, _db, acc), do: acc
  defp scan({:struct, ":", [_, _]}, _db, acc), do: acc

  defp scan({:struct, f, [a, b]}, db, acc) when f in [",", ";", "->", "*->"],
    do: scan(b, db, scan(a, db, acc))

  defp scan({:struct, "\\+", [a]}, db, acc), do: scan(a, db, acc)
  defp scan({:struct, "call", [c | extra]}, db, acc), do: closure(c, length(extra), db, acc)
  defp scan({:atom, n}, db, acc), do: pred(n, [], db, acc)
  defp scan({:struct, n, args}, db, acc), do: pred(n, args, db, acc)
  defp scan(_, _db, acc), do: acc

  defp pred(n, args, db, acc) do
    a = length(args)

    # schon nach user importiert gilt als sichtbar, auch wo locate/4 es
    # nicht findet (trace/0: eingebaut mit Heimat traces) – sonst käme der
    # Import bei jeder Anfrage wieder
    found =
      if Map.has_key?(db, {:import, "user", n, a}),
        do: :imported,
        else: PrologEx.locate(db, "user", n, a)

    {acc, meta} =
      case found do
        :imported ->
          {acc, Map.get(@control_meta, {n, a})}

        :none ->
          case PrologEx.LibraryIndex.choice(n, a) do
            nil ->
              {acc, Map.get(@control_meta, {n, a})}

            lib ->
              {[{lib, {n, a}} | acc],
               PrologEx.Builtins.meta(PrologEx.Builtins.source(lib, n, a), n, a)}
          end

        {:db, m, _} ->
          {acc, Map.get(db, {:meta, m, n, a})}

        {:builtin, m, _} ->
          {acc, PrologEx.Builtins.meta(m, n, a) || Map.get(@control_meta, {n, a})}
      end

    case meta do
      specs when is_list(specs) and length(specs) == a ->
        Enum.zip(args, specs)
        |> Enum.reduce(acc, fn
          {g, 0}, acc -> scan(g, db, acc)
          {c, k}, acc when is_integer(k) -> closure(c, k, db, acc)
          {g, "^"}, acc -> scan(strip_caret(g), db, acc)
          {c, "//"}, acc -> closure(c, 2, db, acc)
          _, acc -> acc
        end)

      _ ->
        acc
    end
  end

  # ein Closure mit k weiteren Argumenten
  defp closure({:atom, n}, k, db, acc), do: pred(n, List.duplicate({:var, 0}, k), db, acc)

  defp closure({:struct, n, args}, k, db, acc) when n != ":",
    do: pred(n, args ++ List.duplicate({:var, 0}, k), db, acc)

  defp closure(_, _k, _db, acc), do: acc

  defp strip_caret({:struct, "^", [_, g]}), do: strip_caret(g)
  defp strip_caret(g), do: g

  defp error_message(e) do
    IO.puts(Terminal.paint(:error, "Fehler: #{Exception.message(e)}"))
    if hint = home_hint(e) || memory_hint(e), do: IO.puts(Terminal.paint(:comment, hint))
  end

  # -g Ziele: still ausführen, nur Fehlschlag melden
  defp show(answers, :goal, _order) do
    if Enum.take(answers, 1) == [],
      do: IO.puts(:stderr, Terminal.paint(:error, "Warnung: Ziel gescheitert"))
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
    fresh_line()
    text = PrologEx.format_answer(ans, order)
    used = used + size(text, page)
    Process.put(@count_key, Process.get(@count_key, 0) + 1)

    cond do
      not more? ->
        IO.puts(text <> ".")
        answer_count(:done)

      # (nicht mit dem Debugger: die nächste Antwort sucht er mit dem
      # Benutzer, nicht probeweise in einem anderen Prozess)
      page != nil and not effects? and room?(page, used) and not PrologEx.Trace.on?() ->
        case lookahead(cont) do
          {:ok, {{:suspended, _, _}, false} = next} ->
            IO.puts(text <> " ;")
            show_next(next, order, page, used)

          # keine weitere Lösung: gleich mit "." enden
          {:ok, {_done, false}} ->
            IO.puts(text <> ".")
            answer_count(:done)

          _ ->
            ask(text, cont, order, page)
        end

      true ->
        ask(text, cont, order, page)
    end
  end

  defp show_next({_done, _effects?}, _order, _page, _used) do
    fresh_line()
    IO.puts("false.")
    answer_count(false)
  end

  # --- Zahl der Antworten am Ende (Flag toplevel_answer_count) -------------
  #
  # Kommentar nach der letzten Antwort: wie viele es gab und wie die Anfrage
  # endete – :done (keine weiteren; nach "false." genügt die Zahl), :stopped
  # (der Benutzer hörte auf, weitere wären möglich), :error, :aborted
  # (Ctrl-C). auto: ab zwei Antworten, nach Abbruch oder Fehler ab einer
  # (Zähler: @count_key)

  defp answer_count(how) do
    n = Process.get(@count_key, 0)

    show? =
      case PrologEx.Flags.get("toplevel_answer_count") do
        {:atom, "on"} -> true
        {:atom, "off"} -> false
        _ -> n >= 2 or (how in [:stopped, :error, :aborted] and n >= 1)
      end

    if show? do
      ans = if n == 1, do: "1 Antwort", else: "#{n} Antworten"

      text =
        case how do
          :done -> ans <> ", keine weiteren"
          false -> ans
          :stopped -> ans <> ", abgebrochen"
          :error -> ans <> ", dann Fehler"
          :aborted -> ans <> ", dann abgebrochen"
        end

      IO.puts(Terminal.paint(:comment, "% " <> text))
    end
  end

  # Antworten beginnen am Zeilenanfang: hat die Anfrage auf user_output
  # geschrieben, ohne die Zeile zu beenden (write(x) ohne nl), erst ein
  # Zeilenumbruch – wie SWI und Scryer; sonst stünde "xtrue."
  defp fresh_line do
    if PrologEx.Stream.get(1).line_pos != 0, do: PrologEx.Stream.put_text(1, "\n")
  end

  defp ask(text, cont, order, page) do
    prompt = ask_prompt(text)
    line = PrologEx.Shell.gets(Terminal.input_prompt(prompt), true)
    Terminal.end_input()

    case line do
      ";" <> _ ->
        show_next(computed(fn -> cont.({:cont, nil}) end), order, page, 0)

      # Ctrl-C: wie "." (keine weiteren Antworten)
      {:error, :interrupted} ->
        IO.puts(Terminal.paint(:input, "."))
        answer_count(:stopped)

      _ ->
        stop_dot(prompt, line)
        answer_count(:stopped)
    end
  end

  # Ende der Antworten: der Punkt hinter der Antwort. Ohne Terminal (Eingabe
  # aus Datei/Pipe, kein Echo) einfach dahinter. Am Terminal steht das
  # Getippte samt Zeilenumbruch schon da: hat der Benutzer selbst etwas
  # getippt (".", oder was sonst als Ende gilt), nichts mehr – früher kam
  # der Punkt noch einmal in eine eigene Zeile; nach bloßem Enter der Punkt
  # zurück in die Zeile der Antwort (eine Zeile hoch, hinter den Prompt)
  defp stop_dot(prompt, line) do
    typed = if is_binary(line), do: String.trim(line), else: ""

    # (:prolog_ex_force_echo: für Tests – das Verhalten am Terminal)
    cond do
      not (Terminal.terminal?() or Process.get(:prolog_ex_force_echo) == true) ->
        IO.puts(Terminal.paint(:input, "."))

      typed != "" ->
        :ok

      true ->
        col =
          case :string.split(prompt, "\n", :trailing) do
            [_, l] -> String.length(l)
            [l] -> String.length(l)
          end

        IO.write("\e[1A\e[#{col + 1}G")
        IO.puts(Terminal.paint(:input, "."))
    end
  end

  # Gefragt wird hinter der Antwort (X = 1 ;). Ist ihre letzte Zeile
  # breiter als das Terminal, endet sie mit einem Zeilenumbruch und die
  # Eingabe steht in einer eigenen Zeile: ein Zeileneditor davor (rlwrap)
  # hielte sonst die ganze umbrochene Antwort für den Prompt, löschte sie
  # vor jedem Neuzeichnen Zeile für Zeile und hinterließe Lücken
  defp ask_prompt(text) do
    last =
      case :string.split(text, "\n", :trailing) do
        [_, l] -> l
        [l] -> l
      end

    case :io.columns() do
      {:ok, cols} when cols > 0 ->
        if String.length(last) + 2 > cols do
          IO.puts(text)
          ""
        else
          text <> " "
        end

      _ ->
        text <> " "
    end
  end

  # Ergebnis von f und ob dabei ein Seiteneffekt passiert ist (der Zustand
  # des Interpreters im Prozess hat sich geändert)
  defp computed(f) do
    PrologEx.Shell.clear_interrupt()
    before = state_snapshot()
    r = PrologEx.Shell.busy(f)
    {r, not same_state?(before, state_snapshot())}
  end

  # Buchführung, kein Seiteneffekt: die Map der Zeit- und Speichergrenzen
  # der Anfrage, der Inferenzzähler und die Ladetiefe – beide werden bei
  # der ersten Anfrage der Sitzung erst angelegt; sonst galt schon deren
  # erste Antwort als Seiteneffekt, und es kam kein Vorausrechnen
  @bookkeeping [:prolog_ex_timers, :prolog_ex_inferences, :prolog_ex_load_depth]

  defp same_state?(a, b) do
    a = without_bookkeeping(a)
    b = without_bookkeeping(b)
    length(a) == length(b) and Enum.all?(a, &(&1 in b))
  end

  defp without_bookkeeping([{k, _} | rest]) when k in @bookkeeping, do: without_bookkeeping(rest)
  defp without_bookkeeping([e | rest]), do: [e | without_bookkeeping(rest)]
  defp without_bookkeeping([]), do: []

  @lookahead_ms 500

  # Nächste Lösung in einem eigenen Prozess vorausrechnen: mit dem Zustand
  # dieses Prozesses, gefangener Ausgabe und Zeitgrenze. {:ok, {r, false}}
  # nur, wenn dabei nichts passiert ist – sonst verwerfen (die Wirkungen
  # bleiben im anderen Prozess).
  defp lookahead(cont) do
    state = PrologEx.Trace.strip(state_snapshot())
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Enum.each(state, fn {k, v} -> Process.put(k, v) end)
        # äußere Wirkungen (Prozesse, Shell, Umgebung) brechen ab, bevor sie
        # passieren (PrologEx.Effects)
        PrologEx.Effects.speculative!()
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

  # Seite: {:lines, n, cols} (auto: die halbe Höhe des Terminals – die
  # Anfrage und was davor stand bleiben sichtbar; cols: Breite, für lange
  # Antworten, die das Terminal umbricht), {:answers, n} oder nil
  defp page do
    case PrologEx.Flags.get("answer_chunk") do
      {:atom, "auto"} ->
        case :io.rows() do
          {:ok, rows} when rows > 3 ->
            cols = with {:ok, c} when c > 0 <- :io.columns(), do: c, else: (_ -> nil)
            {:lines, div(rows, 2), cols}

          _ ->
            nil
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

  # Zeilen auf dem Schirm (eine Zeile länger als das Terminal breit ist,
  # belegt mehrere; " ;" kommt dazu)
  defp size(text, {:lines, _, cols}), do: screen_lines(String.split(text, "\n"), cols, 0)

  defp size(_text, _), do: 1

  defp screen_lines([], _cols, n), do: n
  defp screen_lines([_ | ls], nil, n), do: screen_lines(ls, nil, n + 1)

  defp screen_lines([l], cols, n),
    do: n + max(div(String.length(l) + 2 + cols - 1, cols), 1)

  defp screen_lines([l | ls], cols, n),
    do: screen_lines(ls, cols, n + max(div(String.length(l) + cols - 1, cols), 1))

  # Platz für eine weitere Antwort auf der Seite?
  defp room?({:lines, n, _}, used), do: used + 1 <= n
  defp room?({:answers, n}, used), do: used < n

  defp prolog_list([]), do: []
  defp prolog_list([h | t]), do: [h | prolog_list(t)]

  defp file_name([]), do: "[]"

  defp file_name(t) do
    PrologEx.Builtins.Modules.file_name(t)
  rescue
    PrologEx.Error -> PrologEx.format(t)
  end

  # existence_error eines Prädikats, das eine Bibliothek exportiert: wo es
  # liegt (PrologEx.LibraryIndex) – eine: der Befehl dazu; mehrere: alle.
  # Eingebaute mit Heimat-Bibliothek (forall/2 in iso_ext): auch swi_compat
  defp home_hint(%PrologEx.Error{term: t}) do
    with {_, "error", [{_, "existence_error", [{:atom, "procedure"}, pi]}, _]} <- t,
         {_, "/", [{:atom, n}, a]} = pi when is_integer(a) <- strip_pi(PrologEx.unmark(pi)),
         [_ | _] = libs <- PrologEx.LibraryIndex.libraries(n, a) do
      what = PrologEx.Writer.format(pi, quoted: true)
      home = PrologEx.Builtins.home(n, a)

      case home || PrologEx.LibraryIndex.choice(n, a) do
        nil ->
          "% #{what} liegt in " <> Enum.map_join(libs, " oder ", &"library(#{&1})")

        lib ->
          "% #{what} liegt in library(#{lib}): :- use_module(library(#{lib}))." <>
            if(home, do: " (oder set_prolog_flag(swi_compat, true))", else: "")
      end
    else
      _ -> nil
    end
  end

  defp home_hint(_), do: nil

  # Syntaxfehler: steht in der Eingabe ein Name, den erst eine Bibliothek
  # zum Operator macht (X #<==> B ohne clpz), wo er liegt
  defp op_hint(text) do
    ops = PrologEx.Ops.table()

    Regex.scan(~r/[#$&*+\-.\/:<=>?@^~\\]+|[a-z][a-zA-Z0-9_]*/, text)
    |> Enum.map(&hd/1)
    |> Enum.uniq()
    |> Enum.reject(&Map.has_key?(ops, &1))
    |> Enum.flat_map(fn name ->
      case PrologEx.LibraryIndex.op_libraries(name) do
        [] ->
          []

        libs ->
          q = PrologEx.Writer.format({:atom, name}, quoted: true)
          use = Enum.map_join(libs, " oder ", &":- use_module(library(#{&1})).")

          [
            "% #{q} ist ein Operator aus " <>
              Enum.map_join(libs, " oder ", &"library(#{&1})") <> ": " <> use
          ]
      end
    end)
    |> Enum.take(3)
  end

  # resource_error(memory) einer Speichergrenze: welche, wie tief, und ob
  # eine endlose Rekursion wahrscheinlich ist
  defp memory_hint(%PrologEx.Error{term: t}) do
    with {_, "error", [{_, "resource_error", [{:atom, "memory"}]}, ctx]} <- PrologEx.unmark(t),
         {_, "context", [where, {_, "memory", [bytes | rest]}]} <- ctx do
      limit =
        case where do
          {:atom, "stack_limit"} ->
            "stack_limit = #{bytes_text(bytes)} (ändern: set_prolog_flag(stack_limit, Bytes) oder unlimited)"

          _ ->
            "call_with_memory_limit/2 mit #{bytes_text(bytes)}"
        end

      detail =
        case rest do
          [depth, cps, rec] ->
            what =
              case prolog_list(rec) do
                [pi] ->
                  "Wahrscheinlich endlose Rekursion in #{PrologEx.Writer.format(pi, quoted: true)}."

                _ ->
                  if depth < 1000,
                    do:
                      "Der Stapel ist flach: es wachsen die Daten (große Terme, findall/3, assert/1, ...).",
                    else: ""
              end

            " Offene Ziele: #{depth}, Choice Points: #{cps}. " <> what

          _ ->
            " Ein eingebautes Prädikat hätte auf einen Schlag mehr Speicher gebraucht."
        end

      "% Speichergrenze überschritten: " <> limit <> "." <> String.trim_trailing(detail)
    else
      _ -> nil
    end
  end

  defp memory_hint(_), do: nil

  defp bytes_text(b) when b >= 1_073_741_824,
    do: :erlang.float_to_binary(b / 1_073_741_824, decimals: 1) <> " GiB"

  defp bytes_text(b) when b >= 1_048_576,
    do: :erlang.float_to_binary(b / 1_048_576, decimals: 1) <> " MiB"

  defp bytes_text(b), do: "#{b} Bytes"

  defp strip_pi({_, ":", [_, pi]}), do: pi
  defp strip_pi(pi), do: pi

  defp err(msg, st) do
    IO.puts(:stderr, Terminal.paint(:error, msg))
    st
  end
end
