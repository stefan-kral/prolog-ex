/* library(tls) aus Scryer Prolog (src/lib/tls.pl, Stand b7066b41, BSD-3-Clause,
   siehe SCRYER-LICENSE). Geändert (mit "PrologEx" markiert): der Client
   nimmt zusätzlich cacertfile(Datei); der Server nimmt Zertifikat und
   Schlüssel als PEM-Dateien (certfile/1, keyfile/1) statt PKCS#12, das
   OTP nicht lesen kann. Die $-Prädikate liefert PrologEx.Builtins.Tls
   (über :ssl).                                                            */

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Negotiation of TLS connections.
   Written Dec. 2021 by Markus Triska (triska@metalevel.at)
   Part of Scryer Prolog.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- module(tls, [tls_client_context/2,   % -Context, +Options
                tls_client_negotiate/3, % +Context, +Stream0, -Stream
                tls_server_context/2,   % -Context, +Options
                tls_server_negotiate/3  % +Context, +Stream0, -Stream
               ]).

:- use_module(library(lists)).
:- use_module(library(error)).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   TLS Clients
   ===========

   Use tls_client_context/2 to create a TLS context, for example with:

   tls_client_context(Context, [hostname("metalevel.at")])

   Using the context and an existing stream S0 (for example, the
   result of socket_client_open/3), a TLS stream S can be negotiated
   with:

   tls_client_negotiate(Context, S0, S)

   S will be an encrypted and authenticated stream with the server.

   The advantage of separating the creation of the client context from
   negotiating a connection is that the context can be created only once,
   and quickly reused if needed. This is currently not implemented: In
   the present implementation, a new internal "Connector" is created for
   every connection, using the specified hostname.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

tls_client_context(tls_context(Host, CA), Options) :-
        must_be(list, Options),
        (   member(hostname(Host), Options) ->
            must_be(chars, Host)
        ;   Host = ""
        ),
        % PrologEx: cacertfile(F) – nur den CAs aus F (PEM) vertrauen
        (   member(cacertfile(CA), Options) ->
            '$tls_file'(CA)
        ;   CA = []
        ).

tls_client_negotiate(tls_context(Host, CA), S0, S) :-
        '$tls_client_connect'(Host, CA, S0, S).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   TLS Servers
   ===========

   Use tls_server_context/2 to create a TLS context, for example with:

   tls_server_context(Context, [pkcs12(Chars)])

   (PrologEx: instead tls_server_context(Context, [certfile("cert.pem"),
   keyfile("key.pem")]) – see the note at the top of this file.)

   where Chars is a list of characters with the contents of a
   DER-formatted PKCS #12 archive. The option password(Ps) can be used
   to specify the password Ps (also a string) for decrypting the key.
   On some versions of OSX, and potentially also on other platforms,
   empty passwords are not supported.

   The archive should contain a leaf certificate and its private key,
   as well any intermediate certificates that should be sent to
   clients to allow them to build a chain to a trusted root. The chain
   certificates should be in order from the leaf certificate towards
   the root.

   PKCS #12 archives typically have the file extension .p12 or .pfx,
   and can be created with the OpenSSL pkcs12 tool:

   $ openssl pkcs12 -export -out identity.pfx \
                    -inkey key.pem -in cert.pem -certfile chain_certs.pem


   You can use phrase_from_file/3 from library(pio) and seq//1 from
   library(dcgs) to read the contents of "identity.pfx" into a string:

   phrase_from_file(seq(Chars), "identity.pfx", [type(binary)])

   The obtained context should be treated as an opaque Prolog term.

   Using the context and an existing stream S0 (for example, the
   result of socket_server_accept/4), a TLS stream S can be negotiated
   by a Prolog-based server with:

   tls_server_negotiate(Context, S0, S)

   S will be an encrypted and authenticated stream with the client.

   The advantage of separating the creation of the server context from
   negotiating a connection is that the context can be created only
   once, and quickly cloned for every incoming connection. This is
   currently not implemented: In the present implementation, a new context
   is created for every connection, using the specified parameters.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

% PrologEx: certfile(F) mit dem Zertifikat (und der Kette dahinter),
% keyfile(K) mit dem Schlüssel (fehlt es: in F), beide PEM; password(Ps)
% für einen verschlüsselten Schlüssel
tls_server_context(tls_context(Cert,Key,Password), Options) :-
        must_be(list, Options),
        (   member(certfile(Cert), Options) ->
            '$tls_file'(Cert)
        ;   domain_error(contains_certfile, Options, tls_server_context/2)
        ),
        (   member(keyfile(Key), Options) ->
            '$tls_file'(Key)
        ;   Key = Cert
        ),
        (   member(password(Password), Options) ->
            must_be(chars, Password)
        ;   Password = ""
        ),
        '$tls_server_context'(Cert, Key, Password).

tls_server_negotiate(tls_context(Cert,Key,Password), S0, S) :-
        '$tls_accept_client'(Cert, Key, Password, S0, S).

% PrologEx: ein Dateiname ist ein Atom oder eine Liste von Zeichen
'$tls_file'(F) :-
        (   atom(F) -> true
        ;   must_be(chars, F)
        ).

