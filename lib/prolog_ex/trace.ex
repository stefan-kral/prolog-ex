defmodule PrologEx.Trace do
  @moduledoc """
  Der Tracer (Procedure-Box-Modell, Byrd): die Ports Call, Exit, Redo,
  Fail und Exception jedes Aufrufs in Benutzer-Code. Die Prädikate gehören
  zu library(traces) (PrologEx.Builtins: Heimat "traces").

  Die Maschine (PrologEx) ruft hier nur im Trace-Modus an: trace/0 lässt
  jeden gezählten Schritt den langsamen Pfad nehmen, den es für
  Inferenz- und Zeitgrenzen ohnehin gibt (st.ilimit, limit_hit/5). Ohne
  Trace-Modus kostet der Tracer darum nichts. Dort legt die Maschine je
  Aufruf eine Exit-Marke auf den Zielstapel und einen Choice Point für Fail
  darunter (siehe PrologEx: trace_call/5, {:"$port_exit", ...},
  {:trace_fail, ...}, {:trace_redo, ...}); hier stehen der Zustand, die
  Ausgabe und die Fragen an den Benutzer.

  Zustand (Prozess-Dictionary, nur wenn der Debugger an ist): der Modus –
  :trace (jeder Port) oder :debug (still bis zu einem Spypunkt, spy/1) –,
  der Stapel der offenen Rahmen (der innerste zuerst; die Choice Points
  des Tracers stellen ihn beim Zurücksetzen wieder her), die nächste
  Rahmennummer und ein laufendes skip. Ein Rahmen: {id, tiefe, ziel,
  ziel_beim_aufruf, modul, höhe, spy?}; höhe ist die Höhe des
  Choice-Point-Stapels mit dem Fail-Punkt des Rahmens. Über Anfragen
  hinweg (eigene Schlüssel): Spypunkte, leash/1, visible/1, die
  Schreibweise der Ziele.

  Gezeigt werden Aufrufe aus Modulen, die nicht zum System gehören
  (PrologEx.Builtins.system_module?/1): ein Bibliotheksprädikat erscheint
  als eine Box, ohne hineinzugehen. Nicht gezeigt: Steuerkonstrukte und
  interne Ziele ($...).
  """

  alias PrologEx.Stream, as: S
  alias PrologEx.Writer

  @key :prolog_ex_trace
  @leash_key :prolog_ex_leash
  @visible_key :prolog_ex_visible
  @spy_key :prolog_ex_spy
  @print_key :prolog_ex_trace_print
  @ports [:call, :exit, :redo, :fail, :exception]

  # Steuerkonstrukte (transparent für den Schnitt oder nur Gerüst) und die
  # Schalter des Tracers selbst
  @control MapSet.new(
             [",", ";", "->", "*->", "|", ":", "!"] ++
               ~w(trace notrace nodebug debug spy nospy nospyall debugging leash visible tracing)
           )

  # --- Schalter ---------------------------------------------------------------

  @doc "Ist der Debugger an (Trace- oder Debug-Modus)?"
  def on?, do: Process.get(@key) != nil

  @doc "nil, :trace oder :debug"
  def mode do
    case Process.get(@key) do
      nil -> nil
      %{mode: m} -> m
    end
  end

  @doc "Trace-Modus an (der Stapel bleibt, wenn der Debugger schon an ist)"
  def on, do: set_mode(:trace, false)

  @doc """
  Ein Spypunkt ist erreicht: Trace-Modus bis zum Ende der Anfrage (danach
  wieder Debug-Modus, new_query/0)
  """
  def on_spy, do: set_mode(:trace, true)

  @doc "Debug-Modus: still bis zu einem Spypunkt"
  def debug, do: set_mode(:debug, false)

  defp set_mode(m, by_spy) do
    case Process.get(@key) do
      nil -> Process.put(@key, %{fresh(m) | by_spy: by_spy})
      tr -> Process.put(@key, %{tr | mode: m, skip: nil, by_spy: by_spy})
    end
  end

  @doc "Debugger aus"
  def off, do: Process.delete(@key)

  @doc "notrace/0, leap: mit Spypunkten weiter im Debug-Modus, sonst aus"
  def stop_tracing, do: if(spies() == MapSet.new(), do: off(), else: debug())

  @doc """
  Neue Anfrage: Stapel und skip zurücksetzen. Der Modus bleibt – außer ein
  Spypunkt hatte den Trace-Modus eingeschaltet: dann wieder Debug-Modus
  """
  def new_query do
    case Process.get(@key) do
      nil -> nil
      %{by_spy: true} -> Process.put(@key, fresh(:debug))
      %{mode: m} -> Process.put(@key, fresh(m))
    end
  end

  defp fresh(m), do: %{mode: m, stack: [], next: 1, skip: nil, by_spy: false}

  @doc "Die Ports, an denen der Tracer fragt (leash/1)"
  def leash, do: Process.get(@leash_key, MapSet.new(@ports))

  def put_leash(ports) do
    Process.put(@leash_key, MapSet.new(ports))
    :ok
  end

  @doc "Die Ports, die der Tracer überhaupt zeigt (visible/1)"
  def visible, do: Process.get(@visible_key, MapSet.new(@ports))

  def put_visible(ports) do
    Process.put(@visible_key, MapSet.new(ports))
    :ok
  end

  def ports, do: @ports

  # --- Spypunkte ------------------------------------------------------------

  @doc "Spypunkte: MapSet von {name, stelligkeit | :any}"
  def spies, do: Process.get(@spy_key, MapSet.new())

  @doc "spy/1, nospy/1: Spezifikation (aufgelöster Term) -> [{name, arity | :any}]"
  def spy_keys(l) when is_list(l), do: Enum.flat_map(l, &spy_keys/1)

  def spy_keys({tag, ":", [_m, spec]}) when tag in [:struct, :gstruct], do: spy_keys(spec)

  def spy_keys({tag, "/", [{:atom, n}, a]}) when tag in [:struct, :gstruct] and is_integer(a),
    do: [{n, a}]

  def spy_keys({:atom, n}), do: [{n, :any}]
  def spy_keys({:var, _}), do: PrologEx.Error.instantiation!()
  def spy_keys(t), do: PrologEx.Error.type!("predicate_indicator", t)

  @doc "Spypunkte setzen (und melden)"
  def spy(keys) do
    Process.put(@spy_key, MapSet.union(spies(), MapSet.new(keys)))
    for k <- keys, do: out("% Spypunkt auf #{key_text(k)}\n")
  end

  @doc "Spypunkte entfernen (nospy/1); keys = :all: alle"
  def nospy(:all), do: Process.delete(@spy_key)

  def nospy(keys) do
    before = spies()

    rest =
      Enum.reduce(keys, spies(), fn
        {n, :any}, acc -> MapSet.reject(acc, &(elem(&1, 0) == n))
        k, acc -> MapSet.delete(acc, k)
      end)

    Process.put(@spy_key, rest)

    for k <- before |> MapSet.difference(rest) |> Enum.sort(),
        do: out("% Spypunkt auf #{key_text(k)} entfernt\n")
  end

  defp key_text({n, :any}), do: Writer.atom(n, %{quoted: true})
  defp key_text({n, a}), do: Writer.atom(n, %{quoted: true}) <> "/#{a}"

  @doc "Hat das Prädikat dieses Ziels einen Spypunkt?"
  def spy?(goal) do
    sp = spies()

    MapSet.size(sp) > 0 and
      case goal_key(goal) do
        {n, a} -> MapSet.member?(sp, {n, a}) or MapSet.member?(sp, {n, :any})
        nil -> false
      end
  end

  defp goal_key({:struct, f, args}), do: {f, length(args)}
  defp goal_key({:atom, f}), do: {f, 0}
  defp goal_key([_ | _]), do: {".", 2}
  defp goal_key([]), do: {"[]", 0}
  defp goal_key(_), do: nil

  @doc "debugging/0: der Zustand des Debuggers"
  def debugging do
    m =
      case mode() do
        nil -> "Debugger aus"
        :trace -> "Trace-Modus"
        :debug -> "Debug-Modus"
      end

    sp =
      case spies() |> Enum.map(&key_text/1) |> Enum.sort() do
        [] -> "keine Spypunkte"
        l -> "Spypunkte: " <> Enum.join(l, ", ")
      end

    ports = fn set -> for(p <- @ports, MapSet.member?(set, p), do: Atom.to_string(p)) end

    out(
      "% #{m}; #{sp}\n% leash: [#{Enum.join(ports.(leash()), ",")}], " <>
        "visible: [#{Enum.join(ports.(visible()), ",")}]\n"
    )
  end

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
    frame = {tr.next, depth, goal, PrologEx.resolve_out(goal, subst), mod, hf, spy?(goal)}
    Process.put(@key, %{tr | stack: [frame | tr.stack], next: tr.next + 1})
    {frame, tr.stack}
  end

  defp depth([frame | _]), do: elem(frame, 1)
  defp depth([]), do: 0

  @doc "Höhe des Fail-Punkts eines Rahmens"
  def height(frame), do: elem(frame, 5)

  @doc "Sind zwei Rahmen derselbe?"
  def same?(f1, f2), do: elem(f1, 0) == elem(f2, 0)

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
  Ergebnis :continue, :fail (das Ziel scheitern lassen), :retry (neu
  beginnen, nicht an Call) oder :abort. subst: die aktuellen Bindungen
  (für Call und Exit), sonst nil (das Ziel wie beim Aufruf).
  """
  def port(kind, frame, subst, ball \\ nil) do
    case Process.get(@key) do
      nil ->
        :continue

      # Debug-Modus: still – außer an den Ports eines Prädikats mit
      # Spypunkt (dann Trace-Modus, wie beim Call)
      %{mode: :debug} ->
        if elem(frame, 6) do
          on_spy()
          show(kind, frame, subst, ball)
        else
          :continue
        end

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

  defp show(kind, frame, subst, ball) do
    cond do
      not MapSet.member?(visible(), kind) ->
        :continue

      MapSet.member?(leash(), kind) ->
        ask(kind, frame, subst, ball)

      true ->
        out(line(kind, frame, subst, ball) <> "\n")
        :continue
    end
  end

  defp line(kind, {_, depth, goal, at_call, mod, _, spy}, subst, ball) do
    g =
      if kind in [:call, :exit] and subst != nil,
        do: PrologEx.resolve_out(goal, subst),
        else: at_call

    if(spy, do: " * ", else: "   ") <>
      port_name(kind) <>
      ": (#{depth}) " <>
      qualified(mod) <> text(g) <> if(kind == :exception, do: " – " <> text(ball), else: "")
  end

  defp port_name(:call), do: "Call"
  defp port_name(:exit), do: "Exit"
  defp port_name(:redo), do: "Redo"
  defp port_name(:fail), do: "Fail"
  defp port_name(:exception), do: "Exception"

  defp qualified("user"), do: ""
  defp qualified(mod), do: Writer.atom(mod, %{quoted: true}) <> ":"

  defp text(nil), do: ""
  defp text(t), do: Writer.format(t, print_opts())

  # Schreibweise der Ziele: print (Vorgabe: quoted, max_depth 10), write
  # (ohne Anführungszeichen), display (ohne Operatoren); w, p, d, <N
  defp print_opts do
    {how, depth} = Process.get(@print_key, {:print, 10})

    base =
      case how do
        :print -> [quoted: true]
        :write -> []
        :display -> [quoted: true, ignore_ops: true]
      end

    [max_depth: depth] ++ base
  end

  defp put_print(how),
    do: Process.put(@print_key, {how, elem(Process.get(@print_key, {:print, 10}), 1)})

  defp put_depth(d),
    do: Process.put(@print_key, {elem(Process.get(@print_key, {:print, 10}), 0), d})

  # --- Fragen -----------------------------------------------------------------

  defp ask(kind, frame, subst, ball) do
    case read_answer(line(kind, frame, subst, ball) <> " ? ") do
      :interrupted ->
        :abort

      :eof ->
        # keine Eingabe mehr (Datei, Pipe): weiter, ohne noch einmal zu fragen
        out("\n")
        put_leash([])
        :continue

      answer ->
        command(String.trim(answer), kind, frame, subst, ball)
    end
  end

  defp command(c, _kind, _frame, _subst, _ball) when c in ["", "c"], do: :continue

  defp command("s", kind, frame, _subst, _ball) do
    if kind in [:call, :redo] do
      tr = Process.get(@key)
      Process.put(@key, %{tr | skip: elem(frame, 0)})
    end

    :continue
  end

  defp command("f", kind, _frame, _subst, _ball) when kind != :exception, do: :fail
  defp command("r", kind, _frame, _subst, _ball) when kind != :call, do: :retry

  defp command("l", _kind, _frame, _subst, _ball) do
    stop_tracing()
    :continue
  end

  defp command("n", _kind, _frame, _subst, _ball) do
    off()
    :continue
  end

  defp command("a", _kind, _frame, _subst, _ball), do: :abort

  defp command("g", kind, frame, subst, ball) do
    for {_, d, _, g, mod, _, _} <- Process.get(@key, %{stack: []}).stack do
      out("     [#{d}] " <> qualified(mod) <> text(g) <> "\n")
    end

    ask(kind, frame, subst, ball)
  end

  defp command(c, kind, frame, subst, ball) when c in ["w", "p", "d"] do
    put_print(%{"w" => :write, "p" => :print, "d" => :display}[c])
    ask(kind, frame, subst, ball)
  end

  defp command("<" <> n, kind, frame, subst, ball) do
    case Integer.parse(String.trim(n)) do
      {d, ""} when d >= 0 -> put_depth(d)
      _ when n == "" -> put_depth(0)
      _ -> out("% < N: N eine Zahl (0: unbegrenzt)\n")
    end

    ask(kind, frame, subst, ball)
  end

  defp command(_c, kind, frame, subst, ball) do
    out("""
    Optionen:
      c, Enter   creep: weiter zum nächsten Port
      s          skip: bis zum Exit oder Fail dieses Aufrufs ohne Ausgabe
      l          leap: bis zum nächsten Spypunkt (ohne Spypunkte: Debugger aus)
      n          nodebug: ohne Debugger weiter
      r          retry: den Aufruf neu beginnen (nicht an Call)
      f          fail: dieses Ziel scheitern lassen
      g          goals: die offenen Aufrufe
      w, p, d    Ziele mit write, print (Vorgabe), display zeigen
      < N        höchstens N tief zeigen (< allein: unbegrenzt)
      a          abort: die Anfrage abbrechen
    """)

    ask(kind, frame, subst, ball)
  end

  # --- Ein- und Ausgabe -----------------------------------------------------

  defp out(text) do
    id = S.lookup!({:atom, "user_error"})
    S.put_text(id, text)
    S.flush(id)
  end

  @doc false
  # für Tests: alles zurück auf die Vorgaben (Debugger aus, keine Spypunkte)
  def reset do
    for k <- [@key, @leash_key, @visible_key, @spy_key, @print_key, :prolog_ex_trace_input],
        do: Process.delete(k)

    :ok
  end

  @doc false
  # für Tests: die Antworten aus diesem Stream statt von user_input
  def put_input(id), do: Process.put(:prolog_ex_trace_input, id)

  # im Terminal wie der Toplevel (eigener Editor oder rlwrap): die Zeile des
  # Ports als Prompt; sonst (Datei, Pipe) aus user_input
  defp read_answer(prompt) do
    for a <- ["user_output", "user_error"], do: S.flush(S.lookup!({:atom, a}))
    PrologEx.Shell.quiet()
    input = Process.get(:prolog_ex_trace_input)

    if input == nil and PrologEx.Terminal.terminal?() do
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
      read_line(input || S.lookup!({:atom, "user_input"}), [])
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
