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

  # --- unix(Pfad) -------------------------------------------------------------

  defp sock_file(name) do
    f = Path.join(System.tmp_dir!(), "pex_#{name}_#{System.unique_integer([:positive])}.sock")
    File.rm(f)
    f
  end

  defp q(f), do: PrologEx.format({:atom, f}, quoted: true)

  test "unix(Pfad): Verbindung, Client '', Datei weg nach dem Schließen", c do
    f = sock_file("u")

    assert ask(c, """
           socket_server_open(unix(#{q(f)}), S), socket_client_open(unix(#{q(f)}), C, []),
           socket_server_accept(S, Cl, SS, []),
           write(C, 'hallo.'), nl(C), flush_output(C), read(SS, T),
           write(SS, 'zurück.'), nl(SS), flush_output(SS), read(C, U),
           close(C), close(SS), S = '$socket'(N)
           """)
           |> Enum.map(&String.replace(&1, ~r/N = \d+/, "N = n")) == [
             "C = <stream>, Cl = '', N = n, S = <socket>, SS = <stream>, T = hallo, U = 'zurück'"
           ]

    # die Datei bleibt, solange der Server offen ist
    assert File.exists?(f)

    n =
      Process.get(:prolog_ex_server_sockets)
      |> Map.keys()
      |> Enum.filter(&is_integer/1)
      |> Enum.max()

    assert ask(c, "socket_server_close('$socket'(#{n}))") == ["true"]
    refute File.exists?(f)
  end

  test "unix(Pfad): vorhandene Datei, reuseaddr(true), relativer Pfad", c do
    f = sock_file("r")
    File.write!(f, "")

    assert err(c, "socket_server_open(unix(#{q(f)}), _)") == [
             "E = permission_error(open,source_sink,unix(#{q(f)}))"
           ]

    assert ask(
             c,
             "socket_server_open(unix(#{q(f)}), S, [reuseaddr(true)]), socket_server_close(S)"
           ) ==
             ["S = <socket>"]

    # relativ: ab dem aktuellen Verzeichnis
    dir = Path.dirname(f)
    name = Path.basename(sock_file("rel"))

    [ans] =
      File.cd!(dir, fn ->
        ask(c, "socket_server_open(unix(#{q(name)}), S), S = '$socket'(N)")
      end)

    assert File.exists?(Path.join(dir, name))
    [_, n] = Regex.run(~r/N = (\d+)/, ans)
    # anderswo geschlossen: die Datei des absoluten Pfads ist weg
    assert ask(c, "socket_server_close('$socket'(#{n}))") == ["true"]
    refute File.exists?(Path.join(dir, name))
  end

  test "unix(Pfad): Fehler", c do
    f = sock_file("weg")

    assert err(c, "socket_client_open(unix(#{q(f)}), _, [])") == [
             "E = existence_error(source_sink,unix(#{q(f)}))"
           ]

    assert err(c, "socket_client_open(unix(_), _, [])") == ["E = instantiation_error"]
    assert err(c, "socket_server_open(unix(_), _)") == ["E = instantiation_error"]

    assert err(c, "socket_client_open(unix(1), _, [])") == [
             "E = type_error(socket_address,unix(1))"
           ]

    assert err(c, "socket_server_open(unix(''), _)") == [
             "E = domain_error(socket_address,unix(''))"
           ]
  end

  # --- socket_select/7 --------------------------------------------------------

  test "socket_select/7: Server bereit, wenn eine Verbindung wartet", c do
    assert ask(c, """
           socket_server_open(P, S), socket_server_open(_, S2),
           socket_select([S, S2], R0, [], _, [], _, 0),
           socket_client_open(localhost:P, C, []),
           socket_select([a-S, b-S2], R1, [], _, [], _, off),
           socket_server_accept(S, Cl, SS, []),
           socket_select([S], R2, [], _, [], _, 0),
           close(C), close(SS), socket_server_close(S), socket_server_close(S2)
           """) == [
             "C = <stream>, Cl = '127.0.0.1', R0 = [], R1 = [a-<socket>], R2 = [], S = <socket>, " <>
               "S2 = <socket>, SS = <stream>"
           ]
  end

  test "socket_select/7: Annahme läuft schon (Timeout), accept holt die Verbindung", c do
    assert ask(c, """
           socket_server_open(P, S),
           socket_select([S], [], [], _, [], _, 0.05),
           socket_client_open(localhost:P, C, []),
           socket_server_accept(S, Cl, SS, []),
           write(C, 'x.'), nl(C), flush_output(C), read(SS, T),
           close(C), close(SS), socket_server_close(S)
           """) == ["C = <stream>, Cl = '127.0.0.1', S = <socket>, SS = <stream>, T = x"]

    # schließen, während die Annahme wartet bzw. schon angenommen hat
    assert ask(c, """
           socket_server_open(P, S), socket_select([S], _, [], _, [], _, 0),
           socket_client_open(localhost:P, C, []), socket_select([S], [_], [], _, [], _, off),
           socket_server_close(S), close(C),
           socket_server_open(_, S2), socket_select([S2], _, [], _, [], _, 0), socket_server_close(S2)
           """) == ["C = <stream>, S = <socket>, S2 = <socket>"]

    # der Annahme-Prozess ist beendet, im Postfach bleibt nichts liegen
    Process.sleep(50)
    assert Process.info(self(), :messages) == {:messages, []}
  end

  test "socket_select/7: Lesen bereit bei Daten, gepuffertem Rest und am Ende", c do
    assert ask(c, """
           #{@pair},
           socket_select([], _, [k-SS], R0, [], _, 0),
           write(C, 'eins. zwei.'), nl(C), flush_output(C),
           socket_select([], _, [k-SS], R1, [], _, off),
           read(SS, T1),
           socket_select([], _, [SS], R2, [], _, 0),
           read(SS, T2), get_char(SS, '\\n'),
           socket_select([], _, [SS], R3, [], _, 0),
           close(C),
           socket_select([], _, [SS], R4, [], _, off), get_char(SS, E),
           socket_select([], _, [SS], R5, [], _, off),
           close(SS), socket_server_close(S)
           """) == [
             "C = <stream>, Cl = '127.0.0.1', E = end_of_file, R0 = [], R1 = [k-<stream>], " <>
               "R2 = [<stream>], R3 = [], R4 = [<stream>], R5 = [<stream>], S = <socket>, SS = <stream>, " <>
               "T1 = eins, T2 = zwei"
           ]
  end

  test "socket_select/7: mehrere Streams, Reihenfolge; Schreiben und Dateien immer bereit", c do
    f = Path.join(System.tmp_dir!(), "pex_sel_#{System.unique_integer([:positive])}.txt")
    File.write!(f, "")

    assert ask(c, """
           #{@pair}, open(#{q(f)}, read, F),
           write(SS, 'a.'), nl(SS), flush_output(SS),
           socket_select([], _, [1-SS, 2-C, 3-F], R, [w-C, v-SS], W, off),
           close(F), close(C), close(SS), socket_server_close(S)
           """) == [
             "C = <stream>, Cl = '127.0.0.1', F = <stream>, R = [2-<stream>,3-<stream>], S = <socket>, " <>
               "SS = <stream>, W = [w-<stream>,v-<stream>]"
           ]
  after
    :ok
  end

  test "socket_select/7: mehrere bereit zugleich; nur Schreiben kehrt sofort zurück", c do
    [a] =
      ask(c, """
      socket_server_open(P, S), socket_server_open(Q, T),
      socket_client_open(localhost:P, C, []), socket_client_open(localhost:Q, D, []),
      socket_select([s-S, t-T], R, [], _, [], _, off),
      socket_server_accept(S, _, SS, []), socket_server_accept(T, _, TT, []),
      write(C, 'a.'), nl(C), flush_output(C), write(D, 'b.'), nl(D), flush_output(D),
      socket_select([], _, [1-SS, 2-TT], L, [], _, off),
      close(C), close(D), close(SS), close(TT), socket_server_close(S), socket_server_close(T)
      """)

    # Server: mindestens einer (Verbindungen kommen nebenläufig an)
    assert a =~ ~r/R = \[(s-<socket>|t-<socket>|s-<socket>,t-<socket>)\]/
    # Streams: alles, was bei der Rückkehr da ist
    assert a =~ "L = [1-<stream>,2-<stream>]"

    # bereit ist bereit: nicht auf die übrigen warten (off)
    for sel <- [
          "socket_select([], _, [], _, [C], [_], off)",
          "socket_select([], _, [SS], [], [C], [_], off)",
          "write(C, 'x.'), nl(C), flush_output(C), socket_select([], _, [SS], [_], [], _, off), " <>
            "socket_select([], _, [C, SS], [SS], [], _, off)"
        ] do
      {us, [_]} =
        :timer.tc(fn ->
          ask(c, "#{@pair}, #{sel}, close(C), close(SS), socket_server_close(S)")
        end)

      assert us < 500_000, sel
    end
  end

  test "socket_select/7: Timeout-Formen; abgelaufen sind alle Listen leer", c do
    for {t, ms} <- [{"0.2", 200}, {"0:200000", 200}, {"1:0", 1000}, {"1", 1000}] do
      {us, [a]} =
        :timer.tc(fn ->
          ask(
            c,
            "#{@pair}, socket_select([S], SR, [SS], RR, [], WR, #{t}), close(C), close(SS), socket_server_close(S)"
          )
        end)

      for l <- ["RR = []", "SR = []", "WR = []"], do: assert(a =~ l, t)
      assert us >= ms * 900 and us < ms * 1000 + 800_000, "#{t}: #{us} µs"
    end
  end

  test "socket_select/7: Fehler", c do
    for {g, e} <- [
          {"socket_select([], _, [], _, [], _, _)", "instantiation_error"},
          {"socket_select([], _, [], _, [], _, foo)", "domain_error(timeout,foo)"},
          {"socket_select([], _, [], _, [], _, -1)", "domain_error(timeout,-1)"},
          {"socket_select([], _, [], _, [], _, 1:(-1))", "domain_error(timeout,1: -1)"},
          {"socket_select([], _, [], _, [], _, _:1)", "instantiation_error"},
          {"socket_select([], _, foo, _, [], _, 0)", "type_error(list,foo)"},
          {"socket_select([], _, [user_input|_], _, [], _, 0)", "instantiation_error"},
          {"socket_select([], _, [user_output], _, [], _, 0)",
           "permission_error(input,stream,user_output)"},
          {"socket_select([], _, [], _, [user_input], _, 0)",
           "permission_error(output,stream,user_input)"},
          {"socket_select([foo], _, [], _, [], _, 0)", "type_error(server_socket,foo)"},
          {"socket_select([t-foo], _, [], _, [], _, 0)", "type_error(server_socket,foo)"}
        ] do
      assert err(c, g) == ["E = #{e}"], g
    end
  end
end
