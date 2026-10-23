defmodule PrologEx.Terminal do
  @moduledoc """
  Eingabe für `[user]` mit Ctrl-D als Ende, ohne dass stdin danach "tot" ist.

  Problem: Liefert stdin in Erlang einmal Dateiende, antwortet die
  Ein-/Ausgabe (`group.erl`) danach auf jede Leseanfrage mit `:eof` – der
  Toplevel könnte also nach `[user]` + Ctrl-D nichts mehr lesen.

  Lösung (nur, wenn stdin ein Terminal ist): Für die Dauer der Eingabe wird
  das Terminal mit `stty eof undef eol ^D` umgestellt. Ctrl-D ist dann kein
  Dateiende mehr, sondern ein Zeilenende-Zeichen, das als `\\x04` ankommt
  und hier als "Eingabe fertig" gedeutet wird. Danach wird der vorherige
  Zustand (`stty -g`) wiederhergestellt. Das Terminal wird über seinen
  Gerätenamen angesprochen (`ps -o tty=`), weil Kindprozesse der BEAM kein
  steuerndes Terminal haben; das funktioniert auf Linux und macOS.

  Ohne Terminal (Pipe, Datei) wird zeilenweise bis Dateiende gelesen.
  Wird der Toplevel während `[user]` hart abgebrochen (Ctrl-C, a), bleibt die
  Umstellung bestehen – `stty sane` behebt das.
  """

  @doc """
  Liest Programmtext bis `end_of_file.` (eigene Zeile), Ctrl-D oder
  Dateiende. Jede Zeile beginnt mit `prompt`.
  """
  def read_until_eof(prompt) do
    with true <- terminal?(),
         {:ok, dev} <- device(),
         {:ok, saved} <- stty(dev, "-g") do
      try do
        case stty(dev, "eof undef eol ^D") do
          {:ok, _} -> read_chars(prompt)
          :error -> read_lines(prompt, [])
        end
      after
        stty(dev, String.trim(saved))
      end
    else
      _ -> read_lines(prompt, [])
    end
  end

  def terminal?, do: Keyword.get(:io.getopts(), :terminal, false) == true

  # ---------------------------------------------------------------------

  # Zeichenweise, damit Ctrl-D sofort wirkt (Erlang würde die Zeile sonst
  # bis zum nächsten "\n" zurückhalten)
  defp read_chars(prompt) do
    IO.write(prompt)
    read_chars(prompt, [], [])
  end

  defp read_chars(prompt, line, acc) do
    case IO.getn("", 1) do
      "\x04" ->
        IO.write("\n")
        finish(line, acc)

      "\n" ->
        text = line |> Enum.reverse() |> Enum.join()

        if String.trim(text) == "end_of_file." do
          finish([], acc)
        else
          IO.write(prompt)
          read_chars(prompt, [], [text <> "\n" | acc])
        end

      c when is_binary(c) ->
        read_chars(prompt, [c | line], acc)

      _eof_or_error ->
        finish(line, acc)
    end
  end

  defp finish(line, acc) do
    rest = line |> Enum.reverse() |> Enum.join()
    Enum.reverse([rest | acc]) |> Enum.join()
  end

  defp read_lines(prompt, acc) do
    case IO.gets(prompt) do
      line when is_binary(line) ->
        if String.trim(line) == "end_of_file.",
          do: acc |> Enum.reverse() |> Enum.join(),
          else: read_lines(prompt, [line | acc])

      _eof_or_error ->
        acc |> Enum.reverse() |> Enum.join()
    end
  end

  defp device do
    case System.cmd("ps", ["-o", "tty=", "-p", System.pid()], stderr_to_stdout: true) do
      {name, 0} ->
        case String.trim(name) do
          n when n in ["", "?", "??"] -> :error
          "/dev/" <> _ = n -> {:ok, n}
          n -> {:ok, "/dev/" <> n}
        end

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp stty(dev, args) do
    case System.cmd("sh", ["-c", "stty #{args} < #{dev}"], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      _ -> :error
    end
  rescue
    _ -> :error
  end
end
