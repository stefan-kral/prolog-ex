defmodule PrologEx.Terminal do
  @moduledoc """
  Eingabe für `[user]` mit Ctrl-D als Ende, ohne dass stdin danach "tot" ist.

  Problem: Liefert stdin in Erlang einmal Dateiende, antwortet die
  Ein-/Ausgabe danach auf jede Leseanfrage mit `:eof` – der Toplevel könnte
  nach `[user]` + Ctrl-D nichts mehr lesen.

  Lösung (nur, wenn stdin ein Terminal ist): Eine kleine Shell liest die
  Zeilen direkt vom Terminalgerät (`ps -o tty=`, weil Kindprozesse der BEAM
  kein steuerndes Terminal haben). Ctrl-D ist dann das Dateiende DIESES
  Lesers; stdin der BEAM sieht es nie. Am Terminal wird nichts umgestellt.

  Früher wurde das Terminal mit `stty eof undef eol ^D` umgestellt. Unter
  rlwrap ging das schief: rlwrap schickt bei Ctrl-D das VEOF-Zeichen des
  Terminals, und das war dann "undef" (macOS: Byte 0xFF, angezeigt als `?`).

  Wie üblich unter Unix beendet Ctrl-D am Zeilenanfang die Eingabe; mitten
  in der Zeile braucht es zweimal Ctrl-D. Ohne Terminal (Pipe, Datei) wird
  zeilenweise bis Dateiende gelesen.
  """

  @doc """
  Liest Programmtext bis `end_of_file.` (eigene Zeile), Ctrl-D oder
  Dateiende. Jede Zeile beginnt mit `prompt`.
  """
  def read_until_eof(prompt) do
    with true <- terminal?(),
         {:ok, dev} <- device(),
         {:ok, text} <- read_via_shell(dev, prompt) do
      text
    else
      _ -> read_lines(prompt, [])
    end
  end

  # Eine Shell liest direkt vom Terminal; Ctrl-D ist dann deren Dateiende,
  # stdin der BEAM bekommt davon nichts mit. Funktioniert auch unter rlwrap
  # (das bei Ctrl-D das VEOF-Zeichen des Terminals schickt).
  @reader_sh ~S"""
  while :; do
    printf '%s' "$1" >&2
    if IFS= read -r line; then
      [ "$line" = "end_of_file." ] && break
      printf '%s\n' "$line"
    else
      # Ctrl-D mitten in der Zeile: Rest übernehmen
      [ -n "$line" ] && printf '%s' "$line"
      printf '\n' >&2
      break
    fi
  done
  """

  defp read_via_shell(dev, prompt) do
    script = "exec < #{dev} 2> #{dev}\n" <> @reader_sh

    case System.cmd("sh", ["-c", script, "sh", prompt]) do
      {text, 0} -> {:ok, text}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  def terminal?, do: Keyword.get(:io.getopts(), :terminal, false) == true

  # ---------------------------------------------------------------------

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
end
