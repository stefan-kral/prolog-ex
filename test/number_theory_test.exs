defmodule PrologEx.NumberTheoryTest do
  # Zahlentheorie in library(arithmetic): Primzahltest gegen das Sieb und
  # bekannte Pseudoprimzahlen, Zerlegungen (Produkt und Primalität
  # nachgerechnet), Fehler, expmod/4 wie die frühere Fassung in Prolog,
  # Abbruch einer langen Zerlegung durch eine Zeitgrenze
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(arithmetic)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(time)).
  :- use_module(library(iso_ext)).
  fzx(X, F) :- N is X, factorize(N, F).
  e(G, E) :- catch((G, E = ok), error(E0, C), E = E0/C).
  % Probedivision als Referenz
  slow_prime(N) :- N >= 2, S is truncate(sqrt(N)), \\+ (between(2, S, D), N mod D =:= 0).
  % Zerlegung prüfen: Produkt, Primzahlen, aufsteigend, Exponenten >= 1
  fz_ok(N) :-
      factorize(N, PEs), prod(PEs, 1, N), all_prime(PEs),
      pairs_keys(PEs, Ps), sort(Ps, Ps), length(Ps, L), length(PEs, L).
  prod([], A, A).
  prod([P-E|T], A0, A) :- E >= 1, A1 is A0 * P^E, prod(T, A1, A).
  all_prime([]).
  all_prime([P-_|T]) :- slow_or_bpsw(P), all_prime(T).
  fac_ref(0, 1) :- !.
  fac_ref(N, F) :- M is N - 1, fac_ref(M, F0), F is F0 * N.
  slow_or_bpsw(P) :- ( P < 10^8 -> slow_prime(P) ; is_prime(P) ).
  pairs_keys([], []).
  pairs_keys([K-_|T], [K|Ks]) :- pairs_keys(T, Ks).
  % die frühere expmod/4 in Prolog (Scryer)
  ref_expmod(_, _, 1, _, 0) :- !.
  ref_expmod(_, 0, _, R, R) :- !.
  ref_expmod(B0, E0, M, C0, R) :-
      E0 /\\ 1 =:= 1, C is (C0 * B0) mod M, !,
      E is E0 >> 1, B is (B0 * B0) mod M, ref_expmod(B, E, M, C, R).
  ref_expmod(B0, E0, M, C, R) :-
      E is E0 >> 1, B is (B0 * B0) mod M, ref_expmod(B, E, M, C, R).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        # Primzahltest gegen das Sieb und die Probedivision
        {"findall(N, (between(-5, 20000, N), is_prime(N)), L), primes_between(-5, 20000, L), length(L, 2262)",
         :succeeds},
        {"findall(N, (between(0, 3000, N), slow_prime(N)), L), primes_between(0, 3000, L)",
         :succeeds},
        {"primes_between(1, 100000, L), length(L, 9592), last(L, 99991)", :succeeds},
        # starke Pseudoprimzahlen zur Basis 2, Carmichael-Zahlen, starke
        # Lucas-Pseudoprimzahlen, Quadrate: alle zusammengesetzt
        {"member(N, [2047, 3277, 4033, 4681, 8321, 15841, 29341, 42799, 49141, 52633, 65281, " <>
           "561, 1105, 1729, 2465, 2821, 6601, 8911, 5459, 5777, 10877, 16109, 18971, 22499, " <>
           "3215031751, 3825123056546413051, 318665857834031151167461, 1018081, 994009, 1018080]), " <>
           "is_prime(N)", :fails},
        # Mersenne-Primzahlen und eine Zahl knapp daneben
        {"member(E, [31, 61, 89, 107, 127, 521, 607]), N is 2^E - 1, \\+ is_prime(N)", :fails},
        {"N is 2^67 - 1, is_prime(N)", :fails},
        {"N is 2^64 + 13, is_prime(N)", :succeeds},
        {"is_prime(1)", :fails},
        {"is_prime(-7)", :fails},
        {"is_prime(2)", :succeeds},
        # nächste, vorige
        {"next_prime(-10, P)", ["P = 2"]},
        {"next_prime(2, P)", ["P = 3"]},
        {"next_prime(13, P)", ["P = 17"]},
        {"N is 2^64, next_prime(N, P), P - N =:= 13", :succeeds},
        {"prev_prime(3, P)", ["P = 2"]},
        {"prev_prime(2, P)", :fails},
        {"N is 2^64, prev_prime(N, P), N - P =:= 59", :succeeds},
        {"prev_prime(1000000, P)", ["P = 999983"]},
        # Sieb bis √H = 2·10^6, darüber Schritt für Schritt: gleich
        {"H is 4*10^12, L is H - 3000, primes_between(L, H, Ps), findall(N, (between(L, H, N), is_prime(N)), Ps), length(Ps, K), K > 50",
         :succeeds},
        {"L is 5*10^12, H is L + 2000, primes_between(L, H, Ps), findall(N, (between(L, H, N), is_prime(N)), Ps)",
         :succeeds},
        {"primes_between(10, 5, L)", ["L = []"]},
        {"primes_between(14, 16, L)", ["L = []"]},
        # Zerlegung
        {"factorize(1, F)", ["F = []"]},
        {"factorize(360, F)", ["F = [2-3,3-2,5-1]"]},
        {"prime_factors(360, F)", ["F = [2,2,2,3,3,5]"]},
        {"factorize(9973, F)", ["F = [9973-1]"]},
        {"factorize(19946, F)", ["F = [2-1,9973-1]"]},
        {"factorize(600851475143, F)", ["F = [71-1,839-1,1471-1,6857-1]"]},
        {"fzx(10007^5, F)", ["F = [10007-5]"]},
        {"fzx(1000003^2*1000033, F)", ["F = [1000003-2,1000033-1]"]},
        {"fzx(2^67 - 1, F)", ["F = [193707721-1,761838257287-1]"]},
        {"fzx((2^31-1)*(2^61-1), F)", ["F = [2147483647-1,2305843009213693951-1]"]},
        {"fzx(999999000001*999999999989, F)", ["F = [999999000001-1,999999999989-1]"]},
        {"fzx(2^64 * 3^40 * 1000000007^3, F)", ["F = [2-64,3-40,1000000007-3]"]},
        {"forall(between(1, 3000, N), fz_ok(N))", :succeeds},
        {"forall(between(0, 200, K), (N is 10^15 + K * 7919, fz_ok(N)))", :succeeds},
        {"divisors(1, D)", ["D = [1]"]},
        {"divisors(360, D)",
         ["D = [1,2,3,4,5,6,8,9,10,12,15,18,20,24,30,36,40,45,60,72,90,120,180,360]"]},
        {"totient(1, T)", ["T = 1"]},
        {"totient(360, T)", ["T = 96"]},
        {"totient(9973, T)", ["T = 9972"]},
        # Fakultät, Binomialkoeffizient
        {"factorial(0, F)", ["F = 1"]},
        {"factorial(20, F)", ["F = 2432902008176640000"]},
        {"factorial(3000, F), fac_ref(3000, F)", :succeeds},
        {"binomial(10, 3, B)", ["B = 120"]},
        {"binomial(10, 0, B)", ["B = 1"]},
        {"binomial(10, 11, B)", ["B = 0"]},
        {"binomial(10, -1, B)", ["B = 0"]},
        {"binomial(0, 0, B)", ["B = 1"]},
        {"binomial(100, 50, B)", ["B = 100891344545564193334812497256"]},
        # Wurzeln
        {"isqrt(0, R)", ["R = 0"]},
        {"isqrt(17, R)", ["R = 4"]},
        {"N is 10^100, isqrt(N, R), R =:= 10^50", :succeeds},
        {"N is 10^100 - 1, isqrt(N, R), R =:= 10^50 - 1", :succeeds},
        {"iroot(1000, 3, R)", ["R = 10"]},
        {"iroot(999, 3, R)", ["R = 9"]},
        {"iroot(5, 1, R)", ["R = 5"]},
        {"N is 3^333, iroot(N, 333, 3), M is N - 1, iroot(M, 333, 2)", :succeeds},
        # modulare Inverse, Jacobi
        {"mod_inverse(3, 7, I)", ["I = 5"]},
        {"mod_inverse(-3, 7, I)", ["I = 2"]},
        {"mod_inverse(2, 4, I)", :fails},
        {"mod_inverse(5, 1, I)", ["I = 0"]},
        {"jacobi(1001, 9907, J)", ["J = -1"]},
        {"jacobi(19, 45, J)", ["J = 1"]},
        {"jacobi(5, 15, J)", ["J = 0"]},
        {"jacobi(-1, 7, J)", ["J = -1"]},
        # expmod/4 wie die frühere Fassung (auch negative Basis und Modul)
        {"forall((member(B, [-7, -1, 0, 1, 2, 3, 10, 123456789]), member(E, [0, 1, 2, 3, 7, 100, 1001]), " <>
           "member(M, [-13, -2, -1, 1, 2, 7, 1000, 18446744073709551629])), " <>
           "(expmod(B, E, M, R), ref_expmod(B, E, M, 1, R)))", :succeeds},
        {"N is 2^127 - 1, E is N - 1, expmod(3, E, N, 1)", :succeeds},
        {"e(expmod(3, 3, 0, _), E/_)", ["E = evaluation_error(zero_divisor)"]},
        {"e(expmod(3, -1, 7, _), E)", ["E = domain_error(not_less_than_zero,-1)/(expmod/4)"]},
        # Fehler
        {"e(is_prime(_), E)", ["E = instantiation_error/(is_prime/1)"]},
        {"e(is_prime(a), E)", ["E = type_error(integer,a)/(is_prime/1)"]},
        {"e(is_prime(7.0), E)", ["E = type_error(integer,7.0)/(is_prime/1)"]},
        {"e(next_prime(1+1, _), E)", ["E = type_error(integer,1+1)/(next_prime/2)"]},
        {"e(factorize(0, _), E)", ["E = domain_error(not_less_than_one,0)/(factorize/2)"]},
        {"e(prime_factors(-4, _), E)",
         ["E = domain_error(not_less_than_one,-4)/(prime_factors/2)"]},
        {"e(factorial(-1, _), E)", ["E = domain_error(not_less_than_zero,-1)/(factorial/2)"]},
        {"e(binomial(-1, 0, _), E)", ["E = domain_error(not_less_than_zero,-1)/(binomial/3)"]},
        {"e(binomial(3, x, _), E)", ["E = type_error(integer,x)/(binomial/3)"]},
        {"e(isqrt(-1, _), E)", ["E = domain_error(not_less_than_zero,-1)/(isqrt/2)"]},
        {"e(iroot(8, 0, _), E)", ["E = domain_error(not_less_than_one,0)/(iroot/3)"]},
        {"e(mod_inverse(3, 0, _), E)", ["E = domain_error(not_less_than_one,0)/(mod_inverse/3)"]},
        {"e(jacobi(3, 8, _), E)", ["E = domain_error(odd,8)/(jacobi/3)"]},
        {"e(primes_between(_, 5, _), E)", ["E = instantiation_error/(primes_between/3)"]},
        # eine Zerlegung ohne Aussicht (F7 = 2^128 + 1, kleinster Faktor
        # mit 17 Stellen): die Zeitgrenze bricht sie ab
        {"N is 2^128 + 1, catch(call_with_time_limit(0.3, factorize(N, _)), E, true), E == time_limit_exceeded",
         :succeeds}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
