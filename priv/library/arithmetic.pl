/** Arithmetic predicates

Wie Scryers library(arithmetic) (siehe SCRYER-LICENSE). Die Prädikate für
Brüche (number_to_rational/2,3, rational_numerator_denominator/3) sind neu
geschrieben, über die eingebauten Brüche (1r3, rational/3):

  * number_to_rational(+Eps, +Real, -F): F ist der einfachste Bruch (kleinster
    Nenner) im geschlossenen Intervall [Real - Eps, Real + Eps], exakt
    gerechnet (ein Float zählt mit seinem exakten Wert). Scryer sucht nur im
    Nachkommateil und trifft dessen Ränder 0 und 1 nie: 2.0000001 mit Eps
    1.0e-6 gibt dort 2 + 1/909091, hier 2; eine negative Ganzzahl -2 gibt
    dort -3. Über Kettenbrüche statt Schritt für Schritt durch den
    Stern-Brocot-Baum: auch number_to_rational(0, 1.0e-300, F) ist sofort
    fertig.
  * number_to_rational(+Real, -F): Ganzzahl unverändert, sonst mit Eps
    1.0e-6 (wie Scryer): number_to_rational(3.14159265, F) gibt 355r113.
  * rational_numerator_denominator(+R, -N, -D): wie rational/3 (auch für
    Ganzzahlen: D = 1; Scryer scheitert dort, sein Bruch 2 rdiv 1 ist keine
    Ganzzahl). Kein Bruch: scheitert. msb/2, lsb/2 und popcount/2 rechnen über
die gleichnamigen Funktionen von is/2.
*/

:- module(arithmetic, [expmod/4, lcm/3, lsb/2, msb/2, number_to_rational/2,
                       number_to_rational/3, popcount/2,
                       rational_numerator_denominator/3,
                       % Zahlentheorie (PrologEx)
                       is_prime/1, next_prime/2, prev_prime/2,
                       primes_between/3, factorize/2, prime_factors/2,
                       divisors/2, totient/2, factorial/2, binomial/3,
                       isqrt/2, iroot/3, mod_inverse/3, jacobi/3,
                       bit_is_set/2]).

:- use_module(library(error)).
:- use_module(library(lists), [member/2, append/3]).

%% expmod(+Base, +Expo, +Mod, -R).
%
% Modular exponentiation. Base, Expo and Mod must be integers.
expmod(Base, Expo, Mod, R) :-
    (   member(N, [Base, Expo, Mod]), var(N) -> instantiation_error(expmod/4)
    ;   member(N, [Base, Expo, Mod]), \+ integer(N) ->
        type_error(integer, N, expmod/4)
    ;   Expo < 0 -> domain_error(not_less_than_zero, Expo, expmod/4)
    ;   '$powm'(Base, Expo, Mod, R)
    ).

%% lcm(+A, +B, -X).
%
% Least common multiple of A and B.
lcm(A, B, X) :-
    must_be_number(A, lcm/2),
    must_be_number(B, lcm/2),
    (   \+ integer(A) -> type_error(integer, A, lcm/2)
    ;   \+ integer(B) -> type_error(integer, B, lcm/2)
    ;   (A = 0, B = 0) -> X = 0
    ;   can_be_number(X, lcm/2),
        X is abs(B) // gcd(A,B) * abs(A)
    ).

%% lsb(+X, -N).
%
% N is the index of the least significant 1 bit of X (X >= 1).
lsb(X, N) :-
    must_be_number(X, lsb/2),
    (   \+ integer(X) -> type_error(integer, X, lsb/2)
    ;   X < 1 -> domain_error(not_less_than_one, X, lsb/2)
    ;   can_be_number(N, lsb/2),
        N is lsb(X)
    ).

%% msb(+X, -N).
%
% N is the index of the most significant 1 bit of X (X >= 1).
msb(X, N) :-
    must_be_number(X, msb/2),
    (   \+ integer(X) -> type_error(integer, X, msb/2)
    ;   X < 1 -> domain_error(not_less_than_one, X, msb/2)
    ;   can_be_number(N, msb/2),
        N is msb(X)
    ).

%% popcount(+X, -N).
%
% N is the number of 1 bits of the non-negative integer X.
popcount(X, N) :-
    must_be(integer, X),
    N is popcount(X).

% wie Scryers builtins:must_be_number/2 und builtins:can_be_number/2
must_be_number(X, PI) :-
    (   var(X) -> instantiation_error(PI)
    ;   number(X) -> true
    ;   type_error(number, X, PI)
    ).

