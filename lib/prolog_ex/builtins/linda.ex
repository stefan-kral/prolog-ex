defmodule PrologEx.Builtins.Linda do
  @moduledoc """
  Die Grundlagen von `library(linda)` (`priv/library/linda.pl`): Server
  (`PrologEx.Linda.Server`) und Client über die Erlang-Distribution.

  Eine Adresse ist ein Knotenname (`'linda_4711@rechner'`). Braucht
  PrologEx einen Namen und läuft noch nicht verteilt, startet es `epmd`
  (wie `erl -sname`; er läuft danach weiter) und wird zum Knoten: der
  Server unter dem gewünschten bzw. `linda_<Prozessnummer>`, ein Client
  unter `linda_client_<Prozessnummer>`; Kurznamen, außer der Rechner im
  Namen enthält einen Punkt (dann lange Namen, wie `-name`). Knoten
  müssen dasselbe Cookie haben – auf einem Rechner und mit demselben
  Benutzer von selbst (`~/.erlang.cookie`).

  Je Sitzung höchstens eine Verbindung (wie SICStus), im
  Prozess-Wörterbuch des Toplevels. Warten blockiert die Anfrage, Ctrl-C
  und Zeitgrenzen brechen es ab (alle 100 ms nachgesehen,
  `PrologEx.Stop.poll!/0`); ein schon vorgemerktes Tupel gibt der Client
  dann zurück (siehe Protokoll im Server).

  Zeitgrenze (`linda_timeout/2`): `off` oder `S:Ms`; gilt für die Antwort
  des Servers bei allem außer dem Warten von `in`/`rd` selbst.
  Voreingestellt `off`.
  """
  use PrologEx.Builtin
  alias PrologEx.{Effects, Error}
  alias PrologEx.Linda.Server

  @client :prolog_ex_linda_client
  @timeout :prolog_ex_linda_timeout
  @poll 100

  # --- Server -----------------------------------------------------------------

  # $linda_start(?Adresse): Server auf diesem Knoten starten; Adresse ist der
  # Knotenname (gebunden: so soll er heißen)
  defbuiltin "$linda_start", [addr] do
    s = subst()
    Effects.external!()

    want =
      case PrologEx.resolve(addr, s) do
        {:var, _} -> nil
        {:atom, a} -> a
        other -> Error.type!("atom", other)
      end

    node = ensure_node!(want, "linda")

    if want && want != Atom.to_string(node),
      do: Error.permission!("create", "linda_server", a(want))

    case Server.start() do
      {:ok, _} ->
        {:unify, [{addr, a(Atom.to_string(node))}]}

      {:error, {:already_started, _}} ->
        Error.permission!("create", "linda_server", a(Atom.to_string(node)))
    end
  end

  # --- Client -----------------------------------------------------------------

  defbuiltin "$linda_connect", [addr] do
    s = subst()
    Effects.external!()

    target =
      case PrologEx.resolve(addr, s) do
        {:var, _} -> Error.instantiation!()
        {:atom, a} -> a
        other -> Error.type!("atom", other)
      end

    if Process.get(@client), do: Error.permission!("create", "linda_client", a(target))
    node = String.to_atom(target)
    ensure_node!(nil, "linda_client", host_of(target))

    unless node == Node.self() or Node.connect(node) == true,
      do: Error.existence!("linda_server", a(target))

    server = {Server.name(), node}
    mon = Process.monitor(server)
    Process.put(@client, %{server: server, mon: mon, addr: a(target)})

    case request(:hello) do
      :ok ->
        :ok

      {:error, :shutdown} ->
        disconnect()
        Error.existence!("linda_server", a(target))

      :timeout ->
        disconnect()
        :fail
    end
  end

  defbuiltin "$linda_close", [] do
    Effects.external!()

    if Process.get(@client) do
      try do
        request(:bye)
      rescue
        PrologEx.Error -> :ok
      end

      disconnect()
    end

    :ok
  end

  defbuiltin "$linda_shutdown", [] do
    Effects.external!()
    client!()
    ok!(request(:shutdown))
  end

  defbuiltin "$linda_timeout", [old, new] do
    s = subst()
    cur = timeout_term(Process.get(@timeout, :off))

    case PrologEx.resolve(new, s) do
      # New offen: nur abfragen (New = Old)
      {:var, _} ->
        {:unify, [{old, cur}, {new, cur}]}

      t ->
        ms = timeout!(t)

        case PrologEx.unify(old, cur, s) do
          {:ok, s} ->
            Process.put(@timeout, ms)
            {:subst, s}

          :error ->
            :fail
        end
    end
  end

  defbuiltin "$linda_out", [t] do
    s = subst()
    if match?({:var, _}, PrologEx.Store.walk(t, s)), do: Error.instantiation!()
    Effects.external!()
    client!()
    ok!(request({:out, export(t, s)}))
  end

  # $linda_in(+Muster, +Blockieren, -Tupel) / $linda_rd(...): Muster ist
  # eine Liste; Tupel das gefundene (frische Variablen)
  defbuiltin "$linda_in", [pats, block, t] do
    take(:in, pats, block, t, subst())
  end

  defbuiltin "$linda_rd", [pats, block, t] do
    take(:rd, pats, block, t, subst())
  end

  # $linda_all(+Muster, +Entfernen, -Tupel): alle passenden, älteste zuerst
  defbuiltin "$linda_all", [pat, remove, ts] do
    s = subst()
    Effects.external!()
    client!()

    case request({:all, export(pat, s), bool!(remove, s)}) do
      {:ok, list} -> {:unify, [{ts, Enum.map(list, &import_term/1)}]}
      :timeout -> :fail
    end
  end

  defp take(op, pats, block, t, s) do
    Effects.external!()
    client!()
    block = bool!(block, s)
    pats = for p <- PrologEx.Builtins.Lists.items(pats, s), do: export(p, s)

    case request({op, pats, block}, block) do
      {:ok, tuple} -> {:unify, [{t, import_term(tuple)}]}
      :none -> :fail
      :timeout -> :fail
    end
  end

  # --- Verbindung ---------------------------------------------------------------

  defp client! do
    Process.get(@client) || Error.existence!("linda_client", a("none"))
  end

  defp disconnect do
    case Process.delete(@client) do
      %{mon: mon} -> Process.demonitor(mon, [:flush])
      nil -> :ok
    end
  end

  # Anfrage schicken und auf die Antwort warten: die Antwort, oder
  # :timeout (Zeitgrenze von linda_timeout/2 – nicht beim Warten von
  # in/rd selbst). Der Server weg: existence_error(linda_server, Adresse),
  # die Verbindung ist dann zu. Ctrl-C oder eine Zeitgrenze der Maschine
  # (PrologEx.Stop) bricht ab; eine Vormerkung wird dann abgesagt, eine
  # angekommene Herausnahme (in, $linda_all mit Entfernen) bestätigt.
  defp request(req, waiting \\ false) do
    %{server: server, mon: mon, addr: addr} = Process.get(@client)
    ref = make_ref()
    send(server, {:linda, self(), ref, req})

    deadline =
      case {waiting, Process.get(@timeout, :off)} do
        {true, _} -> nil
        {_, :off} -> nil
        {_, ms} -> System.monotonic_time(:millisecond) + ms
      end

    try do
      await(ref, mon, addr, deadline)
    rescue
      e in PrologEx.Stop ->
        cancel(server, ref)
        reraise e, __STACKTRACE__
    else
      {:ok, _} = r when elem(req, 0) == :in or (elem(req, 0) == :all and elem(req, 2)) ->
        send(server, {:ack, ref})
        r

      :timeout = r ->
        cancel(server, ref)
        r

      r ->
        r
    end
  end

  defp await(ref, mon, addr, deadline) do
    wait =
      case deadline do
        nil -> @poll
        d -> max(0, min(@poll, d - System.monotonic_time(:millisecond)))
      end

    receive do
      {:linda_reply, ^ref, answer} ->
        answer

      {:DOWN, ^mon, _, _, _} ->
        Process.delete(@client)
        Error.existence!("linda_server", addr)
    after
      wait ->
        PrologEx.Stop.poll!()

        if deadline && System.monotonic_time(:millisecond) >= deadline,
          do: :timeout,
          else: await(ref, mon, addr, deadline)
    end
  end

  # absagen und eine schon angekommene Antwort wegräumen
  defp cancel(server, ref) do
    send(server, {:cancel, ref})

    receive do
      {:linda_reply, ^ref, _} -> :ok
    after
      0 -> :ok
    end
  end

  defp ok!(:ok), do: :ok
  defp ok!(:timeout), do: :fail

  # --- Terme ------------------------------------------------------------------

  defp export(t, s), do: PrologEx.copy_fresh(t, s)
  defp import_term(t), do: elem(PrologEx.copy_mapped(t, %{}), 0)

  defp bool!(t, s) do
    case PrologEx.resolve(t, s) do
      {:atom, "true"} -> true
      {:atom, "false"} -> false
    end
  end

  defp timeout_term(:off), do: a("off")
  defp timeout_term(ms), do: mk(":", [div(ms, 1000), rem(ms, 1000)])

  defp timeout!({:atom, "off"}), do: :off

  defp timeout!({:struct, ":", [sec, ms]} = t) when is_integer(sec) and is_integer(ms) do
    if sec < 0 or ms < 0, do: Error.domain!("linda_timeout", t)
    sec * 1000 + ms
  end

  defp timeout!({:struct, ":", [{:var, _}, _]}), do: Error.instantiation!()
  defp timeout!({:struct, ":", [_, {:var, _}]}), do: Error.instantiation!()

  # Sekunden als Zahl (wie SWI: 0.25), auf Millisekunden gerundet
  defp timeout!(sec) when is_number(sec) and sec >= 0, do: round(sec * 1000)

  defp timeout!({:var, _}), do: Error.instantiation!()
  defp timeout!(t), do: Error.domain!("linda_timeout", t)

  # --- Knoten -----------------------------------------------------------------

  # Diesen Knoten verteilt machen, falls noch nicht: want (Name samt
  # Rechner oder nil), sonst prefix_<Prozessnummer>; host: Rechner des
  # Gegenübers (lange Namen, wenn er einen Punkt hat)
  defp ensure_node!(want, prefix, host \\ nil) do
    if Node.alive?() do
      Node.self()
    else
      start_epmd()

      {name, long} =
        case want do
          nil ->
            long = host != nil and String.contains?(host, ".")
            base = "#{prefix}_#{System.pid()}"
            # lange Namen brauchen einen Rechner im eigenen Namen: die
            # eigene Adresse auf dem Weg zum Gegenüber
            {if(long, do: base <> "@" <> local_address(host), else: base), long}

          w ->
            if name_taken?(w), do: Error.permission!("create", "linda_server", a(w))
            {w, String.contains?(host_of(w) || "", ".")}
        end

      domain = if long, do: :longnames, else: :shortnames

      case start_node(String.to_atom(name), domain) do
        {:ok, _} -> Node.self()
        {:error, _} -> Error.resource!("linda_node")
      end
    end
  end

  # als verborgener Knoten (wie erl -hidden): Clients verbinden sich nur mit
  # dem Server, nicht über global auch untereinander (das vollständige Netz
  # wüchse quadratisch, und global trennte beim Ende eines Clients andere
  # Verbindungen, um Partitionen zu vermeiden). Ältere OTP ohne die
  # Option: normal
  defp start_node(name, domain) do
    :net_kernel.start(name, %{name_domain: domain, hidden: true})
  rescue
    _ -> :net_kernel.start([name, domain])
  end

  # schon ein Knoten dieses Namens auf diesem Rechner (bei epmd gemeldet)?
  defp name_taken?(w) do
    [short | _] = String.split(w, "@", parts: 2)

    case :erl_epmd.names() do
      {:ok, names} -> Enum.any?(names, fn {n, _port} -> to_string(n) == short end)
      _ -> false
    end
  end

  # die eigene IP-Adresse, über die host erreicht wird (UDP "verbinden"
  # schickt nichts, wählt aber die Schnittstelle); sonst der Rechnername
  defp local_address(host) do
    with {:ok, ip} <- :inet.getaddr(String.to_charlist(host), :inet),
         {:ok, sock} <- :gen_udp.open(0, [:inet]) do
      try do
        with :ok <- :gen_udp.connect(sock, ip, 9),
             {:ok, {me, _}} <- :inet.sockname(sock) do
          to_string(:inet.ntoa(me))
        else
          _ -> fallback_host()
        end
      after
        :gen_udp.close(sock)
      end
    else
      _ -> fallback_host()
    end
  end

  defp fallback_host do
    {:ok, h} = :inet.gethostname()
    to_string(h)
  end

  defp host_of(name) do
    case String.split(name, "@", parts: 2) do
      [_, host] -> host
      _ -> nil
    end
  end

  # wie erl -sname: epmd im Hintergrund (läuft er schon, endet der neue
  # gleich wieder)
  defp start_epmd do
    exe =
      Enum.find(
        [Path.join([:code.root_dir(), "bin", "epmd"]), System.find_executable("epmd")],
        &(&1 && File.exists?(&1))
      )

    if exe, do: System.cmd(exe, ["-daemon"], stderr_to_stdout: true)
    :ok
  end
end
