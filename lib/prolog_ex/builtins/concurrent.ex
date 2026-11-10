defmodule PrologEx.Builtins.Concurrent do
  @moduledoc """
  Kindprozesse für `library(concurrent)` (Prolog-Teil:
  `priv/library/concurrent.pl`).

  `'$conc_run'(+Jobs, +Mode, +Max, +Deadline, +Budget, +Mem, -R)`:
  jeder Job `T-G` läuft in einem eigenen BEAM-Prozess mit einer Kopie des
  Interpreter-Zustands, super-strikt ohne Seiteneffekte (`'$nse_call'/1`,
  siehe `call_with_no_side_effects/1`), höchstens Max gleichzeitig.

    * Mode `once`: je Job die erste Lösung; R = `ok([T1, ...])` in der
      Reihenfolge der Jobs, `fail`, sobald ein Job scheitert.
    * Mode `findall`: je Job alle Lösungen; R = `ok([L1, ...])`.
    * Mode `first(OnFail)`: wer zuerst eine Lösung hat, gewinnt (R =
      `ok([T])`); OnFail `stop`: das erste Scheitern beendet alles (R =
      `fail`), `continue`: erst wenn alle gescheitert sind.

  Eine Ausnahme in einem Kind (auch der Seiteneffekt-Fehler) beendet alle
  anderen sofort und wird hier geworfen – welche, wenn mehrere werfen,
  entscheidet der Scheduler. Ebenso beim Scheitern (once) und beim ersten
  Erfolg (first): die übrigen Kinder werden beendet. Weil die Kinder keine
  Wirkung haben können, ist das gefahrlos.

  Grenzen der aufrufenden Maschine gelten weiter: die Deadline (für die
  Kinder und das Warten hier), das restliche Inferenzbudget (für alle
  zusammen: die Kinder erben den Inferenzzähler – ein `:atomics`, das die
  Prozesse teilen – und zählen dort mit), die engste Speichergrenze je
  Kind.

  Ergebnisse kommen als aufgelöste Kopien zurück (Nachrichten; geteilte
  Teilbäume werden dabei ausgerollt). Attributierte Variablen in Jobs oder
  Ergebnissen: `representation_error(concurrent_attributed_variable)`,
  zyklische Ergebnisse: `representation_error(cyclic_term)`.
  """
  use PrologEx.Builtin
  alias PrologEx.Error

  # concurrent_child(-I/N): im Kind seine Position unter den Zielen des
  # (innersten) Aufrufs, 1-basiert, und deren Anzahl; außerhalb scheitert es
  defbuiltin "$conc_child", [p] do
    case Process.get(:conc_child) do
      {pos, total} -> {:unify, [{p, mk("/", [pos, total])}]}
      nil -> :fail
    end
  end

  # concurrent_child_stack(-Stack): [I/N, ...], innerster Aufruf oben;
  # außerhalb jedes Kinds []
  defbuiltin "$conc_child_stack", [p] do
    path = for {i, n} <- Process.get(:conc_path, []), do: mk("/", [i, n])
    {:unify, [{p, path}]}
  end

  # im Kind, vor dem Kopieren des Ergebnisses: keine attributierten
  # Variablen darin (ihre Bedingungen gingen verloren), sonst
  # representation_error; atomare Ergebnisse sofort
  defbuiltin "$conc_no_attvars", [t] do
    s = subst()

    case PrologEx.Store.walk(t, s) do
      x when is_number(x) or x == [] -> true
      {:atom, _} -> true
      {:rat, _, _} -> true
      _ -> if PrologEx.term_attvars(t, s) == [], do: true, else: Error.throw!(attv_error())
    end
  end

  defbuiltin "$conc_run", [jobs, mode, max, deadline, budget, mem, r] do
    s = subst()
    jobs = for j <- PrologEx.Builtins.Lists.items(jobs, s), do: PrologEx.resolve(j, s)
    Enum.each(jobs, &no_attvars!/1)
    mode = mode!(PrologEx.resolve(mode, s))

    # Max: N | default | sched(N | default, K | auto) (Arbeiter, Paketgröße)
    {max, chunk} =
      case PrologEx.resolve(max, s) do
        {:struct, "sched", [w, k]} ->
          {workers(w), if(is_integer(k) and k >= 1, do: k, else: :auto)}

        w ->
          {workers(w), :auto}
      end

    limits = {opt(deadline, s), opt(budget, s), opt(mem, s)}
    # Zufall in den Kindern: Startwerte aus dem Generator des Aufrufers (im
    # Bereich ohne Seiteneffekte nur angesehen, nicht weitergeschaltet)
    Process.put(:conc_seed, PrologEx.Builtins.Random.split_base(PrologEx.Effects.random_ok?(s)))
    Process.delete(:conc_prints)
    # Anzahl der Ziele dieses Aufrufs (concurrent_child/1 im Kind)
    Process.put(:conc_total, length(jobs))

    try do
      res = run(jobs, mode, {max, chunk}, limits)
      emit(s)
      {:unify, [{r, res}]}
    rescue
      e in Error ->
        emit(s)
        reraise e, __STACKTRACE__
    end
  end

  # gepufferte Ausgabe der Kinder hier ausgeben (siehe conclude/4); im
  # Bereich ohne Seiteneffekte nur in einen Stream des Bereichs
  defp emit(s) do
    for {kind, text} <- Process.delete(:conc_prints) || [] do
      {id, name, arity, args} =
        case kind do
          :out -> {PrologEx.Stream.current_output(), "write", 1, [a(text)]}
          :err -> {2, "write", 2, [a("user_error"), a(text)]}
        end

      PrologEx.Effects.nse_check!(s, "io", name, arity, fn -> mk(name, args) end, args)
      PrologEx.Stream.put_text(id, text)
    end

    :ok
  end

  defp workers(n) when is_integer(n) and n >= 1, do: n
  defp workers(_), do: System.schedulers_online()

  defp opt(t, s) do
    case PrologEx.Store.walk(t, s) do
      n when is_integer(n) -> n
      _ -> nil
    end
  end

  defp mode!({:atom, "once"}), do: :once
  defp mode!({:atom, "findall"}), do: :findall

  defp mode!({:struct, "first", [{:atom, on_fail}, {:atom, output}, {:atom, on_error}]}),
    do: {:first, on_fail, output, on_error}

  # --- Elternprozess ----------------------------------------------------------

  defp run([], {:first, _, _, _}, _max, _limits), do: a("fail")
  defp run([], _mode, _max, _limits), do: mk("ok", [[]])

  defp run(jobs, mode, {max, chunk}, {deadline, _, _} = limits) do
    ref = make_ref()
    # der Zustand einmal je Aufruf als persistent_term: die Arbeiter lesen
    # ihn, ohne ihn in ihren Heap zu kopieren (eine Kopie je Kind kostete bei
    # 2 MiB Datenbank rund 2 ms, so sind es ~30 µs); am Ende gelöscht
    state = {:prolog_ex_conc_state, ref}
    :persistent_term.put(state, child_state())
    waiting = Enum.with_index(jobs)
    n = length(jobs)
    # first: jedes Ziel ein eigener Arbeiter (sie laufen gegeneinander)
    w = if match?({:first, _, _, _}, mode), do: n, else: min(max, n)
    sched = %{w: w, chunk: chunk, n_wait: n}

    try do
      {running, waiting, sched} =
        Enum.reduce(1..w, {%{}, waiting, sched}, fn _, {running, waiting, sched} ->
          pid = spawn_worker(ref, mode, limits, state)
          dispatch(ref, pid, running, waiting, sched)
        end)

      loop(ref, running, {waiting, sched}, mode, limits, state, deadline, %{})
    after
      # alle noch laufenden beenden (auch bei Ausnahmen hier), dann den
      # geteilten Zustand freigeben (die Arbeiter sind entkoppelt: einer,
      # der ihn noch zu lesen versucht, stirbt allein)
      kill_all(ref)
      :persistent_term.erase(state)
    end
  end

  # Blockung (wie OpenMP schedule(dynamic) mit guided-Paketen): ein Arbeiter,
  # der nichts mehr zu tun hat, bekommt das nächste Paket – Rest / (2·W),
  # mindestens 1, oder eine feste Größe (chunk(K)); ist nichts mehr da, wird
  # er beendet. running: Arbeiter -> seine offenen Indizes (der erste läuft)
  defp dispatch(ref, pid, running, [], sched) do
    send(pid, {:stop, ref})
    {Map.delete(running, pid), [], sched}
  end

  defp dispatch(ref, pid, running, waiting, %{w: w, chunk: chunk, n_wait: nw} = sched) do
    k =
      case chunk do
        :auto -> max(1, div(nw, 2 * w))
        k -> k
      end

    {pkg, rest} = Enum.split(waiting, k)
    send(pid, {:jobs, ref, for({{:struct, "-", [t, g]}, i} <- pkg, do: {i, t, g})})
    running = Map.put(running, pid, for({_, i} <- pkg, do: i))
    {running, rest, %{sched | n_wait: nw - length(pkg)}}
  end

  # results: Index -> Ergebnis
  defp loop(ref, running, queue, mode, limits, state, deadline, results) do
    if map_size(running) == 0 do
      res = finish(mode, results)
      conclude(ref, mode, running, if(res == a("fail"), do: nil, else: :all))
      res
    else
      timeout = if deadline, do: max(div(deadline - now_us(), 1000), 0), else: :infinity

      receive do
        {:conc, ^ref, pid, i, res, text} when is_map_key(running, pid) ->
          oc = outcome(res, mode)
          outs = Process.get({:conc_outs, ref}, %{})
          Process.put({:conc_outs, ref}, Map.put(outs, i, {status(oc), text}))
          # das Element ist fertig; der Arbeiter macht mit seinem Paket weiter
          running = Map.update!(running, pid, &List.delete(&1, i))

          case {oc, mode} do
            # first_solution/3 mit on_error(continue): wie ein Scheitern
            # (sind alle gescheitert oder haben geworfen: scheitern, wie SWI)
            {{:error, _}, {:first, _, _, "continue"}} ->
              next(ref, pid, running, queue, mode, limits, state, deadline, results)

            {{:error, ball}, _} ->
              conclude(ref, mode, Map.delete(running, pid), nil)
              Error.throw!(ball)

            {:fail, :once} ->
              a("fail")

            {:fail, {:first, "stop", _, _}} ->
              conclude(ref, mode, Map.delete(running, pid), nil)
              a("fail")

            {:fail, _} ->
              next(ref, pid, running, queue, mode, limits, state, deadline, results)

            {{:ok, t}, {:first, _, _, _}} ->
              conclude(ref, mode, Map.delete(running, pid), i)
              mk("ok", [[t]])

            {{:ok, t}, _} ->
              results = Map.put(results, i, t)
              next(ref, pid, running, queue, mode, limits, state, deadline, results)
          end

        # ein abgestürzter Arbeiter bei on_error(continue) (first: ein Ziel
        # je Arbeiter): wie ein Scheitern
        {:DOWN, _mon, :process, pid, _reason}
        when is_map_key(running, pid) and elem(mode, 0) == :first and
               elem(mode, 3) == "continue" ->
          Process.put({:conc_mon, ref}, Map.delete(Process.get({:conc_mon, ref}, %{}), pid))
          outs = Process.get({:conc_outs, ref}, %{})

          outs =
            Enum.reduce(running[pid], outs, fn i, o -> Map.put(o, i, {:error, ""}) end)

          Process.put({:conc_outs, ref}, outs)
          running = Map.delete(running, pid)
          loop(ref, running, queue, mode, limits, state, deadline, results)

        {:DOWN, _mon, :process, pid, reason} when is_map_key(running, pid) ->
          # (ein Arbeiter, der normal endet, hat nichts mehr offen; hier also
          # ein Absturz)
          conclude(ref, mode, running, nil)

          Error.throw!(
            mk("error", [
              mk("system_error", [mk("concurrent_child", [a(inspect(reason, limit: 5))])]),
              fresh_var()
            ])
          )
      after
        timeout ->
          conclude(ref, mode, running, nil)
          Error.throw!(a("time_limit_exceeded"))
      end
    end
  end

  # ist der Arbeiter mit seinem Paket fertig: das nächste (oder beenden)
  defp next(ref, pid, running, {waiting, sched} = queue, mode, limits, state, deadline, results) do
    {running, queue} =
      case running[pid] do
        [] ->
          {running, waiting, sched} = dispatch(ref, pid, running, waiting, sched)
          {running, {waiting, sched}}

        _ ->
          {running, queue}
      end

    loop(ref, running, queue, mode, limits, state, deadline, results)
  end

  defp finish({:first, _, _, _}, _results), do: a("fail")

  defp finish(_mode, results) do
    l = results |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
    mk("ok", [PrologEx.list(l)])
  end

  # Ergebnis eines Kindes: r(Res, Inferenzen) mit Res = ok(L) | error(E)
  defp outcome({:struct, "ok", [l]}, :findall), do: {:ok, l}

  defp outcome({:struct, "ok", [l]}, _mode) do
    case PrologEx.unmark_top(l) do
      [t | _] -> {:ok, t}
      [] -> :fail
    end
  end

  defp outcome({:struct, "error", [e]}, _mode), do: {:error, e}

  # --- gepufferte Ausgabe ------------------------------------------------------
  #
  # Jedes Kind schreibt in einen eigenen Speicher-Stream. Ausgegeben wird
  # beim Aufrufer, wenn alles entschieden ist (emit/1): bei once/findall nach
  # Erfolg alle in der Reihenfolge der Ziele, bei first die des Gewinners;
  # mit output(all) dazu die übrigen (auch abgebrochene: was sie bis dahin
  # geschrieben hatten) auf user_error, je mit einer Kopfzeile.

  defp status({:ok, _}), do: :ok
  defp status(:fail), do: :fail
  defp status({:error, _}), do: :error

  defp conclude(ref, mode, running, winner) do
    outs = Process.get({:conc_outs, ref}, %{})
    Process.delete({:conc_outs, ref})

    prints =
      case {mode, winner} do
        {{:first, _, out, _}, _} ->
          w = if winner, do: [{:out, elem(Map.fetch!(outs, winner), 1)}], else: []
          if out == "all", do: w ++ others(ref, mode, outs, running, winner), else: w

        {_, :all} ->
          for {_i, {_, text}} <- Enum.sort(outs), do: {:out, text}

        _ ->
          []
      end

    Process.put(:conc_prints, Enum.reject(prints, fn {_, t} -> t == "" end))
  end

  defp others(ref, mode, outs, running, winner) do
    done = for {i, {st, text}} <- outs, i != winner, do: {i, st, text}

    cut =
      for {pid, [i | _]} <- running do
        {st, text} = final(ref, mode, pid)
        {i, st, text}
      end

    for {i, st, text} <- Enum.sort(done ++ cut), text != "" do
      label =
        case st do
          :ok -> "fertig"
          :fail -> "gescheitert"
          :error -> "Ausnahme"
          :killed -> "abgebrochen"
        end

      nl = if String.ends_with?(text, "\n"), do: "", else: "\n"
      {:err, "% Ziel #{i + 1}: #{label}\n" <> text <> nl}
    end
  end

  # ein noch nicht abgeholtes Kind: fertig (Nachricht wartet schon), sonst
  # was es bisher geschrieben hat (aus seinem Prozess-Wörterbuch, vor dem
  # Beenden)
  defp final(ref, mode, pid) do
    receive do
      {:conc, ^ref, ^pid, _i, res, text} -> {status(outcome(res, mode)), text}
    after
      0 ->
        case partial(pid) do
          nil ->
            # eben beendet: seine Nachricht ist vor dem Ende geschickt
            receive do
              {:conc, ^ref, ^pid, _i, res, text} -> {status(outcome(res, mode)), text}
            after
              0 -> {:killed, ""}
            end

          text ->
            {:killed, text}
        end
    end
  end

  defp partial(pid) do
    with {:dictionary, d} <- Process.info(pid, :dictionary),
         {:conc_out, id} <- List.keyfind(d, :conc_out, 0),
         {_, %{buf: buf}} <- List.keyfind(d, {:prolog_ex_streams, id}, 0) do
      IO.iodata_to_binary(buf)
    else
      nil -> nil
      _ -> ""
    end
  end

  defp kill_all(ref) do
    for pid <- Process.get({:conc_pids, ref}, []) do
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end

    for {_pid, mon} <- Process.get({:conc_mon, ref}, %{}), do: Process.demonitor(mon, [:flush])
    Process.delete({:conc_pids, ref})
    Process.delete({:conc_mon, ref})
    Process.delete({:conc_outs, ref})
    flush(ref)
  end

  defp flush(ref) do
    receive do
      {:conc, ^ref, _, _, _, _} -> flush(ref)
    after
      0 -> :ok
    end
  end

  # --- Kind ---------------------------------------------------------------------

  # der Zustand des Interpreters (Datenbank, Flags, Streams, ...) für die
  # Kinder; ohne Timer und Speichergrenzen dieses Prozesses (die Kinder
  # bekommen eigene)
  defp child_state do
    PrologEx.Toplevel.state_snapshot()
    |> Enum.reject(fn {k, _} -> k == :prolog_ex_timers end)
  end

  # ein Arbeiter: holt sich den Zustand (ohne Kopie) und bearbeitet Pakete
  # von Elementen nacheinander, jedes auf einem frischen Zustand – für das
  # Programm sieht es aus wie ein eigenes Kind je Element
  defp spawn_worker(ref, mode, limits, state) do
    parent = self()
    base = Process.get(:conc_seed)
    total = Process.get(:conc_total)
    outer = Process.get(:conc_path, [])
    # Tiefengrenzen des Aufrufers (von '$conc_limits' gesetzt)
    depth = Process.get(:conc_depth)

    pid =
      spawn_link(fn ->
        Process.put(:conc_depth, depth)
        st = :persistent_term.get(state)
        worker(parent, ref, st, base, total, outer, mode, limits)
      end)

    mon = Process.monitor(pid)
    Process.put({:conc_pids, ref}, [pid | Process.get({:conc_pids, ref}, [])])
    Process.put({:conc_mon, ref}, Map.put(Process.get({:conc_mon, ref}, %{}), pid, mon))
    pid
  end

  defp worker(parent, ref, st, base, total, outer, mode, limits) do
    receive do
      {:jobs, ^ref, jobs} ->
        for {i, t, g} <- jobs do
          res_text = job(st, base, total, outer, i, t, g, mode, limits)
          send(parent, {:conc, ref, self(), i, elem(res_text, 0), elem(res_text, 1)})
        end

        worker(parent, ref, st, base, total, outer, mode, limits)

      {:stop, ^ref} ->
        :ok
    end
  end

  # ein Element: Zustand zurücksetzen (was das vorige angelegt hat, weg;
  # die geteilten Werte wieder ein – Verweise, keine Kopien), dann wie bisher
  defp job(st, base, total, outer, i, t, g, mode, limits) do
    for {k, _} <- PrologEx.Toplevel.state_snapshot(),
        k != :prolog_ex_timers,
        do: Process.delete(k)

    Enum.each(st, fn {k, v} -> Process.put(k, v) end)
    # eigener Generator; Zufall ist im Kind erlaubt (PrologEx.Effects)
    PrologEx.Builtins.Random.seed_child(base, i)
    PrologEx.Effects.mark_child!()
    # wer bin ich: Position (1-basiert) und Anzahl (concurrent_child/1); die
    # Kette der Aufrufe, innerster zuerst
    Process.put(:conc_child, {i + 1, total})
    Process.put(:conc_path, [{i + 1, total} | outer])
    # Ausgabe in einen eigenen Puffer (gehört dem Bereich des Kinds)
    out = PrologEx.Stream.open_memory_out(1)
    PrologEx.Stream.set_output(out)
    Process.put(:conc_out, out)
    res = child(t, g, mode, limits)
    {res, PrologEx.Stream.memory_text(out)}
  end

  # findall(T, '$nse_call'(G'), L) mit den Grenzen; G' = once(G) außer bei
  # findall; Ausnahmen als error(E)
  defp child(t, g, mode, {deadline, budget, mem}) do
    us = if deadline, do: max(deadline - now_us(), 1), else: a("none")
    m = if mode == :findall, do: a("findall"), else: a("once")
    out = {:var, {"$conc", PrologEx.Vars.next()}}

    body =
      PrologEx.conj([
        # Tiefengrenzen des Aufrufers: die Ebene zählt vom Aufrufpunkt weiter
        mk("$conc_depth_enter", [[]]),
        mk(":", [
          a("concurrent"),
          mk("$conc_job", [t, g, m, us, budget || a("none"), mem || a("none"), out])
        ])
      ])

    try do
      case PrologEx.current_db() |> PrologEx.query(body) |> Enum.take(1) do
        [ans] ->
          res = Map.fetch!(ans, "$conc")

          if attvars?(res),
            do: mk("error", [attv_error()]),
            else: res

        [] ->
          mk("ok", [[]])
      end
    rescue
      e in PrologEx.Error -> mk("error", [e.term])
    end
  end

  # call_with_inference_limit/3 meldet inference_limit_exceeded als
  # Ergebnis: dann als Ausnahme weiter (die Grenze des Elternprozesses
  # fängt sie)
  defp now_us, do: System.monotonic_time(:microsecond)

  # --- attributierte Variablen ------------------------------------------------

  defp attv_error do
    mk("error", [mk("representation_error", [a("concurrent_attributed_variable")]), fresh_var()])
  end

  defp no_attvars!(t), do: if(attvars?(t), do: Error.throw!(attv_error()), else: :ok)

  defp attvars?({:var, {:attv, _}}), do: true
  defp attvars?({:struct, _, args}), do: Enum.any?(args, &attvars?/1)
  defp attvars?([h | t]), do: attvars?(h) or attvars?(t)
  defp attvars?(_), do: false
end
