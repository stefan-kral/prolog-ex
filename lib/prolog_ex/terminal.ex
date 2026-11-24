defmodule PrologEx.Terminal do
  @moduledoc """
  Das Terminal: was es kann (`capabilities/0`), Farben im Toplevel
  (`paint/2`, Flag `color_term`), und Eingabe für `[user]` mit Ctrl-D als
  Ende, ohne dass stdin danach "tot" ist.

  ## Farben

  Vier Rollen (gedacht für dunklen Hintergrund):

    * `:normal`  – was der Rechner gewöhnlich ausgibt (Prompt, Antworten,
      Ausgaben des Programms): weiß. Das ist die Grundfarbe der Sitzung:
      nach jedem farbigen Stück geht es zu Weiß zurück, am Ende zur Farbe
      des Terminals (`restore/0`)
    * `:error`   – Fehler und Warnungen: rot
    * `:comment` – Kommentare (`% ...`: Laden, Hinweise): grün
    * `:input`   – was man eintippt: blau (die Farbe wird nach dem Prompt
      gesetzt und nach der Zeile zurückgesetzt)

  Farbig nur, wenn das Flag `color_term` true ist (Vorgabe, wie SWI),
  `NO_COLOR` nicht gesetzt ist (no-color.org), die Ausgabe ein Terminal ist
  und das Terminal Farben kann (`TERM` nicht `dumb`). Mit 256 Farben oder
  Truecolor (`COLORTERM`) etwas hellere Töne, die auf Schwarz besser zu
  lesen sind; `demo/0` zeigt alle Varianten nebeneinander.

  ## Eingabe für `[user]`

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
  # (Prompt weiß, die Eingabe in der Farbe von :input, danach wieder weiß)
  def read_until_eof(prompt) do
    prompt = input_prompt(prompt)

    # mit dem eigenen Editor (PrologEx.Shell) liest der (Ctrl-D: Dateiende
    # nur dieses Lesens); die Shell darunter bekäme das Terminal im Rohmodus
    with false <- PrologEx.Shell.active?(),
         true <- terminal?(),
         {:ok, dev} <- device(),
         {:ok, text} <- read_via_shell(dev, prompt) do
      text
    else
      :interrupted ->
        PrologEx.Shell.clear_interrupt()
        IO.puts(paint(:comment, "\n% Eingabe abgebrochen"))
        ""

      _ ->
        read_lines(prompt, [])
    end
  after
    end_input()
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

  # (als Port, damit Ctrl-C als SIGTERM – :prolog_interrupt, siehe
  # PrologEx.Shell.trap_sigterm/0 – das Lesen abbrechen kann)
  defp read_via_shell(dev, prompt) do
    script = "exec < #{dev} 2> #{dev}\n" <> @reader_sh
    PrologEx.Shell.flush_interrupts()

    port =
      Port.open({:spawn_executable, System.find_executable("sh")}, [
        :binary,
        :exit_status,
        args: ["-c", script, "sh", prompt]
      ])

    collect(port, [])
  rescue
    _ -> :error
  end

  defp collect(port, acc) do
    receive do
      {^port, {:data, d}} ->
        collect(port, [acc | d])

      {^port, {:exit_status, 0}} ->
        {:ok, IO.iodata_to_binary(acc)}

      {^port, {:exit_status, _}} ->
        :error

      :prolog_interrupt ->
        with {:os_pid, pid} <- Port.info(port, :os_pid),
             do: System.cmd("kill", [to_string(pid)], stderr_to_stdout: true)

        catch_close(port)
        :interrupted
    end
  end

  defp catch_close(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end

  def terminal?, do: Keyword.get(:io.getopts(), :terminal, false) == true

  # ---------------------------------------------------------------------
  # Fähigkeiten und Farben
  # ---------------------------------------------------------------------

  @doc "Was das Terminal kann (aus TERM, COLORTERM und IO.ANSI)"
  def capabilities do
    term = System.get_env("TERM", "")
    color_term = System.get_env("COLORTERM", "")

    %{
      ansi: IO.ANSI.enabled?(),
      colors: color_count(term, color_term),
      truecolor: truecolor?(color_term),
      unicode: true,
      terminal: term
    }
  end

  defp color_count(term, color_term) do
    cond do
      String.contains?(color_term, "truecolor") or String.contains?(color_term, "24bit") ->
        16_777_216

      String.contains?(color_term, "256color") ->
        256

      String.contains?(term, "256color") ->
        256

      term == "dumb" ->
        0

      IO.ANSI.enabled?() ->
        8

      true ->
        0
    end
  end

  defp truecolor?(color_term), do: color_term in ["truecolor", "24bit"]

  @doc "Farbig ausgeben? (Flag color_term, NO_COLOR, Terminal, Farben)"
  def color? do
    PrologEx.Flags.get("color_term") == {:atom, "true"} and
      System.get_env("NO_COLOR", "") == "" and terminal?() and capabilities().colors > 0
  end

  @doc "Text in der Farbe der Rolle, danach wieder weiß (ohne Farben unverändert)"
  def paint(role, text) do
    if role != :normal and color?(),
      do: [code(role), text, code(:normal)] |> IO.iodata_to_binary(),
      else: text
  end

  @doc "Text in der Grundfarbe (weiß), auch am Anfang der Sitzung"
  def normal(text), do: if(color?(), do: code(:normal) <> text, else: text)

  @doc "Prompt in Weiß, danach erscheint die Eingabe in der Farbe von :input"
  def input_prompt(prompt),
    do: if(color?(), do: code(:normal) <> prompt <> code(:input), else: prompt)

  @doc "Nach der Eingabe: wieder weiß (ohne Farben nichts)"
  def end_input, do: if(color?(), do: IO.write(code(:normal)))

  @doc "Sitzung beginnt: weiß (ohne Farben nichts)"
  def start, do: if(color?(), do: IO.write(code(:normal)))

  @doc "Sitzung endet: die Farbe und der Titel des Terminals zurück"
  def restore do
    title_restore()
    if color?(), do: IO.write(IO.ANSI.reset())
  end

  # ---------------------------------------------------------------------
  # Titel des Fensters (Flag terminal_title)
  # ---------------------------------------------------------------------

  @title :prolog_ex_title

  @doc """
  Titel des Terminalfensters nach dem Flag `terminal_title` (vor jedem
  Prompt; schreibt nur, wenn er sich ändert). Beim ersten Mal kommt der
  alte Titel auf den Titelstapel (xterm: `CSI 22;0 t`; iTerm2, kitty,
  xterm), `restore/0` holt ihn zurück; '' oder false: kein eigener Titel.
  Nur am Terminal und nicht bei `TERM=dumb`.
  """
  def title({:atom, t}) do
    t = if t == "false", do: "", else: String.replace(t, ~r/[\x00-\x1f\x7f]/u, "")

    case Process.get(@title) do
      ^t ->
        :ok

      nil when t == "" ->
        :ok

      :none ->
        :ok

      old ->
        cond do
          old == nil and not title_terminal?() ->
            Process.put(@title, :none)

          t == "" ->
            title_restore()

          true ->
            IO.write([if(old == nil, do: "\e[22;0t", else: ""), "\e]0;", t, "\a"])
            Process.put(@title, t)
        end
    end

    :ok
  end

  def title(_), do: :ok

  # der alte Titel zurück: erst leer (wo es keinen Stapel gibt, etwa
  # Terminal.app: dessen eigener Titel), dann vom Stapel
  defp title_restore do
    case Process.delete(@title) do
      t when is_binary(t) -> IO.write("\e]0;\a\e[23;0t")
      _ -> :ok
    end
  end

  defp title_terminal? do
    (terminal?() or Process.get(:prolog_ex_force_title) == true) and
      System.get_env("TERM") != "dumb"
  end

  defp code(role), do: code(role, palette())

  # 8 Farben: die Grundfarben (wie sie aussehen, bestimmt das Farbschema des
  # Terminals); 256: Rot etwas heller, für Kommentare ein sattes Grün (34,
  # #00af00), für die Eingabe ein sattes Blau (27, #005fff); Truecolor:
  # dieselben Töne genau
  defp palette do
    c = capabilities()

    cond do
      c.truecolor -> :truecolor
      c.colors >= 256 -> :c256
      true -> :c8
    end
  end

  defp code(:error, :c8), do: IO.ANSI.red()
  defp code(:comment, :c8), do: IO.ANSI.green()
  defp code(:input, :c8), do: IO.ANSI.blue()
  defp code(:error, :c256), do: IO.ANSI.color(203)
  defp code(:comment, :c256), do: IO.ANSI.color(34)
  defp code(:input, :c256), do: IO.ANSI.color(27)
  defp code(:error, :truecolor), do: rgb(255, 95, 95)
  defp code(:comment, :truecolor), do: rgb(0, 175, 0)
  defp code(:input, :truecolor), do: rgb(0, 95, 255)
  defp code(:normal, :c8), do: IO.ANSI.light_white()
  defp code(:normal, :c256), do: IO.ANSI.color(231)
  defp code(:normal, :truecolor), do: rgb(255, 255, 255)

  defp rgb(r, g, b), do: "\e[38;2;#{r};#{g};#{b}m"

  @doc """
  Zeigt die Fähigkeiten des Terminals und eine kleine Sitzung in allen
  Farbvarianten (8, 256, Truecolor; dazu hell statt normal), unabhängig
  vom Flag – zum Vergleichen in verschiedenen Terminals:

      mix run -e "PrologEx.Terminal.demo()"
  """
  def demo do
    IO.puts("Terminal: #{inspect(capabilities())}")

    IO.puts(
      "Farben im Toplevel: #{if color?(), do: "ja", else: "nein"} (Flag color_term, NO_COLOR, Terminal)\n"
    )

    variants = [
      {"8 Farben", :c8},
      {"8 Farben, hell", :bright},
      {"256 Farben", :c256},
      {"Truecolor", :truecolor}
    ]

    for {name, v} <- variants do
      IO.puts("── #{name} " <> String.duplicate("─", 50 - String.length(name)))

      c = fn role ->
        if v == :bright, do: bright(role), else: code(role, v)
      end

      r = IO.ANSI.reset()
      IO.puts(c.(:comment) <> "% lade library(clpz) ..." <> r)
      IO.puts("?- " <> c.(:input) <> "X #= 3 + 4, Y in 1..X." <> r)
      IO.puts("X = 7,")
      IO.puts("clpz:(Y in 1..7).")
      IO.puts("")
      IO.puts("?- " <> c.(:input) <> "atom_length(X, 3)." <> r)
      IO.puts(c.(:error) <> "Fehler: instantiation_error" <> r)
      IO.puts(c.(:comment) <> "% between/3 liegt in library(between)" <> r)
      IO.puts("")
    end

    # Blautöne zur Auswahl (256 Farben; Nummer und Truecolor-Wert)
    IO.puts("── Blautöne (256 Farben) " <> String.duplicate("─", 38))

    for {n, hex} <- [
          {19, "#0000af"},
          {20, "#0000d7"},
          {21, "#0000ff"},
          {26, "#005fd7"},
          {27, "#005fff"},
          {32, "#0087d7"},
          {33, "#0087ff"},
          {63, "#5f5fff"},
          {69, "#5f87ff"},
          {75, "#5fafff"}
        ] do
      IO.puts(
        IO.ANSI.color(n) <>
          "?- X #= 3 + 4, Y in 1..X." <> IO.ANSI.reset() <> "   #{n} #{hex}"
      )
    end

    IO.puts(
      IO.ANSI.blue() <>
        "?- X #= 3 + 4, Y in 1..X." <> IO.ANSI.reset() <> "   Grundfarbe Blau (8 Farben)"
    )

    # Grüntöne zur Auswahl (256 Farben)
    IO.puts("── Grüntöne (256 Farben) " <> String.duplicate("─", 38))

    for {n, hex} <- [
          {22, "#005f00"},
          {28, "#008700"},
          {34, "#00af00"},
          {40, "#00d700"},
          {64, "#5f8700"},
          {70, "#5faf00"},
          {71, "#5faf5f"},
          {76, "#5fd700"},
          {77, "#5fd75f"},
          {114, "#87d787"}
        ] do
      IO.puts(
        IO.ANSI.color(n) <> "% lade library(clpz) ..." <> IO.ANSI.reset() <> "   #{n} #{hex}"
      )
    end

    IO.puts(
      IO.ANSI.green() <>
        "% lade library(clpz) ..." <> IO.ANSI.reset() <> "   Grundfarbe Grün (8 Farben)"
    )

    :ok
  end

  defp bright(:error), do: IO.ANSI.light_red()
  defp bright(:comment), do: IO.ANSI.light_green()
  defp bright(:input), do: IO.ANSI.light_blue()

  # ---------------------------------------------------------------------

  defp read_lines(prompt, acc) do
    case PrologEx.Shell.gets(prompt, true) do
      line when is_binary(line) ->
        if String.trim(line) == "end_of_file.",
          do: acc |> Enum.reverse() |> Enum.join(),
          else: read_lines(prompt, [line | acc])

      # Ctrl-C (eigener Editor): Eingabe verwerfen
      {:error, :interrupted} ->
        PrologEx.Shell.clear_interrupt()
        IO.puts(paint(:comment, "% Eingabe abgebrochen"))
        ""

      _eof_or_error ->
        acc |> Enum.reverse() |> Enum.join()
    end
  end

  @doc false
  def device do
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