can_be_number(X, PI) :-
    (   var(X) -> true
    ;   number(X) -> true
    ;   type_error(number, X, PI)
    ).

%% number_to_rational(+Real, -Fraction).
%
% Fraction ist Real als Bruch: eine Ganzzahl unverändert, sonst der
% einfachste Bruch im Abstand höchstens 1.0e-6.
number_to_rational(Real, Fraction) :-
    (   var(Real) -> instantiation_error(number_to_rational/2)
    ;   integer(Real) -> Fraction = Real
    ;   number(Real) -> number_to_rational(1.0e-6, Real, Fraction)
    ;   type_error(number, Real, number_to_rational/2)
    ).

%% number_to_rational(+Eps, +Real, -Fraction).
%
% Fraction ist der einfachste Bruch (kleinster Nenner, dann kleinster
% Betrag) mit |Fraction - Real| =< Eps, exakt gerechnet.
number_to_rational(Eps0, Real0, Fraction) :-
    (   var(Eps0) -> instantiation_error(number_to_rational/3)
    ;   \+ number(Eps0) -> type_error(number, Eps0, number_to_rational/3)
    ;   Eps0 < 0 -> domain_error(not_less_than_zero, Eps0, number_to_rational/3)
    ;   var(Real0) -> instantiation_error(number_to_rational/3)
    ;   \+ number(Real0) -> type_error(number, Real0, number_to_rational/3)
    ;   Eps is rational(Eps0),
        Real is rational(Real0),
        Lo is Real - Eps,
        Hi is Real + Eps,
        '$simplest_rational'(Lo, Hi, Fraction)
    ).

%% rational_numerator_denominator(+Fraction, -Numerator, -Denominator).
%
% Zähler und Nenner eines Bruchs (einer Ganzzahl: Nenner 1).
rational_numerator_denominator(R, N, D) :-
    rational(R, N, D).

/* Zahlentheorie (PrologEx; Rechnung in Elixir, PrologEx.NumberTheory)

  * is_prime(+N): Baillie-PSW nach Probedivision; unter 2^64 bewiesen
    exakt, darüber ohne bekanntes Gegenbeispiel. N < 2: scheitert.
  * next_prime(+N, -P): kleinste Primzahl > N; prev_prime(+N, -P): größte
    < N (N =< 2: scheitert).
  * primes_between(+L, +H, -Ps): die Primzahlen in L..H, aufsteigend.
  * factorize(+N, -PEs): N >= 1, PEs = [P1-E1, ...] mit P1 < P2 < ...
    (factorize(1, [])); prime_factors(+N, -Ps): die Primfaktoren mit
    Vielfachheit, aufsteigend. Probedivision bis 10^4, Potenzen, Pollard
    p-1 (Stufe 1, B1 = 10^5, ab 2^64) und Pollard-Rho (Brent); beide in
    Stücken, zwischen denen Zeitgrenzen und Abbruch greifen.
  * divisors(+N, -Ds): alle Teiler aufsteigend; totient(+N, -T): Eulers phi.
  * factorial(+N, -F), binomial(+N, +K, -B): N >= 0; K < 0 oder K > N: 0.
  * isqrt(+N, -R), iroot(+N, +K, -R): abgerundete Quadrat- bzw. K-te Wurzel
    (N >= 0, K >= 1).
  * mod_inverse(+A, +M, -I): A*I =:= 1 (mod M), 0 =< I < M (M >= 1);
    scheitert, wenn gcd(A, M) =\= 1.
  * jacobi(+A, +N, -J): Jacobi-Symbol, N ungerade und >= 1.

  Fehler: ungebunden instantiation_error, keine Ganzzahl
  type_error(integer, X), zu klein domain_error(not_less_than_zero bzw.
  not_less_than_one, X); Kontext das Prädikat.
*/

%% bit_is_set(+N, +K).
%
% Bit K (>= 0) von N ist gesetzt (negative N im Zweierkomplement). Wie
% getbit(N, K) =:= 1 (auswertbare Funktion, wie SWI): ohne die
% verschobene Zahl, wo das teurer ist – für große N der kürzere Weg über
% eine Maske aus K Bits oder den Rest oberhalb von K.
bit_is_set(N, K) :-
    '$bit_is_set'(N, K).

is_prime(N) :-
    '$int_arg'(N, none, _, is_prime/1),
    '$is_prime'(N).

next_prime(N, P) :-
    '$int_arg'(N, none, _, next_prime/2),
    '$next_prime'(N, P).

prev_prime(N, P) :-
    '$int_arg'(N, none, _, prev_prime/2),
    '$prev_prime'(N, P).

