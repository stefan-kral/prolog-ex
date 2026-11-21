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
    * Mode `split` (für `library(clpz_concurrent)`): Jobs = `[T-C]`, die
      Kinder teilen die Suche untereinander auf (Work Stealing); R =
      `ok([T])` mit der ersten Lösung in der Reihenfolge der Suche oder
      `fail` (siehe run_split/3).

  Eine Ausnahme in einem Kind (auch der Seiteneffekt-Fehler) beendet alle
  anderen sofort und wird hier geworfen – welche, wenn mehrere werfen,
  entscheidet der Scheduler. Ebenso beim Scheitern (once) und beim ersten
  Erfolg (first): die übrigen Kinder werden beendet. Weil die Kinder keine
  Wirkung haben können, ist das gefahrlos.

  Grenzen der aufrufenden Maschine gelten weiter: die Deadline (für die
  Kinder und das Warten hier), das restliche Inferenzbudget (für alle
  zusammen: die Kinder erben den Inferenzzähler – ein `:atomics`, das die
  Prozesse teilen – und zählen dort mit; jedes Kind rechnet beim Start aus,
  was von der Grenze noch übrig ist), die engste Speichergrenze je Kind.

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
      {:bytes, _} -> true
      _ -> if PrologEx.term_attvars(t, s) == [], do: true, else: Error.throw!(attv_error())
    end
  end

  # --- im Kind beim Teilen (Mode split, siehe run_split/3) ---------------------
  #
  # Ein erlaubter Kanal zum Elternprozess (kein Seiteneffekt für das
  # Programm). '$conc_steal_node'(T, Req) je Knoten der Suche: T die Zeit in
  # µs; Req yes, wenn der Elternprozess um einen Teil bittet, stop, wenn
  # alles ab hier vergeblich ist (rechts einer bekannten Lösung), sonst no
  # (außerhalb eines solchen Kinds T = 0, Req = no – billig). Die Antwort
  # auf eine Bitte: '$conc_steal_give'(D, Ds) (der rechte Zweig des Knotens
  # der Tiefe D) oder '$conc_steal_offer'(none). Die Suche überspringt einen
  # abgegebenen Zweig später ('$conc_steal_taken'/2).
  #
  # Marken: Tiefe -> {G, Schnitt?}, G die Nummer des abgegebenen Teils in
  # diesem Kind. Hat der Teil G (oder einer darin) eine Lösung, meldet der
  # Elternprozess {:conc_steal_cut, ref, i, G}: wer G überspringt, kann
  # aufhören – alles danach liegt rechts der Lösung.
  defbuiltin "$conc_steal_node", [t, req] do
    case Process.get(:conc_steal) do
      nil ->
        {:unify, [{t, 0}, {req, a("no")}]}

      {_parent, ref, i} ->
        r = steal_msgs(ref, i, "no")
        r = if Process.get(:conc_steal_stop), do: "stop", else: r

        {:unify, [{t, System.monotonic_time(:microsecond)}, {req, a(r)}]}
    end
  end

  defbuiltin "$conc_steal_offer", [ds] do
    case Process.get(:conc_steal) do
      nil ->
        true

      {parent, ref, i} ->
        send(parent, {:conc_offer, ref, i, PrologEx.resolve(ds, subst()), 0, 0})
        true
    end
  end

  # '$conc_steal_give'(D, Ds): den rechten Zweig des Knotens der Tiefe D
  # als Teil Ds abgeben. Seine Stelle unter den Teilen, die dieser Teil
  # abgegeben hat (links zuerst): erst die schon übersprungenen, dann die
  # noch offenen von tief nach flach – also Rang = übersprungene + offene
  # tiefer als D
  defbuiltin "$conc_steal_give", [d, ds] do
    d = PrologEx.Store.walk(d, subst())
    marks = Process.get(:conc_steal_marks, %{})
    rank = Process.get(:conc_steal_skipped, 0) + Enum.count(marks, fn {k, _} -> k > d end)
    g = Process.get(:conc_steal_given, 0) + 1
    Process.put(:conc_steal_given, g)
    Process.put(:conc_steal_marks, Map.put(marks, d, {g, false}))

    case Process.get(:conc_steal) do
      nil ->
        true

      {parent, ref, i} ->
        send(parent, {:conc_offer, ref, i, PrologEx.resolve(ds, subst()), rank, g})
    end

    true
  end

  # --- im Kind: ein Arbeiter, viele Teile (part_loop/3, clpz_concurrent) ----
  #
  # Ein Arbeiter beim Teilen läuft als eine Anfrage: das Modell einmal
  # aufbauen, dann Teil für Teil. '$conc_next_part'(Id, Ds) wartet auf den
  # nächsten Teil ({:conc_part, ref, id, ds}) und stellt den Kanal für ihn
  # ein (Id = stop: Ende); '$conc_part_done'(Id, R) meldet sein Ergebnis,
  # R = ok(T) | fail | error(E).
  defbuiltin "$conc_next_part", [id, ds] do
    case Process.get(:conc_loop) do
      nil ->
        {:unify, [{id, a("stop")}]}

      {parent, ref} ->
        receive do
          {:conc_part, ^ref, i, d} ->
            Process.put(:conc_steal, {parent, ref, i})
            Process.put(:conc_steal_marks, %{})
            Process.put(:conc_steal_skipped, 0)
            Process.put(:conc_steal_given, 0)
            Process.put(:conc_steal_passed, MapSet.new())
            Process.delete(:conc_steal_stop)
            {:unify, [{id, i}, {ds, d}]}

          {:stop, ^ref} ->
            Process.put(:conc_loop_stopped, true)
            {:unify, [{id, a("stop")}]}
        end
    end
  end

  defbuiltin "$conc_part_done", [id, r] do
    case Process.get(:conc_loop) do
      nil ->
        true

      {parent, ref} ->
        s = subst()
        i = PrologEx.Store.walk(id, s)

        oc =
          case PrologEx.resolve(r, s) do
            {:struct, "ok", [t]} -> if attvars?(t), do: {:error, attv_error()}, else: {:ok, t}
            {:struct, "error", [e]} -> {:error, e}
            _ -> :fail
          end

        send(parent, {:conc_split, ref, self(), i, oc, Process.get(:conc_steal_skipped, 0)})
        true
    end
  end

  # '$conc_steal_skipped'(K): so viele abgegebene Zweige hat die Suche
  # dieses Teils bisher übersprungen (eine Lösung jetzt liegt in SK, siehe
  # run_split/4)
  defbuiltin "$conc_steal_skipped", [k] do
    {:unify, [{k, Process.get(:conc_steal_skipped, 0)}]}
  end

  # --- Branch and Bound im Kind (split_best, part_steal_best/8) ----------------
  #
  # :conc_best = %{dir, strict, glob, own, sol, k}: strict die Schranke vor
  # der Phase (echt), glob die beste anderer Teile (einschließlich: bei
  # gleichem Wert entscheidet die Reihenfolge), own der beste eigene Wert
  # (echt), sol die Lösung dazu, k: so viele abgegebene Teile lagen davor

  defbuiltin "$conc_best_init", [dir, b0] do
    s = subst()
    {:atom, d} = PrologEx.Store.walk(dir, s)

    strict =
      case PrologEx.Store.walk(b0, s) do
        n when is_integer(n) -> n
        _ -> nil
      end

    Process.put(:conc_best, %{dir: d, strict: strict, glob: nil, own: nil, sol: nil, k: 0})
    true
  end

  # '$conc_best_limit'(L): die engste Schranke, einschließlich (min: E =< L,
  # max: E >= L), oder none
  defbuiltin "$conc_best_limit", [l] do
    b = Process.get(:conc_best)

    lim =
      case b.dir do
        "min" -> [b.strict && b.strict - 1, b.glob, b.own && b.own - 1]
        "max" -> [b.strict && b.strict + 1, b.glob, b.own && b.own + 1]
      end
      |> Enum.reject(&is_nil/1)

    v =
      cond do
        lim == [] -> a("none")
        b.dir == "min" -> Enum.min(lim)
        true -> Enum.max(lim)
      end

    {:unify, [{l, v}]}
  end

  # '$conc_best_put'(V, Sol): eine bessere eigene Lösung; dem Elternprozess
  # melden (er gibt den Wert an die anderen weiter)
  defbuiltin "$conc_best_put", [v, sol] do
    s = subst()
    v = PrologEx.Store.walk(v, s)
    b = Process.get(:conc_best)
    k = Process.get(:conc_steal_skipped, 0)
    Process.put(:conc_best, %{b | own: v, sol: PrologEx.resolve(sol, s), k: k})

    case Process.get(:conc_steal) do
      {parent, ref, i} -> send(parent, {:conc_improve, ref, i, v})
      nil -> :ok
    end

    true
  end

  defbuiltin "$conc_best_result", [r] do
    b = Process.get(:conc_best)
    res = if b.own == nil, do: a("none"), else: mk("best", [b.own, b.sol, b.k])
    {:unify, [{r, res}]}
  end

  defp best_glob(v) do
    case Process.get(:conc_best) do
      %{glob: g, dir: d} = b ->
        if g == nil or (d == "min" and v < g) or (d == "max" and v > g),
          do: Process.put(:conc_best, %{b | glob: v})

      _ ->
        :ok
    end
  end

  defbuiltin "$conc_steal_marked", [d] do
    is_map_key(Process.get(:conc_steal_marks, %{}), PrologEx.Store.walk(d, subst())) || :fail
  end

  # '$conc_kept'(D): der rechte Zweig des Knotens der Tiefe D ist nicht
  # abgegeben (gelingt). Ist er abgegeben: Marke weg, einer mehr
  # übersprungen, scheitern – oder, hat er (oder einer darin) eine Lösung,
  # aufhören: alles danach liegt rechts davon ('$conc_steal_stop', fängt
  # part_steal/5)
  defbuiltin "$conc_kept", [d] do
    case Process.get(:conc_steal_marks) do
      marks when is_map(marks) and map_size(marks) > 0 ->
        d = PrologEx.Store.walk(d, subst())

        case marks do
          %{^d => {g, cut}} ->
            Process.put(:conc_steal_marks, Map.delete(marks, d))
            Process.put(:conc_steal_skipped, Process.get(:conc_steal_skipped, 0) + 1)
            passed = MapSet.put(Process.get(:conc_steal_passed, MapSet.new()), g)
            Process.put(:conc_steal_passed, passed)
            if cut, do: Error.throw!(a("$conc_steal_stop")), else: :fail

          _ ->
            true
        end

      _ ->
        true
    end
  end

  # '$conc_node'(+Vs, +X, -I, -T, -Req) je Knoten: I die Stelle von X in Vs
  # (wie '$conc_var_index'/3), T und Req wie '$conc_steal_node'/2 – in
  # einem Aufruf (jeder Aufruf je Knoten kostet)
  defbuiltin "$conc_node", [vs, x, i, t, req] do
    case node_info(vs, x, subst()) do
      {:ok, n, tt, r} -> {:unify, [{i, n}, {t, tt}, {req, a(r)}]}
      :error -> :fail
    end
  end

  @doc false
  # für '$conc_node'/5 und '$clpz_conc_step'/5 (ClpzPrims): {:ok, Stelle von X
  # in Vs, Zeit in µs (0 außerhalb eines teilenden Kinds), "no" | "yes" |
  # "stop"} oder :error
  def node_info(vs, x, s) do
    with {:var, _} = xv <- PrologEx.Store.walk(x, s),
         n when is_integer(n) <- vindex(vs, xv, 1, s) do
      case Process.get(:conc_steal) do
        nil ->
          {:ok, n, 0, "no"}

        {_parent, ref, j} ->
          r = steal_msgs(ref, j, "no")
          r = if Process.get(:conc_steal_stop), do: "stop", else: r
          {:ok, n, System.monotonic_time(:microsecond), r}
      end
    else
      _ -> :error
    end
  end

  # '$conc_var_index'(+Vs, +X, -I): I ist die Stelle (1-basiert) der
  # Variablen X in Vs (==); scheitert, wenn X keine Variable ist oder fehlt
  defbuiltin "$conc_var_index", [vs, x, i] do
    s = subst()

    with {:var, _} = xv <- PrologEx.Store.walk(x, s),
         n when is_integer(n) <- vindex(vs, xv, 1, s) do
      {:unify, [{i, n}]}
    else
      _ -> :fail
    end
  end

  defp vindex(l, xv, n, s) do
    case PrologEx.Store.walk(l, s) do
      [h | t] -> if PrologEx.Store.walk(h, s) == xv, do: n, else: vindex(t, xv, n + 1, s)
      _ -> nil
    end
  end

  # Nachrichten für diesen Teil: Bitten (r = "yes") und Schnitte (die
  # Marke des Teils G bekommt den Schnitt; schon übersprungen: alles ab
  # hier vergeblich, :conc_steal_stop). Ältere, für frühere Teile desselben
  # Arbeiters: weg
  defp steal_msgs(ref, i, r) do
    receive do
      {:conc_steal_req, ^ref, ^i} ->
        steal_msgs(ref, i, "yes")

      {:conc_steal_cut, ^ref, ^i, g} ->
        steal_cut(g)
        steal_msgs(ref, i, r)

      {:conc_steal_req, ^ref, _} ->
        steal_msgs(ref, i, r)

      {:conc_steal_cut, ^ref, _, _} ->
        steal_msgs(ref, i, r)

      {:conc_bound, ^ref, v} ->
        best_glob(v)
        steal_msgs(ref, i, r)
    after
      0 -> r
    end
  end

  defp steal_cut(g) do
    if MapSet.member?(Process.get(:conc_steal_passed, MapSet.new()), g) do
      Process.put(:conc_steal_stop, true)
    else
      marks = Process.get(:conc_steal_marks, %{})

      marks =
        Map.new(marks, fn
          {d, {^g, _}} -> {d, {g, true}}
          kv -> kv
        end)

      Process.put(:conc_steal_marks, marks)
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
  defp mode!({:atom, "split"}), do: :split
  defp mode!({:atom, "split_all"}), do: :split_all

  defp mode!({:struct, "split_best", [{:atom, dir}]}) when dir in ["min", "max"],
    do: {:split_best, dir}

  defp mode!({:struct, "first", [{:atom, on_fail}, {:atom, output}, {:atom, on_error}]}),
    do: {:first, on_fail, output, on_error}

  # --- Elternprozess ----------------------------------------------------------

  defp run([], {:first, _, _, _}, _max, _limits), do: a("fail")
  defp run([], _mode, _max, _limits), do: mk("ok", [[]])

  defp run(jobs, :split, {max, _chunk}, limits), do: run_split(jobs, max, limits, :first)
  defp run(jobs, :split_all, {max, _chunk}, limits), do: run_split(jobs, max, limits, :all)

  defp run(jobs, {:split_best, dir}, {max, _chunk}, limits),
    do: run_split(jobs, max, limits, {:best, dir})

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

  # --- Teilen: die erste Lösung in der Reihenfolge der Suche -------------------
  #
  # Mode split, Jobs = [_-C]: jeder Arbeiter führt C einmal aus (part_loop/3
  # in clpz_concurrent: das Modell aufbauen, dann Teil für Teil); ein Teil
  # ist eine Liste von Entscheidungen Ds ({:conc_part, ref, id, Ds}, siehe
  # '$conc_next_part'/2), der erste Ds = []; sein Ergebnis ok(T), fail oder
  # error(E) ('$conc_part_done'/2). Freie Arbeiter
  # bekommen den linkesten wartenden Teil; wartet keiner, bittet der
  # Elternprozess laufende Teile (von links) um Arbeit, und das Kind gibt
  # einen Teil ab (oder none: frühestens nach @split_retry ms wieder).
  #
  # Reihenfolge: die Teile bilden einen Baum. Ein Teil P mit den
  # abgegebenen Teilen G1, ..., Gm (links zuerst) liegt in der Suche als
  # S0 G1 S1 ... Gm Sm, die Si die eigene Arbeit von P. Das Kind meldet zu
  # jedem abgegebenen Teil dessen Rang unter G1.., zu seiner Lösung, wie
  # viele Gi es schon übersprungen hatte (die Lösung liegt in Sk). Ist ein
  # Teil fertig (Lösung oder Ausnahme), fällt alles rechts davon weg; das
  # Ergebnis steht fest, sobald links davon alles gescheitert ist: dieselbe
  # Lösung wie nacheinander (die erste in der Reihenfolge der Suche),
  # dieselbe Ausnahme, oder fail. Ausgaben der Kinder werden verworfen.
  #
  # Mode split_all (alle Lösungen): Jobs = [T-C, Ds1, ..., Dsn], die Dsi
  # feste Teile in der Reihenfolge der Suche (ohne: ein Teil []); das
  # Ergebnis eines Teils ist ok(L), L die Liste seiner Lösungen als K-Lösung (K wie
  # oben: sie liegt in SK). Die festen Teile hängen an einer Wurzel ohne
  # eigene Lösungen. Erst wenn keiner mehr wartet, bitten freie Arbeiter
  # laufende um Arbeit. Nichts fällt weg; sind alle Teile fertig, ist das
  # Ergebnis ok(Lösungen) in der Reihenfolge der Suche: S0, dann G1
  # (rekursiv), S1, ... Eine Ausnahme in einem Teil beendet alles und kommt
  # hier an.
  #
  # Mode split_best(min | max) (Branch and Bound): Jobs = [_-C], das Ergebnis
  # eines Teils ok(Res), Res none oder best(Wert, Lösung, K). Meldet ein Kind
  # einen besseren Wert ({:conc_improve, ...}), geht er als gemeinsame
  # Schranke an alle laufenden Kinder (und an jedes neue). Sind alle Teile
  # fertig: ok([Wert-Lösung]) mit dem besten Wert, bei gleichem der erste
  # in der Reihenfolge der Suche, sonst fail.
  @split_retry 2

  defp run_split([{:struct, "-", [t, c]} | fixed], w, {deadline, _, _} = limits, mode) do
    ref = make_ref()
    state = {:prolog_ex_conc_state, ref}
    :persistent_term.put(state, child_state())

    try do
      sp = %{
        mode: mode,
        ref: ref,
        t: t,
        c: c,
        limits: limits,
        state: state,
        deadline: deadline,
        # Id -> %{st: :pending | :running | :failed | :pruned | {:ok, T, K}
        # | {:error, E, K}, ds: Ds, givens: [Id], up: Id | nil, cut: Id | nil}
        # (cut: rechts von diesem abgegebenen Teil ist alles weggefallen)
        parts: split_roots(fixed),
        next: length(fixed) + 1,
        idle: [],
        # Id -> Arbeiter
        run: %{},
        # Id, um Arbeit gebeten (Antwort offen)
        asked: %{},
        # Id -> Zeit (ms) seines letzten none
        none: %{}
      }

      idle = for _ <- 1..w, do: split_spawn(sp)
      split_loop(%{sp | idle: idle})
    after
      kill_all(ref)
      :persistent_term.erase(state)
    end
  end

  # ein Arbeiter: eine Anfrage C (part_loop/3), die Teil für Teil abarbeitet
  defp split_spawn(sp) do
    pid = spawn_worker(sp.ref, :split, sp.limits, sp.state)
    send(pid, {:jobs, sp.ref, [{0, a("true"), sp.c}]})
    pid
  end

  # ohne feste Teile: einer mit Ds = []; sonst eine fertige Wurzel (keine
  # eigenen Lösungen) mit ihnen als abgegebenen Teilen 1..n
  defp split_roots([]), do: %{0 => %{st: :pending, ds: [], givens: [], up: nil, cut: nil, g: 0}}

  defp split_roots(fixed) do
    ids = Enum.to_list(1..length(fixed))

    fixed
    |> Enum.zip(ids)
    |> Map.new(fn {ds, id} ->
      {id, %{st: :pending, ds: ds, givens: [], up: 0, cut: nil, g: id}}
    end)
    |> Map.put(0, %{st: {:all, []}, ds: [], givens: ids, up: nil, cut: nil, g: 0})
  end

  defp split_loop(sp) do
    decided =
      case sp.mode do
        :all -> sall(sp.parts)
        {:best, dir} -> sbest(sp.parts, dir)
        :first -> sdecide(sp.parts, 0)
      end

    case decided do
      :empty ->
        a("fail")

      {:found, {:ok, t}} ->
        mk("ok", [[t]])

      {:found, {:all, sols}} ->
        mk("ok", [sols])

      {:found, {:best, v, sol}} ->
        mk("ok", [[mk("-", [v, sol])]])

      {:found, {:error, ball}} ->
        Error.throw!(ball)

      :undecided ->
        {sp, wait} = split_dispatch(sp)
        ref = sp.ref
        dl = if sp.deadline, do: max(div(sp.deadline - now_us(), 1000), 0), else: :infinity
        timeout = if wait == :infinity, do: dl, else: min(wait, dl)
        mons = Process.get({:conc_mon, ref}, %{})

        receive do
          {:conc_split, ^ref, pid, i, oc, k} ->
            sp |> split_result(pid, i, oc, k) |> split_loop()

          # ein Arbeiter ist unerwartet fertig (seine Anfrage endet sonst nie)
          {:conc_loop_end, ^ref, _pid, res} ->
            case res do
              {:struct, "error", [e]} ->
                Error.throw!(e)

              _ ->
                Error.throw!(
                  mk("error", [
                    mk("system_error", [mk("concurrent_child", [a("split_worker_ended")])]),
                    fresh_var()
                  ])
                )
            end

          {:conc_offer, ^ref, i, ds, rank, g} ->
            sp |> split_offer(i, ds, rank, g) |> split_loop()

          {:conc_improve, ^ref, _i, v} ->
            sp |> split_improve(v) |> split_loop()

          {:DOWN, _mon, :process, pid, reason} when is_map_key(mons, pid) ->
            Error.throw!(
              mk("error", [
                mk("system_error", [mk("concurrent_child", [a(inspect(reason, limit: 5))])]),
                fresh_var()
              ])
            )
        after
          timeout ->
            if sp.deadline && now_us() >= sp.deadline,
              do: Error.throw!(a("time_limit_exceeded")),
              else: split_loop(sp)
        end
    end
  end

  # das Ergebnis ab Teil id (ihn und seine abgegebenen Teile in der
  # Reihenfolge der Suche): :empty (keine Lösung), :undecided oder
  # {:found, {:ok, T} | {:error, E}}
  defp sdecide(parts, id) do
    p = parts[id]

    case p.st do
      :failed -> sdecide_list(parts, p.givens)
      :pruned -> :empty
      {:ok, t, k} -> sdecide_found(parts, Enum.take(p.givens, k), {:ok, t})
      {:error, e, k} -> sdecide_found(parts, Enum.take(p.givens, k), {:error, e})
      _ -> :undecided
    end
  end

  defp sdecide_found(parts, before, res) do
    case sdecide_list(parts, before) do
      :empty -> {:found, res}
      r -> r
    end
  end

  defp sdecide_list(_parts, []), do: :empty

  defp sdecide_list(parts, [g | gs]) do
    case sdecide(parts, g) do
      :empty -> sdecide_list(parts, gs)
      r -> r
    end
  end

  # alle Lösungen: :undecided, solange ein Teil wartet oder läuft; eine
  # Ausnahme gleich (die erste in der Reihenfolge der Suche)
  defp sall(parts) do
    order = sorder(parts, 0)

    cond do
      e = Enum.find_value(order, fn {_, st} -> match?({:error, _, _}, st) && elem(st, 1) end) ->
        {:found, {:error, e}}

      Enum.any?(order, fn {_, st} -> st in [:pending, :running] end) ->
        :undecided

      true ->
        {:found, {:all, sassemble(parts, 0)}}
    end
  end

  # Branch and Bound: wie sall/1, dann der beste Wert, bei gleichem der
  # erste in der Reihenfolge der Suche; :empty ohne Lösung
  defp sbest(parts, dir) do
    order = sorder(parts, 0)

    cond do
      e = Enum.find_value(order, fn {_, st} -> match?({:error, _, _}, st) && elem(st, 1) end) ->
        {:found, {:error, e}}

      Enum.any?(order, fn {_, st} -> st in [:pending, :running] end) ->
        :undecided

      true ->
        case sbest_list(parts, 0) do
          [] ->
            :empty

          cands ->
            vals = Enum.map(cands, &elem(&1, 0))
            best = if dir == "min", do: Enum.min(vals), else: Enum.max(vals)
            {v, sol} = Enum.find(cands, fn {v, _} -> v == best end)
            {:found, {:best, v, sol}}
        end
    end
  end

  # die Bestwerte der Teile in der Reihenfolge der Suche: der des Teils an
  # der Stelle K unter seinen abgegebenen
  defp sbest_list(parts, id) do
    %{st: {:best, res}, givens: gs} = parts[id]

    {own, k} =
      case PrologEx.unmark(res) do
        {:struct, "best", [v, sol, k]} -> {[{v, sol}], k}
        _ -> {[], 0}
      end

    {before, rest} = Enum.split(gs, k)

    Enum.flat_map(before, &sbest_list(parts, &1)) ++
      own ++ Enum.flat_map(rest, &sbest_list(parts, &1))
  end

  # ein besserer Wert: die gemeinsame Schranke, an alle laufenden Kinder
  defp split_improve(%{mode: {:best, dir}} = sp, v) do
    gb = Map.get(sp, :bound)

    if gb == nil or (dir == "min" and v < gb) or (dir == "max" and v > gb) do
      for pid <- Map.values(sp.run), do: send(pid, {:conc_bound, sp.ref, v})
      Map.put(sp, :bound, v)
    else
      sp
    end
  end

  defp split_improve(sp, _v), do: sp

  # S0, G1, S1, ..., Gm, Sm: die Lösungen des Teils nach K, dazwischen die
  # seiner abgegebenen Teile
  defp sassemble(parts, id) do
    %{st: {:all, sols}, givens: gs} = parts[id]

    by_k =
      sols
      |> PrologEx.unmark()
      |> Enum.group_by(fn {:struct, "-", [k, _]} -> k end, fn {:struct, "-", [_, v]} -> v end)

    m = length(gs)

    Enum.flat_map(0..m, fn k ->
      Map.get(by_k, k, []) ++ if(k < m, do: sassemble(parts, Enum.at(gs, k)), else: [])
    end)
  end

  # die Teile in der Reihenfolge der Suche (ein Teil vor seinen abgegebenen)
  defp sorder(parts, id) do
    p = parts[id]
    if p.st == :pruned, do: [], else: [{id, p.st} | Enum.flat_map(p.givens, &sorder(parts, &1))]
  end

  # wartende Teile an freie Arbeiter (von links); bleiben welche frei: um
  # Arbeit bitten. wait: wann wieder bitten (ms) oder :infinity
  defp split_dispatch(sp) do
    order = sorder(sp.parts, 0)

    sp =
      Enum.reduce(order, sp, fn
        {id, :pending}, %{idle: [pid | idle]} = sp ->
          send(pid, {:conc_part, sp.ref, id, sp.parts[id].ds})

          # die gemeinsame Schranke gleich mit (Branch and Bound)
          if gb = Map.get(sp, :bound), do: send(pid, {:conc_bound, sp.ref, gb})

          sp = put_in(sp.parts[id].st, :running)
          %{sp | idle: idle, run: Map.put(sp.run, id, pid)}

        _, sp ->
          sp
      end)

    free = length(sp.idle) - map_size(sp.asked)

    if free > 0 and not Enum.any?(order, &match?({_, :pending}, &1)) do
      now = System.monotonic_time(:millisecond)

      {asks, later} =
        for {id, _} <- order,
            sp.parts[id].st == :running,
            not is_map_key(sp.asked, id),
            reduce: {[], false} do
          {asks, later} ->
            case sp.none do
              %{^id => t} when now - t < @split_retry -> {asks, true}
              _ -> {[id | asks], later}
            end
        end

      asks = asks |> Enum.reverse() |> Enum.take(free)
      for id <- asks, do: send(Map.fetch!(sp.run, id), {:conc_steal_req, sp.ref, id})
      asked = Enum.reduce(asks, sp.asked, &Map.put(&2, &1, true))
      {%{sp | asked: asked}, if(later, do: @split_retry, else: :infinity)}
    else
      {sp, :infinity}
    end
  end

  # ein Teil ist fertig (Ergebnisse weggefallener Teile: übergehen); k:
  # so viele seiner abgegebenen Teile lagen vor seiner Lösung
  defp split_result(sp, pid, i, oc, k) do
    case sp.run do
      %{^i => ^pid} ->
        sp = split_free(sp, i)
        sp = %{sp | idle: [pid | sp.idle]}

        case {sp.mode, oc} do
          {{:best, _}, {:ok, t}} -> put_in(sp.parts[i].st, {:best, t})
          {{:best, _}, :fail} -> put_in(sp.parts[i].st, {:best, a("none")})
          {{:best, _}, {:error, e}} -> put_in(sp.parts[i].st, {:error, e, k})
          {:all, :fail} -> put_in(sp.parts[i].st, {:all, []})
          {:all, {:ok, t}} -> put_in(sp.parts[i].st, {:all, t})
          {:all, {:error, e}} -> put_in(sp.parts[i].st, {:error, e, k})
          {_, :fail} -> put_in(sp.parts[i].st, :failed)
          {_, {:ok, t}} -> split_settle(sp, i, {:ok, t, k}, k)
          {_, {:error, e}} -> split_settle(sp, i, {:error, e, k}, k)
        end

      _ ->
        sp
    end
  end

  defp split_free(sp, i) do
    %{
      sp
      | run: Map.delete(sp.run, i),
        asked: Map.delete(sp.asked, i),
        none: Map.delete(sp.none, i)
    }
  end

  # Teil i hat eine Lösung oder Ausnahme in seinem Abschnitt k: seine
  # abgegebenen Teile ab k und alles rechts von ihm fällt weg
  defp split_settle(sp, i, st, k) do
    sp = put_in(sp.parts[i].st, st)
    sp = Enum.reduce(Enum.drop(sp.parts[i].givens, k), sp, &split_prune(&2, &1))
    split_cut(sp, i)
  end

  # rechts von Teil i (in seinen Vorfahren) alles weg
  defp split_cut(sp, i) do
    case sp.parts[i].up do
      nil ->
        sp

      up ->
        givens = sp.parts[up].givens
        right = givens |> Enum.drop_while(&(&1 != i)) |> tl()
        sp = put_in(sp.parts[up].cut, i)

        # läuft up noch: überspringt es i, kann es aufhören
        if pid = sp.run[up], do: send(pid, {:conc_steal_cut, sp.ref, up, sp.parts[i].g})

        sp = Enum.reduce(right, sp, &split_prune(&2, &1))
        split_cut(sp, up)
    end
  end

  # Teil id und seine abgegebenen fallen weg (laufende Arbeiter: beenden,
  # ersetzen)
  defp split_prune(sp, id) do
    p = sp.parts[id]

    sp =
      case p.st do
        :running ->
          split_kill(sp.ref, Map.fetch!(sp.run, id))
          pid = split_spawn(sp)
          sp = split_free(sp, id)
          %{sp | idle: [pid | sp.idle]}

        _ ->
          sp
      end

    sp = put_in(sp.parts[id].st, :pruned)
    Enum.reduce(p.givens, sp, &split_prune(&2, &1))
  end

  defp split_kill(ref, pid) do
    Process.unlink(pid)
    mons = Process.get({:conc_mon, ref}, %{})
    if mon = mons[pid], do: Process.demonitor(mon, [:flush])
    Process.exit(pid, :kill)
    Process.put({:conc_mon, ref}, Map.delete(mons, pid))
    Process.put({:conc_pids, ref}, List.delete(Process.get({:conc_pids, ref}, []), pid))
  end

  # Antwort auf eine Bitte: ein neuer Teil an Stelle rank unter den
  # abgegebenen von i (rechts von dessen cut: gleich weggefallen), oder none
  defp split_offer(sp, i, ds, rank, g) do
    if is_map_key(sp.run, i) do
      sp = %{sp | asked: Map.delete(sp.asked, i)}

      case ds do
        {:atom, "none"} ->
          %{sp | none: Map.put(sp.none, i, System.monotonic_time(:millisecond))}

        _ ->
          p = sp.parts[i]
          id = sp.next
          givens = List.insert_at(p.givens, rank, id)

          st =
            if p.cut && rank > Enum.find_index(givens, &(&1 == p.cut)),
              do: :pruned,
              else: :pending

          parts =
            sp.parts
            |> Map.put(i, %{p | givens: givens})
            |> Map.put(id, %{st: st, ds: ds, givens: [], up: i, cut: nil, g: g})

          %{sp | parts: parts, next: id + 1, none: Map.delete(sp.none, i)}
      end
    else
      sp
    end
  end

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
      msg when is_tuple(msg) and tuple_size(msg) >= 2 and elem(msg, 1) == ref -> flush(ref)
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
          # beim Teilen: eine Anfrage für alle Teile ('$conc_next_part'/2)
          if mode == :split, do: Process.put(:conc_loop, {parent, ref})

          res_text = job(st, base, total, outer, i, t, g, mode, limits)

          if mode == :split do
            unless Process.get(:conc_loop_stopped),
              do: send(parent, {:conc_loop_end, ref, self(), elem(res_text, 0)})
          else
            send(parent, {:conc, ref, self(), i, elem(res_text, 0), elem(res_text, 1)})
          end
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
  defp child(t, g, mode, {deadline, limit, mem}) do
    us = if deadline, do: max(deadline - now_us(), 1), else: a("none")
    # die Inferenzgrenze des Aufrufers ist absolut (geteilter Zähler): was
    # davon jetzt noch übrig ist
    budget = if limit, do: max(limit - PrologEx.inferences(), 0)
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
