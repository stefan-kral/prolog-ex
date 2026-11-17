% Peano-Arithmetik nach "The Art of Prolog" (Sterling/Shapiro), Kapitel 3
% (Programme 3.1-3.9), mit umbenannten Praedikaten: plus/3 und =< sind in
% SWI eingebaut. nat/1, le/2, add/3, mul/3, pow/3, fact/2, minimum/3,
% mod/3 (Programm 3.8b, das fuer gebundene X, Y endet), ack/3, gcd/3;
% dazu Umwandlung von und nach Ganzzahlen, Teiler und Kompositionen
% (relational, mit OEIS-Anzahlen) und Vergleiche mit is/2.

nat(0).
nat(s(X)) :- nat(X).

le(0, X) :- nat(X).
le(s(X), s(Y)) :- le(X, Y).

lt(X, Y) :- le(s(X), Y).

add(0, X, X) :- nat(X).
add(s(X), Y, s(Z)) :- add(X, Y, Z).

mul(0, X, 0) :- nat(X).
mul(s(X), Y, Z) :- mul(X, Y, XY), add(XY, Y, Z).

% pow(N, X, Y): Y = X^N
pow(s(N), 0, 0) :- nat(N).
pow(0, s(X), s(0)) :- nat(X).
pow(s(N), X, Y) :- pow(N, X, Z), mul(Z, X, Y).

fact(0, s(0)).
fact(s(N), F) :- fact(N, F1), mul(s(N), F1, F).

% wie im Buch: bei gleichen Zahlen zwei Loesungen
minimum(N1, N2, N1) :- le(N1, N2).
minimum(N1, N2, N2) :- le(N2, N1).

mod(X, Y, X) :- lt(X, Y).
mod(X, Y, Z) :- add(X1, Y, X), mod(X1, Y, Z).

ack(0, N, s(N)).
ack(s(M), 0, V) :- ack(M, s(0), V).
ack(s(M), s(N), V) :- ack(s(M), N, V1), ack(M, V1, V).

gcd(X, Y, G) :- lt(0, Y), mod(X, Y, Z), gcd(Y, Z, G).
gcd(X, 0, X) :- lt(0, X).

% --- Umwandlung --------------------------------------------------------------

% int_peano(+N, -P) und peano_int(+P, -N), endrekursiv
int_peano(N, P) :- int_peano(N, 0, P).
int_peano(0, P, P) :- !.
int_peano(N, P0, P) :- N1 is N - 1, int_peano(N1, s(P0), P).

peano_int(P, N) :- peano_int(P, 0, N).
peano_int(0, N, N).
peano_int(s(P), N0, N) :- N1 is N0 + 1, peano_int(P, N1, N).

% --- relational --------------------------------------------------------------

% Teiler von N (OEIS A000005): le/2 zaehlt die Kandidaten auf, mod/3
% prueft (mul(D, _, N) endete nicht: mul(0, X, 0) :- nat(X) zaehlt alle X
% auf)
divisor(N, D) :- le(D, N), lt(0, D), mod(N, D, 0).

divisors_of(K, C) :- int_peano(K, N), findall(D, divisor(N, D), Ds), len(Ds, C).

% Kompositionen von N in positive Teile (OEIS A011782): add/3 zerlegt
composition(0, []).
composition(N, [P|Ps]) :- add(P, R, N), lt(0, P), composition(R, Ps).

compositions_of(K, C) :- int_peano(K, N), findall(Ps, composition(N, Ps), L), len(L, C).

% die Zerlegungen von N in zwei Summanden: N+1 Stueck
splits_of(K, C) :- int_peano(K, N), findall(X-Y, add(X, Y, N), L), len(L, C).

len(L, N) :- len(L, 0, N).
len([], N, N).
len([_|T], N0, N) :- N1 is N0 + 1, len(T, N1, N).

% --- gegen is/2 ----------------------------------------------------------------

% Abweichungen fuer alle A, B in 0..Max: add, mul, le, lt, mod, gcd, minimum
mismatches(Max, Bad) :- findall(B, mismatch(Max, B), Bad).

mismatch(Max, add(A, B)) :- pair(Max, A, B), \+ ok_add(A, B).
mismatch(Max, mul(A, B)) :- pair(Max, A, B), \+ ok_mul(A, B).
mismatch(Max, le(A, B)) :- pair(Max, A, B), \+ ok_le(A, B).
mismatch(Max, mod(A, B)) :- pair(Max, A, B), B > 0, \+ ok_mod(A, B).
mismatch(Max, gcd(A, B)) :- pair(Max, A, B), B > 0, A > 0, \+ ok_gcd(A, B).
mismatch(Max, minimum(A, B)) :- pair(Max, A, B), \+ ok_min(A, B).

pair(Max, A, B) :- upto(0, Max, A), upto(0, Max, B).

upto(I, N, I) :- I =< N.
upto(I, N, X) :- I < N, I1 is I + 1, upto(I1, N, X).

ok_add(A, B) :- int_peano(A, X), int_peano(B, Y), add(X, Y, Z), peano_int(Z, C), C =:= A + B,
    findall(Z1, add(X, Y, Z1), [_]).
ok_mul(A, B) :- int_peano(A, X), int_peano(B, Y), mul(X, Y, Z), peano_int(Z, C), C =:= A * B,
    findall(Z1, mul(X, Y, Z1), [_]).
ok_le(A, B) :- int_peano(A, X), int_peano(B, Y), ( le(X, Y) -> A =< B ; A > B ).
ok_mod(A, B) :- int_peano(A, X), int_peano(B, Y), findall(Z, mod(X, Y, Z), [Z]), peano_int(Z, C),
    C =:= A mod B.
ok_gcd(A, B) :- int_peano(A, X), int_peano(B, Y), findall(G, gcd(X, Y, G), [G]), peano_int(G, C),
    gcd_int(A, B, C).
ok_min(A, B) :- int_peano(A, X), int_peano(B, Y), findall(M, minimum(X, Y, M), Ms),
    ( A =:= B -> len(Ms, 2) ; len(Ms, 1) ), Ms = [M|_], peano_int(M, C), C =:= min(A, B).

gcd_int(A, 0, A) :- !.
gcd_int(A, B, G) :- R is A mod B, gcd_int(B, R, G).

% --- tiefe Terme -------------------------------------------------------------

% 100 000 + 100 000 als Peano-Zahl, zurueck als Ganzzahl
deep_add(K, C) :- int_peano(K, P), add(P, P, Q), peano_int(Q, C).
% le/2 auf zwei tiefen Zahlen
deep_le(K) :- int_peano(K, P), K1 is K + 1, int_peano(K1, Q), le(P, Q), \+ le(Q, P).