primes_between(L, H, Ps) :-
    '$int_arg'(L, none, _, primes_between/3),
    '$int_arg'(H, none, _, primes_between/3),
    '$primes_between'(L, H, Ps).

factorize(N, PEs) :-
    '$int_arg'(N, 1, not_less_than_one, factorize/2),
    factorize_(N, PEs).

prime_factors(N, Ps) :-
    '$int_arg'(N, 1, not_less_than_one, prime_factors/2),
    factorize_(N, PEs),
    expand_pes(PEs, Ps).

divisors(N, Ds) :-
    '$int_arg'(N, 1, not_less_than_one, divisors/2),
    factorize_(N, PEs),
    '$divisors'(PEs, Ds).

totient(N, T) :-
    '$int_arg'(N, 1, not_less_than_one, totient/2),
    factorize_(N, PEs),
    '$totient'(PEs, T).

factorial(N, F) :-
    '$int_arg'(N, 0, not_less_than_zero, factorial/2),
    '$factorial'(N, F).

binomial(N, K, B) :-
    '$int_arg'(N, 0, not_less_than_zero, binomial/3),
    '$int_arg'(K, none, _, binomial/3),
    '$binomial'(N, K, B).

isqrt(N, R) :-
    '$int_arg'(N, 0, not_less_than_zero, isqrt/2),
    '$isqrt'(N, R).

iroot(N, K, R) :-
    '$int_arg'(N, 0, not_less_than_zero, iroot/3),
    '$int_arg'(K, 1, not_less_than_one, iroot/3),
    '$iroot'(N, K, R).

mod_inverse(A, M, I) :-
    '$int_arg'(A, none, _, mod_inverse/3),
    '$int_arg'(M, 1, not_less_than_one, mod_inverse/3),
    '$mod_inverse'(A, M, I).

jacobi(A, N, J) :-
    '$int_arg'(A, none, _, jacobi/3),
    '$int_arg'(N, 1, not_less_than_one, jacobi/3),
    (   N /\ 1 =:= 1 -> '$jacobi'(A, N, J)
    ;   domain_error(odd, N, jacobi/3)
    ).

% kleine Faktoren durch Probedivision (aufsteigend), der Rest hat nur
% größere
factorize_(N, PEs) :-
    '$trial_factor'(N, PEs0, M),
    factor_big(M, Ps0),
    msort(Ps0, Ps),
    pack(Ps, PEs1),
    append(PEs0, PEs1, PEs).

factor_big(1, []) :- !.
factor_big(M, [M]) :- '$is_prime'(M), !.
factor_big(M, Ps) :-
    '$perfect_power'(M, R, K), !,
    factor_big(R, Ps0),
    copies(K, Ps0, Ps).
factor_big(M, Ps) :-
    split(M, D),
    M1 is M // D,
    factor_big(D, Ps1),
    factor_big(M1, Ps2),
    append(Ps1, Ps2, Ps).

copies(0, _, []) :- !.
copies(K, Ps0, Ps) :-
    K1 is K - 1,
    copies(K1, Ps0, Ps1),
    append(Ps0, Ps1, Ps).

% ein echter Teiler D von M (ungerade, zusammengesetzt, keine Potenz)
split(M, D) :-
    (   M >= 18446744073709551616, pm1(M, 2, 0, D0) -> D = D0
    ;   rho(M, 1, D)
    ).

pm1(M, A, I, D) :-
    '$pm1'(M, A, I, R),
    (   R = found(D) -> true
    ;   R = more(A1, I1) -> pm1(M, A1, I1, D)
    ).

rho(M, C, D) :-
    rho_(M, C, start, D).

rho_(M, C, S, D) :-
    '$rho'(M, C, S, R),
    (   R = found(D) -> true
    ;   R = more(S1) -> rho_(M, C, S1, D)
    ;   C1 is C + 1,
        rho(M, C1, D)
    ).

pack([], []).
pack([P|Ps], [P-E|PEs]) :-
    run(Ps, P, 1, E, Rest),
    pack(Rest, PEs).

run([Q|Qs], P, E0, E, Rest) :-
    Q =:= P, !,
    E1 is E0 + 1,
    run(Qs, P, E1, E, Rest).
run(Rest, _, E, E, Rest).

expand_pes([], []).
expand_pes([P-E|PEs], Ps) :-
    expand_pe(E, P, Ps, Ps1),
    expand_pes(PEs, Ps1).

expand_pe(0, _, Ps, Ps) :- !.
expand_pe(E, P, [P|Ps], Ps1) :-
    E1 is E - 1,
    expand_pe(E1, P, Ps, Ps1).
