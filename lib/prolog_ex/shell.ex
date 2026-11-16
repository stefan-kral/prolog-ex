defmodule PrologEx.Shell do
  @moduledoc """
  Der interaktive Toplevel als Shell der BEAM (`:shell.start_interactive/1`,
  ab OTP 26): Zeilen liest der Zeileneditor der BEAM (Pfeiltasten,
  Verlauf, TAB-Completion über `PrologEx.Shell.Complete`), und Ctrl-C
  bricht die laufende Anfrage ab.

  ## Ctrl-C

  Mit dem Emulator-Flag `+Bc` (`bin/prolog` setzt es) schickt die BEAM bei
  Ctrl-C kein BREAK-Menü, sondern unterbricht die Shell: Wartet der
  Toplevel gerade auf eine Zeile, liefert das Lesen `{:error, :interrupted}`
  (die Zeile wird verworfen); rechnet er, bekommt der Wächterprozess – für
  die BEAM ist er die Shell – ein Exit-Signal `:interrupt` und setzt ein
  `:atomics`-Flag. Die Maschine liest es an ihren Prüfpunkten (alle 1000
  Inferenzen, wo sie auch Zeit- und Speichergrenzen prüft) und wirft
  `'$aborted'`; der Toplevel meldet „Ausführung abgebrochen“. Datenbank,
  Flags und Operatoren bleiben. Ohne `+Bc` öffnet Ctrl-C weiter das
  BREAK-Menü der BEAM.

  Ein Builtin, das lange in Elixir rechnet, ohne Inferenzen zu zählen,
  bricht erst danach ab.

  Ohne Terminal, mit `--no-edit` oder unter iex (`repl/1`) bleibt es beim
  Lesen von stdin wie bisher (dann greift rlwrap mit seiner Zeilenbearbeitung).
  """

  @key :prolog_shell

  @doc """
  Toplevel als Shell der BEAM starten; true, wenn das geklappt hat.
  `slogan`: die erste Zeile (statt der Versionszeile der BEAM)
  """
  def start(slogan) do
    owner = self()
    Application.put_env(:stdlib, :shell_slogan, slogan)

    with true <- Code.ensure_loaded?(:shell) and function_exported?(:shell, :start_interactive, 1),
         :ok <- :shell.start_interactive({__MODULE__, :watcher, [owner]}) do
      receive do
        {@key, gl, watcher, ref} ->
          Process.group_leader(self(), gl)
          :io.setopts(binary: true, expand_fun: &PrologEx.Shell.Complete.expand/1)
          PrologEx.arm_interrupt(ref)
          PrologEx.Shell.Complete.init()
          Process.put(@key, %{ref: ref, watcher: watcher})
          true
      after
        5000 -> false
      end
    else
      _ -> false
    end
  end

  @doc false
  # von der BEAM als „Shell“ gestartet (läuft in der neuen Gruppe): nimmt
  # das Exit-Signal :interrupt entgegen, das Ctrl-C (+Bc) der Shell schickt
  def watcher(owner) do
    spawn(fn ->
      Process.flag(:trap_exit, true)
      ref = :atomics.new(1, [])
      send(owner, {@key, Process.group_leader(), self(), ref})
      watch(ref)
    end)
  end

  defp watch(ref) do
    receive do
      {:EXIT, _, :interrupt} -> :atomics.put(ref, 1, 1)
      _ -> :ok
    end

    watch(ref)
  end

  @doc "Läuft der Toplevel als Shell der BEAM?"
  def active?, do: Process.get(@key) != nil

  @doc "Ctrl-C-Flag zurücksetzen (vor jeder Anfrage und jeder Eingabe)"
  def clear_interrupt do
    case Process.get(@key) do
      %{ref: ref} -> :atomics.put(ref, 1, 0)
      _ -> :ok
    end
  end

  @doc "Ball von Ctrl-C (wie abort/0 in SWI)"
  def abort_ball, do: {:atom, "$aborted"}

  # ---------------------------------------------------------------------
  # Animation, während gerechnet wird
  # ---------------------------------------------------------------------

  @spinner :prolog_spinner
  @delay 500
  @tick 100
  @frames ~w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

  @doc """
  f ausführen; dauert es länger als 0,5 s, zeigt ein eigener Prozess am
  Zeilenanfang einen Kreisel mit der Laufzeit. Er verschwindet spurlos,
  sobald f fertig ist oder etwas ausgibt bzw. liest (`quiet/0`). Nur am
  Terminal mit Farben (`PrologEx.Terminal.color?/0`) und am Zeilenanfang.
  Die Rechnung kostet das nichts (der Kreisel läuft im eigenen Prozess).
  """
  def busy(f) do
    if PrologEx.Terminal.color?() and PrologEx.Stream.get(1).line_pos == 0 and
         Process.get(@spinner) == nil do
      owner = self()
      hint = if active?(), do: "  (Ctrl-C bricht ab)", else: ""
      Process.put(@spinner, spawn(fn -> spin_wait(owner, hint) end))

      try do
        f.()
      after
        quiet()
      end
    else
      f.()
    end
  end

  @doc "Kreisel anhalten und löschen (vor jeder Ausgabe; ohne Kreisel: nichts)"
  def quiet do
    case Process.get(@spinner) do
      nil ->
        :ok

      pid ->
        Process.delete(@spinner)
        ref = Process.monitor(pid)
        send(pid, :stop)

        receive do
          {:DOWN, ^ref, _, _, _} -> :ok
        after
          1000 -> :ok
        end
    end
  end

  defp spin_wait(owner, hint) do
    ref = Process.monitor(owner)

    receive do
      :stop -> :ok
      {:DOWN, ^ref, _, _, _} -> :ok
    after
      @delay -> spin(ref, hint, System.monotonic_time(:millisecond) - @delay, 0)
    end
  end

  defp spin(ref, hint, t0, i) do
    secs = (System.monotonic_time(:millisecond) - t0) / 1000
    time = secs |> :erlang.float_to_binary(decimals: 1) |> String.replace(".", ",")
    frame = Enum.at(@frames, rem(i, length(@frames)))
    IO.write("\r" <> PrologEx.Terminal.paint(:comment, "#{frame} #{time} s#{hint}") <> "\e[K")

    receive do
      :stop -> IO.write("\r\e[K")
      {:DOWN, ^ref, _, _, _} -> IO.write("\r\e[K")
    after
      @tick -> spin(ref, hint, t0, i + 1)
    end
  end
end
