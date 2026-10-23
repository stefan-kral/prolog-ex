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
  """

  alias PrologEx.{Consult, Reader}

  def main(args) do
    {files, goals, quiet} = parse_args(args, [], [], false)
    {:ok, reader} = Reader.start_link()
    st = %{db: %{}, reader: reader}

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
    path = if File.exists?(file) or Path.extname(file) != "", do: file, else: file <> ".pl"

    case File.read(path) do
      {:ok, text} -> load_text(text, path, st)
      {:error, reason} -> err("#{path}: #{:file.format_error(reason)}", st)
    end
  end

  defp eof_to_text(:eof), do: ""
  defp eof_to_text(text), do: text

  defp load_text(text, name, st) do
    items = Reader.read_terms(st.reader, text)
    {db, msgs} = Consult.load(st.db, items)
    Enum.each(msgs, &IO.puts(:stderr, "#{name}: #{&1}"))
    %{st | db: db}
  end

  # [user]: bis end_of_file., Ctrl-D oder Dateiende (siehe PrologEx.Terminal)
  defp read_user, do: PrologEx.Terminal.read_until_eof("|: ")

  # ---------------------------------------------------------------------
  # Interaktiv
  # ---------------------------------------------------------------------

  defp interactive(st, quiet) do
    unless quiet,
      do: IO.puts("PrologEx – Hilfe: siehe `mix help prolog`, Ende mit halt. oder Ctrl-D\n")

    loop(st)
  end

  defp loop(st) do
    case read_query("?- ", []) do
      :eof ->
        IO.puts("")
        0

      text ->
        loop(run_text(text, st, :interactive))
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

  defp run_text(text, st, mode) do
    Enum.reduce(Reader.read_terms(st.reader, text), st, fn
      {:error, msg}, st -> err(msg, st)
      {:term, t, _names}, st -> run_query(PrologEx.unmark(t), st, mode)
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
    answers = PrologEx.solutions(st.db, goal)

    try do
      show(answers, mode)
    rescue
      e in RuntimeError -> IO.puts("Fehler: #{e.message}")
    end

    if mode != :goal, do: IO.puts("")
    st
  end

  # -g Ziele: still ausführen, nur Fehlschlag melden
  defp show(answers, :goal) do
    if Enum.take(answers, 1) == [], do: IO.puts(:stderr, "Warnung: Ziel gescheitert")
  end

  defp show(answers, _mode), do: show_from(answers, 0)

  # Lösung Nr. n zeigen; nur nach ";" fragen, wenn noch Choice Points da sind
  # (wie SWI: deterministische Antworten enden direkt mit ".")
  defp show_from(answers, n) do
    case answers |> Stream.drop(n) |> Enum.take(1) do
      [] ->
        IO.puts("false.")

      [{ans, more?}] ->
        text = PrologEx.format_answer(ans)

        if more? do
          case IO.gets(text <> " ") do
            ";" <> _ -> show_from(answers, n + 1)
            _ -> IO.puts(".")
          end
        else
          IO.puts(text <> ".")
        end
    end
  end

  defp prolog_list([]), do: []
  defp prolog_list([h | t]), do: [h | prolog_list(t)]

  defp file_name({:atom, name}), do: name
  defp file_name({:struct, "/", [a, b]}), do: file_name(a) <> "/" <> file_name(b)
  defp file_name([]), do: "[]"
  defp file_name(other), do: PrologEx.format(other)

  defp err(msg, st) do
    IO.puts(:stderr, msg)
    st
  end
end
