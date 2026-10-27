defmodule PrologEx.Reader do
  @moduledoc """
  Liest Prolog-Text mit `PrologEx.Parser` (in Elixir, ohne gprolog).

  Gelesen wird im aufrufenden Prozess, mit der Operatortabelle der Sitzung
  (`PrologEx.Ops`) und dem Flag `double_quotes` – beides liegt im
  Sitzungsprozess, Änderungen gelten ab dem nächsten gelesenen Term.

      {:ok, r} = PrologEx.Reader.start_link()
      PrologEx.Reader.read_terms(r, "foo(X) :- bar(X, Y).\\n")
      #=> [{:term, term, %{"X" => "X", "Y" => "Y"}}]

  Ergebnis pro gelesenem Term:

    * `{:term, term, var_names}` – Variablen tragen ihre Namen aus dem
      Text; jede anonyme Variable einen eigenen Namen `_N`
    * `{:error, message}` – Syntaxfehler (mit Zeile und Spalte)

  Die Prozess-Schnittstelle (`start_link/1`, `current/0`, ...) stammt aus
  der Zeit, als gprolog las; der Prozess selbst hält keinen Zustand mehr.
  """

  alias PrologEx.Parser

  @files :prolog_ex_reader_files

  def start_link(_opts \\ []), do: Agent.start_link(fn -> nil end)

  @doc "Wie start_link/1, aber nicht verknüpft"
  def start(_opts \\ []), do: Agent.start(fn -> nil end)

  def stop(reader), do: Agent.stop(reader)

  @doc "Reader der Sitzung (für die alte Schnittstelle; ohne eigene Bedeutung)"
  def current do
    case Process.get(:prolog_ex_reader) do
      pid when is_pid(pid) -> pid
      _ -> self()
    end
  end

  def put_current(pid), do: Process.put(:prolog_ex_reader, pid)

  @doc """
  Alle Terme eines Textes. `:- op/3`, `:- module/2` (Exportliste) und
  `:- set_prolog_flag(double_quotes, _)` gelten für den Rest des Textes
  (nicht für die Sitzung – dafür muss die Direktive ausgeführt werden);
  der Term `end_of_file` beendet den Text. Mit `lines: true` kommt die
  Zeile des Termanfangs dazu: `{:term, t, names, zeile}`.
  """
  def read_terms(_reader, text, opts \\ []), do: Parser.read_terms(text, opts)

  @doc "Setzt das Flag double_quotes (codes, chars, atom)"
  def set_double_quotes(_reader, value) when value in ["codes", "chars", "atom"] do
    PrologEx.Flags.set("double_quotes", PrologEx.a(value))
    :ok
  end

  @doc "Operator eintragen (für Bibliotheksexporte, schon geprüft)"
  def op(_reader, priority, type, name), do: PrologEx.Ops.add(priority, type, name)

  def available?, do: true

  # --- Dateien -------------------------------------------------------------

  @doc """
  Datei zum schrittweisen Lesen öffnen (oben auf einen Stapel offener
  Dateien des Prozesses): `:ok` oder `{:error, meldung}`. Danach
  `next_chunk/1`, bis `:eof` kommt.
  """
  def open_file(_reader, path) do
    case File.read(path) do
      {:ok, text} ->
        {rest, pos} =
          case text do
            <<0xEF, 0xBB, 0xBF, rest::binary>> -> {rest, 3}
            _ -> {text, 0}
          end

        Process.put(@files, [{text, rest, pos, {1, 0}} | Process.get(@files, [])])
        :ok

      {:error, reason} ->
        {:error, "#{path}: #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Terme der obersten offenen Datei bis einschließlich der nächsten
  Direktive: `{ergebnisse, :pause | :eof}`. Bei `:pause` ist die Direktive
  das letzte Ergebnis; sie kann ausgeführt werden (auch mit weiteren
  open_file/next_chunk), bevor es weitergeht – Operatoren und
  double_quotes, die sie setzt, gelten dann schon für den Rest der Datei.
  Bei `:eof` (Dateiende oder der Term `end_of_file`) ist die Datei
  geschlossen. Mit `lines: true` wie bei `read_terms/3`.
  """
  def next_chunk(_reader, opts \\ []) do
    case Process.get(@files, []) do
      [] -> {[], :eof}
      [{text, rest, pos, lc} | more] -> chunk(text, rest, pos, lc, more, [], opts[:lines])
    end
  end

  # lc: {Zeile, Position} für inkrementelle Zeilennummern
  defp chunk(text, rest, pos, lc, more, acc, lines?) do
    case Parser.read_term(rest, pos, Parser.context(text)) do
      :eof ->
        close(more, acc)

      {:term, {:atom, "end_of_file"}, _, _, _, _} ->
        close(more, acc)

      {:term, t, names, rest, pos, start} ->
        {line, _} = lc = Parser.line_at(text, lc, start)
        acc = [if(lines?, do: {:term, t, names, line}, else: {:term, t, names}) | acc]

        if directive?(t) do
          Process.put(@files, [{text, rest, pos, lc} | more])
          {Enum.reverse(acc), :pause}
        else
          chunk(text, rest, pos, lc, more, acc, lines?)
        end

      {:error, msg, rest, pos} ->
        chunk(text, rest, pos, lc, more, [{:error, msg} | acc], lines?)
    end
  end

  defp close(more, acc) do
    Process.put(@files, more)
    {Enum.reverse(acc), :eof}
  end

  defp directive?({tag, ":-", [_]}) when tag in [:struct, :gstruct], do: true
  defp directive?(_), do: false
end
