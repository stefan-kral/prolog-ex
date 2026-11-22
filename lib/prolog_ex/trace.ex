defmodule PrologEx.Trace do
  @moduledoc """
  Der Tracer (Procedure-Box-Modell, Byrd): die Ports Call, Exit, Redo,
  Fail und Exception jedes Aufrufs in Benutzer-Code.

  Die Maschine (PrologEx) ruft hier nur im Trace-Modus an: trace/0 lässt
  jeden gezählten Schritt den langsamen Pfad nehmen, den es für
  Inferenz- und Zeitgrenzen ohnehin gibt (st.ilimit, limit_hit/5). Ohne
  Trace-Modus kostet der Tracer darum nichts. Dort legt die Maschine je
  Aufruf eine Exit-Marke auf den Zielstapel und einen Choice Point für Fail
  darunter (siehe PrologEx: trace_call/5, {:"$port_exit", ...},
  {:trace_fail, ...}, {:trace_redo, ...}); hier stehen der Zustand, die
  Ausgabe und die Fragen an den Benutzer.

  Zustand (Prozess-Dictionary, nur im Trace-Modus): der Stapel der offenen
  Rahmen (der innerste zuerst) – die Choice Points des Tracers stellen ihn
  beim Zurücksetzen wieder her –, die nächste Rahmennummer und ein
  laufendes skip. Ein Rahmen: {id, tiefe, ziel, ziel_beim_aufruf, modul,
  höhe}; höhe ist die Höhe des Choice-Point-Stapels mit dem Fail-Punkt
  des Rahmens.

  Gezeigt werden Aufrufe aus Modulen, die nicht zum System gehören
  (PrologEx.Builtins.system_module?/1): ein Bibliotheksprädikat erscheint
  als eine Box, ohne hineinzugehen. Nicht gezeigt: Steuerkonstrukte und
  interne Ziele ($...).
  """

  alias PrologEx.Stream, as: S
  alias PrologEx.Writer

  @key :prolog_ex_trace
  @leash_key :prolog_ex_leash
  @ports [:call, :exit, :redo, :fail, :exception]

  # Steuerkonstrukte (transparent für den Schnitt oder nur Gerüst) und die
  # Schalter des Tracers selbst
  @control MapSet.new([",", ";", "->", "*->", "|", ":", "!", "trace", "notrace", "nodebug"])

  # --- Schalter ---------------------------------------------------------------

  @doc "Ist der Trace-Modus an?"
  def on?, do: Process.get(@key) != nil

  @doc "Trace-Modus an (der Stapel bleibt, wenn er schon an ist)"
  def on, do: if(on?(), do: :ok, else: Process.put(@key, fresh()))

  @doc "Trace-Modus aus"
  def off, do: Process.delete(@key)

  @doc "Neue Anfrage im Trace-Modus: Stapel und skip zurücksetzen"
  def new_query, do: if(on?(), do: Process.put(@key, fresh()))

  defp fresh, do: %{stack: [], next: 1, skip: nil}

  @doc "Die Ports, an denen der Tracer fragt (leash/1)"
  def leash, do: Process.get(@leash_key, MapSet.new(@ports))
  def put_leash(ports), do: Process.put(@leash_key, MapSet.new(ports))
  def ports, do: @ports

  # --- Rahmen -----------------------------------------------------------------

  @doc "Wird dieses Ziel (im Kontextmodul mod) gezeigt?"
  def traced?(goal, mod) do
    traced_goal?(goal) and not PrologEx.Builtins.system_module?(mod)
  end

  defp traced_goal?({:struct, f, _}), do: not internal?(f)
  defp traced_goal?({:atom, f}), do: not internal?(f)
  defp traced_goal?([_ | _]), do: true
  defp traced_goal?([]), do: true
  defp traced_goal?(_), do: false

  defp internal?(f), do: MapSet.member?(@control, f) or String.starts_with?(f, "$")

  @doc """
  Ein Aufruf beginnt: neuer Rahmen oben auf dem Stapel. Ergebnis {rahmen,
  stapel_davor}; hf: die Höhe, die der Fail-Punkt des Rahmens bekommt.
  """
  def enter(goal, mod, subst, hf) do
    tr = Process.get(@key)
    depth = depth(tr.stack) + 1
    frame = {tr.next, depth, goal, PrologEx.resolve_out(goal, subst), mod, hf}
    Process.put(@key, %{tr | stack: [frame | tr.stack], next: tr.next + 1})
    {frame, tr.stack}
  end

  defp depth([{_, d, _, _, _, _} | _]), do: d
  defp depth([]), do: 0

  @doc "Höhe des Fail-Punkts eines Rahmens"
  def height({_, _, _, _, _, hf}), do: hf

  @doc "Den Stapel der offenen Rahmen setzen (Exit, Fail, Redo)"
  def set_stack(stack) do
    case Process.get(@key) do
      nil -> :ok
      tr -> Process.put(@key, %{tr | stack: stack})
    end
  end

  @doc """
  Eine Ausnahme verlässt den Rahmen (beim Abwickeln über seinen Fail-Punkt):
  ist er noch offen, der Port Exception. Ergebnis wie port/4.
  """
  def exception(frame, parent, ball) do
    case Process.get(@key) do
      %{stack: stack} ->
        cond do
          not Enum.any?(stack, &(elem(&1, 0) == elem(frame, 0))) ->
            :continue

          # abort (auch aus dem Tracer): ohne Ports
          ball == {:atom, "$aborted"} ->
            set_stack(parent)
            :continue

          true ->
            set_stack(parent)
            port(:exception, frame, nil, ball)
        end

      nil ->
        :continue
    end
  end

  # --- Ports ------------------------------------------------------------------

  @doc """
  Ein Port eines Rahmens: zeigen und, wo leash/1 es verlangt, fragen.
  Ergebnis :continue, :fail (das Ziel scheitern lassen) oder :abort. subst:
  die aktuellen Bindungen (für Call und Exit), sonst nil (das Ziel wie beim
  Aufruf).
  """
  def port(kind, frame, subst, ball \\ nil) do
    case Process.get(@key) do
      nil ->
        :continue

      %{skip: skip} = tr when skip != nil ->
        if skip == elem(frame, 0) and kind in [:exit, :fail, :exception] do
          Process.put(@key, %{tr | skip: nil})
          show(kind, frame, subst, ball)
        else
          :continue
        end

      _ ->
        show(kind, frame, subst, ball)
    end
  end

  defp show(kind, {_, depth, goal, at_call, mod, _} = frame, subst, ball) do
    g =
      if kind in [:call, :exit] and subst != nil,
        do: PrologEx.resolve_out(goal, subst),
        else: at_call

    line =
      "   " <>
        port_name(kind) <>
        ": (#{depth}) " <>
        qualified(mod) <> text(g) <> if(kind == :exception, do: " – " <> text(ball), else: "")

    if MapSet.member?(leash(), kind),
      do: ask(line, kind, frame),
      else:
        (
          out(line <> "\n")
          :continue
        )
  end

  defp port_name(:call), do: "Call"
  defp port_name(:exit), do: "Exit"
  defp port_name(:redo), do: "Redo"
  defp port_name(:fail), do: "Fail"
  defp port_name(:exception), do: "Exception"

  defp qualified("user"), do: ""
  defp qualified(mod), do: Writer.atom(mod, %{quoted: true}) <> ":"

  defp text(nil), do: ""
  defp text(t), do: Writer.format(t, quoted: true, max_depth: 10)

  # --- Fragen -----------------------------------------------------------------

  defp ask(line, kind, frame) do
    case read_answer(line <> " ? ") do
      :interrupted ->
        :abort

      :eof ->
        # keine Eingabe mehr (Datei, Pipe): weiter, ohne noch einmal zu fragen
        out("\n")
        put_leash([])
        :continue

      answer ->
        command(String.trim(answer), line, kind, frame)
    end
  end

  defp command(c, _line, _kind, _frame) when c in ["", "c"], do: :continue

  defp command("s", _line, kind, frame) do
    if kind in [:call, :redo] do
      tr = Process.get(@key)
      Process.put(@key, %{tr | skip: elem(frame, 0)})
    end

    :continue
  end

  defp command(c, _line, kind, _frame) when c in ["f"] and kind != :exception, do: :fail

  defp command(c, _line, _kind, _frame) when c in ["l", "n"] do
    off()
    :continue
  end

  defp command("a", _line, _kind, _frame), do: :abort

  defp command("g", line, kind, frame) do
    for {_, d, _, g, mod, _} <- Process.get(@key, %{stack: []}).stack do
      out("     [#{d}] " <> qualified(mod) <> text(g) <> "\n")
    end

    ask(line, kind, frame)
  end

  defp command(_c, line, kind, frame) do
    out("""
    Optionen:
      c, Enter   creep: weiter zum nächsten Port
      s          skip: bis zum Exit oder Fail dieses Aufrufs ohne Ausgabe
      l, n       leap, nodebug: ohne Tracer weiter (Trace-Modus aus)
      f          fail: dieses Ziel scheitern lassen
      g          goals: die offenen Aufrufe
      a          abort: die Anfrage abbrechen
    """)

    ask(line, kind, frame)
  end

  # --- Ein- und Ausgabe -----------------------------------------------------

  defp out(text) do
    id = S.lookup!({:atom, "user_error"})
    S.put_text(id, text)
    S.flush(id)
  end

  # im Terminal wie der Toplevel (eigener Editor oder rlwrap): die Zeile des
  # Ports als Prompt; sonst (Datei, Pipe) aus user_input
  defp read_answer(prompt) do
    for a <- ["user_output", "user_error"], do: S.flush(S.lookup!({:atom, a}))
    PrologEx.Shell.quiet()

    if PrologEx.Terminal.terminal?() do
      p = PrologEx.Terminal.input_prompt(prompt)

      data =
        if PrologEx.Shell.active?() or PrologEx.Shell.sigterm?(),
          do: PrologEx.Shell.gets(p, true),
          else: IO.gets(:stdio, p)

      PrologEx.Terminal.end_input()

      case data do
        d when is_binary(d) -> String.trim_trailing(d, "\n")
        {:error, :interrupted} -> :interrupted
        _ -> :eof
      end
    else
      out(prompt)
      read_line(S.lookup!({:atom, "user_input"}), [])
    end
  end

  defp read_line(id, acc) do
    case S.get_char(id) do
      :eof when acc == [] -> :eof
      :eof -> acc |> Enum.reverse() |> List.to_string()
      ?\n -> acc |> Enum.reverse() |> List.to_string()
      c -> read_line(id, [c | acc])
    end
  end
end
