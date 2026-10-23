defmodule PrologEx.Reader do
  @moduledoc """
  Liest Prolog-Text (mit Operatoren) über einen GNU-Prolog-Kindprozess.

  Der Prozess besitzt einen Port zu `priv/gprolog/reader` (übersetzt mit
  `mix prolog.build_reader`). Operator-Definitionen bleiben über mehrere
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

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, opts)

  def read_terms(reader, text), do: GenServer.call(reader, {:read, text}, @timeout + 1000)

  def stop(reader), do: GenServer.stop(reader)

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

  @doc "Ist das übersetzte Programm älter als priv/gprolog/reader.pl?"
  def stale? do
    src = Path.join(["priv", "gprolog", "reader.pl"])

    with {:ok, %{mtime: bin}} <- File.stat(executable()),
         {:ok, %{mtime: pl}} <- File.stat(src) do
      pl > bin
    else
      _ -> false
    end
  end

  # ---------------------------------------------------------------------

  @impl true
  def init(_opts) do
    if available?() do
      {:ok, %{port: open_port(), batch: 0, buf: "", lines: 0}}
    else
      {:stop,
       {:reader_missing, "#{executable()} fehlt – bitte `mix prolog.build_reader` ausführen"}}
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

      {:timeout, results} ->
        Port.close(st.port)
        err = {:error, "Reader antwortet nicht (unvollständige Eingabe?) – neu gestartet"}
        {:reply, Enum.map(results, fix) ++ [err], fresh(st)}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, _}}, %{port: port} = st),
    do: {:noreply, fresh(st)}

  def handle_info(_msg, st), do: {:noreply, st}

  defp fresh(st), do: %{st | port: open_port(), batch: 0, buf: "", lines: 0}

  defp count_newlines(s), do: length(:binary.matches(s, "\n"))

  defp fix_line({:error, msg}, offset) do
    {:error,
     Regex.replace(~r/user_input:(\d+)/, msg, fn _, l ->
       "Zeile #{String.to_integer(l) - offset}"
     end)}
  end

  defp fix_line(other, _), do: other

  defp open_port do
    Port.open({:spawn_executable, executable()}, [:binary, {:line, 1_000_000}, :exit_status])
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

      {:ok, {tag, "term", [t, vs]}} when tag in [:struct, :gstruct] ->
        {t, names} = Canonical.rename_vars(t, vs)
        {:term, t, names}

      {:ok, {tag, "error", [e]}} when tag in [:struct, :gstruct] ->
        {:error, error_message(e)}

      {:error, e} ->
        {:error, "Antwort des Readers nicht lesbar: #{inspect(e)}: #{line}"}
    end
  end

  defp error_message(e) do
    case PrologEx.unmark(e) do
      {:struct, "error", [{:struct, "syntax_error", [{:atom, msg}]}, _]} -> "Syntaxfehler: #{msg}"
      other -> PrologEx.format(other)
    end
  end
end
