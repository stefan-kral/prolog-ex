defmodule PrologEx.LindaTest do
  # library(linda): Tupelraum über die Erlang-Distribution. Der Testknoten
  # wird dafür selbst zum Knoten (einmal, beim ersten Server-Start) und ist
  # Server und Client zugleich; andere Clients sind eigene Prozesse dieses
  # Knotens (je Prozess eine Verbindung) und ein eigener Betriebssystem-
  # prozess (ein zweiter Knoten).
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(
          r,
          ":- use_module(library(linda)).\n:- use_module(library(time)).\n" <>
            ":- use_module(library(lists)).\n:- use_module(library(iso_ext)).\n:- use_module(library(between)).\n" <>
            ":- use_module(library(dif)).\n:- use_module(library(random)).\n"
        )
      )

    {:ok, reader: r, db: db}
  end

  # vor jedem Test: ein Server (nach shutdown_server ein neuer), dieser
  # Prozess verbunden, der Raum leer
  setup c do
    Reader.put_current(c.reader)
    wait_stopped()
    [_] = ask(c, "catch(linda(_-true), error(permission_error(_, _, _), _), true)")
    addr = Atom.to_string(Node.self())
    assert ask(c, "linda_client('#{addr}')") == ["true"]
    ask(c, "linda:'$linda_all'(_, true, _)")
    on_exit(fn -> :ok end)
    {:ok, addr: addr}
  end

  defp wait_stopped do
    case Process.whereis(:prolog_ex_linda) do
      nil ->
        :ok

      pid ->
        if :sys.get_state(pid).shutdown do
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, _, _, _}, 2000
        end
    end
  end

  defp wait_waiters(n, tries \\ 100) do
    cond do
      length(:sys.get_state(:prolog_ex_linda).waiters) >= n -> :ok
      tries == 0 -> flunk("keine #{n} Wartenden")
      true -> Process.sleep(20) && wait_waiters(n, tries - 1)
    end
  end

  defp ask(c, q, n \\ 3) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(n)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch((#{goal}), error(E, _), true)")

  # eine Anfrage in einem eigenen Prozess mit eigener Verbindung
  defp other(c, q) do
    me = self()

    spawn(fn ->
      Reader.put_current(c.reader)

      r =
        try do
          ask(c, "linda_client('#{c.addr}'), #{q}, close_client")
        rescue
          e in PrologEx.Error -> {:error, e.term}
        end

      send(me, {:other, r})
    end)
  end

  test "out, rd, in: das älteste passende Tupel; Variablen in Tupeln", c do
    assert ask(c, """
           out(f(1)), out(g(a)), out(f(2)), out(h(X, X)),
           rd(f(A)), in(f(B)), in(f(C)), rd(h(b, D)), in(h(E, F))
           """) == ["A = 1, B = 1, C = 2, D = b, E = F"]

    assert ask(c, "rd_noblock(f(_))") == []
    assert ask(c, "rd_noblock(g(X))") == ["X = a"]
    assert ask(c, "in_noblock(g(X)), \\+ rd_noblock(g(_))") == ["X = a"]
  end

  test "in/2, rd/2: das erste verfügbare zu einem der Muster", c do
    assert ask(c, "out(b(1)), out(a(1)), rd([a(X), b(X)], T)") == ["T = b(1)"]
    assert ask(c, "in([a(_), c], T), in([b(_)], U)") == ["T = a(1), U = b(1)"]
    # passt das Gefundene nicht: Scheitern, es bleibt draußen
    assert ask(c, "out(z(1)), in([z(_)], z(2))") == []
    assert ask(c, "rd_noblock(z(_))") == []
  end

  test "bagof_rd_noblock/3, bagof_in_noblock/3: alle auf einmal, ^ wie bei bagof", c do
    assert ask(
             c,
             "forall(member(K-V, [a-1, b-2, a-3]), out(p(K, V))), bagof_rd_noblock(V, K^p(K, V), L)"
           ) ==
             ["L = [1,2,3]"]

    assert ask(c, "bagof_rd_noblock(V, p(K, V), L)") == ["K = a, L = [1,3]", "K = b, L = [2]"]
    assert ask(c, "bagof_in_noblock(V, p(a, V), L)") == ["L = [1,3]"]
    assert ask(c, "bagof_rd_noblock(K-V, p(K, V), L)") == ["L = [b-2]"]
    assert ask(c, "bagof_rd_noblock(V, p(c, V), L)") == []
  end

  test "in/1 wartet, bis ein anderer Client das Tupel ablegt", c do
    other(c, "sleep(0.3), out(job(42))")
    assert ask(c, "in(job(X))") == ["X = 42"]
    assert_receive {:other, ["true"]}, 2000
  end

  test "rd/1 wartet ebenso; ein Tupel weckt alle rd, aber nur ein in", c do
    other(c, "rd(sig(X)), out(saw_rd(X))")
    other(c, "in(sig(X)), out(saw_in(X))")
    # beide warten schon (sonst nähme in das Tupel vielleicht vor rd)
    wait_waiters(2)

    assert ask(c, "out(sig(1)), in(saw_rd(A)), in(saw_in(B)), \\+ rd_noblock(sig(_))") ==
             ["A = 1, B = 1"]

    assert_receive {:other, _}, 2000
    assert_receive {:other, _}, 2000
  end

  test "eine Zeitgrenze bricht das Warten ab; das Tupel geht danach nicht verloren", c do
    assert ask(c, "catch(call_with_time_limit(0.3, in(never)), E, true)") ==
             ["E = time_limit_exceeded"]

    assert ask(c, "out(never), rd_noblock(never)") == ["true"]
  end

  test "Client endet, ohne das vorgemerkte Tupel zu bestätigen: es kommt zurück", c do
    server = {:prolog_ex_linda, Node.self()}
    ask(c, "out(t(1)), out(t(2))")

    pid =
      spawn(fn ->
        ref = make_ref()
        pat = {:struct, "t", [{:var, PrologEx.Vars.next()}]}
        send(server, {:linda, self(), ref, :hello})
        receive do: ({:linda_reply, ^ref, :ok} -> :ok)
        ref = make_ref()
        send(server, {:linda, self(), ref, {:in, [pat], true}})
        receive do: ({:linda_reply, ^ref, {:ok, _}} -> :ok)
        # kein ack: einfach enden
      end)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}, 1000
    Process.sleep(50)
    assert ask(c, "bagof_rd_noblock(N, t(N), L)") == ["L = [1,2]"]
  end

  test "linda_timeout/2 und /1", c do
    assert ask(c, "linda_timeout(O, 1:500), linda_timeout(P, P), linda_timeout(_, O)") ==
             ["O = off, P = 1:500"]

    assert ask(c, "linda_timeout(0:100), linda_timeout(T, T)") == ["T = 0:100"]
    # nach dem Backtracking (und Cut, Ausnahme) wieder das Alte
    assert ask(c, "( linda_timeout(0:100), fail ; linda_timeout(T, T) )") == ["T = off"]
    assert ask(c, "once(linda_timeout(0:100)), linda_timeout(T, T)") == ["T = off"]
    assert err(c, "linda_timeout(_, soon)") == ["E = domain_error(linda_timeout,soon)"]
    assert err(c, "linda_timeout(_, -1:0)") == ["E = domain_error(linda_timeout,-1:0)"]
  end

  test "Fehler: ohne Verbindung, zweite Verbindung, kein Server", c do
    assert err(c, "linda_client('#{c.addr}')") ==
             ["E = permission_error(create,linda_client,'#{c.addr}')"]

    assert ask(c, "close_client, close_client") == ["true"]
    assert err(c, "out(x)") == ["E = existence_error(linda_client,none)"]
    [_, host] = String.split(c.addr, "@")

    assert err(c, "linda_client('nobody@#{host}')") ==
             ["E = existence_error(linda_server,'nobody@#{host}')"]
  end

  test "ein Client in einem anderen Betriebssystemprozess (zweiter Knoten)", c do
    elixir = System.find_executable("elixir")
    lib = :code.lib_dir(:prolog_ex) |> to_string()

    goal =
      "use_module(library(linda)), linda_client('#{c.addr}'), in(ping(X)), Y is X + 1, out(pong(Y)), close_client"

    task =
      Task.async(fn ->
        System.cmd(
          elixir,
          [
            "-pa",
            Path.join(lib, "consolidated"),
            "-pa",
            Path.join(lib, "ebin"),
            "-e",
            "System.halt(PrologEx.Toplevel.main(System.argv()))",
            "--",
            "-q",
            "-g",
            goal,
            "-g",
            "halt"
          ],
          stderr_to_stdout: true
        )
      end)

    assert ask(c, "out(ping(41)), in(pong(Y))") == ["Y = 42"]
    assert {"", 0} = Task.await(task, 20_000)
  end

  test "Ecken: Variable als Tupel, zyklisch, Attribute, Listen der Muster", c do
    assert err(c, "out(_)") == ["E = instantiation_error"]
    assert err(c, "X = f(X), out(X)") == ["E = representation_error(cyclic_term)"]
    # Attribute gehen nicht mit (wie bei SICStus): dif/2 bindet die Kopie nicht
    assert ask(c, "dif(D, a), out(s(D)), in(s(V)), V = a") == ["V = a, dif(D,a)"]
    assert err(c, "in(_, _)") == ["E = instantiation_error"]
    assert err(c, "rd(foo, _)") == ["E = type_error(list,foo)"]
    assert ask(c, "in_noblock(_)") == []
    assert err(c, "bagof_rd_noblock(X, X, _)") == ["E = instantiation_error"]
  end

  test "in/1 nimmt heraus, auch wenn danach etwas scheitert oder wirft", c do
    assert ask(c, "out(t(1)), catch((in(t(_)), throw(weg)), weg, true), \\+ rd_noblock(t(_))") ==
             ["true"]

    assert ask(c, "out(t(2)), ( in(t(_)), fail ; true ), \\+ rd_noblock(t(_))") == ["true"]
  end

  test "linda_timeout: Sekunden als Zahl (SWI), offene Teile", c do
    assert ask(c, "linda_timeout(O, 0.25), linda_timeout(T, T), linda_timeout(_, O)") ==
             ["O = off, T = 0:250"]

    assert err(c, "linda_timeout(_, _:3)") == ["E = instantiation_error"]
    assert err(c, "linda_timeout(_, 1:2.0)") == ["E = domain_error(linda_timeout,1:2.0)"]
  end

  test "verboten in library(concurrent) und ohne Seiteneffekte: Fehler nennt das Prädikat", c do
    assert err(c, "call_with_no_side_effects(out(x))") ==
             ["E = permission_error(perform,side_effect,out(x))"]

    assert err(c, "call_with_no_side_effects(rd_noblock(x))") ==
             ["E = permission_error(perform,side_effect,rd_noblock(x))"]

    assert ask(
             c,
             "catch(call_with_no_side_effects(linda_timeout(_, off)), error(_, context(C, K)), true)"
           ) ==
             ["C = linda:linda_timeout/2, K = state"]
  end

  test "Index nach dem ersten Argument: in(f(I)) rückwärts ohne Suche durch alle", c do
    ask(c, "forall(between(1, 2000, I), out(f(I)))")
    :erlang.trace_pattern({PrologEx, :unify_status, 3}, true, [:call_count])

    try do
      assert ask(c, "forall(between(1, 2000, J), (I is 2001 - J, in(f(I))))") == ["true"]
      {:call_count, n} = :erlang.trace_info({PrologEx, :unify_status, 3}, :call_count)
      # je in ein Vergleich (vorher bis zu 2000: ~2 Mio.)
      assert n >= 2000 and n < 3 * 2000, "#{n}"
    after
      :erlang.trace_pattern({PrologEx, :unify_status, 3}, false, [:call_count])
    end
  end

  test "Zeitgrenzen beim Warten: kein Tupel geht verloren (6 Prozesse, 1 Token)", c do
    ask(c, "out(tok(1))")

    loop = """
    forall(between(1, 40, _),
      ( random_between(5, 30, Ms), S is Ms / 1000,
        ( catch(call_with_time_limit(S, in(tok(X))), time_limit_exceeded, fail)
        -> sleep(0.003), out(tok(X)) ; true ) ))
    """

    assert others(c, List.duplicate(loop, 6)) == List.duplicate(["true"], 6)
    assert ask(c, "bagof_in_noblock(I, tok(I), L)") == ["L = [1]"]
    st = :sys.get_state(:prolog_ex_linda)
    assert st.reserved == %{} and st.waiters == []
  end

  test "linda_timeout reißt (Server hängt): Scheitern, das Tupel bleibt", c do
    ask(c, "out(slow(1))")
    pid = Process.whereis(:prolog_ex_linda)
    :sys.suspend(pid)

    try do
      assert ask(
               c,
               "linda_timeout(_, 0:150), ( in_noblock(slow(_)) -> R = da ; R = weg ), linda_timeout(_, off)"
             ) ==
               ["R = weg"]
    after
      :sys.resume(pid)
    end

    # die Anfrage kam nach der Absage an: das vorgemerkte Tupel ist zurück
    assert ask(c, "rd_noblock(slow(X))") == ["X = 1"]
    assert :sys.get_state(pid).reserved == %{}
  end

  # --- Anwendungsfälle (wie examples/linda.pl, hier mit Prozessen dieses
  # Knotens, je einer Verbindung) -------------------------------------------

  defp others(c, qs) do
    for q <- qs, do: other(c, q)
    for _ <- qs, do: assert_receive({:other, r}, 10_000) && r
  end

  test "kritischer Bereich: count(N) als einziges Tupel, 4 Prozesse je 25 Schritte", c do
    ask(c, "out(count(0))")
    step = "forall(between(1, 25, _), (in(count(C)), C1 is C + 1, out(count(C1))))"
    assert others(c, List.duplicate(step, 4)) == List.duplicate(["true"], 4)
    assert ask(c, "in(count(N))") == ["N = 100"]
  end

  test "Arbeitsliste: Worker nehmen Aufgaben bis stop, jede genau einmal", c do
    worker = """
    W = (in([task(_), stop], T), ( T = stop -> out(stop) ; T = task(I), R is I * I, out(result(I, R)), fail )),
    repeat, call(W), !
    """

    for _ <- 1..3, do: other(c, worker)
    assert ask(c, "forall(between(1, 30, I), out(task(I)))") == ["true"]

    assert ask(
             c,
             "findall(I-R, (between(1, 30, _), in(result(I, R))), L), msort(L, M), length(M, N)",
             1
           )
           |> hd() =~ "N = 30"

    ask(c, "out(stop)")
    for _ <- 1..3, do: assert_receive({:other, [_]}, 5000)
    assert ask(c, "\\+ rd_noblock(task(_)), \\+ rd_noblock(result(_, _)), in(stop)") == ["true"]
  end

  test "Philosophen: 5 Gabeln, 4 Plätze, keine Verklemmung", c do
    ask(c, "forall(between(1, 5, I), out(fork(I))), forall(between(1, 4, _), out(room))")

    ph = fn i ->
      j = rem(i, 5) + 1

      "forall(between(1, 10, R), (in(room), in(fork(#{i})), in(fork(#{j})), out(ate(#{i}, R)), " <>
        "out(fork(#{i})), out(fork(#{j})), out(room)))"
    end

    assert others(c, Enum.map(1..5, ph)) == List.duplicate(["true"], 5)

    assert ask(c, """
           findall(N-Gs, (bagof_in_noblock(x, I^R^ate(I, R), L), length(L, N),
                          bagof_in_noblock(F, fork(F), Fs), msort(Fs, Gs)), [P])
           """) == ["P = 50-[1,2,3,4,5]"]
  end

  test "beschränkter Puffer: nie mehr Elemente als Plätze", c do
    ask(c, "out(slot), out(slot)")
    other(c, "forall(between(1, 40, I), (in(slot), out(item(I)))), out(item(ende))")

    assert ask(c, """
           Lauf = (repeat, findall(I, (bagof_rd_noblock(I, item(I), L), member(I, L), integer(I)), Is),
                   length(Is, Da),
                   ( Da > 2 -> throw(zu_viele(Da)) ; true ),
                   in(item(J)), ( J == ende -> ! ; out(slot), out(gesehen(J)), fail )),
           call(Lauf), bagof_in_noblock(K, gesehen(K), Js), length(Js, N), sum_list(Js, S)
           """)
           |> hd() =~ "N = 40, S = 820"

    assert_receive {:other, ["true"]}, 5000
  end

  test "Server in einem anderen Betriebssystemprozess stirbt: Wartende bekommen einen Fehler",
       c do
    lib = to_string(:code.lib_dir(:prolog_ex))
    [_, host] = String.split(c.addr, "@")
    name = "fremd_#{System.unique_integer([:positive])}@#{host}"

    goal =
      "use_module(library(linda)), linda('#{name}'-true), linda_client('#{name}'), in(quit)"

    port =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        args: [
          "-pa",
          Path.join(lib, "consolidated"),
          "-pa",
          Path.join(lib, "ebin"),
          "-e",
          "System.halt(PrologEx.Toplevel.main(System.argv()))",
          "--",
          "-q",
          "-g",
          goal,
          "-g",
          "halt"
        ]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    ask(c, "close_client")
    # warten, bis der fremde Server läuft
    connect = "catch(linda_client('#{name}'), error(existence_error(_, _), _), fail)"

    assert Enum.any?(1..100, fn _ ->
             ask(c, connect) == ["true"] or (Process.sleep(100) && false)
           end)

    spawn(fn ->
      Process.sleep(300)
      System.cmd("kill", ["-9", to_string(os_pid)])
    end)

    assert err(c, "in(nie)") == ["E = existence_error(linda_server,'#{name}')"]
    # die Verbindung ist zu
    assert err(c, "out(x)") == ["E = existence_error(linda_client,none)"]
    assert_receive {^port, {:exit_status, _}}, 5000
  end

  test "shutdown_server: keine neuen Clients, Ende nach dem letzten", c do
    pid = Process.whereis(:prolog_ex_linda)
    ref = Process.monitor(pid)
    assert ask(c, "shutdown_server") == ["true"]
    # der andere kommt nicht mehr hinein
    other(c, "true")

    assert_receive {:other, {:error, {:struct, "error", [{:gstruct, "existence_error", _}, _]}}},
                   2000

    assert Process.alive?(pid)
    assert ask(c, "close_client") == ["true"]
    assert_receive {:DOWN, ^ref, _, _, _}, 1000
  end
end
