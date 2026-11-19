defmodule PrologEx.TlsTest do
  # library(tls) aus Scryer: Client und Server über library(sockets), die
  # Gegenseite mit :ssl in Elixir; Zertifikate von
  # :public_key.pkix_test_data/1 (Wurzel, Zwischen-CA, Server für localhost)
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(
          r,
          ":- use_module(library(sockets)).\n:- use_module(library(tls)).\n" <>
            ":- use_module(library(lists)).\n"
        )
      )

    # wie heute üblich (TLS 1.3 lehnt die Vorgaben ab)
    k = [digest: :sha256, key: {:namedCurve, :secp256r1}]
    san = [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]

    data =
      :public_key.pkix_test_data(%{
        server_chain: %{root: k, intermediates: [k], peer: [{:extensions, san} | k]},
        client_chain: %{root: k, intermediates: [], peer: k}
      })

    {:ok, reader: r, db: db, data: data}
  end

  setup c do
    Reader.put_current(c.reader)
    srv = c.data[:server_config]
    cli = c.data[:client_config]
    {kt, kder} = srv[:key]
    dir = c.tmp_dir

    pem = fn name, entries ->
      f = Path.join(dir, name)
      File.write!(f, :public_key.pem_encode(entries))
      f
    end

    # Zertifikat, dahinter die Kette (Zwischen-CA); Schlüssel auch
    # verschlüsselt (Passwort geheim)
    chain = for der <- chain(srv), do: {:Certificate, der, :not_encrypted}
    key = :public_key.der_decode(kt, kder)

    enc =
      :public_key.pem_entry_encode(
        kt,
        key,
        {{~c"AES-128-CBC", :crypto.strong_rand_bytes(16)}, ~c"geheim"}
      )

    files = %{
      cert: pem.("cert.pem", chain),
      key: pem.("key.pem", [{kt, kder, :not_encrypted}]),
      enckey: pem.("enc.pem", [enc]),
      ca: pem.("ca.pem", for(der <- cli[:cacerts], do: {:Certificate, der, :not_encrypted}))
    }

    {:ok, files: files, srv: srv, cli: cli}
  end

  # Server-Zertifikat und Zwischen-CA (cacerts enthält auch die Wurzeln)
  defp chain(srv),
    do: [srv[:cert] | Enum.reject(srv[:cacerts], &:public_key.pkix_is_self_signed/1)]

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  # Elixir-Server: eine Verbindung, liest einen Term, antwortet echo(Term).
  defp elixir_server(c) do
    {:ok, l} =
      :ssl.listen(0, [
        :binary,
        active: false,
        reuseaddr: true,
        log_level: :none,
        cert: chain(c.srv),
        key: c.srv[:key]
      ])

    {:ok, {_, port}} = :ssl.sockname(l)

    spawn_link(fn ->
      {:ok, t} = :ssl.transport_accept(l)

      case :ssl.handshake(t, 5000) do
        {:ok, s} ->
          {:ok, data} = :ssl.recv(s, 0, 5000)
          :ok = :ssl.send(s, "echo(" <> String.trim_trailing(String.trim(data), ".") <> ").\n")
          :ssl.close(s)

        {:error, _} ->
          :ok
      end

      :ssl.close(l)
    end)

    port
  end

  defp context(opts),
    do: "atom_chars(localhost, H), tls_client_context(Ctx, [hostname(H)#{opts}])"

  test "Client: Zertifikat und Name geprüft, ein Term hin und zurück", c do
    port = elixir_server(c)

    assert ask(c, """
           #{context(", cacertfile('#{c.files.ca}')")},
           socket_client_open(localhost:#{port}, S0, []),
           tls_client_negotiate(Ctx, S0, S),
           write(S, 'frage(1).'), nl(S), flush_output(S),
           socket_select([], _, [S], R, [], _, 5), length(R, NR),
           read(S, T), read(S, E), close(S),
           catch(write(S0, x), error(Alt, _), true)
           """)
           |> hd() =~
             ~r/^Alt = existence_error\(stream,.*E = end_of_file, .*NR = 1, .*T = echo\(frage\(1\)\)$/
  end

  test "Client ohne Rechnernamen: nur die Kette (wie Scryer)", c do
    port = elixir_server(c)

    assert [a] =
             ask(c, """
             tls_client_context(Ctx, [cacertfile('#{c.files.ca}')]),
             socket_client_open(localhost:#{port}, S0, []),
             tls_client_negotiate(Ctx, S0, S),
             write(S, 'x.'), nl(S), flush_output(S), read(S, T), close(S)
             """)

    assert a =~ "T = echo(x)"
  end

  test "Client: falscher Name oder unbekannte CA – permission_error", c do
    port = elixir_server(c)

    assert [a] =
             ask(c, """
             atom_chars('example.org', H),
             tls_client_context(Ctx, [hostname(H), cacertfile('#{c.files.ca}')]),
             socket_client_open(localhost:#{port}, S0, []),
             catch(tls_client_negotiate(Ctx, S0, _), error(E, _), true)
             """)

    assert a =~ ~S'E = permission_error(open,source_sink,"example.org")'

    port = elixir_server(c)

    assert [a] =
             ask(c, """
             #{context("")},
             socket_client_open(localhost:#{port}, S0, []),
             catch(tls_client_negotiate(Ctx, S0, _), error(E, _), true)
             """)

    assert a =~ ~S'E = permission_error(open,source_sink,"localhost")'
  end

  # Prolog-Server, Elixir-Client (versucht es, bis der Server lauscht)
  defp elixir_client(c, port) do
    me = self()

    spawn_link(fn ->
      opts = [
        :binary,
        active: false,
        verify: :verify_peer,
        cacerts: c.cli[:cacerts],
        server_name_indication: ~c"localhost",
        log_level: :none
      ]

      s = connect(port, opts, 100)
      :ok = :ssl.send(s, "frage(2).\n")
      send(me, {:antwort, recv_all(s, "")})
    end)
  end

  defp recv_all(s, acc) do
    case :ssl.recv(s, 0, 5000) do
      {:ok, data} -> recv_all(s, acc <> data)
      {:error, _} -> acc
    end
  end

  defp connect(port, opts, n) do
    case :ssl.connect(~c"localhost", port, opts, 5000) do
      {:ok, s} ->
        s

      {:error, _} when n > 0 ->
        Process.sleep(20)
        connect(port, opts, n - 1)
    end
  end

  defp free_port do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, p} = :inet.port(l)
    :gen_tcp.close(l)
    p
  end

  for {name, key} <- [{"Schlüssel offen", :key}, {"Schlüssel verschlüsselt", :enckey}] do
    test "Server mit PEM-Dateien, #{name}", c do
      port = free_port()
      elixir_client(c, port)

      pw =
        if unquote(key) == :enckey,
          do: ", atom_chars(geheim, Pw), Opt = [password(Pw)]",
          else: ", Opt = []"

      assert [a] =
               ask(c, """
               true#{pw},
               append([certfile('#{c.files.cert}'), keyfile('#{c.files[unquote(key)]}')], Opt, Os),
               tls_server_context(Ctx, Os),
               socket_server_open(#{port}, Srv),
               socket_server_accept(Srv, _, S0, []),
               tls_server_negotiate(Ctx, S0, S),
               read(S, T), write(S, antwort(T)), write(S, '.'), nl(S), flush_output(S),
               close(S), socket_server_close(Srv)
               """)

      assert a =~ "T = frage(2)"
      assert_receive {:antwort, "antwort(frage(2)).\n"}, 5000
    end
  end

  test "Server-Kontext: Fehler früh", c do
    assert [a] = ask(c, "catch(tls_server_context(_, []), error(E, _), true)")
    assert a =~ "E = domain_error(contains_certfile,[])"

    assert [a] = ask(c, "catch(tls_server_context(_, [certfile(nix)]), error(E, _), true)")
    assert a =~ "E = existence_error(source_sink,nix)"

    # Schlüssel fehlt in der Zertifikatsdatei
    assert [a] =
             ask(
               c,
               "catch(tls_server_context(_, [certfile('#{c.files.cert}')]), error(E, _), true)"
             )

    assert a =~ "E = domain_error(pem_private_key,"

    # falsches Passwort
    assert [a] =
             ask(c, """
             atom_chars(falsch, Pw),
             catch(tls_server_context(_, [certfile('#{c.files.cert}'), keyfile('#{c.files.enckey}'),
                                         password(Pw)]), error(E, _), true)
             """)

    assert a =~ "E = domain_error(pem_private_key,"
  end
end
