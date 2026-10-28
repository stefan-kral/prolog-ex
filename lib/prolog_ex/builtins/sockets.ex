defmodule PrologEx.Builtins.Sockets do
  @moduledoc """
  `library(sockets)` wie SICStus 4 (dazu `current_hostname/1` aus Scryer):
  TCP über `:gen_tcp`.

    * `socket_client_open(+Addr, -Stream, +Optionen)`
    * `socket_server_open(?Addr, -Server)`, `socket_server_open(?Addr, -Server, +Optionen)`
    * `socket_server_accept(+Server, -Client, -Stream, +Optionen)`
    * `socket_server_close(+Server)`
    * `current_host(?Name)`, `current_hostname(?Name)`

  Adressen: `Host:Port`, `inet(Host, Port)`; beim Server auch nur `Port`.
  Host ist ein Atom (`''`: dieser Rechner bzw. alle Schnittstellen), Port
  eine Zahl 0..65535, ein Atom aus Ziffern oder ein Dienstname (`http`);
  beim Server darf Port offen sein, dann wird ein freier gewählt und
  gebunden.

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

    host = if host == "", do: ~c"localhost", else: String.to_charlist(host)

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

    case :gen_tcp.listen(port, @tcp ++ [reuseaddr: Map.get(o, "reuseaddr", false)] ++ ip) do
      {:ok, l} ->
        {:ok, actual} = :inet.port(l)
        t = Process.get(@servers, %{next: 0})
        n = t.next
        Process.put(@servers, Map.put(%{t | next: n + 1}, n, l))

        bind =
          case port_t do
            {:var, _} = v -> [{v, actual}]
            _ -> []
          end

        {:unify, [{server, mk("$socket", [n])} | bind]}

      {:error, _} ->
        Error.permission!("open", "source_sink", addr_t)
    end
  end

  defbuiltin "socket_server_accept", [server, client, stream, opts] do
    s = subst()
    {_, l} = server!(server, s)
    must_be_var!(client, s)
    must_be_var!(stream, s)
    sopts = stream_options!(opts, s)
    Effects.external!()

    case :gen_tcp.accept(l) do
      {:ok, sock} ->
        peer =
          case :inet.peername(sock) do
            {:ok, {ip, _port}} -> a(to_string(:inet.ntoa(ip)))
            _ -> a("")
          end

        {:unify, [{client, peer}, {stream, S.term(S.open_socket(sock, sopts))}]}

      {:error, _} ->
        Error.existence!("server_socket", resolve(server))
    end
  end

  defbuiltin "socket_server_close", [server] do
    {n, l} = server!(server, subst())
    Effects.external!()
    :gen_tcp.close(l)
    Process.put(@servers, Map.delete(Process.get(@servers), n))
    :ok
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

  # {host, port} aus Host:Port oder inet(Host, Port)
  defp address!(addr, _kind) do
    case PrologEx.unmark_top(addr) do
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

  # Server: wie address!/2, dazu Port allein; Port darf offen sein
  defp server_address!(addr) do
    case PrologEx.unmark_top(addr) do
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
          {:ok, l} -> {n, l}
          :error -> Error.existence!("server_socket", sock)
        end

      other ->
        Error.type!("server_socket", other)
    end
  end
end
