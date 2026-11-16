defmodule PrologEx.Shell do
  @moduledoc """
  Der interaktive Toplevel am Terminal: eigener Zeileneditor
  (`PrologEx.Shell.Edit`) auf dem Terminal im Rohmodus
  (`:shell.start_interactive({:noshell, :raw})`, ab OTP 26).

  Warum ein eigener Editor: Im Rohmodus kommen Ctrl-D und (mit dem
  Emulator-Flag `+Bc`: `elixir --erl "+Bc" -S mix prolog`) Ctrl-C als gewöhnliche
  Zeichen an. So beendet Ctrl-D auf leerer Zeile die Eingabe (`[user]`,
  `consult(user)`, am Prompt `?-` die Sitzung) und Ctrl-C bricht eine
  laufende Anfrage ab. Der Zeileneditor der BEAM (edlin) kennt kein
  Dateiende auf Ctrl-D – dort löscht es nur ein Zeichen.

  ## Leser und Ctrl-C

  Ein Leseprozess holt Zeichen für Zeichen von stdin und schickt sie dem
  Toplevel. Wartet der Toplevel gerade nicht auf eine Zeile (er rechnet),
  setzt Ctrl-C stattdessen ein `:atomics`-Flag; die Maschine liest es an
  ihren Prüfpunkten (alle 1000 Inferenzen, wo sie auch Zeit- und
  Speichergrenzen prüft) und wirft `'$aborted'`; der Toplevel meldet
  „Ausführung abgebrochen“. Datenbank, Flags und Operatoren bleiben. Was
  man während einer Rechnung tippt, geht nicht verloren (Vorauseingabe).
  Ohne `+Bc` öffnet Ctrl-C weiter das BREAK-Menü der BEAM.

  Ein Builtin, das lange in Elixir rechnet, ohne Inferenzen zu zählen,
  bricht erst danach ab.

  ## Terminal

  Der Rohmodus schaltet auch die Ausgabe um (`\\n` ohne Wagenrücklauf);
  `stty opost onlcr` auf dem Terminalgerät stellt das zurück. Die
  Einstellungen von vorher (`stty -g`) kommen am Ende wieder
  (`stop/0`). Ohne Terminalgerät, mit `--no-edit` oder unter iex
  (`repl/1`) liest der Toplevel wie bisher zeilenweise von stdin (dann
  greift rlwrap).
  """

  @key :prolog_shell
  # Ctrl-C-Flag (:atomics), auch ohne eigenen Editor (SIGTERM, siehe
  # trap_sigterm/0)
  @ref_key :prolog_interrupt_ref
  @sigterm_key :prolog_sigterm

  @doc "Am Terminal in den Rohmodus mit eigenem Editor; true, wenn das geklappt hat"
  def start do
    with true <- Code.ensure_loaded?(:shell) and function_exported?(:shell, :start_interactive, 1),
         {:ok, dev} <- PrologEx.Terminal.device(),
         {saved, 0} <- stty(dev, "-g"),
         :ok <- :shell.start_interactive({:noshell, :raw}),
         {_, 0} <- stty(dev, "opost onlcr") do
      ref = :atomics.new(1, [])
      waiting = :atomics.new(1, [])
      owner = self()
      reader = spawn_link(fn -> read_keys(owner, ref, waiting) end)
      PrologEx.arm_interrupt(ref)
      Process.put(@ref_key, ref)
      PrologEx.Shell.Complete.init()

      Process.put(@key, %{
        ref: ref,
        waiting: waiting,
        reader: reader,
        dev: dev,
        saved: String.trim(saved)
      })

      PrologEx.Shell.Edit.load_history()
      true
    else
      _ -> false
    end
  end

  @doc "Terminal wie vorher (am Ende der Sitzung)"
  def stop do
    untrap_sigterm()

    case Process.delete(@key) do
      %{dev: dev, saved: saved, reader: reader} ->
        Process.unlink(reader)
        Process.exit(reader, :kill)
        stty(dev, saved)
        :ok

      _ ->
        :ok
    end
  end

  defp stty(dev, args) do
    System.cmd("sh", ["-c", "stty #{args} < #{dev}"], stderr_to_stdout: true)
  rescue
    _ -> {"", 1}
  end

  # Leseprozess: Zeichen für Zeichen; Ctrl-C, während niemand liest,
  # setzt das Flag (statt als Zeichen anzukommen)
  defp read_keys(owner, ref, waiting) do
    case IO.getn("", 1) do
      <<3>> ->
        if :atomics.get(waiting, 1) == 1,
          do: send(owner, {:prolog_key, <<3>>}),
          else: :atomics.put(ref, 1, 1)

        read_keys(owner, ref, waiting)

      c when is_binary(c) ->
        send(owner, {:prolog_key, c})
        read_keys(owner, ref, waiting)

      _eof_or_error ->
        send(owner, {:prolog_key, :eof})
    end
  end

  @doc "Läuft die BEAM mit +Bc (Ctrl-C kommt als Zeichen an, statt BREAK)?"
  def ctrl_c?, do: ~c"-Bc" in :erlang.system_info(:emu_args)

  @doc "Läuft der eigene Editor (Rohmodus)?"
  def active?, do: Process.get(@key) != nil

  @doc false
  def state, do: Process.get(@key)

  @doc """
  Eine Zeile lesen: mit dem eigenen Editor (Rohmodus) oder wie bisher mit
  `IO.gets/1`. Ergebnis wie `IO.gets/1`, dazu `{:error, :interrupted}` für
  Ctrl-C
  """
  def gets(prompt, interruptible \\ false) do
    cond do
      active?() -> PrologEx.Shell.Edit.read(prompt)
      sigterm?() -> term_gets(prompt, interruptible)
      true -> IO.gets(prompt)
    end
  end

  @doc "Bricht SIGTERM ab (--no-edit, trap_sigterm/0)?"
  def sigterm?, do: Process.get(@sigterm_key) == true

  # Mit SIGTERM als Ctrl-C (rlwrap -I): ein Hilfsprozess liest, der
  # Toplevel wartet auf die Zeile oder :prolog_interrupt. Abgebrochen
  # (interruptible: Lesen für eine Anfrage) bleibt der Hilfsprozess stehen –
  # ihn abzuschießen ließe die nächste getippte Zeile im Ein-/Ausgabe-Server
  # verschwinden; seine Zeile bekommt das nächste Lesen, das dann nur den
  # Prompt selbst zeigt. Ctrl-C, während niemand liest, zählt hier nicht
  @pending :prolog_pending_read

  defp term_gets(prompt, interruptible) do
    flush_interrupts()

    case Process.get(@pending) do
      nil ->
        me = self()
        Process.put(@pending, spawn(fn -> send(me, {:prolog_line, IO.gets(prompt)}) end))

      _ ->
        IO.write(prompt)
    end

    wait_line(interruptible)
  end

  defp wait_line(interruptible) do
    receive do
      {:prolog_line, data} ->
        Process.delete(@pending)
        data

      :prolog_interrupt when interruptible ->
        IO.write("\n")
        {:error, :interrupted}

      :prolog_interrupt ->
        wait_line(false)
    end
  end

  @doc false
  def flush_interrupts do
    receive do
      :prolog_interrupt -> flush_interrupts()
    after
      0 -> :ok
    end
  end

  @doc "Ctrl-C-Flag zurücksetzen (vor jeder Anfrage und jeder Eingabe)"
  def clear_interrupt do
    case Process.get(@ref_key) do
      nil -> :ok
      ref -> :atomics.put(ref, 1, 0)
    end
  end

  @doc """
  Ohne eigenen Editor (`--no-edit`, etwa unter `rlwrap -I` in `start_ex`):
  SIGTERM setzt das Ctrl-C-Flag, statt die BEAM zu beenden. `rlwrap -I`
  (`--pass-sigint-as-sigterm`) schickt bei Ctrl-C ein SIGTERM; SIGINT
  selbst kann die BEAM nicht abfangen (es führt zum BREAK-Menü). Kommt
  SIGTERM, während keine Anfrage läuft, passiert nichts. Beenden: `halt.`
  oder Ctrl-D.
  """
  def trap_sigterm do
    ref = :atomics.new(1, [])
    PrologEx.arm_interrupt(ref)
    Process.put(@ref_key, ref)

    :ok =
      :gen_event.swap_handler(
        :erl_signal_server,
        {:erl_signal_handler, []},
        {PrologEx.Shell.Sigterm, {ref, self()}}
      )

    :os.set_signal(:sigterm, :handle)
    Process.put(@sigterm_key, true)
    :ok
  rescue
    _ -> :error
  end

  @doc "SIGTERM wieder wie üblich (beendet die BEAM)"
  def untrap_sigterm do
    if Process.delete(@sigterm_key) do
      :gen_event.swap_handler(
        :erl_signal_server,
        {PrologEx.Shell.Sigterm, []},
        {:erl_signal_handler, []}
      )
    end

    :ok
  end

  @doc "Bricht Ctrl-C eine laufende Anfrage ab (eigener Editor mit +Bc, oder SIGTERM)?"
  def interruptible?,
    do: (active?() and ctrl_c?()) or Process.get(@sigterm_key) == true

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
      hint = if interruptible?(), do: "  (Ctrl-C bricht ab)", else: ""
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
