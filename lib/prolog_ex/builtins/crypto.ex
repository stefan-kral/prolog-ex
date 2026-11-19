defmodule PrologEx.Builtins.Crypto do
  @moduledoc """
  Grundlagen für `library(crypto)` (priv/library/crypto.pl, aus Scryer
  Prolog): die `$`-Prädikate, die dort die Scryer-Maschine (Rust: ring,
  crrl, sha3, blake2, ripemd) liefert, hier über `:crypto` (OpenSSL). Die
  Argumente sind schon geprüft (in Prolog); Text kommt als Liste von
  Zeichen mit der Kodierung `utf8` oder `octet` (Zeichencode = Byte),
  Bytes als Liste von Ganzzahlen, Ergebnisse wie bei Scryer als Bytes bzw.
  als Zeichen mit den Codes 0..255.

  Was `:crypto` nicht hat: HKDF (RFC 5869, hier aus HMAC) und die
  Skalarmultiplikation auf secp256k1 mit beliebigem Punkt (OpenSSLs ECDH
  gibt nur die x-Koordinate; hier mit Ganzzahlen in Jacobi-Koordinaten).
  Diese Multiplikation läuft nicht in konstanter Zeit – wie Scryer rät:
  für neue Anwendungen Curve25519 (`curve25519_scalar_mult/3`, über
  OpenSSL).
  """
  use PrologEx.Builtin
  alias PrologEx.Store
  alias PrologEx.Builtins.Lists

  # --- Hilfen ----------------------------------------------------------------

  # Text (Liste von Zeichen) als Bytes
  defp text_bytes(t, enc, s) do
    cs = for x <- Lists.items(t, s), do: char(Store.walk(x, s))

    case Store.walk(enc, s) do
      {:atom, "octet"} -> :erlang.list_to_binary(cs)
      _ -> :unicode.characters_to_binary(cs)
    end
  end

  defp char({:atom, <<c::utf8>>}), do: c

  defp bytes(t, s),
    do: :erlang.list_to_binary(for(x <- Lists.items(t, s), do: Store.walk(x, s)))

  defp int_list(bin), do: list(:binary.bin_to_list(bin))
  defp octet_chars(bin), do: list(for(<<b <- bin>>, do: a(<<b::utf8>>)))

  defp hash_alg("ripemd160"), do: :ripemd160
  defp hash_alg("sha256"), do: :sha256
  defp hash_alg("sha384"), do: :sha384
  defp hash_alg("sha512"), do: :sha512
  defp hash_alg("sha512_256"), do: :sha512_256
  defp hash_alg("sha3_224"), do: :sha3_224
  defp hash_alg("sha3_256"), do: :sha3_256
  defp hash_alg("sha3_384"), do: :sha3_384
  defp hash_alg("sha3_512"), do: :sha3_512
  defp hash_alg("blake2s256"), do: :blake2s
  defp hash_alg("blake2b512"), do: :blake2b

  defp alg(t, s) do
    {:atom, name} = Store.walk(t, s)
    hash_alg(name)
  end

  # --- Zufall, Prüfung -------------------------------------------------------

  defbuiltin "$crypto_random_byte", [b] do
    <<x>> = :crypto.strong_rand_bytes(1)
    {:unify, [{b, x}]}
  end

  # das erste Zeichen mit Code über 255, sonst scheitern
  defbuiltin "$first_non_octet", [cs, f] do
    s = subst()

    Lists.items(cs, s)
    |> Enum.find(fn x -> char(Store.walk(x, s)) > 255 end)
    |> case do
      nil -> :fail
      x -> {:unify, [{f, Store.walk(x, s)}]}
    end
  end

  # --- Hashes ----------------------------------------------------------------

  defbuiltin "$crypto_data_hash", [data, enc, hash, algo] do
    s = subst()
    {:unify, [{hash, int_list(:crypto.hash(alg(algo, s), text_bytes(data, enc, s)))}]}
  end

  defbuiltin "$crypto_hmac", [data, enc, key, hash, algo] do
    s = subst()
    mac = :crypto.mac(:hmac, alg(algo, s), bytes(key, s), text_bytes(data, enc, s))
    {:unify, [{hash, int_list(mac)}]}
  end

  # RFC 5869; ohne Salz HashLen Nullen (gleichwertig: HMAC füllt den
  # Schlüssel mit Nullen auf). Mehr als 255 Blöcke: scheitern (wie ring)
  defbuiltin "$crypto_data_hkdf", [data, enc, salt, info, algo, len, out] do
    s = subst()
    a = alg(algo, s)
    l = Store.walk(len, s)
    hlen = byte_size(:crypto.hash(a, ""))

    if l > 255 * hlen do
      :fail
    else
      prk = :crypto.mac(:hmac, a, bytes(salt, s), text_bytes(data, enc, s))
      okm = hkdf_expand(a, prk, bytes(info, s), l, "", "", 1)
      {:unify, [{out, int_list(okm)}]}
    end
  end

  defp hkdf_expand(_a, _prk, _info, l, _t, acc, _i) when byte_size(acc) >= l,
    do: binary_part(acc, 0, l)

  defp hkdf_expand(a, prk, info, l, t, acc, i) do
    t = :crypto.mac(:hmac, a, prk, t <> info <> <<i>>)
    hkdf_expand(a, prk, info, l, t, acc <> t, i + 1)
  end

  # PBKDF2-HMAC-SHA512 mit 64 Bytes
  defbuiltin "$crypto_password_hash", [pw, salt, iter, out] do
    s = subst()

    case Store.walk(iter, s) do
      n when is_integer(n) and n in 1..0xFFFFFFFF ->
        h = :crypto.pbkdf2_hmac(:sha512, bytes(pw, s), bytes(salt, s), n, 64)
        {:unify, [{out, int_list(h)}]}

      _ ->
        :fail
    end
  end

  # --- ChaCha20-Poly1305 (RFC 8439) -----------------------------------------

  defbuiltin "$crypto_data_encrypt", [plain, aad, enc, key, iv, tag, cipher] do
    s = subst()

    {c, t} =
      :crypto.crypto_one_time_aead(
        :chacha20_poly1305,
        bytes(key, s),
        bytes(iv, s),
        text_bytes(plain, enc, s),
        text_bytes(aad, enc, s),
        true
      )

    {:unify, [{tag, int_list(t)}, {cipher, octet_chars(c)}]}
  end

  # der Geheimtext mit dem Etikett (16 Bytes) am Ende, wie in Scryer
  defbuiltin "$crypto_data_decrypt", [cipher, aad, key, iv, enc, plain] do
    s = subst()
    data = text_bytes(cipher, a("octet"), s)

    with true <- byte_size(data) >= 16,
         n = byte_size(data) - 16,
         <<c::binary-size(^n), t::binary-size(16)>> = data,
         p when is_binary(p) <-
           :crypto.crypto_one_time_aead(
             :chacha20_poly1305,
             bytes(key, s),
             bytes(iv, s),
             c,
             text_bytes(aad, enc, s),
             t,
             false
           ),
         {:ok, text} <- decode(p, Store.walk(enc, s)) do
      {:unify, [{plain, text}]}
    else
      _ -> :fail
    end
  end

  defp decode(p, {:atom, "octet"}), do: {:ok, octet_chars(p)}

  defp decode(p, _utf8) do
    if String.valid?(p),
      do: {:ok, list(for(<<c::utf8 <- p>>, do: a(<<c::utf8>>)))},
      else: :error
  end

  # --- Ed25519 (RFC 8032) ----------------------------------------------------

  defbuiltin "$ed25519_seed_to_public_key", [seed, pub] do
    {p, _} = :crypto.generate_key(:eddsa, :ed25519, bytes(seed, subst()))
    {:unify, [{pub, octet_chars(p)}]}
  end

  defbuiltin "$ed25519_sign_raw", [seed, data, enc, sig] do
    s = subst()
    sg = :crypto.sign(:eddsa, :none, text_bytes(data, enc, s), [bytes(seed, s), :ed25519])
    {:unify, [{sig, int_list(sg)}]}
  end

  defbuiltin "$ed25519_verify_raw", [key, data, enc, sig] do
    s = subst()
    k = text_bytes(key, a("octet"), s)

    ok =
      byte_size(k) == 32 and
        try do
          :crypto.verify(:eddsa, :none, text_bytes(data, enc, s), bytes(sig, s), [k, :ed25519])
        rescue
          ErlangError -> false
        end

    if ok, do: :ok, else: :fail
  end

  # --- X25519 (RFC 7748) -----------------------------------------------------

  # OpenSSL lehnt ein Ergebnis aus lauter Nullen ab (Punkt kleiner
  # Ordnung); RFC 7748 und Scryer geben es zurück – dann hier selbst
  # gerechnet (die Leiter aus RFC 7748, Abschnitt 5)
  defbuiltin "$curve25519_scalar_mult", [scalar, point, out] do
    s = subst()
    k = bytes(scalar, s)
    u = bytes(point, s)

    r =
      try do
        :crypto.compute_key(:ecdh, u, k, :x25519)
      rescue
        ErlangError -> x25519(k, u)
      end

    {:unify, [{out, octet_chars(r)}]}
  end

  @p25519 Bitwise.<<<(1, 255) - 19

  @doc false
  def x25519(k, u) do
    import Bitwise
    <<kn::little-256>> = k
    # Klammern nach RFC 7748: untere 3 Bits und Bit 255 weg, Bit 254 an
    kn = (kn &&& (1 <<< 255) - 8) ||| 1 <<< 254
    <<un::little-256>> = u
    un = (un &&& (1 <<< 255) - 1) |> rem(@p25519)
    r = ladder(kn, un, 254, 1, 0, un, 1, 0)
    <<r::little-256>>
  end

  defp ladder(_k, _x1, t, x2, z2, x3, z3, swap) when t < 0 do
    {x2, z2, _, _} = cswap(swap, x2, z2, x3, z3)
    rem(x2 * pw(z2, @p25519 - 2), @p25519)
  end

  defp ladder(k, x1, t, x2, z2, x3, z3, swap) do
    p = @p25519
    kt = Bitwise.band(Bitwise.bsr(k, t), 1)
    swap = Bitwise.bxor(swap, kt)
    {x2, z2, x3, z3} = cswap(swap, x2, z2, x3, z3)
    a = rem(x2 + z2, p)
    aa = rem(a * a, p)
    b = Integer.mod(x2 - z2, p)
    bb = rem(b * b, p)
    e = Integer.mod(aa - bb, p)
    c = rem(x3 + z3, p)
    d = Integer.mod(x3 - z3, p)
    da = rem(d * a, p)
    cb = rem(c * b, p)
    x3 = rem((da + cb) * (da + cb), p)
    z3 = rem(x1 * Integer.mod((da - cb) * (da - cb), p), p)
    x2 = rem(aa * bb, p)
    z2 = rem(e * (aa + 121_665 * e), p)
    ladder(k, x1, t - 1, x2, z2, x3, z3, kt)
  end

  defp cswap(0, x2, z2, x3, z3), do: {x2, z2, x3, z3}
  defp cswap(1, x2, z2, x3, z3), do: {x3, z3, x2, z2}

  defp pw(b, e), do: :crypto.mod_pow(b, e, @p25519) |> :binary.decode_unsigned()

  # --- secp256k1 -------------------------------------------------------------

  @p 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
  @n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  # Skalar als Bytes (little-endian, mod n reduziert wie crrl), Punkt
  # unkomprimiert (04 || X || Y); Ergebnis ebenso, der unendlich ferne
  # Punkt wie in crrl mit X = Y = 0 (crypto_curve_scalar_mult/4 gibt dann
  # point(0, 0) wie Scryer)
  defbuiltin "$crypto_curve_scalar_mult", [_name, scalar, point, out] do
    s = subst()
    k = scalar |> bytes(s) |> :binary.decode_unsigned(:little) |> rem(@n)
    <<4, x::256, y::256>> = bytes(point, s)

    r =
      case ec_mul(k, {x, y, 1}) do
        {_, _, 0} ->
          <<4, 0::512>>

        {jx, jy, jz} ->
          zi = inv(jz)
          zi2 = rem(zi * zi, @p)
          <<4, rem(jx * zi2, @p)::256, rem(jy * rem(zi2 * zi, @p), @p)::256>>
      end

    {:unify, [{out, octet_chars(r)}]}
  end

  defp inv(z), do: :crypto.mod_pow(z, @p - 2, @p) |> :binary.decode_unsigned()

  # Jacobi-Koordinaten (x = X/Z², y = Y/Z³), a = 0; Verdoppeln und Addieren
  # von oben
  defp ec_mul(k, pt), do: ec_mul(k, pt, Integer.digits(k, 2), {0, 1, 0})

  defp ec_mul(_k, _pt, [], acc), do: acc

  defp ec_mul(k, pt, [b | bs], acc) do
    acc = dbl(acc)
    acc = if b == 1, do: add(acc, pt), else: acc
    ec_mul(k, pt, bs, acc)
  end

  defp dbl({_, _, 0} = o), do: o
  defp dbl({_, 0, _}), do: {0, 1, 0}

  defp dbl({x, y, z}) do
    p = @p
    yy = rem(y * y, p)
    s = rem(4 * x * yy, p)
    m = rem(3 * x * x, p)
    x3 = Integer.mod(m * m - 2 * s, p)
    y3 = Integer.mod(m * (s - x3) - 8 * yy * yy, p)
    z3 = rem(2 * y * z, p)
    {x3, y3, z3}
  end

  defp add({_, _, 0}, q), do: q
  defp add(p1, {_, _, 0}), do: p1

  defp add({x1, y1, z1} = p1, {x2, y2, z2}) do
    p = @p
    z1z1 = rem(z1 * z1, p)
    z2z2 = rem(z2 * z2, p)
    u1 = rem(x1 * z2z2, p)
    u2 = rem(x2 * z1z1, p)
    s1 = rem(y1 * z2 * z2z2, p)
    s2 = rem(y2 * z1 * z1z1, p)

    cond do
      u1 == u2 and s1 == s2 ->
        dbl(p1)

      u1 == u2 ->
        {0, 1, 0}

      true ->
        h = Integer.mod(u2 - u1, p)
        r = Integer.mod(s2 - s1, p)
        hh = rem(h * h, p)
        hhh = rem(h * hh, p)
        v = rem(u1 * hh, p)
        x3 = Integer.mod(r * r - hhh - 2 * v, p)
        y3 = Integer.mod(r * (v - x3) - s1 * hhh, p)
        z3 = rem(h * z1 * z2, p)
        {x3, y3, z3}
    end
  end
end
