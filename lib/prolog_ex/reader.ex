defmodule PrologEx.Reader do
  @moduledoc """
  Liest Prolog-Text (mit Operatoren) über einen GNU-Prolog-Kindprozess.

  Der Prozess besitzt einen Port zu `priv/gprolog/reader` (übersetzt von
  `mix compile`, siehe `mix.exs`). Operator-Definitionen bleiben über mehrere
  Aufrufe hinweg erhalten – wie in einer Prolog-Sitzung.

      {:ok, r} = PrologEx.Reader.start_link()
      PrologEx.Reader.read_terms(r, "foo(X) :- bar(X, Y).\\n")
      #=> [{:term, term, %{"_7" => "X", ...}}]

  Ergebnis pro gelesenem Term:

    * `{:term, term, var_names}` – Variablen tragen bereits ihre
      Originalnamen; anonyme Variablen heißen `_N`
    * `{:error, message}` – Syntaxfehler (mit Zeile/Spalte von gprolog)

  ## Protokoll

  Nach dem Text werden zwei Markierungen `'$batch_end'(N).` geschickt: Fehlt
  im Text der abschließende Punkt, verschluckt der Syntaxfehler die erste,
  die zweite kommt trotzdem an. Überzählige Markierungen alter Batches
  werden ignoriert. Antwortet gprolog nicht (z. B. hängende Eingabe), wird
  der Kindprozess nach einem Timeout neu gestartet.
  """

  use GenServer
  alias PrologEx.Canonical

  @timeout 10_000

  # opts: name (GenServer), env (Umgebung für gprolog, z. B. [{"GLOBALSZ", "4096"}])
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  @doc "Wie start_link/1, aber nicht verknüpft (überlebt den Aufrufer, siehe Toplevel.repl/1)"
  def start(opts \\ []), do: GenServer.start(__MODULE__, opts, Keyword.take(opts, [:name]))

  def read_terms(reader, text), do: GenServer.call(reader, {:read, text}, @timeout + 1000)

  def stop(reader), do: GenServer.stop(reader)

  @doc """
  Datei zum schrittweisen Lesen öffnen (oben auf den Dateistapel des
  Readers): `:ok` oder `{:error, meldung}`. Danach `next_chunk/1`, bis
  `:eof` kommt.
  """
  def open_file(reader, path), do: GenServer.call(reader, {:open, path}, @timeout + 1000)

  @doc """
  Terme der obersten offenen Datei bis einschließlich der nächsten
  Direktive: `{ergebnisse, :pause | :eof}`. Bei `:pause` ist die Direktive
  das letzte Ergebnis; sie kann ausgeführt werden (auch mit weiteren
  open_file/next_chunk), bevor es weitergeht – Operatoren, die sie
  definiert, gelten dann schon für den Rest der Datei.
  """
  def next_chunk(reader), do: GenServer.call(reader, :next, @timeout + 1000)

  @doc """
  Reader der Sitzung (für consult/1, use_module/1 aus Prolog heraus).
  Der Toplevel setzt ihn mit `put_current/1`; fehlt er, wird einer
  gestartet und im Prozess gemerkt.
  """
  def current do
    case Process.get(:prolog_ex_reader) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: pid, else: start_current()

      _ ->
        start_current()
    end
  end

  def put_current(pid), do: Process.put(:prolog_ex_reader, pid)

  defp start_current do
    {:ok, pid} = start_link()
    put_current(pid)
    pid
  end

  @doc "Operator im Reader setzen (für Bibliotheksexporte); Fehler: raise"
  def op(reader, priority, type, name) do
    case op_call(reader, "#{priority}, #{type}, #{quote_atom(name)}") do
      :ok -> PrologEx.Ops.add(priority, type, name)
      {:error, e} -> raise "op(#{priority}, #{type}, #{name}): #{PrologEx.format(e)}"
    end
  end

  @doc """
  op/3 in gprolog ausführen; `args` ist der Text `P, T, Ops` (kanonisch
  geschrieben, Variablen erlaubt). Ergebnis `:ok` oder `{:error, formal}`
  mit dem ISO-Fehlerterm (Formal aus error(Formal, _)).
  """
  def op_call(reader, args), do: GenServer.call(reader, {:op, args}, @timeout + 1000)

  @doc """
  gprologs `writeq`-Text eines Terms (für Tests des Writers); `text` ist
  der Term in kanonischer Schreibweise.
  """
  def gprolog_writeq(reader, text), do: GenServer.call(reader, {:writeq, text}, @timeout + 1000)

  @doc "Aktuelle Operatortabelle: [{priorität, typ, name}]"
  def current_ops(reader), do: GenServer.call(reader, :ops, @timeout + 1000)

  @doc "Setzt double_quotes im Reader (codes, chars, atom)"
  def set_double_quotes(reader, value) when value in ["codes", "chars", "atom"] do
    read_terms(reader, ":- set_prolog_flag(double_quotes, #{value}).\n")
    :ok
  end

  @doc "Pfad zum übersetzten Reader-Programm"
  def executable do
    priv =
      case :code.priv_dir(:prolog_ex) do
        {:error, _} -> "priv"
        dir -> List.to_string(dir)
      end

    Path.join([priv, "gprolog", "reader"])
  end

  def available?, do: File.exists?(executable())

  # ---------------------------------------------------------------------

  @impl true
  def init(opts) do
    if available?() do
      env = Keyword.get(opts, :env, [])
      {:ok, %{port: open_port(env), env: env, batch: 0, buf: "", lines: 0}}
    else
      {:stop,
       {:reader_missing, "#{executable()} fehlt – bitte `mix compile` (braucht gplc) ausführen"}}
    end
  end

  @impl true
  def handle_call({:read, text}, _from, st) do
    n = st.batch + 1
    marker = "\n'$batch_end'(#{n}).\n'$batch_end'(#{n}).\n"
    # 1_000_000 und Ganzzahlen jenseits von gprologs max_integer
    {text, big?} = PrologEx.NumberSyntax.rewrite(text)
    sent = text <> marker

    fix_big = fn
      {:term, t, names} when big? -> {:term, PrologEx.NumberSyntax.unwrap(t), names}
      other -> other
    end

    Port.command(st.port, sent)

    # gprolog zählt Zeilen über die ganze Sitzung; auf diesen Text umrechnen
    fix = &(&1 |> fix_line(st.lines) |> fix_big.())

    case collect(st.port, n, st.buf, []) do
      {:ok, results, buf} ->
        lines = st.lines + count_newlines(sent)
        {:reply, Enum.map(results, fix), %{st | batch: n, buf: buf, lines: lines}}

      {:died, results} ->
        err = {:error, "Reader (gprolog) beendet (Term zu tief verschachtelt?) – neu gestartet"}
        {:reply, Enum.map(results, fix) ++ [err], restart(st)}

      {:timeout, results} ->
        err = {:error, "Reader antwortet nicht (unvollständige Eingabe?) – neu gestartet"}
        {:reply, Enum.map(results, fix) ++ [err], restart(st)}
    end
  end

  def handle_call({:open, path}, _from, st) do
    Port.command(st.port, "'$open'(#{quote_atom(path)}).\n")

    case collect_until(st.port, st.buf, [], &(&1 in [:opened] or match?({:error, _}, &1))) do
      {:ok, [:opened], buf} ->
        {:reply, :ok, %{st | buf: buf}}

      {:ok, [{:error, msg}], buf} ->
        {:reply, {:error, msg}, %{st | buf: buf}}

      {why, _} when why in [:timeout, :died] ->
        {:reply, {:error, "Reader antwortet nicht"}, restart(st)}
    end
  end

  def handle_call({:op, args}, _from, st) do
    Port.command(st.port, "'$op'(#{args}).\n")

    case collect_until(st.port, st.buf, [], &match?({:op, _}, &1)) do
      {:ok, results, buf} ->
        reply =
          case List.last(results) do
            {:op, :ok} -> :ok
            {:op, {:error, e}} -> {:error, e}
          end

        {:reply, reply, %{st | buf: buf}}

      {why, _} when why in [:timeout, :died] ->
        {:reply, {:error, {:atom, "reader_timeout"}}, restart(st)}
    end
  end

  def handle_call({:writeq, text}, _from, st) do
    Port.command(st.port, "'$writeq'(#{text}).\n")

    case collect_until(st.port, st.buf, [], &match?({:writeq, _}, &1)) do
      {:ok, results, buf} ->
        {:writeq, out} = List.last(results)
        {:reply, {:ok, out}, %{st | buf: buf}}

      {why, results} when why in [:timeout, :died] ->
        {:reply, {:error, results}, restart(st)}
    end
  end

  def handle_call(:ops, _from, st) do
    Port.command(st.port, "'$ops'.\n")

    case collect_until(st.port, st.buf, [], &match?({:ops, _}, &1)) do
      {:ok, results, buf} ->
        {:ops, ops} = List.last(results)
        {:reply, ops, %{st | buf: buf}}

      {why, _} when why in [:timeout, :died] ->
        {:reply, [], restart(st)}
    end
  end

  def handle_call(:next, _from, st) do
    Port.command(st.port, "'$next'.\n")

    case collect_until(st.port, st.buf, [], &(&1 in [:pause, :file_end])) do
      {:ok, results, buf} ->
        {last, items} = List.pop_at(results, -1)
        status = if last == :pause, do: :pause, else: :eof
        {:reply, {Enum.map(items, &fix_file_line/1), status}, %{st | buf: buf}}

      {why, results} when why in [:timeout, :died] ->
        err = {:error, "Reader antwortet nicht – neu gestartet"}
        {:reply, {results ++ [err], :eof}, restart(st)}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, _}}, %{port: port} = st),
    do: {:noreply, fresh(st)}

  def handle_info(_msg, st), do: {:noreply, st}

  defp fresh(st), do: %{st | port: open_port(st.env), batch: 0, buf: "", lines: 0}

  defp restart(st) do
    # der Port kann schon tot sein (gprolog abgestürzt)
    try do
      Port.close(st.port)
    rescue
      ArgumentError -> :ok
    end

    # eine bereits eingetroffene exit_status-Nachricht des alten Ports verwerfen
    receive do
      {port, {:exit_status, _}} when port == st.port -> :ok
    after
      0 -> :ok
    end

    fresh(st)
  end

  defp quote_atom(name),
    do: "'" <> String.replace(String.replace(name, "\\", "\\\\"), "'", "''") <> "'"

  # Antworten sammeln, bis eine `stop?` erfüllt (die kommt mit zurück)
  defp collect_until(port, buf, acc, stop?) do
    receive do
      {^port, {:data, {:noeol, chunk}}} ->
        collect_until(port, buf <> chunk, acc, stop?)

      {^port, {:data, {:eol, chunk}}} ->
        case decode(buf <> chunk) do
          # veraltete Endemarke einer Leseanfrage (jede sendet ihre Marke
          # zweimal); kann z. B. nach op/3 aus einer Direktive kommen, während
          # die Datei pausiert
          {:batch_end, _} ->
            collect_until(port, "", acc, stop?)

          result ->
            acc = [result | acc]

            if stop?.(result),
              do: {:ok, Enum.reverse(acc), ""},
              else: collect_until(port, "", acc, stop?)
        end

      {^port, {:exit_status, _}} ->
        {:died, Enum.reverse(acc)}
    after
      @timeout -> {:timeout, Enum.reverse(acc)}
    end
  end

  # Syntaxfehler aus Dateien: gprolog nennt "pfad:zeile"
  defp fix_file_line({:error, msg}),
    do: {:error, Regex.replace(~r/^(Syntaxfehler: )\S+:(\d+)/, msg, "\\1Zeile \\2")}

  defp fix_file_line(other), do: other

  defp count_newlines(s), do: length(:binary.matches(s, "\n"))

  defp fix_line({:error, msg}, offset) do
    {:error,
     Regex.replace(~r/user_input:(\d+)/, msg, fn _, l ->
       "Zeile #{String.to_integer(l) - offset}"
     end)}
  end

  defp fix_line(other, _), do: other

  defp open_port(env) do
    env = for {k, v} <- env, do: {String.to_charlist(k), String.to_charlist(v)}

    Port.open({:spawn_executable, executable()}, [
      :binary,
      {:line, 1_000_000},
      :exit_status,
      {:env, env}
    ])
  end

  # Zeilen einsammeln bis batch_end(n); lange Zeilen kommen ggf. in Stücken
  defp collect(port, n, buf, acc) do
    receive do
      {^port, {:data, {:noeol, chunk}}} ->
        collect(port, n, buf <> chunk, acc)

      {^port, {:data, {:eol, chunk}}} ->
        line = buf <> chunk

        case decode(line) do
          {:batch_end, ^n} -> {:ok, Enum.reverse(acc), ""}
          {:batch_end, _old} -> collect(port, n, "", acc)
          :eof -> {:ok, Enum.reverse(acc), ""}
          result -> collect(port, n, "", [result | acc])
        end

      {^port, {:exit_status, _}} ->
        {:died, Enum.reverse(acc)}
    after
      @timeout -> {:timeout, Enum.reverse(acc)}
    end
  end

  defp decode(line) do
    case Canonical.parse(line) do
      {:ok, {:gstruct, "batch_end", [n]}} ->
        {:batch_end, n}

      {:ok, {:atom, "eof"}} ->
        :eof

      {:ok, {:atom, a}} when a in ["opened", "pause", "file_end"] ->
        String.to_atom(a)

      {:ok, {tag, "writeq", [{:atom, text}]}} when tag in [:struct, :gstruct] ->
        {:writeq, text}

      {:ok, {:gstruct, "writeq", [[]]}} ->
        {:writeq, "[]"}

      {:ok, {:atom, "op_ok"}} ->
        {:op, :ok}

      {:ok, {tag, "op_error", [e]}} when tag in [:struct, :gstruct] ->
        case PrologEx.unmark(e) do
          {:struct, "error", [formal, _]} -> {:op, {:error, formal}}
          other -> {:op, {:error, other}}
        end

      {:ok, {tag, "ops", [l]}} when tag in [:struct, :gstruct] ->
        ops =
          for {:struct, "op", [p, {:atom, type}, name]} <- prolog_list(PrologEx.unmark(l)),
              do: {p, type, op_name(name)}

        {:ops, ops}

      {:ok, {tag, "term", [t, vs]}} when tag in [:struct, :gstruct] ->
        {t, names} = Canonical.rename_vars(t, vs)
        {:term, t, names}

      {:ok, {tag, "error", [e]}} when tag in [:struct, :gstruct] ->
        {:error, error_message(e)}

      {:error, e} ->
        {:error, "Antwort des Readers nicht lesbar: #{inspect(e)}: #{line}"}
    end
  end

  defp prolog_list([h | t]), do: [h | prolog_list(t)]
  defp prolog_list(_), do: []

  defp op_name({:atom, n}), do: n
  defp op_name([]), do: "[]"

  defp error_message(e) do
    case PrologEx.unmark(e) do
      {:struct, "error", [{:struct, "syntax_error", [{:atom, msg}]}, _]} -> "Syntaxfehler: #{msg}"
      other -> PrologEx.format(other)
    end
  end
end
