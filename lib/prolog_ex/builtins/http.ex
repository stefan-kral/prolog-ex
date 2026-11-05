defmodule PrologEx.Builtins.Http do
  @moduledoc """
  Interne Prädikate für `library(http/http_open)` und
  `library(http/http_server)` (Prolog-Quelltext in priv/library/http/,
  nach Scryer Prolog). Bei Scryer stecken sie in Rust (reqwest, Warp);
  hier über `:httpc` (OTP) und `PrologEx.HttpServer`.

    * `'$http_open'(+Adresse, -Stream, +Methode, -Status, +Daten,
      -Header, +AnfrageHeader)` – Anfrage; Stream liest den Rumpf
      (Text, UTF-8; kein gültiges UTF-8: Bytes). Scheitert, wenn keine
      Antwort kommt (wie Scryer).
    * `'$http_listen'(+Adresse, -Listener, +TlsSchlüssel, +TlsZertifikat,
      +Grenze)`, `'$http_listen_stop'(+Listener)`
    * `'$http_accept'(+Listener, -Methode, -Pfad, -Header, -Query, -Stream,
      -Antwort)` – wartet auf die nächste Anfrage
    * `'$http_answer'(+Antwort, +Status, +Header, -Stream)` (Binärstream
      wie Scryer) und `'$http_answer'/5` mit Typ `text`/`binary`; `close/1`
      schickt die Antwort
    * `'$http_send_file'(+Antwort, +Status, +Header, +Datei)`,
      `'$http_put_byte_chars'(+Stream, +Bytes)`,
      `'$http_parse_query'(+Zeichen, -Paare)`, `'$http_utf8_chars'(+Bytes,
      -Zeichen)` – Hilfen der Bibliothek (in Scryer: library(crypto), clpz)

  Header sind Terme `name(Wert)` mit Namen in Kleinbuchstaben (Atom) und
  Wert als Zeichenliste, wie bei Scryer. Netzwerkzugriffe sind äußere
  Wirkungen (`PrologEx.Effects`): der Toplevel rechnet sie nie voraus.
  """
  use PrologEx.Builtin
  alias PrologEx.{Effects, Error, HttpServer}
  alias PrologEx.Stream, as: S

  @profile :prolog_ex

  # --- Client -------------------------------------------------------------

  defbuiltin "$http_open", [address, stream, method, code, data, headers, req_headers] do
    Effects.external!()
    s = subst()
    url = text!(address, s)
    m = String.to_atom(atom_name!(method, s))
    hs = header_terms!(req_headers, s)
    body = data_bytes(PrologEx.Store.walk(data, s), s)
    profile!()

    {ct, hs} =
      case List.keytake(hs, "content-type", 0) do
        {{_, v}, rest} -> {v, rest}
        nil -> {"", hs}
      end

    hs = for {k, v} <- hs, do: {String.to_charlist(k), String.to_charlist(v)}
    u = String.to_charlist(url)

    # :httpc will bei post, put, patch immer einen Rumpf (auch leer)
    request =
      if m in [:post, :put, :patch] or (m == :delete and (body != "" or ct != "")),
        do: {u, hs, String.to_charlist(ct), body},
        else: {u, hs}

    case :httpc.request(m, request, http_opts(url), [body_format: :binary], @profile) do
      {:ok, {{_, status, _}, rhs, rbody}} ->
        type = if String.valid?(rbody), do: :text, else: :binary
        id = S.open_memory(rbody, type)

        rterms =
          for {k, v} <- rhs,
              do: mk(String.downcase(List.to_string(k)), [chars(List.to_string(v))])

        {:unify, [{stream, S.term(id)}, {code, status}, {headers, list(rterms)}]}

      {:error, _} ->
        :fail
    end
  end

  defp profile! do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    case :inets.start(:httpc, profile: @profile) do
      {:ok, _} -> :httpc.set_options(proxy_opts(), @profile)
      {:error, {:already_started, _}} -> :ok
    end
  end

  # Proxy aus der Umgebung, wie reqwest (Scryers HTTP-Client)
  defp proxy_opts do
    no =
      (env("NO_PROXY") || "") |> String.split(",", trim: true) |> Enum.map(&String.to_charlist/1)

    for {opt, var} <- [proxy: "HTTP_PROXY", https_proxy: "HTTPS_PROXY"],
        url = env(var),
        %URI{host: h, port: p} when is_binary(h) <- [URI.parse(url)],
        do: {opt, {{String.to_charlist(h), p}, no}}
  end

  defp env(name), do: System.get_env(name) || System.get_env(String.downcase(name))

  # HTTPS: Zertifikat und Rechnername prüfen; Zertifikate des Systems oder
  # aus SSL_CERT_FILE (wie OpenSSL und reqwest)
  defp http_opts("https" <> _) do
    cas =
      case System.get_env("SSL_CERT_FILE") do
        nil -> [cacerts: :public_key.cacerts_get()]
        file -> [cacertfile: String.to_charlist(file)]
      end

    [
      autoredirect: true,
      ssl:
        [
          verify: :verify_peer,
          depth: 10,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ] ++ cas
    ]
  end

  defp http_opts(_), do: [autoredirect: true]

  defp data_bytes([], _s), do: ""
  defp data_bytes(d, s), do: text!(d, s)

  # --- Server -------------------------------------------------------------

  defbuiltin "$http_listen", [address, listener, key, cert, limit] do
    Effects.external!()
    s = subst()

    with {:ok, ip, port} <- host_port(text!(address, s)) do
      tls =
        case {text!(key, s), text!(cert, s)} do
          {"", _} -> nil
          {_, ""} -> nil
          kc -> kc
        end

      case HttpServer.listen(ip, port, tls: tls, limit: int!(limit, s)) do
        {:ok, info} ->
          Process.put({:prolog_ex_http_listener, info.id}, info)
          {:unify, [{listener, mk("$http_listener", [info.id])}]}

        {:error, _} ->
          :fail
      end
    else
      _ -> :fail
    end
  end

  defbuiltin "$http_listen_stop", [listener] do
    Effects.external!()
    id = listener_id!(listener, subst())

    case Process.delete({:prolog_ex_http_listener, id}) do
      nil -> :ok
      info -> HttpServer.stop(info)
    end

    :ok
  end

  defbuiltin "$http_accept", [listener, method, path, headers, query, stream, handle] do
    Effects.external!()
    id = listener_id!(listener, subst())

    receive do
      {:prolog_ex_http, ^id, req} ->
        h = System.unique_integer([:positive])
        Process.put({:prolog_ex_http_handle, h}, {req.conn, req.id})
        body = S.open_memory(req.body, :binary)

        {:unify,
         [
           {method, a(req.method)},
           {path, chars(req.path)},
           {headers, list(for {k, v} <- req.headers, do: mk(k, [chars(v)]))},
           {query, chars(req.query)},
           {stream, S.term(body)},
           {handle, mk("$http_handle", [h])}
         ]}
    end
  end

  defbuiltin "$http_answer", [handle, code, headers, stream] do
    answer(handle, code, headers, stream, :binary, subst())
  end

  defbuiltin "$http_answer", [handle, code, headers, type, stream] do
    t =
      case atom_name!(type, subst()) do
        "text" -> :text
        "binary" -> :binary
        _ -> Error.domain!("stream_type", resolve(type))
      end

    answer(handle, code, headers, stream, t, subst())
  end

  defp answer(handle, code, headers, stream, type, s) do
    {conn, rid} = take_handle!(handle, s)
    st = status!(code, s)
    hs = header_terms!(headers, s)
    id = S.open_http_out(fn body -> HttpServer.reply(conn, rid, st, hs, body) end, type)
    {:unify, [{stream, S.term(id)}]}
  end

  # Datei als Rumpf: erst lesen (fehlt sie, existence_error vor jeder
  # Antwort), dann auf einmal schicken
  defbuiltin "$http_send_file", [handle, code, headers, file] do
    s = subst()
    name = text!(file, s)

    case File.read(name) do
      {:ok, body} ->
        {conn, rid} = take_handle!(handle, s)
        HttpServer.reply(conn, rid, status!(code, s), header_terms!(headers, s), body)
        :ok

      {:error, _} ->
        Error.existence!("source_sink", resolve(file))
    end
  end

  # Zeichen mit Codes 0..255 als Bytes ausgeben (bytes(B) eines Rumpfs)
  defbuiltin "$http_put_byte_chars", [stream, cs] do
    s = subst()
    id = S.lookup!(PrologEx.Store.walk(stream, s))

    bin =
      for c <- items!(cs, s), into: <<>> do
        case c do
          {:atom, <<b::utf8>>} when b < 256 -> <<b>>
          other -> Error.type!("byte", other)
        end
      end

    S.put_bytes(id, bin)
    :ok
  end

  # "a=1&b=x+y%C3%A4" → [a-"1", b-"x yä"] (Schlüssel und Werte als
  # Zeichenlisten, www-form-Kodierung: + ist ein Leerzeichen)
  defbuiltin "$http_parse_query", [cs, pairs] do
    q = text!(cs, subst())

    ps =
      for part <- String.split(q, "&", trim: true) do
        {k, v} =
          case :binary.split(part, "=") do
            [k, v] -> {k, v}
            [k] -> {k, ""}
          end

        mk("-", [chars(form_decode(k)), chars(form_decode(v))])
      end

    {:unify, [{pairs, list(ps)}]}
  end

  # Bytes (als Zeichen 0..255) → Zeichen nach UTF-8; kein gültiges UTF-8:
  # die Bytes selbst
  defbuiltin "$http_utf8_chars", [bytes, cs] do
    bin = for {:atom, <<b::utf8>>} <- items!(bytes, subst()), into: <<>>, do: <<b>>
    text = if String.valid?(bin), do: bin, else: for(<<b <- bin>>, into: "", do: <<b::utf8>>)
    {:unify, [{cs, chars(text)}]}
  end

  defp form_decode(t) do
    t = String.replace(t, "+", " ")

    decoded =
      try do
        URI.decode(t)
      rescue
        ArgumentError -> t
      end

    if String.valid?(decoded), do: decoded, else: t
  end

  # --- Hilfen ---------------------------------------------------------------

  defp take_handle!(handle, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(handle, s)) do
      {:struct, "$http_handle", [h]} ->
        case Process.delete({:prolog_ex_http_handle, h}) do
          nil -> Error.existence!("http_response", PrologEx.resolve(handle, s))
          v -> v
        end

      {:var, _} ->
        Error.instantiation!()

      other ->
        Error.domain!("http_response", PrologEx.resolve(other, s))
    end
  end

  defp listener_id!(l, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(l, s)) do
      {:struct, "$http_listener", [id]} -> id
      {:var, _} -> Error.instantiation!()
      other -> Error.domain!("http_listener", PrologEx.resolve(other, s))
    end
  end

  defp host_port(text) do
    with [host, port] <- String.split(text, ":", parts: 2),
         {p, ""} <- Integer.parse(port),
         {:ok, ip} <- :inet.getaddr(String.to_charlist(host), :inet) do
      {:ok, ip, p}
    else
      _ -> :error
    end
  end

  defp status!(code, s) do
    case PrologEx.Store.walk(code, s) do
      n when is_integer(n) and n >= 100 and n <= 999 -> n
      {:var, _} -> Error.instantiation!()
      n when is_integer(n) -> Error.domain!("http_status", n)
      other -> Error.type!("integer", PrologEx.resolve(other, s))
    end
  end

  defp int!(t, s) do
    case PrologEx.Store.walk(t, s) do
      n when is_integer(n) -> n
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("integer", PrologEx.resolve(other, s))
    end
  end

  defp atom_name!(t, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(t, s)) do
      {:atom, n} -> n
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("atom", PrologEx.resolve(other, s))
    end
  end

  # [name(Wert), ...] → [{"name", "wert"}]
  defp header_terms!(l, s) do
    for h <- items!(l, s) do
      case PrologEx.unmark_top(PrologEx.Store.walk(h, s)) do
        {:struct, name, [v]} -> {String.downcase(name), text!(v, s)}
        {:var, _} -> Error.instantiation!()
        other -> Error.type!("http_header", PrologEx.resolve(other, s))
      end
    end
  end

  defp items!(l, s) do
    case PrologEx.Builtins.Lists.skip_list(l, s) do
      {_, []} -> PrologEx.Builtins.Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  # Zeichenliste, Codeliste oder Atom → Binary
  defp text!(t, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(t, s)) do
      {:atom, n} ->
        n

      [] ->
        ""

      {:var, _} ->
        Error.instantiation!()

      _ ->
        for c <- items!(t, s), into: "" do
          case PrologEx.Store.walk(c, s) do
            {:atom, <<_::utf8>> = ch} -> ch
            n when is_integer(n) and n >= 0 -> <<n::utf8>>
            {:var, _} -> Error.instantiation!()
            other -> Error.type!("character", PrologEx.resolve(other, s))
          end
        end
    end
  end

  defp chars(text), do: list(for <<c::utf8 <- text>>, do: a(<<c::utf8>>))
end
