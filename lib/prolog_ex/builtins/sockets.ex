defmodule PrologEx.Builtins.Sockets do
  @moduledoc """
  `library(sockets)` wie SICStus 4 (dazu `current_hostname/1` aus Scryer):
  TCP über `:gen_tcp`.

    * `socket_client_open(+Addr, -Stream, +Optionen)`
    * `socket_server_open(?Addr, -Server)`, `socket_server_open(?Addr, -Server, +Optionen)`
    * `socket_server_accept(+Server, -Client, -Stream, +Optionen)`
    * `socket_server_close(+Server)`
    * `socket_select(+Server, -SBereit, +Lesen, -LBereit, +Schreiben, -SchBereit, +Timeout)`
    * `current_host(?Name)`, `current_hostname(?Name)`

  Adressen: `Host:Port`, `inet(Host, Port)`, `unix(Pfad)`; beim Server
  auch nur `Port`.
  Host ist ein Atom (`''`: dieser Rechner bzw. alle Schnittstellen), Port
  eine Zahl 0..65535, ein Atom aus Ziffern oder ein Dienstname (`http`);
  beim Server darf Port offen sein, dann wird ein freier gewählt und
  gebunden.

  `unix(Pfad)` (wie SICStus seit 4.0.3): Unix-Domain-Socket an dieser
  Stelle im Dateisystem; ein relativer Pfad gilt ab dem aktuellen
  Verzeichnis. Beim Server löscht `reuseaddr(true)` eine vorhandene Datei
  vorher; `socket_server_close/1` löscht die Datei wieder (SICStus sagt
  dazu nichts). `Client` beim Annehmen ist dann `''`.

  `socket_select/7` wie SICStus: wartet, bis ein Server eine Verbindung
  zum Annehmen hat oder ein Stream lesen bzw. schreiben kann, ohne zu
  blockieren (auch, wenn die Operation einen Fehler gäbe, etwa am Ende).
  Einträge sind Server bzw. Streams oder `Term-Eintrag` (Term zur
  Buchführung, bleibt am bereiten Eintrag); die Bereit-Listen behalten
  die Reihenfolge. Timeout: `off` (warten), Sekunden (Zahl ≥ 0) oder
  `S:U` (Sekunden und Mikrosekunden); abgelaufen: alle Listen `[]`.
  Gemeldet wird, was bei der Rückkehr bereit ist: alle lesbaren Streams;
  von Servern, deren Verbindungen zugleich ankommen, sicher mindestens
  einer (die übrigen spätestens beim nächsten Aufruf).
  Bereit zum Lesen heißt für einen Text-Stream: mindestens ein Byte da
  (ein angefangenes UTF-8-Zeichen kann noch warten). Schreiben auf einen
  Socket blockiert praktisch nie: Schreib-Streams sind immer bereit,
  ebenso Datei- und Speicher-Streams zum Lesen; Standardeingabe und Pipes
  wartet `socket_select/7` nicht ab (immer bereit).

  Ein Socket-Stream ist ein Stream für beide Richtungen (`input` und
  `output`), nicht positionierbar; voreingestellt Text (UTF-8), mit
  `type(binary)` binär. Stream-Optionen wie bei `open/4`: `type/1`,
  `alias/1`, `eof_action/1`, `encoding(utf8)`, `reposition(false)`.

  Fehler:

    * Verbindung abgelehnt, Rechner unbekannt oder nicht erreichbar:
      `existence_error(source_sink, Addr)`
    * Port belegt oder nicht erlaubt: `permission_error(open, source_sink, Addr)`
    * keine Adresse: `type_error(socket_address, Addr)`; Port außerhalb
      0..65535: `domain_error(socket_address, Addr)`
    * kein Server-Socket: `type_error(server_socket, S)`; geschlossen:
      `existence_error(server_socket, S)`
    * `socket_select/7`: Timeout offen → `instantiation_error`, kein
      gültiger → `domain_error(timeout, T)`; Liste unvollständig →
      `instantiation_error`, keine Liste → `type_error(list, L)`
    * Senden, wenn die Gegenseite weg ist: `socket_error(Grund)` (wie SWI)

  `Client` beim Annehmen ist die IP-Adresse der Gegenseite als Atom
  (`'127.0.0.1'`, wie SICStus; ohne Port).

  Alle Operationen sind äußere Wirkungen (`PrologEx.Effects`): der Toplevel
  rechnet sie nicht voraus.
  """
  use PrologEx.Builtin, module: "sockets"
  alias PrologEx.{Effects, Error}
  alias PrologEx.Builtins.IO, as: PIO
  alias PrologEx.Stream, as: S

  @servers :prolog_ex_server_sockets
  @tcp [:binary, active: false, packet: :raw]

  # --- Client ----------------------------------------------------------------

  defbuiltin "socket_client_open", [addr, stream, opts] do
    s = subst()
    addr_t = PrologEx.resolve(addr, s)
    if match?({:var, _}, addr_t), do: Error.instantiation!()
    must_be_var!(stream, s)
    sopts = stream_options!(opts, s)
    {host, port} = address!(addr_t, :client)
    Effects.external!()

    host =
      case host do
        {:local, _} = local -> local
        "" -> ~c"localhost"
        h -> String.to_charlist(h)
      end

    case :gen_tcp.connect(host, port, @tcp) do
      {:ok, sock} ->
        {:unify, [{stream, S.term(S.open_socket(sock, sopts))}]}

      {:error, reason} when reason in [:eacces, :eperm] ->
        Error.permission!("open", "source_sink", addr_t)

      {:error, _} ->
        Error.existence!("source_sink", addr_t)
    end
  end

  # --- Server ----------------------------------------------------------------

  defbuiltin "socket_server_open", [addr, server] do
    server_open(addr, server, [], subst())
  end

  defbuiltin "socket_server_open", [addr, server, opts] do
    server_open(addr, server, opts, subst())
  end

  @server_options ~w(reuseaddr numeric_nodename numeric_servname loopback)

  defp server_open(addr, server, opts, s) do
    must_be_var!(server, s)

    o =
      for opt <- PIO.option_list!(opts, s), into: %{} do
        case opt do
          {:struct, name, [{:atom, b}]} when name in @server_options and b in ["true", "false"] ->
            {name, b == "true"}

          {:struct, name, [{:var, _}]} when name in @server_options ->
            Error.instantiation!()

          {:var, _} ->
            Error.instantiation!()

          other ->
            Error.domain!("socket_option", other)
        end
      end

    addr_t = PrologEx.resolve(addr, s)
    {host, port_t} = server_address!(addr_t)

    port =
      case port_t do
        :unix ->
          0

        {:var, _} ->
          0

        p ->
          if Map.get(o, "numeric_servname", false) and not match?(n when is_integer(n), p) and
               not numeric_atom?(p),
             do: Error.domain!("socket_address", addr_t)

          port_number!(p, addr_t)
      end

    ip =
      cond do
        match?({:local, _}, host) ->
          {:local, path} = host
          if Map.get(o, "reuseaddr", false), do: File.rm(path)
          [ifaddr: host]

        Map.get(o, "loopback", false) ->
          [ip: {127, 0, 0, 1}]

        host == "" ->
          []

        true ->
          case :inet.parse_address(String.to_charlist(host)) do
            {:ok, ip} ->
              [ip: ip]

            _ ->
              if Map.get(o, "numeric_nodename", false),
                do: Error.domain!("socket_address", addr_t)

              case :inet.getaddr(String.to_charlist(host), :inet) do
                {:ok, ip} -> [ip: ip]
                _ -> Error.existence!("source_sink", addr_t)
              end
          end
      end

    Effects.external!()

    reuse =
      if match?({:local, _}, host), do: [], else: [reuseaddr: Map.get(o, "reuseaddr", false)]

    case :gen_tcp.listen(port, @tcp ++ reuse ++ ip) do
      {:ok, l} ->
        t = Process.get(@servers, %{next: 0})
        n = t.next
        file = with {:local, path} <- host, do: path, else: (_ -> nil)
        entry = %{l: l, file: file, acceptor: nil, ready: []}
        Process.put(@servers, Map.put(%{t | next: n + 1}, n, entry))

        bind =
          case port_t do
            {:var, _} = v ->
              {:ok, actual} = :inet.port(l)
              [{v, actual}]

            _ ->
              []
          end

        {:unify, [{server, mk("$socket", [n])} | bind]}

      {:error, _} ->
        Error.permission!("open", "source_sink", addr_t)
    end
  end

  defbuiltin "socket_server_accept", [server, client, stream, opts] do
    s = subst()
    {n, entry} = server!(server, s)
    must_be_var!(client, s)
    must_be_var!(stream, s)
    sopts = stream_options!(opts, s)
    Effects.external!()

    case take_connection(n, entry) do
      {:ok, sock} ->
        peer =
          case :inet.peername(sock) do
            {:ok, {:local, _}} -> a("")
            {:ok, {ip, _port}} -> a(to_string(:inet.ntoa(ip)))
            _ -> a("")
          end

        {:unify, [{client, peer}, {stream, S.term(S.open_socket(sock, sopts))}]}

      {:error, _} ->
        Error.existence!("server_socket", resolve(server))
    end
  end

  defbuiltin "socket_server_close", [server] do
    {n, entry} = server!(server, subst())
    Effects.external!()
    stop_acceptor(entry)
    for sock <- entry.ready, not match?({:error, _}, sock), do: :gen_tcp.close(sock)
    :gen_tcp.close(entry.l)
    if entry.file, do: File.rm(entry.file)
    Process.put(@servers, Map.delete(Process.get(@servers), n))
    :ok
  end

  # Verbindung zum Annehmen: eine schon von socket_select/7 angenommene,
  # sonst die des laufenden Annahme-Prozesses, sonst direkt accept
  defp take_connection(n, %{ready: [first | more]} = entry) do
    put_server(n, %{entry | ready: more})

    case first do
      {:error, _} = err -> err
      sock -> {:ok, sock}
    end
  end

  defp take_connection(n, %{acceptor: {_pid, ref}} = entry) do
    receive do
      {^ref, :accepted, sock} ->
        put_server(n, %{entry | acceptor: nil})
        {:ok, sock}

      {^ref, :error, reason} ->
        put_server(n, %{entry | acceptor: nil})
        {:error, reason}
    end
  end

  defp take_connection(_n, entry), do: :gen_tcp.accept(entry.l)

  defp put_server(n, entry), do: Process.put(@servers, Map.put(Process.get(@servers), n, entry))

  defp stop_acceptor(%{acceptor: {pid, ref}}) do
    Process.exit(pid, :kill)

    # schon angenommen? Dann die Verbindung schließen
    receive do
      {^ref, :accepted, sock} -> :gen_tcp.close(sock)
      {^ref, :error, _} -> :ok
    after
      0 -> :ok
    end
  end

  defp stop_acceptor(_), do: :ok

  # Annahme-Prozess: accept auf dem Listen-Socket, die Verbindung dann an
  # den Aufrufer übergeben (controlling_process) und melden
  defp start_acceptor(n, entry) do
    owner = self()
    ref = make_ref()

    pid =
      spawn(fn ->
        case :gen_tcp.accept(entry.l) do
          {:ok, sock} ->
            :ok = :gen_tcp.controlling_process(sock, owner)
            send(owner, {ref, :accepted, sock})

          {:error, reason} ->
            send(owner, {ref, :error, reason})
        end
      end)

    entry = %{entry | acceptor: {pid, ref}}
    put_server(n, entry)
    entry
  end

  # --- socket_select/7 ------------------------------------------------------

  defbuiltin "socket_select", [servers, sready, reads, rready, writes, wready, timeout] do
    s = subst()
    tmo = timeout!(PrologEx.resolve(timeout, s))

    srvs = for {orig, e} <- entries(servers, s), do: {orig, elem(server!(e, s), 0)}
    rds = for {orig, e} <- entries(reads, s), do: {orig, PIO.input!(e, :any)}
    wrs = for {orig, e} <- entries(writes, s), do: {orig, PIO.output!(e, :any)}
    Effects.external!()

    # schon bereit (oder Schreiben gewünscht: immer bereit) → nur nachsehen
    ready_now? =
      wrs != [] or Enum.any?(srvs, fn {_, n} -> server_entry(n).ready != [] end) or
        Enum.any?(rds, fn {_, id} -> S.read_wait(id) == :ready end)

    wait(srvs, rds, if(ready_now?, do: 0, else: tmo))

    {:unify,
     [
       {sready, PrologEx.list(for {o, n} <- srvs, server_entry(n).ready != [], do: o)},
       {rready, PrologEx.list(for {o, id} <- rds, S.read_wait(id) == :ready, do: o)},
       {wready, PrologEx.list(for {o, _} <- wrs, do: o)}
     ]}
  end

  # Einträge einer Liste: {Eintrag wie gegeben, Server bzw. Stream}
  defp entries(list, s) do
    for e <- PIO.option_list!(list, s) do
      case e do
        {:struct, "-", [_, x]} -> {e, x}
        x -> {e, x}
      end
    end
  end

  defp server_entry(n), do: Map.fetch!(Process.get(@servers), n)

  # off | Sekunden ≥ 0 | S:U → Millisekunden bzw. :infinity
  defp timeout!(t) do
    case PrologEx.unmark_top(t) do
      {:var, _} ->
        Error.instantiation!()

      {:atom, "off"} ->
        :infinity

      n when is_integer(n) and n >= 0 ->
        n * 1000

      x when is_float(x) and x >= 0 ->
        ceil(x * 1000)

      {:struct, ":", [sec, u]} when is_integer(sec) and sec >= 0 and is_integer(u) and u >= 0 ->
        sec * 1000 + div(u + 999, 1000)

      {:struct, ":", [sec, u]} = st ->
        if match?({:var, _}, sec) or match?({:var, _}, u),
          do: Error.instantiation!(),
          else: Error.domain!("timeout", st)

      other ->
        Error.domain!("timeout", other)
    end
  end

  # Warten: Server ohne angenommene Verbindung bekommen einen
  # Annahme-Prozess, Socket-Streams ohne Daten melden sich einmal aktiv
  # (active: :once); die erste Meldung oder der Timeout beendet das Warten,
  # danach wird eingesammelt, was sonst noch da ist
  defp wait(srvs, rds, tmo) do
    refs =
      for {_, n} <- srvs, (e = server_entry(n)).ready == [], into: %{} do
        e = if e.acceptor, do: e, else: start_acceptor(n, e)
        {elem(e.acceptor, 1), n}
      end

    socks =
      for {_, id} <- rds, {:wait, sock} <- [S.read_wait(id)], reduce: %{} do
        acc ->
          case :inet.setopts(sock, active: :once) do
            :ok ->
              Map.put(acc, sock, id)

            # Socket schon unbrauchbar: gilt als am Ende, also bereit
            _ ->
              S.socket_received(id, :closed)
              acc
          end
      end

    if refs != %{} or socks != %{} do
      if receive_one(refs, socks, tmo), do: drain(refs, socks)

      for {sock, id} <- socks do
        :inet.setopts(sock, active: false)
        # was zwischen Meldung und Abschalten noch kam
        receive_sock(sock, id)
      end
    end

    :ok
  end

  defp receive_one(refs, socks, tmo) do
    receive do
      {ref, kind, x} when is_map_key(refs, ref) ->
        accepted(Map.fetch!(refs, ref), kind, x)
        true

      {tag, sock, data} when tag in [:tcp, :tcp_error] and is_map_key(socks, sock) ->
        S.socket_received(Map.fetch!(socks, sock), if(tag == :tcp, do: data, else: :closed))
        true

      {:tcp_closed, sock} when is_map_key(socks, sock) ->
        S.socket_received(Map.fetch!(socks, sock), :closed)
        true
    after
      tmo -> false
    end
  end

  defp drain(refs, socks), do: if(receive_one(refs, socks, 0), do: drain(refs, socks))

  # nach dem Abschalten: was noch im Postfach liegt, sonst nicht blockierend
  # nachsehen – alles, was jetzt schon da ist, wird gemeldet
  defp receive_sock(sock, id) do
    receive do
      {:tcp, ^sock, data} -> S.socket_received(id, data)
      {:tcp_closed, ^sock} -> S.socket_received(id, :closed)
      {:tcp_error, ^sock, _} -> S.socket_received(id, :closed)
    after
      0 ->
        if S.read_wait(id) != :ready do
          case :gen_tcp.recv(sock, 0, 0) do
            {:ok, data} -> S.socket_received(id, data)
            {:error, :timeout} -> :ok
            {:error, _} -> S.socket_received(id, :closed)
          end
        end
    end
  end

  # Annahme-Prozess fertig: die Verbindung (oder der Fehler) wartet beim
  # Server auf socket_server_accept/4
  defp accepted(n, :accepted, sock) do
    e = server_entry(n)
    put_server(n, %{e | acceptor: nil, ready: e.ready ++ [sock]})
  end

  defp accepted(n, :error, reason) do
    e = server_entry(n)
    put_server(n, %{e | acceptor: nil, ready: e.ready ++ [{:error, reason}]})
  end

  # --- Rechnername -------------------------------------------------------

  # current_host/1 wie SICStus: der volle Name; gebunden gelingt es auch
  # mit dem unqualifizierten Namen in Kleinbuchstaben
  defbuiltin "current_host", [h] do
    {full, short} = host_names()

    case deref(h) do
      {:var, _} -> {:unify, [{h, a(full)}]}
      {:atom, name} -> name == full or name == String.downcase(short)
      _ -> :fail
    end
  end

  # current_hostname/1 wie Scryer: der Name, den das System meldet
  defbuiltin "current_hostname", [h] do
    {_, short} = host_names()
    {:unify, [{h, a(short)}]}
  end

  defp host_names do
    {:ok, short} = :inet.gethostname()

    full =
      case :inet.gethostbyname(short) do
        {:ok, {:hostent, name, _, _, _, _}} -> to_string(name)
        _ -> to_string(short)
      end

    {full, to_string(short)}
  end

  # --- Hilfen ----------------------------------------------------------------

  defp must_be_var!(t, s) do
    case PrologEx.walk(t, s) do
      {:var, _} -> :ok
      other -> Error.uninstantiation!(PrologEx.resolve(other, s))
    end
  end

  # Stream-Optionen wie open/4; reposition(true) geht nicht
  defp stream_options!(opts, s) do
    o = Enum.map(PIO.option_list!(opts, s), &PIO.open_option!/1)

    if Keyword.get(o, :reposition, false),
      do: Error.permission!("open", "source_sink", mk("reposition", [a("true")]))

    case Keyword.get(o, :alias) do
      nil ->
        :ok

      al ->
        if S.alias_taken?(al), do: Error.permission!("open", "source_sink", mk("alias", [a(al)]))
    end

    o
  end

  # {host, port} aus Host:Port, inet(Host, Port) oder unix(Pfad)
  defp address!(addr, _kind) do
    case PrologEx.unmark_top(addr) do
      {:struct, "unix", [p]} ->
        {{:local, unix_path!(p)}, 0}

      {:struct, f, [h, p]} when f in [":", "inet"] ->
        host =
          case h do
            {:atom, name} -> name
            {:var, _} -> Error.instantiation!()
            _ -> Error.type!("socket_address", addr)
          end

        case p do
          {:var, _} -> Error.instantiation!()
          p -> {host, port_number!(p, addr)}
        end

      _ ->
        Error.type!("socket_address", addr)
    end
  end

  # Pfad eines Unix-Domain-Sockets (absolut; relativ ab cwd)
  defp unix_path!(p) do
    case p do
      {:atom, ""} -> Error.domain!("socket_address", mk("unix", [p]))
      {:atom, name} -> Path.expand(name)
      {:var, _} -> Error.instantiation!()
      _ -> Error.type!("socket_address", mk("unix", [p]))
    end
  end

  # Server: wie address!/2, dazu Port allein; Port darf offen sein
  defp server_address!(addr) do
    case PrologEx.unmark_top(addr) do
      {:struct, "unix", [p]} ->
        {{:local, unix_path!(p)}, :unix}

      {:var, _} = v ->
        {"", v}

      p when is_integer(p) ->
        {"", p}

      {:struct, f, [h, p]} when f in [":", "inet"] ->
        case h do
          {:atom, name} -> {name, p}
          {:var, _} -> Error.instantiation!()
          _ -> Error.type!("socket_address", addr)
        end

      {:atom, _} = p ->
        {"", p}

      _ ->
        Error.type!("socket_address", addr)
    end
  end

  defp numeric_atom?({:atom, name}), do: name != "" and String.match?(name, ~r/^\d+$/)
  defp numeric_atom?(_), do: false

  defp port_number!(p, addr) do
    n =
      case p do
        n when is_integer(n) ->
          n

        {:atom, name} = at ->
          if numeric_atom?(at) do
            String.to_integer(name)
          else
            # Dienstname (/etc/services); :inet will ihn als Atom – nur
            # kurze Namen aus Buchstaben, Ziffern und -, damit die
            # Atomtabelle nicht beliebig wächst
            with true <- String.match?(name, ~r/^[a-z][a-z0-9-]{0,31}$/),
                 {:ok, n} <- :inet.getservbyname(String.to_atom(name), :tcp) do
              n
            else
              _ -> Error.domain!("socket_address", addr)
            end
          end

        _ ->
          Error.type!("socket_address", addr)
      end

    if n in 0..65535, do: n, else: Error.domain!("socket_address", addr)
  end

  defp server!(t, s) do
    case PrologEx.resolve(t, s) do
      {:var, _} ->
        Error.instantiation!()

      {tag, "$socket", [n]} = sock when tag in [:struct, :gstruct] and is_integer(n) ->
        case Map.fetch(Process.get(@servers, %{}), n) do
          {:ok, entry} -> {n, entry}
          :error -> Error.existence!("server_socket", sock)
        end

      other ->
        Error.type!("server_socket", other)
    end
  end
end
