defmodule PrologEx.NumberTheory do
  @moduledoc """
  Zahlentheorie auf Ganzzahlen beliebiger Größe (für `library(arithmetic)`,
  über die Builtins in `PrologEx.Builtins.IntPrims`).

    * `powm/3` – modulare Potenz; ab 2^64 über `:crypto.mod_pow/3`
      (OpenSSL), darunter direkt.
    * `isqrt/1`, `iroot/2` – abgerundete Wurzeln (Newton), exakt für jede
      Größe.
    * `jacobi/2` – Jacobi-Symbol.
    * `prime?/1` – Probedivision durch die Primzahlen unter 1000, dann
      Baillie-PSW: starker Fermat-Test zur Basis 2 und starker Lucas-Test
      (Selfridge, Methode A: erstes D aus 5, −7, 9, … mit (D/n) = −1,
      P = 1, Q = (1 − D)/4). Unter 2^64 bewiesen exakt (kein Gegenbeispiel
      dort, Feitsma/Gilchrist), darüber ohne bekanntes Gegenbeispiel.
    * `next_prime/1`, `prev_prime/1`, `primes_between/2` – das Letzte als
      segmentiertes Sieb (bis √H ≤ 2·10^6), sonst über `prime?/1`.
    * `factorial/1`, `binomial/2` – Produktbaum (gleich große Faktoren:
      Karatsuba der BEAM), bei `factorial/1` ohne die Zweierpotenz, die am
      Ende ein Shift anhängt.
    * Zerlegung: `trial_factor/1` (Primzahlen bis 10^4), `perfect_power/1`,
      `rho_step/4` (Pollard-Rho mit Brents Zyklensuche, ggT über Stapel von
      128 Differenzen) und `pm1_step/3` (Pollard p−1, Stufe 1, B1 = 10^5) –
      beide in Stücken, damit der Prolog-Teil zwischen ihnen Zeitgrenzen
      und Abbruch prüft.
  """
  import Bitwise

  @crypto_min 1 <<< 64

  # Primzahlen bis n (Eratosthenes, zur Übersetzungszeit)
  sieve = fn n ->
    Enum.reduce(2..trunc(:math.sqrt(n)), MapSet.new(2..n), fn p, set ->
      if MapSet.member?(set, p),
        do: Enum.reduce((p * p)..n//p, set, &MapSet.delete(&2, &1)),
        else: set
    end)
    |> Enum.sort()
  end

  @small_primes sieve.(997)
  @small_set MapSet.new(@small_primes)
  @trial_primes sieve.(10_000)
  @pm1_primes sieve.(100_000) |> List.to_tuple()
  @pm1_chunk 1000
  @pm1_b1 100_000

  # --- Grundlagen -----------------------------------------------------------

  @doc "Bitlänge von n > 0"
  def bit_length(n) when n > 0 and n < @crypto_min, do: small_bits(n, 0)

  def bit_length(n) when n > 0 do
    <<b, _::binary>> = bin = :binary.encode_unsigned(n)
    (byte_size(bin) - 1) * 8 + small_bits(b, 0)
  end

  defp small_bits(0, c), do: c
  defp small_bits(n, c), do: small_bits(n >>> 1, c + 1)

  @doc "Anzahl der Nullen am Ende von n > 0 (in Binärdarstellung)"
  def trailing_zeros(n) when (n &&& 0xFFFFFFFF) == 0, do: 32 + trailing_zeros(n >>> 32)
  def trailing_zeros(n), do: tz(n, 0)

  defp tz(n, c) when (n &&& 1) == 1, do: c
  defp tz(n, c), do: tz(n >>> 1, c + 1)

  defp popcount(0), do: 0
  defp popcount(n), do: (n &&& 1) + popcount(n >>> 1)

  @doc "B^E mod M für E ≥ 0, M ≥ 1 (Ergebnis in 0..M-1)"
  def powm(_b, _e, 1), do: 0

  def powm(b, e, m) when m < @crypto_min, do: pw(Integer.mod(b, m), e, m, 1)

  def powm(b, e, m),
    do: :crypto.mod_pow(Integer.mod(b, m), e, m) |> :binary.decode_unsigned()

  defp pw(_b, 0, _m, acc), do: acc

  defp pw(b, e, m, acc) do
    acc = if (e &&& 1) == 1, do: rem(acc * b, m), else: acc
    if e == 1, do: acc, else: pw(rem(b * b, m), e >>> 1, m, acc)
  end

  @doc "⌊√n⌋ für n ≥ 0"
  def isqrt(n) when n < 1 <<< 52 do
    r = trunc(:math.sqrt(n))

    cond do
      r * r > n -> r - 1
      (r + 1) * (r + 1) <= n -> r + 1
      true -> r
    end
  end

  def isqrt(n), do: newton2(n, 1 <<< div(bit_length(n) + 1, 2))

  defp newton2(n, x) do
    y = (x + div(n, x)) >>> 1
    if y >= x, do: x, else: newton2(n, y)
  end

  @doc "⌊n^(1/k)⌋ für n ≥ 0, k ≥ 1"
  def iroot(n, 1), do: n
  def iroot(n, _k) when n < 2, do: n
  def iroot(n, 2), do: isqrt(n)

  def iroot(n, k) do
    b = bit_length(n)
    if k >= b, do: 1, else: newtonk(n, k, 1 <<< (div(b, k) + 1))
  end

  defp newtonk(n, k, x) do
    y = div((k - 1) * x + div(n, Integer.pow(x, k - 1)), k)
    if y >= x, do: x, else: newtonk(n, k, y)
  end

  @doc "Jacobi-Symbol (a/n), n ungerade, n ≥ 1"
  def jacobi(a, n), do: jac(Integer.mod(a, n), n, 1)

  defp jac(0, n, t), do: if(n == 1, do: t, else: 0)

  defp jac(a, n, t) do
    z = trailing_zeros(a)
    a = a >>> z
    r8 = n &&& 7
    t = if (z &&& 1) == 1 and (r8 == 3 or r8 == 5), do: -t, else: t
    t = if (a &&& 3) == 3 and (n &&& 3) == 3, do: -t, else: t
    jac(rem(n, a), a, t)
  end

  @doc "Inverses von a modulo m ≥ 1, oder nil"
  def mod_inverse(_a, 1), do: 0

  def mod_inverse(a, m) do
    case Integer.extended_gcd(Integer.mod(a, m), m) do
      {1, s, _} -> Integer.mod(s, m)
      _ -> nil
    end
  end

  # --- Primzahltest ---------------------------------------------------------

  @doc "Ist n prim? (Baillie-PSW, siehe oben)"
  def prime?(n) when n < 2, do: false
  def prime?(n) when n < 1000, do: MapSet.member?(@small_set, n)

  def prime?(n) do
    cond do
      Enum.any?(@small_primes, &(rem(n, &1) == 0)) -> false
      n < 1_018_081 -> true
      true -> sprp2?(n) and lucas?(n)
    end
  end

  # starker Fermat-Test zur Basis 2
  defp sprp2?(n) do
    s = trailing_zeros(n - 1)
    x = powm(2, (n - 1) >>> s, n)
    x == 1 or x == n - 1 or squares(x, s - 1, n)
  end

  defp squares(_x, 0, _n), do: false

  defp squares(x, k, n) do
    x = rem(x * x, n)

    cond do
      x == n - 1 -> true
      x == 1 -> false
      true -> squares(x, k - 1, n)
    end
  end

  # starker Lucas-Test, Selfridge Methode A
  defp lucas?(n) do
    r = isqrt(n)

    if r * r == n do
      false
    else
      case selfridge(n, 5) do
        :composite -> false
        d -> strong_lucas(n, d, div(1 - d, 4))
      end
    end
  end

  defp selfridge(n, d) do
    case jacobi(d, n) do
      -1 -> d
      0 when abs(d) != n -> :composite
      _ -> selfridge(n, if(d > 0, do: -(d + 2), else: -d + 2))
    end
  end

  defp strong_lucas(n, d, q) do
    m = n + 1
    s = trailing_zeros(m)
    [1 | bits] = Integer.digits(m >>> s, 2)
    qm = Integer.mod(q, n)
    {u, v, qk} = lucas_chain(bits, 1, 1, qm, n, d, qm)

    u == 0 or v == 0 or lucas_v(v, qk, s - 1, n)
  end

  defp lucas_chain([], u, v, qk, _n, _d, _q), do: {u, v, qk}

  defp lucas_chain([b | bits], u, v, qk, n, d, q) do
    u2 = rem(u * v, n)
    v2 = Integer.mod(v * v - 2 * qk, n)
    qk2 = rem(qk * qk, n)

    if b == 1 do
      u3 = half(u2 + v2, n)
      v3 = half(d * u2 + v2, n)
      lucas_chain(bits, u3, v3, rem(qk2 * q, n), n, d, q)
    else
      lucas_chain(bits, u2, v2, qk2, n, d, q)
    end
  end

  defp half(x, n) do
    x = Integer.mod(x, n)
    if (x &&& 1) == 1, do: (x + n) >>> 1, else: x >>> 1
  end

  defp lucas_v(_v, _qk, 0, _n), do: false

  defp lucas_v(v, qk, k, n) do
    v = Integer.mod(v * v - 2 * qk, n)
    v == 0 or lucas_v(v, rem(qk * qk, n), k - 1, n)
  end

  @doc "kleinste Primzahl > n"
  def next_prime(n) when n < 2, do: 2
  def next_prime(2), do: 3
  def next_prime(n), do: next_odd(if((n &&& 1) == 0, do: n + 1, else: n + 2))

  defp next_odd(c), do: if(prime?(c), do: c, else: next_odd(c + 2))

  @doc "größte Primzahl < n, oder nil"
  def prev_prime(n) when n <= 2, do: nil
  def prev_prime(3), do: 2
  def prev_prime(n), do: prev_odd(if((n &&& 1) == 0, do: n - 1, else: n - 2))

  defp prev_odd(2), do: 2
  defp prev_odd(c), do: if(prime?(c), do: c, else: prev_odd(c - 2))

  @doc "Primzahlen in l..h, aufsteigend"
  def primes_between(l, h) do
    l = max(l, 2)

    cond do
      h < l -> []
      h < 1000 -> Enum.filter(@small_primes, &(&1 >= l and &1 <= h))
      isqrt(h) <= 2_000_000 -> sieve_range(l, h)
      true -> walk_primes(next_prime(l - 1), h, [])
    end
  end

  defp walk_primes(p, h, acc) when p > h, do: Enum.reverse(acc)
  defp walk_primes(p, h, acc), do: walk_primes(next_prime(p), h, [p | acc])

  @segment 1 <<< 16

  defp sieve_range(l, h) do
    base = base_primes(isqrt(h))
    two = if l <= 2, do: [2], else: []
    lo = if (l &&& 1) == 0, do: l + 1, else: l
    lo = max(lo, 3)
    two ++ segments(lo, h, base, [])
  end

  # ungerade Primzahlen bis lim (3, 5, ...)
  defp base_primes(lim) when lim < 3, do: []

  defp base_primes(lim) do
    size = div(lim - 1, 2)
    a = :atomics.new(size, [])
    # Index i (1-basiert) steht für 2i + 1
    for i <- 1..size,
        :atomics.get(a, i) == 0,
        p = 2 * i + 1,
        p * p <= lim,
        j <- div(p * p - 1, 2)..size//p,
        do: :atomics.put(a, j, 1)

    for i <- 1..size, :atomics.get(a, i) == 0, do: 2 * i + 1
  end

  defp segments(lo, h, _base, acc) when lo > h, do: acc |> Enum.reverse() |> Enum.concat()

  defp segments(lo, h, base, acc) do
    hi = min(h, lo + 2 * (@segment - 1))
    n = div(hi - lo, 2) + 1
    a = :atomics.new(n, [])

    Enum.each(base, fn p ->
      if p * p <= hi do
        st = max(p * p, div(lo + p - 1, p) * p)
        st = if (st &&& 1) == 0, do: st + p, else: st
        mark(a, div(st - lo, 2) + 1, p, n)
      end
    end)

    ps = for i <- 1..n, :atomics.get(a, i) == 0, do: lo + 2 * (i - 1)
    segments(hi + 2, h, base, [ps | acc])
  end

  defp mark(_a, i, _p, n) when i > n, do: :ok

  defp mark(a, i, p, n) do
    :atomics.put(a, i, 1)
    mark(a, i + p, p, n)
  end

  # --- Fakultät, Binomialkoeffizient ---------------------------------------

  @doc "n! für n ≥ 0"
  def factorial(n) when n < 21, do: Enum.reduce(1..max(n, 1)//1, 1, &*/2)

  def factorial(n) do
    tree(for k <- 1..n, do: k >>> trailing_zeros(k)) <<< (n - popcount(n))
  end

  @doc "Binomialkoeffizient (n über k), n ≥ 0"
  def binomial(n, k) when k < 0 or k > n, do: 0

  def binomial(n, k) do
    k = min(k, n - k)
    if k == 0, do: 1, else: div(tree(Enum.to_list((n - k + 1)..n)), factorial(k))
  end

  @doc "Produkt einer Liste als Baum (gleich große Faktoren)"
  def tree([]), do: 1
  def tree([x]), do: x

  def tree(l) do
    case pairup(l, []) do
      [x] -> x
      l2 -> tree(l2)
    end
  end

  defp pairup([a, b | t], acc), do: pairup(t, [a * b | acc])
  defp pairup([a], acc), do: [a | acc]
  defp pairup([], acc), do: acc

  # --- Zerlegung ------------------------------------------------------------

  @doc """
  Probedivision durch die Primzahlen bis 10^4: {[{p, e}, ...] aufsteigend,
  Rest}; der Rest ist 1 oder hat nur Primfaktoren größer als alle
  gefundenen (und ist prim, wenn er kleiner als das Quadrat der nächsten
  Primzahl ist)
  """
  def trial_factor(n), do: trial(n, @trial_primes, [])

  defp trial(1, _ps, acc), do: {Enum.reverse(acc), 1}
  defp trial(n, [], acc), do: {Enum.reverse(acc), n}
  defp trial(n, [p | _], acc) when p * p > n, do: {Enum.reverse(acc), n}

  defp trial(n, [p | ps], acc) do
    case divide(n, p, 0) do
      {n, 0} -> trial(n, ps, acc)
      {n, e} -> trial(n, ps, [{p, e} | acc])
    end
  end

  defp divide(n, p, e) when rem(n, p) == 0, do: divide(div(n, p), p, e + 1)
  defp divide(n, _p, e), do: {n, e}

  @doc "n = r^k mit größtem Primexponenten k ≥ 2 zuerst gefunden: {r, k} oder nil"
  def perfect_power(n) when n < 4, do: nil

  def perfect_power(n) do
    b = bit_length(n)

    Enum.find_value(exponents(b), fn k ->
      r = iroot(n, k)
      if Integer.pow(r, k) == n, do: {r, k}
    end)
  end

  defp exponents(b), do: Enum.filter(2..b, &prime?/1)

  @doc """
  Pollard-Rho (Brent), f(x) = x² + c mod n, n ungerade und zusammengesetzt.
  Zustand st (nil zu Beginn); höchstens budget Schritte: {:found, d} mit
  1 < d < n, {:more, st} oder :fail (dieses c findet nichts, ein anderes
  nehmen)
  """
  def rho_step(n, c, nil, budget), do: rho_step(n, c, {0, 2, 2, 1, 1, 1, 0}, budget)

  # Phase 0: y r-mal weiter (rest Schritte übrig); Phase 1: ab k Stapel
  # von höchstens 128 Schritten, q sammelt |x − y|
  def rho_step(_n, _c, st, budget) when budget <= 0, do: {:more, st}

  def rho_step(n, c, {0, x, y, r, rest, q, _k}, budget) do
    steps = min(rest, budget)
    y = iter(y, c, n, steps)

    if steps < rest,
      do: {:more, {0, x, y, r, rest - steps, q, 0}},
      else: rho_step(n, c, {1, x, y, r, 0, q, 0}, budget - steps)
  end

  def rho_step(n, c, {1, _x, y, r, _, q, k}, budget) when k >= r,
    do: rho_step(n, c, {0, y, y, 2 * r, 2 * r, q, 0}, budget)

  def rho_step(n, c, {1, x, y, r, _, q, k}, budget) do
    lim = min(128, r - k)
    {y2, q} = batch(x, y, q, c, n, lim)

    case Integer.gcd(q, n) do
      1 -> rho_step(n, c, {1, x, y2, r, 0, q, k + 128}, budget - lim)
      g when g < n -> {:found, g}
      _ -> backtrack(x, y, c, n, lim)
    end
  end

  defp iter(y, _c, _n, 0), do: y
  defp iter(y, c, n, k), do: iter(rem(y * y + c, n), c, n, k - 1)

  defp batch(_x, y, q, _c, _n, 0), do: {y, q}

  defp batch(x, y, q, c, n, k) do
    y = rem(y * y + c, n)
    batch(x, y, rem(q * abs(x - y), n), c, n, k - 1)
  end

  # der Stapel traf n: Schritt für Schritt ab seinem Anfang
  defp backtrack(_x, _ys, _c, _n, 0), do: :fail

  defp backtrack(x, ys, c, n, k) do
    ys = rem(ys * ys + c, n)

    case Integer.gcd(abs(x - ys), n) do
      1 -> backtrack(x, ys, c, n, k - 1)
      g when g < n -> {:found, g}
      _ -> :fail
    end
  end

  @doc """
  Pollard p−1, Stufe 1 bis B1 = 10^5, ab dem i-ten Primfaktor (0-basiert)
  ein Stück von 1000: {:found, d}, {:more, a, i} oder :none
  """
  def pm1_step(n, a, i) do
    j = min(i + @pm1_chunk, tuple_size(@pm1_primes))

    e =
      tree(
        for t <- i..(j - 1)//1 do
          p = elem(@pm1_primes, t)
          Integer.pow(p, max_pow(p, p))
        end
      )

    a = powm(a, e, n)

    case Integer.gcd(a - 1, n) do
      1 when j < tuple_size(@pm1_primes) -> {:more, a, j}
      g when g > 1 and g < n -> {:found, g}
      _ -> :none
    end
  end

  defp max_pow(p, pk) when pk * p > @pm1_b1, do: 1
  defp max_pow(p, pk), do: 1 + max_pow(p, pk * p)

  @doc "Teiler aus [{p, e}], aufsteigend"
  def divisors(pes) do
    Enum.reduce(pes, [1], fn {p, e}, ds ->
      for d <- ds, k <- 0..e, do: d * Integer.pow(p, k)
    end)
    |> Enum.sort()
  end

  @doc "Eulersche φ aus [{p, e}]"
  def totient(pes),
    do: Enum.reduce(pes, 1, fn {p, e}, t -> t * Integer.pow(p, e - 1) * (p - 1) end)
end
