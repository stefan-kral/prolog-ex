defmodule PrologEx.HttpServer do
  @moduledoc """
  HTTP/1.1-Server für `library(http/http_server)` (Gegenstück zu Scryers
  Warp-Anbindung), ohne Prolog: ein Acceptor-Prozess je Listener und ein
  Prozess je Verbindung. Die Verbindungen laufen parallel; jede Anfrage
  geht als Nachricht

      {:prolog_ex_http, listener_id, %{method:, path:, query:, headers:,
                                       body:, conn:, id:}}

  an den Prozess, der `listen/4` aufgerufen hat (die Prolog-Maschine), und
  die Verbindung wartet, bis `reply/5` die Antwort schickt. Die Maschine
  holt die Anfragen der Reihe nach ab (`'$http_accept'/7`), wie bei Scryer.

  Unterstützt: Keep-Alive (HTTP/1.1, `Connection: close` beendet),
  Rümpfe mit `Content-Length` oder `Transfer-Encoding: chunked`, Grenze
  für die Rumpfgröße (413), `Expect: 100-continue`, `HEAD` (ohne Rumpf),
  TLS mit Schlüssel und Zertifikat als PEM.
  """

  @head_limit 65_536
  @idle_ms 60_000

  @methods ~w(get post put delete patch head options trace connect)

  @doc """
  Lauschen auf `ip`:`port`. opts: `limit` (Bytes, Rumpf), `tls`
  (`{schlüssel_pem, zertifikat_pem}` oder nil). Ergebnis
  `{:ok, %{id, socket, transport, acceptor}}` oder `{:error, grund}`.
  """
  def listen(ip, port, opts) do
    tcp = [:binary, active: false, packet: :raw, reuseaddr: true, ip: ip]

    listened =
      case Keyword.get(opts, :tls) do
        nil ->
          {:gen_tcp, :gen_tcp.listen(port, tcp)}

        {key, cert} ->
          :ok = ensure_ssl()
          {:ssl, :ssl.listen(port, tcp ++ tls_opts(key, cert))}
      end

    case listened do
      {transport, {:ok, sock}} ->
        owner = self()
        id = System.unique_integer([:positive])
        limit = Keyword.get(opts, :limit, 32_768)

        acceptor =
          spawn(fn ->
            Process.monitor(owner)
            accept_loop(transport, sock, owner, id, limit)
          end)

        {:ok, %{id: id, socket: sock, transport: transport, acceptor: acceptor}}

      {_, {:error, reason}} ->
        {:error, reason}
    end
  end

  @doc "Lauschen beenden (laufende Verbindungen beenden ihre Anfrage)"
  def stop(%{socket: sock, transport: t, acceptor: a}) do
    t.close(sock)
    Process.exit(a, :kill)
    :ok
  end

  @doc "Antwort auf Anfrage `id` an die Verbindung `conn`"
  def reply(conn, id, code, headers, body) do
    send(conn, {:prolog_ex_http_reply, id, code, headers, body})
    :ok
  end

  # --- TLS ----------------------------------------------------------------

  defp ensure_ssl do
    case Application.ensure_all_started(:ssl) do
      {:ok, _} -> :ok
      {:error, e} -> raise "ssl: #{inspect(e)}"
    end
  end

  # PEM-Text (wie Scryer); ein Dateiname geht auch
  defp tls_opts(key, cert) do
    [{:Certificate, cert_der, _} | _] =
      cert |> pem() |> :public_key.pem_decode() |> Enum.filter(&(elem(&1, 0) == :Certificate))

    [{type, key_der, _} | _] = key |> pem() |> :public_key.pem_decode()
    [cert: cert_der, key: {type, key_der}]
  end

  defp pem(text) do
    if String.contains?(text, "-----BEGIN"), do: text, else: File.read!(text)
  end

  # --- Annehmen -------------------------------------------------------------

  defp accept_loop(transport, lsock, owner, id, limit) do
    accepted =
      case transport do
        :gen_tcp -> :gen_tcp.accept(lsock)
        :ssl -> :ssl.transport_accept(lsock)
      end

    case accepted do
      {:ok, sock} ->
        pid = spawn(fn -> connection(transport, owner, id, limit) end)
        :ok = transport.controlling_process(sock, pid)
        send(pid, {:go, sock})
        accept_loop(transport, lsock, owner, id, limit)

      {:error, :closed} ->
        :ok

      {:error, _} ->
        accept_loop(transport, lsock, owner, id, limit)
    end
  end

  defp connection(transport, owner, id, limit) do
    sock =
      receive do
        {:go, s} -> s
      end

    Process.monitor(owner)

    # TLS: Handshake hier, nicht im Acceptor (ein langsamer Client hält
    # sonst alle auf)
    sock =
      if transport == :ssl do
        case :ssl.handshake(sock, @idle_ms) do
          {:ok, s} -> s
          _ -> exit(:normal)
        end
      else
        sock
      end

    serve(%{t: transport, sock: sock, owner: owner, lid: id, limit: limit}, "")
    transport.close(sock)
  end

  # --- Eine Verbindung: Anfragen nacheinander --------------------------------

  defp serve(c, buf) do
    with {:ok, head, rest} <- read_head(c, buf),
         {:ok, req} <- parse_head(head) do
      case read_body(c, req, rest) do
        {:ok, body, rest} ->
          rid = System.unique_integer([:positive])
          req = %{req | body: body}

          msg = Map.take(req, [:method, :path, :query, :headers, :body])
          send(c.owner, {:prolog_ex_http, c.lid, Map.merge(msg, %{conn: self(), id: rid})})

          receive do
            {:prolog_ex_http_reply, ^rid, code, headers, body} ->
              keep = keep_alive?(req)
              write_response(c, req, code, headers, body, keep)
              if keep, do: serve(c, rest)

            {:DOWN, _, :process, _, _} ->
              :ok
          end

        {:error, :too_large} ->
          write_response(c, req, 413, [], "", false)

        {:error, _} ->
          :ok
      end
    else
      {:error, :bad_request} -> write_response(c, %{method: "get"}, 400, [], "Bad Request", false)
      {:error, :head_too_large} -> write_response(c, %{method: "get"}, 431, [], "", false)
      {:error, _} -> :ok
    end
  end

  defp read_head(c, buf) do
    case :binary.split(buf, "\r\n\r\n") do
      [head, rest] ->
        {:ok, head, rest}

      [_] when byte_size(buf) > @head_limit ->
        {:error, :head_too_large}

      [_] ->
        case recv(c, 0) do
          {:ok, data} -> read_head(c, buf <> data)
          e -> e
        end
    end
  end

  defp parse_head(head) do
    [line | lines] = String.split(head, "\r\n")

    case String.split(line, " ") do
      [method, target, "HTTP/" <> version] ->
        {path, query} =
          case :binary.split(target, "?") do
            [p, q] -> {p, q}
            [p] -> {p, ""}
          end

        headers =
          for l <- lines,
              l != "",
              [k, v] = :binary.split(l, ":"),
              do: {String.downcase(String.trim(k)), String.trim(v)}

        m = String.downcase(method)

        {:ok,
         %{
           method: if(m in @methods, do: m, else: "unsupported_extension"),
           path: path,
           query: query,
           headers: headers,
           version: version,
           body: ""
         }}

      _ ->
        {:error, :bad_request}
    end
  rescue
    MatchError -> {:error, :bad_request}
  end

  defp header(req, name) do
    Enum.find_value(req.headers, fn {k, v} -> if k == name, do: v end)
  end

  defp read_body(c, req, rest) do
    te = header(req, "transfer-encoding")
    cl = header(req, "content-length")

    cond do
      te != nil and String.downcase(te) =~ "chunked" ->
        continue(c, req)
        read_chunks(c, rest, [], 0)

      cl != nil ->
        case Integer.parse(cl) do
          {n, ""} when n > c.limit ->
            {:error, :too_large}

          {n, ""} when n >= 0 ->
            continue(c, req)
            read_exact(c, rest, n)

          _ ->
            {:error, :bad_request}
        end

      true ->
        {:ok, "", rest}
    end
  end

  # curl & Co. warten bei größeren Rümpfen auf "100 Continue"
  defp continue(c, req) do
    if (header(req, "expect") || "") |> String.downcase() == "100-continue",
      do: c.t.send(c.sock, "HTTP/1.1 100 Continue\r\n\r\n")
  end

  defp read_exact(_c, buf, n) when byte_size(buf) >= n do
    {body, rest} = :erlang.split_binary(buf, n)
    {:ok, body, rest}
  end

  defp read_exact(c, buf, n) do
    case recv(c, 0) do
      {:ok, data} -> read_exact(c, buf <> data, n)
      e -> e
    end
  end

  defp read_chunks(c, buf, acc, size) do
    case :binary.split(buf, "\r\n") do
      [line, rest] ->
        {n, _} = Integer.parse(hd(String.split(line, ";")), 16)

        cond do
          n == 0 ->
            # Trailer bis zur Leerzeile überspringen
            case read_head(c, "\r\n" <> rest) do
              {:ok, _trailer, rest} -> {:ok, IO.iodata_to_binary(Enum.reverse(acc)), rest}
              e -> e
            end

          size + n > c.limit ->
            {:error, :too_large}

          true ->
            with {:ok, chunk, rest} <- read_exact(c, rest, n + 2) do
              read_chunks(c, rest, [binary_part(chunk, 0, n) | acc], size + n)
            end
        end

      [_] ->
        case recv(c, 0) do
          {:ok, data} -> read_chunks(c, buf <> data, acc, size)
          e -> e
        end
    end
  end

  defp recv(c, n), do: c.t.recv(c.sock, n, @idle_ms)

  defp keep_alive?(req) do
    conn = String.downcase(header(req, "connection") || "")

    case req.version do
      "1.1" -> conn != "close"
      _ -> conn == "keep-alive"
    end
  end

  defp write_response(c, req, code, headers, body, keep) do
    names = for {k, _} <- headers, do: String.downcase(k)

    extra =
      [
        if("content-length" not in names,
          do: {"content-length", Integer.to_string(byte_size(body))}
        ),
        if(not keep and "connection" not in names, do: {"connection", "close"})
      ]
      |> Enum.reject(&is_nil/1)

    head = [
      "HTTP/1.1 ",
      Integer.to_string(code),
      " ",
      reason(code),
      "\r\n",
      for({k, v} <- headers ++ extra, do: [k, ": ", v, "\r\n"]),
      "\r\n"
    ]

    c.t.send(c.sock, if(req.method == "head", do: head, else: [head, body]))
  end

  @reasons %{
    100 => "Continue",
    200 => "OK",
    201 => "Created",
    202 => "Accepted",
    204 => "No Content",
    301 => "Moved Permanently",
    302 => "Found",
    303 => "See Other",
    304 => "Not Modified",
    307 => "Temporary Redirect",
    308 => "Permanent Redirect",
    400 => "Bad Request",
    401 => "Unauthorized",
    403 => "Forbidden",
    404 => "Not Found",
    405 => "Method Not Allowed",
    409 => "Conflict",
    413 => "Payload Too Large",
    415 => "Unsupported Media Type",
    422 => "Unprocessable Content",
    429 => "Too Many Requests",
    431 => "Request Header Fields Too Large",
    500 => "Internal Server Error",
    501 => "Not Implemented",
    502 => "Bad Gateway",
    503 => "Service Unavailable"
  }

  defp reason(code), do: Map.get(@reasons, code, "Status")
end
