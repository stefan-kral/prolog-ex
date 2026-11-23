defmodule PrologEx.ConcurrentRobustTest do
  # library(concurrent) unter Störungen: ein Arbeiter stirbt (von außen
  # beendet), Grenzen und Fehler beim Aufteilen (clpz_concurrent), Teile,
  # die nach einer Lösung wegfallen. Danach muss der Aufrufer sauber sein:
  # keine Arbeiter mehr, keine Nachrichten im Postfach, trap_exit wie
  # vorher, keine :conc_*-Schlüssel im Prozess.
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}

  @prog """
  spin(_) :- between(1, inf, _), fail.
  sq(X, Y) :- Y is X * X.
  late(X) :- sleep(0.3), X = spaet.
  queens(N, Qs) :- length(Qs, N), Qs ins 1..N, safe(Qs).
  safe([]).
  safe([Q|Qs]) :- no_attack(Qs, Q, 1), safe(Qs).
  no_attack([], _, _).
  no_attack([Q1|Qs], Q, D) :- Q #\\= Q1, abs(Q - Q1) #\\= D, D1 is D + 1, no_attack(Qs, Q, D1).
  % ohne Lösung, lange Suche (Schubfach): 10 Variablen, 9 Werte
  ph(N, Vs) :- N1 is N + 1, length(Vs, N1), Vs ins 1..N, all_different(Vs).
  % links schnell eine Lösung, rechts (X = 2) eine lange Suche ohne Lösung
  lr([X|Ys]) :- X in 1..2, length(Ys, 9), Ys ins 1..9, all_different(Ys),
      no_nine(Ys, X).
  no_nine([], _).
  no_nine([Y|Ys], X) :- X #= 2 #==> Y #\\= 9, no_nine(Ys, X).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ~w(clpz clpz_concurrent concurrent between lists time swi))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @prog))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  # Anfrage in einem eigenen Prozess; liefert die Antworten und den Zustand
  # des Prozesses danach
  defp start(c, q) do
    Task.async(fn ->
      Reader.put_current(c.reader)
      Process.put(:prolog_ex_ops, c.ops)
      {_, ans} = TableCase.run(c.reader, c.db, q)
      {:messages, msgs} = Process.info(self(), :messages)
      {:trap_exit, trap} = Process.info(self(), :trap_exit)
      keys = for {k, _} <- Process.get(), conc_key?(k), do: k
      {ans, %{messages: msgs, trap_exit: trap, keys: keys}}
    end)
  end

  defp conc_key?({k, _}) when is_atom(k), do: String.starts_with?(Atom.to_string(k), "conc_")
  defp conc_key?(_), do: false

  defp clean!(state) do
    assert state.messages == []
    assert state.trap_exit == false
    assert state.keys == []
  end

  defp workers do
    for p <- Process.list(),
        {:dictionary, d} <- [Process.info(p, :dictionary)],
        Keyword.get(d, :prolog_ex_conc_child) == true,
        do: p
  end

  defp await_workers(n) do
    Enum.find_value(1..300, fn _ ->
      ws = workers()
      if length(ws) >= n, do: ws, else: Process.sleep(10) && nil
    end) || flunk("keine #{n} Arbeiter")
  end

  # der Arbeiter, der am meisten rechnet
  defp busiest(ws) do
    Process.sleep(100)
    Enum.max_by(ws, fn p -> elem(Process.info(p, :reductions) || {:r, 0}, 1) end)
  end

  defp gone! do
    Enum.find(1..100, fn _ -> workers() == [] || (Process.sleep(10) && false) end) ||
      flunk("Arbeiter übrig: #{inspect(workers())}")
  end

  # Während eines Laufs fängt der Aufrufer Exit-Signale ab (trap_exit), um
  # tote Arbeiter zu bemerken. Ein Signal eines fremden verbundenen
  # Prozesses gehört nicht dazu: danach muss es wirken wie ohne den Lauf
  # (abnormal: der Aufrufer stirbt mit demselben Grund; normal: nichts)
  test "fremdes Exit-Signal während eines Laufs wirkt danach wie sonst", c do
    me = self()

    for {reason, dies?} <- [{:fremd, true}, {:normal, false}] do
      {pid, mref} =
        spawn_monitor(fn ->
          Reader.put_current(c.reader)
          Process.put(:prolog_ex_ops, c.ops)
          spawn_link(fn -> Process.sleep(50) && exit(reason) end)
          {_, ans} = TableCase.run(c.reader, c.db, "concurrent_maplist(late, [A, B])")
          {:trap_exit, trap} = Process.info(self(), :trap_exit)
          send(me, {:fertig, ans, trap})
        end)

      if dies? do
        assert_receive {:DOWN, ^mref, :process, ^pid, ^reason}, 5_000
        refute_received {:fertig, _, _}
      else
        assert_receive {:fertig, {:answers, ["A = spaet, B = spaet"]}, false}, 5_000
        assert_receive {:DOWN, ^mref, :process, ^pid, :normal}, 5_000
      end
    end

    gone!()
  end

  test "ein Arbeiter stirbt: Fehler beim Aufrufer, alles aufgeräumt", c do
    t = start(c, "catch(concurrent_maplist(spin, [1, 2]), error(E, _), true)")
    [w | _] = await_workers(2)
    Process.exit(w, :kill)
    {ans, state} = Task.await(t, 10_000)
    assert ans == {:answers, ["E = system_error(concurrent_child(killed))"]}
    clean!(state)
    gone!()
  end

  test "first_solution/3 mit on_error(continue): ein toter Arbeiter wie ein Scheitern", c do
    t = start(c, "first_solution(X, [spin(X), late(X)], [on_error(continue)])")
    ws = await_workers(2)
    Process.exit(busiest(ws), :kill)
    {ans, state} = Task.await(t, 10_000)
    assert ans == {:answers, ["X = spaet"]}
    clean!(state)
    gone!()
  end

  test "beim Aufteilen (clpz_concurrent) stirbt ein Arbeiter", c do
    t =
      start(
        c,
        "ph(9, Vs), catch(concurrent_labelings([], Vs, _, [serial(0)]), error(E, _), true)"
      )

    [w | _] = await_workers(1)
    Process.sleep(50)
    Process.exit(w, :kill)
    {ans, state} = Task.await(t, 30_000)

    assert ans ==
             {:answers,
              ["E = system_error(concurrent_child(killed)), Vs = [_A,_B,_C,_D,_E,_F,_G,_H,_I,_J]"]} or
             match?({:answers, ["E = system_error(concurrent_child(killed))" <> _]}, ans)

    clean!(state)
    gone!()
  end

  test "nach einem gewöhnlichen Lauf: sauber", c do
    for q <- [
          "concurrent_maplist(sq, [1, 2, 3, 4, 5], L)",
          "first_solution(X, [late(X), X = schnell], [])",
          "concurrent_forall(between(1, 20, X), X > 0, [threads(3)])",
          "queens(8, Qs), concurrent_labeling([], Qs, [serial(0), parts(8)])",
          "queens(6, Qs), concurrent_labelings([], Qs, L, [serial(0)]), length(L, N)",
          "catch(concurrent_maplist(sq, [1, a]), error(E, _), true)"
        ] do
      {ans, state} = Task.await(start(c, q), 30_000)
      assert match?({:answers, [_]}, ans), q
      clean!(state)
    end

    gone!()
  end

  # --- Aufteilen: Teile fallen weg, Grenzen, Fehler ----------------------------

  test "Teile rechts der ersten Lösung fallen weg (wartende und laufende)", c do
    # kurzer Anfang nacheinander, dann feste Teile auf 2 Arbeitern; ganz
    # rechts (X = 2) eine lange Suche ohne Lösung (Sekunden): wartete der
    # Lauf auf sie, dauerte er so lange. Die Lösung immer die von
    # once(labeling/2); ob es Teile gibt, hängt davon ab, wie weit der
    # Anfang kommt – wenigstens einmal von mehreren Versuchen
    runs =
      for serial <- ~w(0.0005 0.001 0.002 0.003 0.0005 0.001) do
        {ans, state} =
          Task.await(
            start(
              c,
              "lr(L0), once(labeling([], L0)), lr(L), " <>
                "concurrent_labeling([], L, [serial(#{serial}), parts(2), stats(S)]), L == L0, " <>
                "memberchk(pruned(P), S), memberchk(time(T), S)"
            ),
            30_000
          )

        assert {:answers, [a]} = ans
        clean!(state)
        [_, p] = Regex.run(~r/\bP = (\d+)/, a)
        [_, t] = Regex.run(~r/\bT = ([\d.]+)/, a)
        {String.to_integer(p), String.to_float(t)}
      end

    assert Enum.any?(runs, fn {p, _} -> p >= 1 end), inspect(runs)
    assert Enum.all?(runs, fn {_, t} -> t < 1500 end), inspect(runs)
    gone!()
  end

  test "Zeit- und Inferenzgrenzen gelten beim Aufteilen", c do
    for q <- [
          "ph(9, Vs), catch(call_with_time_limit(0.3, concurrent_labelings([], Vs, _, [serial(0)])), E, true)",
          "ph(9, Vs), catch(call_with_time_limit(0.3, concurrent_labeling([], Vs, [serial(0)])), E, true)",
          "ph(9, Vs), catch(call_with_time_limit(0.3, concurrent_labeling([min(V)], Vs, [serial(0)])), E, true), Vs = [V|_]"
        ] do
      {ans, state} = Task.await(start(c, q), 30_000)
      assert {:answers, [a]} = ans, q
      assert a =~ "E = time_limit_exceeded", q
      clean!(state)
    end

    {ans, _} =
      Task.await(
        start(
          c,
          "ph(8, Vs), call_with_inference_limit(concurrent_labelings([], Vs, _, [serial(0)]), 20000, R)"
        ),
        30_000
      )

    assert {:answers, [a]} = ans
    assert a =~ "R = inference_limit_exceeded"
    gone!()
  end

  # Abbruch mitten im Aufteilen, oft: ein Arbeiter, der beim Beenden
  # gerade eine Nachricht schickt (conc_offer, conc_loop_end, ...), darf
  # sie nicht im Postfach des Aufrufers hinterlassen (das Zeitfenster ist
  # klein: der Test fing den alten Fehler nur in etwa jedem sechsten Lauf)
  test "nach Abbruch keine späten Nachrichten im Postfach", c do
    for _ <- 1..40 do
      {ans, state} =
        Task.await(
          start(
            c,
            "ph(9, Vs), catch(call_with_time_limit(0.01, " <>
              "concurrent_labeling([], Vs, [serial(0), parts(16)])), E, true)"
          ),
          30_000
        )

      assert {:answers, [_]} = ans
      clean!(state)
    end

    gone!()
  end
end
