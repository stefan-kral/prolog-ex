% check.pl – library(crypto) gegen die Testvektoren aus gen.py:
% bad(Art, Fakt, Was) für jede Abweichung, counts/1 die Zahl je Art.
% (Mit double_quotes = chars wie die Bibliothek.)
:- set_prolog_flag(double_quotes, chars).
:- use_module(library(crypto)).
:- use_module(library(lists)).
:- use_module(library(charsio)).

% Hex als Atom (wie in vectors.pl) <-> Zeichen mit den Codes der Bytes
hex_chars(H, Cs) :- atom_chars(H, Hs), hex_bytes(Hs, Bs), maplist(char_code, Cs, Bs).
hex_list(H, Bs) :- atom_chars(H, Hs), hex_bytes(Hs, Bs).
chars_hex(Cs, H) :- maplist(char_code, Cs, Bs), hex_bytes(Hs, Bs), atom_chars(H, Hs).

ok(hash(A, M, D)) :-
    hex_chars(M, Cs),
    crypto_data_hash(Cs, H, [algorithm(A), encoding(octet)]),
    atom_chars(D, H).
% RFC 4231, Fall 5: der Wert ist auf 128 Bits gekürzt
ok(hmac(A, K, M, D)) :-
    hex_list(K, Ks), hex_chars(M, Cs),
    crypto_data_hash(Cs, H, [algorithm(A), encoding(octet), hmac(Ks)]),
    atom_chars(D, Ds), append(Ds, _, H).
ok(hkdf(A, I, S, F, L, O)) :-
    hex_chars(I, Is), hex_list(S, Ss), hex_list(F, Fs), hex_list(O, Os),
    crypto_data_hkdf(Is, L, Os, [algorithm(A), encoding(octet), salt(Ss), info(Fs)]).
ok(aead(K, V, A, P, C, T, R)) :-
    hex_list(K, Ks), hex_list(V, Vs), hex_chars(A, As), hex_chars(P, Ps),
    hex_chars(C, Cs), hex_list(T, Ts),
    (   R == ok ->
        crypto_data_encrypt(Ps, 'chacha20-poly1305', Ks, Vs, Cs1,
                            [encoding(octet), aad(As), tag(Ts1)]),
        Cs1 == Cs, Ts1 == Ts,
        crypto_data_decrypt(Cs, 'chacha20-poly1305', Ks, Vs, Ps1,
                            [encoding(octet), aad(As), tag(Ts)]),
        Ps1 == Ps
    ;   \+ crypto_data_decrypt(Cs, 'chacha20-poly1305', Ks, Vs, _,
                               [encoding(octet), aad(As), tag(Ts)])
    ).
ok(ed25519(Seed, Pub, M, Sig)) :-
    hex_list(Seed, Ss), hex_chars(M, Ms),
    ed25519_seed_keypair(Ss, KP),
    ed25519_keypair_public_key(KP, P), chars_hex(P, Pub),
    ed25519_sign(KP, Ms, S, [encoding(octet)]), atom_chars(Sig, S),
    ed25519_verify(P, Ms, S, [encoding(octet)]),
    % ein verändertes Byte: ungültig
    (   Ms = [C0|Rest] -> char_code(C0, X0), X1 is X0 xor 1, char_code(C1, X1), Ms1 = [C1|Rest]
    ;   Ms1 = ['\x0\']
    ),
    \+ ed25519_verify(P, Ms1, S, [encoding(octet)]).
ok(x25519(K, U, O)) :-
    hex_list(K, Ks), hex_chars(U, Us),
    curve25519_scalar_mult(Ks, Us, R), chars_hex(R, O).
ok(pbkdf2(P, S, I, O)) :-
    hex_list(P, Ps), hex_list(S, Ss), hex_list(O, Os),
    % crypto_password_hash nimmt 2^cost Durchläufe: I muss eine Potenz sein,
    % sonst direkt über das Format von crypto_password_hash/2
    pbkdf2_check(Ps, Ss, I, Os).
ok(secp256k1(K, X, Y)) :-
    crypto_name_curve(secp256k1, C), crypto_curve_generator(C, G),
    crypto_curve_scalar_mult(C, K, G, point(X, Y)).
ok(secp256k1_at(BX, BY, K, X, Y)) :-
    crypto_name_curve(secp256k1, C),
    crypto_curve_scalar_mult(C, K, point(BX, BY), point(X, Y)).

% der Hash im Format von crypto_password_hash/2 ($pbkdf2-sha512$t=I$Salz$Hash,
% Base64 ohne Auffüllen), dann prüfen lassen
pbkdf2_check(Ps, Ss, I, Os) :-
    maplist(char_code, Pw, Ps),
    b64(Ss, SB), b64(Os, OB),
    number_chars(I, Is),
    append(["$pbkdf2-sha512$t=", Is, "$", SB, "$", OB], H),
    crypto_password_hash(Pw, H),
    % und mit falschem Passwort nicht
    \+ crypto_password_hash(['x'|Pw], H).

b64(Bs, B) :- maplist(char_code, Cs, Bs), chars_base64(Cs, B, [padding(false)]).

kind(hash(_,_,_), hash).
kind(hmac(_,_,_,_), hmac).
kind(hkdf(_,_,_,_,_,_), hkdf).
kind(aead(_,_,_,_,_,_,_), aead).
kind(ed25519(_,_,_,_), ed25519).
kind(x25519(_,_,_), x25519).
kind(pbkdf2(_,_,_,_), pbkdf2).
kind(secp256k1(_,_,_), secp256k1).
kind(secp256k1_at(_,_,_,_,_), secp256k1).

vector(F) :-
    member(P, [hash/3, hmac/4, hkdf/6, aead/7, ed25519/4, x25519/3, pbkdf2/4,
               secp256k1/3, secp256k1_at/5]),
    P = N/A, functor(F, N, A), catch(call(F), error(existence_error(_, _), _), fail).

% die abweichenden Fälle
bad(K, F, W) :-
    vector(F), kind(F, K),
    (   catch(ok(F), E, true) -> nonvar(E), W = E
    ;   W = fail
    ).

counts(Cs) :- findall(K, (vector(F), kind(F, K)), Ks), msort(Ks, S), clumped(S, Cs).
