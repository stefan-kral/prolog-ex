defmodule PrologEx.HttpTest do
  # library(http/http_server) und library(http/http_open) wie bei Scryer
  # Prolog: der Server läuft in einem eigenen Prozess (eigene Maschine),
  # der Client im Testprozess; nur über 127.0.0.1
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag timeout: 120_000

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)

    {db, []} =
      PrologEx.Consult.load(
        PrologEx.use_library(%{}, "lists"),
        Reader.read_terms(
          c.reader,
          ":- use_module(library(http/http_open)).\n:- use_module(library(charsio)).\n"
        )
      )

    PrologEx.put_db(db)
    :ok
  end

  @server_src """
  :- use_module(library(http/http_server)).
  :- use_module(library(lists)).
  :- use_module(library(charsio)).

  text_handler(_, Response) :-
      http_status_code(Response, 200),
      http_body(Response, text("Welcome to Scryer Prolog! äöü")).
  root(_, Response) :- http_body(Response, text("root")).
  user(User, _, Response) :- http_body(Response, text(User)).
  echo(Request, Response) :- http_body(Request, text(T)), http_body(Response, text(T)).
  echo_bytes(Request, Response) :- http_body(Request, bytes(B)), http_body(Response, bytes(B)).
  form(Request, Response) :-
      http_body(Request, form(F)),
      write_term_to_chars(F, [quoted(true)], Cs),
      http_body(Response, text(Cs)).
  query(Request, Response) :-
      findall(K-V, http_query(Request, K, V), L),
      write_term_to_chars(L, [quoted(true)], Cs),
      http_body(Response, text(Cs)).
  hdrs(Request, Response) :-
      http_headers(Request, H),
      ( member("x-test"-V, H) -> true ; V = "fehlt" ),
      http_headers(Response, ["x-antwort"-V, "content-type"-"text/plain; charset=utf-8"]),
      http_status_code(Response, 201),
      http_body(Response, text(V)).
  redirect(_, Response) :- http_redirect(Response, "/echo").
  file(F, _, Response) :- http_body(Response, file(F)).
  fails(_, _) :- fail.
  boom(_, _) :- X is 1 / 0, X > 0.
  login(User, Pass) :- User = "anna", Pass = "geheim".
  inside(Data, User, _, Response) :-
      append(Data, [' '|User], T),
      http_body(Response, text(T)).
  any(Path, _, Response) :- http_body(Response, text(Path)).
  val(_, Response, S) :- http_body(Response, text(S)).
  inc(_, Response, S0, S) :- S = ['I'|S0], http_body(Response, text(S)).

  handlers([
      get(/, root),
      get(echo, text_handler),
      post(user/User, user(User)),
      post(echo, echo),
      post(bytes, echo_bytes),
      post(form, form),
      get(query, query),
      get(hdrs, hdrs),
      get(redirect, redirect),
      get(datei, file(_F)),
      get(fails, fails),
      get(boom, boom),
      get(geheim, http_basic_auth(login, inside("drin:"))),
      get(val, val),
      get(inc, inc),
      get(a/b/c, root),
      get(P, any(P))
  ]).

  run(P, Opts) :- handlers(H0), ( member(file(F), Opts) -> true ; F = none ),
      maplist(set_file(F), H0, H),
      select_opts(Opts, Os),
      http_listen(P, H, Os).
  set_file(F, get(datei, file(_)), get(datei, file(F))) :- !.
  set_file(_, H, H).
  select_opts(Opts, Os) :- findall(O, (member(O, Opts), O \\= file(_)), Os).
  """

  # Server in eigenem Prozess; wartet, bis er lauscht; Ausgabe geschluckt
  defp server(c, opts \\ "[]") do
    port = 20_000 + :rand.uniform(20_000)
    parent = self()

    pid =
      spawn(fn ->
        {:ok, io} = StringIO.open("")
        Process.group_leader(self(), io)
        Reader.put_current(c.reader)
        {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, @server_src))
        PrologEx.put_db(db)
        [{:term, g, _}] = Reader.read_terms(c.reader, "run(#{port}, #{opts}).")

        result =
          try do
            PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
          rescue
            e in PrologEx.Error -> {:error, Exception.message(e)}
          end

        send(parent, {:server_ended, self(), result})
      end)

    wait_listening(port, 100)
    on_exit(fn -> Process.exit(pid, :kill) end)
    %{port: port, pid: pid}
  end

  defp wait_listening(_port, 0), do: flunk("Server lauscht nicht")

  defp wait_listening(port, n) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 100) do
      {:ok, s} ->
        :gen_tcp.close(s)

      _ ->
        Process.sleep(20)
        wait_listening(port, n - 1)
    end
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(1)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  # GET/POST mit http_open: {Status, Rumpf als Atom}
  defp req(c, srv, path, opts \\ "") do
    q =
      ~s|http_open("http://127.0.0.1:#{srv.port}#{path}", _S, [status_code(C)#{opts}]), | <>
        ~s|get_n_chars(_S, _, _B), atom_chars(A, _B), close(_S)|

    case ask(c, q) do
      [a] ->
        [_, code] = Regex.run(~r/C = (\d+)/, a)
        [_, body] = Regex.run(~r/^A = (.*), C = \d+$/, a)
        {String.to_integer(code), body}

      [] ->
        :fail
    end
  end

  # rohe Anfrage über TCP: Antwort als Text
  defp raw(port, text) do
    {:ok, s} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    :ok = :gen_tcp.send(s, text)
    out = recv_all(s, "")
    :gen_tcp.close(s)
    out
  end

  defp recv_all(s, acc) do
    case :gen_tcp.recv(s, 0, 2000) do
      {:ok, d} -> recv_all(s, acc <> d)
      _ -> acc
    end
  end

  test "GET: Text, Status, Größe, UTF-8; Wurzel; Pfadparameter; Muster", c do
    srv = server(c)
    assert req(c, srv, "/echo") == {200, "'Welcome to Scryer Prolog! äöü'"}
    assert req(c, srv, "/") == {200, "root"}
    assert req(c, srv, "/user/alice", ", method(post)") == {200, "alice"}
    assert req(c, srv, "/a/b/c") == {200, "root"}
    # Variable als Muster: der ganze Pfad
    assert req(c, srv, "/irgend/wo") == {200, "'/irgend/wo'"}

    # size/1: Content-Length als Zahl, auch ohne headers/1
    [a] = ask(c, ~s|http_open("http://127.0.0.1:#{srv.port}/echo", S, [size(N)]), close(S)|)
    assert a =~ "N = 32"
  end

  test "POST: Text und Bytes zurück, Formular, Query", c do
    srv = server(c)
    assert req(c, srv, "/echo", ~s|, method(post), data("hallo äö")|) == {200, "'hallo äö'"}
    assert req(c, srv, "/echo", ", method(post)") == {200, "''"}

    # Bytes: über TCP, damit auch 0 und 255 durchgehen
    out =
      raw(
        srv.port,
        "POST /bytes HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nConnection: close\r\n\r\n" <>
          <<0, 255, 10, 65>>
      )

    assert out =~ "HTTP/1.1 200 OK"
    assert String.ends_with?(out, <<0, 255, 10, 65>>)

    form = ~s|, method(post), data("a=1&b=x+y%C3%A4"), request_headers(['content-type'("CT")])|
    expected = {200, ~s|'[[a]-[\\'1\\'],[b]-[x,\\' \\',y,\\'ä\\']]'|}

    assert req(c, srv, "/form", String.replace(form, "CT", "application/x-www-form-urlencoded")) ==
             expected

    assert req(
             c,
             srv,
             "/form",
             String.replace(form, "CT", "application/x-www-form-urlencoded; charset=utf-8")
           ) ==
             expected

    # Schlüssel und Werte als Zeichenlisten, + und %XX (UTF-8) dekodiert;
    # ohne "=" ein leerer Wert
    assert req(c, srv, "/query?a=1&b=x+y%C3%A4&c") ==
             {200, ~s|'[[a]-[\\'1\\'],[b]-[x,\\' \\',y,\\'ä\\'],[c]-[]]'|}

    # anderer Content-Type: kein Formular, der Handler scheitert (500,
    # danach endet der Server)
    assert {500, _} = req(c, srv, "/form", String.replace(form, "CT", "text/plain"))
  end

  test "Header in beide Richtungen, eigener Status, Weiterleitung", c do
    srv = server(c)

    [a] =
      ask(
        c,
        ~s|http_open("http://127.0.0.1:#{srv.port}/hdrs", S, [status_code(C), headers(H), request_headers(['x-test'("hallo")])]), member('x-antwort'(V), H), member('content-type'(T), H), close(S)|
      )

    assert a =~ ~s|C = 201|
    assert a =~ ~s|V = "hallo"|
    assert a =~ ~s|T = "text/plain; charset=utf-8"|
    # 307 mit Location: http_open folgt (wie reqwest bei Scryer)
    assert req(c, srv, "/redirect") == {200, "'Welcome to Scryer Prolog! äöü'"}
    out = raw(srv.port, "GET /redirect HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    assert out =~ "HTTP/1.1 307 Temporary Redirect"
    assert out =~ ~r/\r\nlocation: \/echo\r\n/i
  end

  test "404, Handler scheitert oder wirft: 500, dann endet der Server (wie Scryer)", c do
    srv = server(c)
    assert req(c, srv, "/nix/da/oben/x") == {200, "'/nix/da/oben/x'"}
    out = raw(srv.port, "DELETE /echo HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    assert out =~ "HTTP/1.1 404 Not Found"
    assert out =~ "\r\n\r\nNot Found"
    assert req(c, srv, "/boom") == {500, "'Internal Server Error'"}
    assert_receive {:server_ended, _, {:error, msg}}, 5000
    assert msg =~ "evaluation_error(zero_divisor)"

    srv = server(c)
    assert req(c, srv, "/fails") == {500, "'Internal Server Error'"}
    assert_receive {:server_ended, _, {:error, _}}, 5000
  end

  test "catch_errors(true): nach einem Fehler geht es weiter", c do
    srv = server(c, "[catch_errors(true)]")
    assert req(c, srv, "/boom") == {500, "'Internal Server Error'"}
    assert req(c, srv, "/echo") == {200, "'Welcome to Scryer Prolog! äöü'"}
    refute_received {:server_ended, _, _}
  end

  test "Zustand: initial_state, lesend und schreibend", c do
    srv = server(c, ~s|[initial_state("I")]|)
    assert req(c, srv, "/val") == {200, "'I'"}
    assert req(c, srv, "/inc") == {200, "'II'"}
    assert req(c, srv, "/inc") == {200, "'III'"}
    assert req(c, srv, "/val") == {200, "'III'"}
  end

  test "Datei als Rumpf; fehlende Datei: 500", c do
    path = Path.join(System.tmp_dir!(), "prolog_ex_http_#{:rand.uniform(1_000_000)}.bin")
    File.write!(path, <<0, 1, 2, 255>> <> "ende")
    on_exit(fn -> File.rm(path) end)
    srv = server(c, ~s|[file("#{path}")]|)
    out = raw(srv.port, "GET /datei HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    assert out =~ "content-length: 8"
    assert String.ends_with?(out, <<0, 1, 2, 255>> <> "ende")

    srv = server(c, ~s|[file("/gibt/es/nicht"), catch_errors(true)]|)
    assert req(c, srv, "/datei") == {500, "'Internal Server Error'"}
  end

  test "HTTP Basic Auth", c do
    srv = server(c)
    out = raw(srv.port, "GET /geheim HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    assert out =~ "HTTP/1.1 401 Unauthorized"
    assert out =~ ~s|www-authenticate: Basic realm="Scryer Prolog"|

    auth = fn up -> ~s|, request_headers([authorization("Basic #{Base.encode64(up)}")])| end
    assert req(c, srv, "/geheim", auth.("anna:falsch")) == {401, "'Unauthorized'"}
    assert req(c, srv, "/geheim", auth.("anna:geheim")) == {200, "'drin: anna'"}
  end

  test "Grenze für den Rumpf: 413; HEAD ohne Rumpf", c do
    srv = server(c, "[content_length_limit(10)]")

    assert req(c, srv, "/echo", ~s|, method(post), data("kurz")|) == {200, "kurz"}

    assert {413, _} =
             req(c, srv, "/echo", ~s|, method(post), data("viel zu lang für die Grenze")|)

    # HEAD: eigene Methode wie bei Scryer (kein head-Handler: 404), aber
    # ohne Rumpf, die Länge steht trotzdem da
    out = raw(srv.port, "HEAD /echo HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    assert out =~ "HTTP/1.1 404 Not Found"
    assert out =~ "content-length: 9"
    assert out =~ "connection: close"
    assert String.ends_with?(out, "\r\n\r\n")

    # Rumpf in Stücken über der Grenze: 413
    out =
      raw(
        srv.port,
        "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n" <>
          "8\r\n12345678\r\n8\r\n12345678\r\n0\r\n\r\n"
      )

    assert out =~ "HTTP/1.1 413 Payload Too Large"
  end

  test "Keep-Alive, chunked, 100-continue, kaputte Anfrage", c do
    srv = server(c)
    {:ok, s} = :gen_tcp.connect(~c"127.0.0.1", srv.port, [:binary, active: false])
    :ok = :gen_tcp.send(s, "GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    {:ok, a} = :gen_tcp.recv(s, 0, 2000)
    assert a =~ "HTTP/1.1 200 OK" and String.ends_with?(a, "root")
    # dieselbe Verbindung, Rumpf in Stücken
    :ok =
      :gen_tcp.send(
        s,
        "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n" <>
          "3\r\nabc\r\n4\r\ndefg\r\n0\r\n\r\n"
      )

    b = recv_all(s, "")
    assert b =~ "HTTP/1.1 200 OK"
    assert String.ends_with?(b, "abcdefg")
    :gen_tcp.close(s)

    {:ok, s} = :gen_tcp.connect(~c"127.0.0.1", srv.port, [:binary, active: false])

    :ok =
      :gen_tcp.send(
        s,
        "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nExpect: 100-continue\r\nConnection: close\r\n\r\n"
      )

    {:ok, cont} = :gen_tcp.recv(s, 0, 2000)
    assert cont == "HTTP/1.1 100 Continue\r\n\r\n"
    :ok = :gen_tcp.send(s, "ok")
    assert String.ends_with?(recv_all(s, ""), "ok")

    assert raw(srv.port, "Unsinn\r\n\r\n") =~ "HTTP/1.1 400 Bad Request"
    # der Server läuft weiter
    assert req(c, srv, "/") == {200, "root"}
  end

  test "Verbindungen parallel: ein langsamer Client hält die anderen nicht auf", c do
    srv = server(c)
    {:ok, slow} = :gen_tcp.connect(~c"127.0.0.1", srv.port, [:binary, active: false])
    :ok = :gen_tcp.send(slow, "GET / HTTP/1.1\r\nHost: x\r\n")
    assert req(c, srv, "/echo") == {200, "'Welcome to Scryer Prolog! äöü'"}
    :ok = :gen_tcp.send(slow, "Connection: close\r\n\r\n")
    assert String.ends_with?(recv_all(slow, ""), "root")
  end

  test "http_open: Fehler und Optionen wie Scryer", c do
    # keine Antwort: scheitert
    assert ask(c, ~s|http_open("http://127.0.0.1:1/", _, [])|) == []

    assert ask(c, ~s|catch(http_open("http://x/", _, [method(M)]), error(E, _), true)|) ==
             ["E = instantiation_error"]

    assert ask(c, ~s|catch(http_open("http://x/", _, [method(fetch)]), error(E, _), true)|) ==
             ["E = domain_error(http_option,method(fetch))"]

    # Port belegt: http_listen scheitert (wie Scryer)
    srv = server(c)
    me = self()

    spawn(fn ->
      {:ok, io} = StringIO.open("")
      Process.group_leader(self(), io)
      Reader.put_current(c.reader)
      {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, @server_src))
      PrologEx.put_db(db)
      [{:term, g, _}] = Reader.read_terms(c.reader, "run(#{srv.port}, []).")
      send(me, {:zweiter, PrologEx.query(db, g) |> Enum.take(1)})
    end)

    assert_receive {:zweiter, []}, 5000
  end

  test "interne Prädikate: Annehmen, Antworten (einmal), Beenden", c do
    port = 20_000 + :rand.uniform(20_000)
    me = self()

    pid =
      spawn(fn ->
        Reader.put_current(c.reader)

        {db, []} =
          PrologEx.Consult.load(
            %{},
            Reader.read_terms(
              c.reader,
              ":- use_module(library(lists)).\n:- use_module(library(charsio)).\n"
            )
          )

        PrologEx.put_db(db)

        q =
          ~s|'$http_listen'("127.0.0.1:#{port}", L, "", "", 100), | <>
            ~s|'$http_accept'(L, M, P, Hs, Q, In, H), get_n_chars(In, _, B), | <>
            ~s|'$http_answer'(H, 202, ['x-a'("1")], text, S), write(S, ok), close(S), | <>
            ~s|catch('$http_answer'(H, 200, [], _), error(E, _), true), '$http_listen_stop'(L)|

        [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")
        [ans] = PrologEx.query(db, g) |> Enum.take(1)
        send(me, {:fertig, PrologEx.format_answer(ans, ["M", "P", "Q", "B", "E", "Hs"])})
        # weiterleben: der Socket gehört diesem Prozess, erst '$http_listen_stop'
        # muss ihn schließen
        receive do
          :ende -> :ok
        end
      end)

    wait_listening(port, 100)

    out =
      raw(
        port,
        "PUT /a/b?x=1 HTTP/1.1\r\nHost: h\r\nX-Eins: Wert\r\nContent-Length: 2\r\nConnection: close\r\n\r\nhi"
      )

    assert out =~ "HTTP/1.1 202 Accepted"
    assert out =~ "x-a: 1"
    assert String.ends_with?(out, "ok")
    assert_receive {:fertig, a}, 5000
    assert a =~ ~s|B = "hi"|
    assert a =~ ~s|M = put, P = "/a/b", Q = "x=1"|
    assert a =~ ~s|E = existence_error(http_response,'$http_handle'(|
    assert a =~ ~s|'x-eins'("Wert")|
    # nach '$http_listen_stop' lauscht niemand mehr
    assert {:error, :econnrefused} = :gen_tcp.connect(~c"127.0.0.1", port, [], 500)
    send(pid, :ende)
  end

  @tag :tls
  test "HTTPS: Server mit Schlüssel und Zertifikat (PEM), Client prüft", c do
    dir = Path.join(System.tmp_dir!(), "prolog_ex_tls_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    key = Path.join(dir, "key.pem")
    cert = Path.join(dir, "cert.pem")
    ca = Path.join(dir, "ca.pem")
    # eigene CA, die das Server-Zertifikat unterschreibt (ein selbst
    # signiertes Server-Zertifikat lehnt OTPs TLS ab, auch als Anker)
    ssl = fn args -> {_, 0} = System.cmd("openssl", args, stderr_to_stdout: true, cd: dir) end

    ssl.(
      ~w(req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=TestCA -keyout ca.key -out ca.pem)
    )

    ssl.(~w(req -newkey rsa:2048 -nodes -subj /CN=localhost -keyout key.pem -out srv.csr))
    File.write!(Path.join(dir, "ext.cnf"), "subjectAltName=DNS:localhost,IP:127.0.0.1\n")

    ssl.(
      ~w(x509 -req -in srv.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 1 -extfile ext.cnf -out cert.pem)
    )

    pem = fn f -> f |> File.read!() |> String.replace("\n", "\\n") end
    srv = server(c, ~s|[tls_key("#{pem.(key)}"), tls_cert("#{pem.(cert)}")]|)

    old = System.get_env("SSL_CERT_FILE")
    System.put_env("SSL_CERT_FILE", ca)

    on_exit(fn ->
      if old, do: System.put_env("SSL_CERT_FILE", old), else: System.delete_env("SSL_CERT_FILE")
    end)

    q = fn host ->
      ask(
        c,
        ~s|http_open("https://#{host}:#{srv.port}/echo", S, [status_code(C)]), get_n_chars(S, _, B), atom_chars(A, B)|
      )
    end

    [a] = q.("localhost")
    assert a =~ "C = 200"
    assert a =~ "Welcome to Scryer Prolog! äöü"

    # Weiterleitung auch über HTTPS
    [a] =
      ask(
        c,
        ~s|http_open("https://localhost:#{srv.port}/redirect", S, [status_code(C)]), get_n_chars(S, _, B), atom_chars(A, B)|
      )

    assert a =~ "C = 200"
    assert a =~ "Welcome"
    # unbekannte CA (nur die Zertifikate des Systems): scheitert (neue
    # Verbindung: :httpc hält die erste offen)
    System.delete_env("SSL_CERT_FILE")
    assert q.("127.0.0.1") == []

    # auch als Dateiname (Erweiterung)
    srv2 = server(c, ~s|[tls_key("#{key}"), tls_cert("#{cert}")]|)
    System.put_env("SSL_CERT_FILE", ca)

    [a] =
      ask(
        c,
        ~s|http_open("https://localhost:#{srv2.port}/", S, []), get_n_chars(S, _, B), atom_chars(A, B)|
      )

    assert a =~ "A = root"
  end
end
