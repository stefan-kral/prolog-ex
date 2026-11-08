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

  defbuiltin "$conc_run", [jobs, mode, max, deadline, budget, mem, r] do
    s = subst()
    jobs = for j <- PrologEx.Builtins.Lists.items(jobs, s), do: PrologEx.resolve(j, s)
    Enum.each(jobs, &no_attvars!/1)
    mode = mode!(PrologEx.resolve(mode, s))

    max =
      case PrologEx.Store.walk(max, s) do
        n when is_integer(n) and n >= 1 -> n
        _ -> System.schedulers_online()
      end

    limits = {opt(deadline, s), opt(budget, s), opt(mem, s)}

    {:unify, [{r, run(jobs, mode, max, limits)}]}
  end

  defp opt(t, s) do
    case PrologEx.Store.walk(t, s) do
      n when is_integer(n) -> n
      _ -> nil
    end
  end

  defp mode!({:atom, "once"}), do: :once
  defp mode!({:atom, "findall"}), do: :findall
  defp mode!({:struct, "first", [{:atom, on_fail}]}), do: {:first, on_fail}

  # --- Elternprozess ----------------------------------------------------------

  defp run([], {:first, _}, _max, _limits), do: a("fail")
  defp run([], _mode, _max, _limits), do: mk("ok", [[]])

  defp run(jobs, mode, max, {deadline, _, _} = limits) do
    ref = make_ref()
    state = child_state()
    indexed = Enum.with_index(jobs)
    {start, waiting} = Enum.split(indexed, max)

    running =
      Map.new(start, fn {job, i} -> {spawn_child(ref, i, job, mode, limits, state), i} end)

    try do
      loop(ref, running, waiting, mode, limits, state, deadline, %{})
    after
      # alle noch laufenden beenden (auch bei Ausnahmen hier)
      kill_all(ref)
    end
  end

  # results: Index -> Ergebnis
  defp loop(ref, running, waiting, mode, limits, state, deadline, results) do
    if map_size(running) == 0 do
      finish(mode, results)
    else
      timeout = if deadline, do: max(div(deadline - now_us(), 1000), 0), else: :infinity

      receive do
        {:conc, ^ref, pid, i, res} ->
          {mon, mons} = Map.pop(Process.get({:conc_mon, ref}, %{}), pid)
          if mon, do: Process.demonitor(mon, [:flush])
          Process.put({:conc_mon, ref}, mons)
          running = Map.delete(running, pid)

          case {outcome(res, mode), mode} do
            {{:error, ball}, _} ->
              Error.throw!(ball)

            {:fail, :once} ->
              a("fail")

            {:fail, {:first, "stop"}} ->
              a("fail")

            {:fail, _} ->
              next(ref, running, waiting, mode, limits, state, deadline, results)

            {{:ok, t}, {:first, _}} ->
              mk("ok", [[t]])

            {{:ok, t}, _} ->
              results = Map.put(results, i, t)
              next(ref, running, waiting, mode, limits, state, deadline, results)
          end

        {:DOWN, _mon, :process, pid, reason} when is_map_key(running, pid) ->
          # (ein Kind, das normal endet, hat seine Nachricht vorher geschickt;
          # hier also ein Absturz)
          Error.throw!(
            mk("error", [
              mk("system_error", [mk("concurrent_child", [a(inspect(reason, limit: 5))])]),
              fresh_var()
            ])
          )
      after
        timeout ->
          Error.throw!(a("time_limit_exceeded"))
      end
    end
  end

  defp next(ref, running, waiting, mode, limits, state, deadline, results) do
    {running, waiting} =
      case waiting do
        [{job, j} | more] ->
          {Map.put(running, spawn_child(ref, j, job, mode, limits, state), j), more}

        [] ->
          {running, waiting}
      end

    loop(ref, running, waiting, mode, limits, state, deadline, results)
  end

  defp finish({:first, _}, _results), do: a("fail")

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

  defp kill_all(ref) do
    for pid <- Process.get({:conc_pids, ref}, []) do
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end

    for {_pid, mon} <- Process.get({:conc_mon, ref}, %{}), do: Process.demonitor(mon, [:flush])
    Process.delete({:conc_pids, ref})
    Process.delete({:conc_mon, ref})
    flush(ref)
  end

  defp flush(ref) do
    receive do
      {:conc, ^ref, _, _, _} -> flush(ref)
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

  defp spawn_child(ref, i, {:struct, "-", [t, g]}, mode, limits, state) do
    parent = self()

    pid =
      spawn_link(fn ->
        Enum.each(state, fn {k, v} -> Process.put(k, v) end)
        res = child(t, g, mode, limits)
        send(parent, {:conc, ref, self(), i, res})
      end)

    mon = Process.monitor(pid)
    Process.put({:conc_pids, ref}, [pid | Process.get({:conc_pids, ref}, [])])
    Process.put({:conc_mon, ref}, Map.put(Process.get({:conc_mon, ref}, %{}), pid, mon))
    pid
  end

  # findall(T, '$nse_call'(G'), L) mit den Grenzen; G' = once(G) außer bei
  # findall; Ausnahmen als error(E)
  defp child(t, g, mode, {deadline, budget, mem}) do
    g = if mode == :findall, do: g, else: mk("once", [g])
    g = mk("$nse_call", [g])
    # Bedingungen auf dem Ergebnis gingen beim Kopieren verloren: Fehler
    vs = fresh_var()

    g =
      PrologEx.conj([
        g,
        mk(":", [a("swi"), mk("term_attvars", [t, vs])]),
        mk(";", [
          mk("->", [mk("==", [vs, []]), a("true")]),
          mk("throw", [attv_error()])
        ])
      ])

    l = fresh_var()
    goal = mk("findall", [t, g, l])

    goal =
      if mem,
        do: mk(":", [a("iso_ext"), mk("call_with_memory_limit", [goal, mem])]),
        else: goal

    {goal, lr} =
      if budget do
        lr = fresh_var()
        {mk("call_with_inference_limit", [goal, budget, lr]), lr}
      else
        {goal, nil}
      end

    goal =
      if deadline do
        us = max(deadline - now_us(), 1)
        mk("$call_with_timeout", [goal, us, a("cumulative"), a("throw")])
      else
        goal
      end

    e = fresh_var()
    out = {:var, {"$conc", PrologEx.Vars.next()}}

    # catch((G -> R = ok(L) ; R = ok([])), E, R = error(E))
    body =
      mk("catch", [
        mk(";", [
          mk("->", [goal, limit_check(lr, acyclic_check(l, mk("=", [out, mk("ok", [l])])))]),
          mk("=", [out, mk("ok", [[]])])
        ]),
        e,
        mk("=", [out, mk("error", [e])])
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
  defp limit_check(nil, then), do: then

  defp limit_check(lr, then) do
    mk(";", [
      mk("->", [
        mk("==", [lr, a("inference_limit_exceeded")]),
        mk("throw", [a("inference_limit_exceeded")])
      ]),
      then
    ])
  end

  # Ergebnisse reisen als aufgelöste Terme: ein Zyklus ginge verloren
  defp acyclic_check(l, then) do
    cyc =
      mk("error", [mk("representation_error", [a("cyclic_term")]), fresh_var()])

    mk(";", [mk("->", [mk("acyclic_term", [l]), then]), mk("throw", [cyc])])
  end

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
