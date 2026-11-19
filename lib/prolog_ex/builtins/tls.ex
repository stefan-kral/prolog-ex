defmodule PrologEx.Builtins.Tls do
  @moduledoc """
  Grundlagen für `library(tls)` (priv/library/tls.pl, aus Scryer Prolog):
  ein Socket-Stream aus `library(sockets)` wird über `:ssl` zu einem
  TLS-Stream. Der neue Stream hat Typ und `eof_action` des alten; der
  alte ist danach geschlossen (sein Socket gehört nun dem TLS-Stream).

  Client: Zertifikat gegen die CAs des Systems (`:public_key.cacerts_get/0`)
  oder die aus `cacertfile(F)` geprüft, dazu der Rechnername (auch
  Platzhalter wie `*.example.org`, über SNI gesendet). Ohne Rechnernamen
  nur die Kette – wie Scryer (native-tls mit leerem Namen).

  Server: Zertifikat (mit Kette) und Schlüssel als PEM-Dateien, statt
  Scryers PKCS#12, das OTP nicht lesen kann; ein verschlüsselter Schlüssel
  mit `password(Ps)`. Die Dateien werden bei jeder Verbindung neu gelesen
  (ein erneuertes Zertifikat gilt sofort) und schon beim Anlegen des
  Kontexts geprüft.

  Fehler wie Scryer: Aushandeln gescheitert →
  `permission_error(open, source_sink, Host)` (Client) bzw. `…, S0)`
  (Server).
  """
  use PrologEx.Builtin
  alias PrologEx.{Effects, Error, Store}
  alias PrologEx.Builtins.Lists
  alias PrologEx.Stream, as: S

  # Zeichenliste als Text
  defp text(t, s) do
    for x <- Lists.items(t, s), into: "" do
      {:atom, c} = Store.walk(x, s)
      c
    end
  end

  # Dateiname (Atom oder Zeichen)
  defp file(t, s), do: PrologEx.Builtins.Modules.file_name(PrologEx.resolve(t, s))

  defp ssl! do
    {:ok, _} = Application.ensure_all_started(:ssl)
    :ok
  end

  # Socket-Stream S0 (Stream oder Alias)
  defp socket_stream!(t, s) do
    t = Store.walk(t, s)
    id = S.lookup!(t)
    if S.get(id).kind != :socket, do: Error.domain!("socket_stream", PrologEx.resolve(t, s))
    id
  end

  defp read!(f) do
    case File.read(f) do
      {:ok, text} -> text
      {:error, :enoent} -> Error.existence!("source_sink", a(f))
      {:error, _} -> Error.permission!("open", "source_sink", a(f))
    end
  end

  # --- Client ----------------------------------------------------------------

  # '$tls_client_connect'(Host, CA, S0, S): CA = [] (die des Systems) oder
  # eine PEM-Datei
  defbuiltin "$tls_client_connect", [host, ca, s0, stream] do
    s = subst()
    name = text(host, s)

    cacerts =
      case Store.walk(ca, s) do
        [] -> system_cacerts()
        _ -> pem_certs(read!(file(ca, s)), file(ca, s))
      end

    id = socket_stream!(s0, s)
    Effects.external!()
    ssl!()
    {sock, opts} = S.take_socket(id)

    sni =
      if name == "",
        do: [server_name_indication: :disable],
        else: [
          server_name_indication: String.to_charlist(name),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]

    tls =
      [mode: :binary, active: false, verify: :verify_peer, cacerts: cacerts, log_level: :none] ++
        sni

    case :ssl.connect(sock, tls, :infinity) do
      {:ok, t} ->
        {:unify, [{stream, S.term(S.open_socket(t, opts))}]}

      {:error, _} ->
        S.transport(sock).close(sock)
        Error.permission!("open", "source_sink", PrologEx.resolve(host, s))
    end
  end

  defp system_cacerts do
    :public_key.cacerts_get()
  rescue
    _ -> []
  end

  # --- Server ----------------------------------------------------------------

  # '$tls_server_context'(Cert, Key, Password): die Dateien vorab prüfen
  defbuiltin "$tls_server_context", [cert, key, pw] do
    s = subst()
    server_opts(file(cert, s), file(key, s), text(pw, s))
    :ok
  end

  # '$tls_accept_client'(Cert, Key, Password, S0, S)
  defbuiltin "$tls_accept_client", [cert, key, pw, s0, stream] do
    s = subst()
    tls = server_opts(file(cert, s), file(key, s), text(pw, s))
    id = socket_stream!(s0, s)
    Effects.external!()
    ssl!()
    {sock, opts} = S.take_socket(id)

    case :ssl.handshake(sock, [mode: :binary, active: false, log_level: :none] ++ tls, :infinity) do
      {:ok, t} ->
        {:unify, [{stream, S.term(S.open_socket(t, opts))}]}

      {:error, _} ->
        S.transport(sock).close(sock)
        Error.permission!("open", "source_sink", PrologEx.resolve(s0, s))
    end
  end

  # Zertifikat mit Kette und Schlüssel als Optionen für :ssl
  defp server_opts(cert_file, key_file, pw) do
    certs = pem_certs(read!(cert_file), cert_file)

    keys =
      for {type, _, _} = e <- :public_key.pem_decode(read!(key_file)),
          type in [:RSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo, :DSAPrivateKey],
          do: e

    key =
      case keys do
        [e | _] -> decode_key(e, pw, key_file)
        [] -> Error.domain!("pem_private_key", a(key_file))
      end

    [cert: certs, key: key]
  end

  defp decode_key({type, der, :not_encrypted}, _pw, _f), do: {type, der}

  defp decode_key({_, _, _} = e, pw, f) do
    k = :public_key.pem_entry_decode(e, String.to_charlist(pw))
    {elem(k, 0), :public_key.der_encode(elem(k, 0), k)}
  rescue
    _ -> Error.domain!("pem_private_key", a(f))
  end

  defp pem_certs(text, f) do
    case for {:Certificate, der, _} <- :public_key.pem_decode(text), do: der do
      [] -> Error.domain!("pem_certificates", a(f))
      ders -> ders
    end
  end
end
