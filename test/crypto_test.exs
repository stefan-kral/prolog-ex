defmodule PrologEx.CryptoTest do
  # library(crypto) und library(uuid) aus Scryer: die Testvektoren
  # (test/fixtures/test_vectors/crypto_vectors.pl, ein Auszug der Ausgabe
  # von conformance/crypto_vectors/gen.py: NIST CAVP, RFC 4231/5869/7748/
  # 8032, OpenSSL/BoringSSL, PBKDF2 nach Python, secp256k1 unabhängig
  # gerechnet), geprüft von conformance/crypto_vectors/check.pl
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})

    for f <- ~w(conformance/crypto_vectors/check.pl test/fixtures/test_vectors/crypto_vectors.pl),
        do: {:ok, _} = PrologEx.Consult.load_file(f)

    {:ok, reader: r, db: PrologEx.current_db()}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp run(c, q) do
    assert {"", {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    a
  end

  test "alle Testvektoren", c do
    assert run(c, "findall(K-W, bad(K, _, W), L)") == "L = []"

    assert run(c, "counts(Cs)") ==
             "Cs = [aead-8,ed25519-8,hash-150,hkdf-3,hmac-18,pbkdf2-7,secp256k1-17,x25519-3]"
  end

  test "Daten als UTF-8, Ver- und Entschlüsseln hin und zurück", c do
    q =
      "atom_chars('Grüße', Cs), crypto_data_hash(Cs, H, [algorithm(sha256)]), " <>
        "atom_chars(A, H), crypto_n_random_bytes(32, K), crypto_n_random_bytes(12, IV), " <>
        "crypto_data_encrypt(Cs, 'chacha20-poly1305', K, IV, X, [tag(T)]), length(T, 16), " <>
        "crypto_data_decrypt(X, 'chacha20-poly1305', K, IV, P, [tag(T)]), atom_chars(B, P), " <>
        "T = [T0|Ts], T1 is T0 xor 1, " <>
        "( crypto_data_decrypt(X, 'chacha20-poly1305', K, IV, _, [tag([T1|Ts])]) -> F = ja ; F = nein )"

    a = run(c, q)
    assert a =~ "A = f83e039796c6453a10f5519e39fd113901572316a1a8ea07cb525d2801dfd074"

    assert a =~ "B = 'Grüße'"
    assert a =~ "F = nein"
  end

  test "Passwort-Hash und Schlüsselpaare", c do
    q =
      "atom_chars(geheim, P), crypto_password_hash(P, H), " <>
        "( crypto_password_hash(P, H) -> R1 = ja ; R1 = nein ), " <>
        "( crypto_password_hash([x|P], H) -> R2 = ja ; R2 = nein ), " <>
        "ed25519_new_keypair(KP), ed25519_keypair_public_key(KP, Pub), " <>
        "ed25519_sign(KP, P, S, []), ( ed25519_verify(Pub, P, S, []) -> R3 = ja ; R3 = nein ), " <>
        "( ed25519_verify(Pub, [x|P], S, []) -> R4 = ja ; R4 = nein )"

    a = run(c, q)
    assert a =~ "R1 = ja"
    assert a =~ "R2 = nein"
    assert a =~ "R3 = ja"
    assert a =~ "R4 = nein"
  end

  test "hex_bytes/2 in beide Richtungen und Fehler", c do
    assert run(c, "hex_bytes(H, [1,171,255]), atom_chars(A, H)") =~ "A = '01abff'"
    assert run(c, "hex_bytes(['0','A',f,f], Bs)") =~ "Bs = [10,255]"

    assert run(c, "catch(hex_bytes(_, _), error(E, _), true)") =~
             "E = instantiation_error"
  end

  test "library(uuid): Version 4 als Text und zurück", c do
    q =
      "use_module(library(uuid)), uuidv4_string(S), length(S, 36), " <>
        "nth0(14, S, V), uuid_string(U, S), length(U, 16), uuid_string(U, S2), " <>
        "( S2 == S -> G = ja ; G = nein )"

    a = run(c, q)
    assert a =~ "V = '4'"
    assert a =~ "G = ja"
  end

  test "die Operatoren von clpz gelten in crypto, aber nicht in user", c do
    assert run(
             c,
             "use_module(library(charsio)), catch(read_from_chars([a,' ',i,n,' ',b,'.'], T), error(E, _), true)"
           ) =~
             "E = syntax_error"
  end

  test "partial_string/3", c do
    assert run(c, "use_module(library(iso_ext)), partial_string(abc, L, T)") =~
             "L = [a,b,c|T]"

    assert run(c, "use_module(library(iso_ext)), partial_string([x,y], L, [])") =~
             "L = [x,y]"

    assert run(
             c,
             "use_module(library(iso_ext)), catch(partial_string([x,1], _, _), error(E, _), true)"
           ) =~ "E = type_error(character,1)"
  end

  test "writeq schreibt unsichtbare Zeichen als \\x…\\ (wie SWI)", c do
    q = "atom_codes(A, [0x81, 0xA0, 0xAD, 0x2028, 0x200B, 0xE4, 0x20AC])"

    # \x81\ und \xA0\ hintereinander: \x81\\xA0\
    assert run(c, q) =~ ~S"A = '\x81\\xA0\\xAD\\x2028\\x200B\ä€'"
  end
end
