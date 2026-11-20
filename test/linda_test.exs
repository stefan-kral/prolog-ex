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
            ":- use_module(library(lists)).\n:- use_module(library(iso_ext)).\n"
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
