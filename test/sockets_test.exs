defmodule PrologEx.SocketsTest do
  # library(sockets) wie SICStus (current_hostname/1 wie Scryer)
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
          ":- use_module(library(sockets)).\n:- use_module(library(iso_ext)).\n" <>
            ":- use_module(library(between)).\n"
        )
      )

    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    |> Enum.map(&String.replace(&1, ~r/'\$(stream|socket)'\(\d+\)/, "<\\1>"))
    |> Enum.map(&String.replace(&1, ~r/P = \d+, /, ""))
  end

  defp err(c, goal), do: ask(c, "catch((#{goal}), error(E, _), true)")

  # Server, Client und angenommene Verbindung in einer Sitzung (der Kernel
  # nimmt die Verbindung schon vor dem accept an)
  @pair "socket_server_open(P, S), socket_client_open(localhost:P, C, []), " <>
          "socket_server_accept(S, Cl, SS, [])"

  test "Verbindung: beide Richtungen auf einem Stream, Client ohne Port", c do
    assert ask(c, """
           #{@pair},
           write(C, 'hallo.'), nl(C), flush_output(C), read(SS, T),
           write(SS, 'zurück.'), nl(SS), flush_output(SS), read(C, U),
           close(C), close(SS), socket_server_close(S)
           """) == [
             "C = <stream>, Cl = '127.0.0.1', S = <socket>, SS = <stream>, T = hallo, U = 'zurück'"
           ]
  end

  test "Stream-Eigenschaften: input und output, Text, nicht positionierbar", c do
    [a] =
      ask(c, """
      #{@pair},
      findall(X, (stream_property(SS, X), X \\= position(_)), L),
      close(C), close(SS), socket_server_close(S)
      """)

    for p <- ~w[input output mode(read_write) type(text) reposition(false) eof_action(eof_code)
                end_of_stream(not)],
        do: assert(a =~ p, p)

    refute a =~ "file_name"
  end

  test "binär; Optionen alias/1, eof_action/1", c do
    assert ask(c, """
           socket_server_open(P, S), socket_client_open(localhost:P, C, [type(binary), alias(k)]),
           socket_server_accept(S, _, SS, [type(binary), eof_action(error)]),
           put_byte(k, 200), put_byte(k, 7), flush_output(k), get_byte(SS, A), get_byte(SS, B),
           close(k), get_byte(SS, E),
           catch(get_byte(SS, _), error(F, _), true),
           close(SS), socket_server_close(S)
           """) == [
             "A = 200, B = 7, C = <stream>, E = -1, F = permission_error(input,past_end_of_stream,<stream>), S = <socket>, SS = <stream>"
           ]
  end

  test "Gegenseite geschlossen: Lesen end_of_file, Senden socket_error", c do
    assert ask(c, """
           #{@pair}, close(C), get_char(SS, X), close(SS), socket_server_close(S)
           """)
           |> hd() =~ "X = end_of_file"

    # Senden, wenn die Gegenseite weg ist: spätestens nach einigen Paketen
    [a] =
      ask(c, """
      #{@pair}, close(SS),
      catch(forall(between(1, 200, _), (write(C, xxxxxxxx), flush_output(C))), error(E, _), true),
      socket_server_close(S)
      """)

    assert a =~ "E = socket_error("
  end

  test "Server: freier Port, fester Port, belegt, reuseaddr, loopback, Dienstname", c do
    assert ask(c, "socket_server_open(P, S), integer(P), P > 0, socket_server_close(S)") ==
             ["S = <socket>"]

    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)

    assert ask(c, "socket_server_open(#{port}, S), socket_server_close(S)") == ["S = <socket>"]

    assert ask(c, "socket_server_open('':#{port}, S), socket_server_close(S)") == ["S = <socket>"]

    assert ask(c, "socket_server_open(inet('127.0.0.1', #{port}), S), socket_server_close(S)") ==
             ["S = <socket>"]

    assert err(c, "socket_server_open(P, S), socket_server_open(P, _)") |> hd() =~
             "E = permission_error(open,source_sink,"

    # nach einer Verbindung, die der Server zuerst schließt (TIME_WAIT):
    # wieder öffnen geht nur mit reuseaddr(true)
    assert ask(c, """
           socket_server_open(P, S, [reuseaddr(true)]),
           socket_client_open(localhost:P, C, []), socket_server_accept(S, _, SS, []),
           close(SS), get_char(C, _), close(C), socket_server_close(S),
           socket_server_open(P, S2, [reuseaddr(true)]), socket_server_close(S2)
           """)
           |> length() == 1

    # Client mit leerem Rechnernamen: dieser Rechner
    assert ask(c, """
           socket_server_open(P, S), socket_client_open('':P, C, []),
           socket_server_accept(S, _, SS, []), close(C), close(SS), socket_server_close(S)
           """)
           |> length() == 1

    assert ask(c, """
           socket_server_open(P, S, [loopback(true)]),
           socket_client_open('127.0.0.1':P, C, []), socket_server_accept(S, Cl, SS, []),
           close(C), close(SS), socket_server_close(S)
           """)
           |> hd() =~ "Cl = '127.0.0.1'"

    # loopback(true): von außen nicht erreichbar
    {:ok, ifs} = :inet.getifaddrs()

    case for {_, o} <- ifs, {:addr, {a, _, _, _} = ip} <- o, a != 127, do: ip do
      [ip | _] ->
        host = PrologEx.format({:atom, to_string(:inet.ntoa(ip))}, quoted: true)

        assert err(
                 c,
                 "socket_server_open(P, S, [loopback(true)]), socket_client_open(#{host}:P, _, [])"
               )
               |> hd() =~ "E = existence_error(source_sink,"

        assert ask(c, """
               socket_server_open(P, S), socket_client_open(#{host}:P, C, []),
               socket_server_accept(S, _, SS, []), close(C), close(SS), socket_server_close(S)
               """)
               |> length() == 1

      [] ->
        :ok
    end

    # Dienstname und Port als Ziffernatom
    assert err(c, "socket_client_open(localhost:'1', _, [])") ==
             ["E = existence_error(source_sink,localhost:'1')"]

    # Dienstname aus /etc/services (http: 80); ob dort jemand lauscht, ist egal
    refute err(c, "socket_client_open(localhost:http, C, []), close(C)") |> hd() =~ "domain_error"

    assert err(c, "socket_client_open(localhost:gibts_nicht_xyz, _, [])") ==
             ["E = domain_error(socket_address,localhost:gibts_nicht_xyz)"]
  end

  test "accept wartet auf eine Verbindung", c do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)

    spawn(fn ->
      Process.sleep(300)
      {:ok, s} = :gen_tcp.connect(~c"localhost", port, [])
      Process.sleep(500)
      :gen_tcp.close(s)
    end)

    {us, ans} =
      :timer.tc(fn ->
        ask(
          c,
          "socket_server_open(#{port}, S), socket_server_accept(S, Cl, SS, []), close(SS), socket_server_close(S)"
        )
      end)

    assert hd(ans) =~ "Cl = '127.0.0.1'"
    assert us > 250_000
  end

  test "gegen einen Echo-Server in Elixir; Umlaute (UTF-8)", c do
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(l)

    # liest eine ganze Zeile und schickt sie mit "echo_" davor zurück
    spawn(fn ->
      {:ok, s} = :gen_tcp.accept(l)
      line = recv_line(s, "")
      :gen_tcp.send(s, "echo_" <> line)
      :gen_tcp.close(s)
      :gen_tcp.close(l)
    end)

    assert ask(c, """
           socket_client_open(localhost:#{port}, C, []), write(C, 'grüß.'), nl(C),
           flush_output(C), read(C, T), get_char(C, N), get_char(C, E), close(C)
           """) == ["C = <stream>, E = end_of_file, N = '\\n', T = 'echo_grüß'"]
  end

  defp recv_line(s, acc) do
    if String.contains?(acc, "\n") do
      acc
    else
      {:ok, data} = :gen_tcp.recv(s, 0)
      recv_line(s, acc <> data)
    end
  end

  test "Fehler", c do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)

    # abgelehnt / unbekannter Rechner: Fehler
    assert err(c, "socket_client_open(localhost:#{port}, _, [])") ==
             ["E = existence_error(source_sink,localhost:#{port})"]

    assert err(c, "socket_client_open('gibts.invalid':80, _, [])") ==
             ["E = existence_error(source_sink,'gibts.invalid':80)"]

    assert err(c, "socket_client_open(_, _, [])") == ["E = instantiation_error"]
    assert err(c, "socket_client_open(localhost:_, _, [])") == ["E = instantiation_error"]
    assert err(c, "socket_client_open(foo, _, [])") == ["E = type_error(socket_address,foo)"]
    assert err(c, "socket_client_open(1:2, _, [])") == ["E = type_error(socket_address,1:2)"]

    assert err(c, "socket_client_open(localhost:99999, _, [])") ==
             ["E = domain_error(socket_address,localhost:99999)"]

    assert err(c, "socket_client_open(localhost:1, x, [])") == ["E = uninstantiation_error(x)"]

    assert err(c, "socket_client_open(localhost:1, _, [foo])") == [
             "E = domain_error(stream_option,foo)"
           ]

    assert err(c, "socket_client_open(localhost:1, _, x)") == ["E = type_error(list,x)"]

    assert err(c, "socket_client_open(localhost:1, _, [reposition(true)])") ==
             ["E = permission_error(open,source_sink,reposition(true))"]

    assert err(c, "socket_server_open(P, _, [foo])") == ["E = domain_error(socket_option,foo)"]
    assert err(c, "socket_server_open(P, _, [loopback(_)])") == ["E = instantiation_error"]
    assert err(c, "socket_server_open(P, x)") == ["E = uninstantiation_error(x)"]
    assert err(c, "socket_server_open(f(x), _)") == ["E = type_error(socket_address,f(x))"]

    assert err(c, "socket_server_open(nohost:P, _, [numeric_nodename(true)])") |> hd() =~
             "E = domain_error(socket_address,nohost:"

    assert err(c, "socket_server_open(http, _, [numeric_servname(true)])") ==
             ["E = domain_error(socket_address,http)"]

    assert err(c, "socket_server_accept(foo, _, _, [])") == ["E = type_error(server_socket,foo)"]
    assert err(c, "socket_server_accept(_, _, _, [])") == ["E = instantiation_error"]

    assert err(c, "socket_server_open(_, S), socket_server_close(S), socket_server_close(S)") ==
             ["E = existence_error(server_socket,<socket>)"]

    assert err(
             c,
             "socket_server_open(_, S), socket_server_close(S), socket_server_accept(S, _, _, [])"
           ) ==
             ["E = existence_error(server_socket,<socket>)"]
  end

  test "current_host/1 (SICStus), current_hostname/1 (Scryer)", c do
    {:ok, short} = :inet.gethostname()

    assert ask(c, "current_hostname(H)") == [
             "H = #{PrologEx.format({:atom, to_string(short)}, quoted: true)}"
           ]

    assert ask(c, "current_host(H), atom(H)") |> length() == 1

    assert ask(
             c,
             "current_host(#{PrologEx.format({:atom, String.downcase(to_string(short))}, quoted: true)})"
           ) == ["true"]

    assert ask(c, "current_host(gibts_nicht_als_name)") == []
  end

  test "äußere Wirkungen: im Vorausrechnen des Toplevels nicht ausgeführt", c do
    PrologEx.Effects.speculative!()

    try do
      assert catch_throw(ask(c, "socket_server_open(_, _)")) == :prolog_ex_speculative_abort

      assert catch_throw(ask(c, "socket_client_open(localhost:1, _, [])")) ==
               :prolog_ex_speculative_abort
    after
      Process.delete(:speculative_lookahead)
    end
  end
end
