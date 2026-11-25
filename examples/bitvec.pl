% Bitvektoren: über die gesetzten Bits iterieren, vom höchsten zum
% niedrigsten – einmal als Ganzzahl, einmal als Byte-Folge
% (library(bytes)). Als Beispielaufgabe: die Indizes der gesetzten Bits
% aufsummieren (Bit i hat den Wert 2^i).
%
%   start_ex examples/bitvec.pl -g bench -q
%   start_ex examples/bitvec.pl -g "bench([20,60,100,200], 2000, 5)" -q
%
% Byte-Folge: Bit 0 ist das höchste Bit des ersten Bytes (wie Erlangs
% Bit-Syntax). Eine Folge aus L Bytes ist die Ganzzahl in Big-Endian; Bit
% P der Folge ist Bit 8L-1-P der Ganzzahl. Von vorn nach hinten heißt also
% von msb nach lsb.

:- use_module(library(bytes)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(aggregate)).
:- use_module(library(random)).
:- use_module(library(format)).
:- use_module(library(yall)).
:- use_module(library(apply)).

% --- Ganzzahl ------------------------------------------------------------------

% int_msb(+V, -Sum): msb/1 liefert das höchste gesetzte Bit; löschen,
% weiter. Ein Schritt je gesetztem Bit.
int_msb(V, S) :- int_msb(V, 0, S).
int_msb(0, S, S) :- !.
int_msb(V, S0, S) :-
    I is msb(V),
    S1 is S0 + I,
    V1 is V xor (1 << I),
    int_msb(V1, S1, S).

% int_scan(+N, +V, -Sum): alle N Bits von oben prüfen (getbit/2). Ein
% Schritt je Bit, gesetzt oder nicht.
int_scan(N, V, S) :- I is N - 1, int_scan(I, V, 0, S).
int_scan(I, _, S, S) :- I < 0, !.
int_scan(I, V, S0, S) :-
    ( getbit(V, I) =:= 1 -> S1 is S0 + I ; S1 = S0 ),
    I1 is I - 1,
    int_scan(I1, V, S1, S).

% --- Byte-Folge ------------------------------------------------------------------

% bytes_bits(+B, -Sum): bytes_bit/3 mit freiem Index und Bit 1 zählt die
% gesetzten Bits von vorn auf (Rücksetzen, Nullbytes übersprungen).
bytes_bits(B, S) :-
    bytes_length(B, L),
    Top is 8 * L - 1,
    aggregate_all(sum(I), (bytes_bit(P, B, 1), I is Top - P), S).

% bytes_next(+B, -Sum): bytes_next_bit/3 springt zum nächsten gesetzten
% Bit (in Elixir; Nullbytes in Stücken zu acht übersprungen). Ein Schritt
% je gesetztem Bit, ohne Rücksetzen.
bytes_next(B, S) :-
    bytes_length(B, L),
    Top is 8 * L - 1,
    bytes_next(B, 0, Top, 0, S).
bytes_next(B, P0, Top, S0, S) :-
    (   bytes_next_bit(B, P0, P)
    ->  S1 is S0 + Top - P,
        P1 is P + 1,
        bytes_next(B, P1, Top, S1, S)
    ;   S = S0
    ).

% bytes_bytewise(+B, -Sum): Byte für Byte (bytes_at/3), Nullbytes
% übergehen, in einem Byte wie bei der Ganzzahl (msb/1 auf 0..255).
bytes_bytewise(B, S) :-
    bytes_length(B, L),
    bytes_bytewise(0, L, B, 0, S).
bytes_bytewise(K, L, _, S, S) :- K >= L, !.
bytes_bytewise(K, L, B, S0, S) :-
    bytes_at(K, B, X),
    (   X =:= 0
    ->  S1 = S0
    ;   Base is 8 * (L - 1 - K),
        byte_bits(X, Base, S0, S1)
    ),
    K1 is K + 1,
    bytes_bytewise(K1, L, B, S1, S).

byte_bits(0, _, S, S) :- !.
byte_bits(X, Base, S0, S) :-
    I is msb(X),
    S1 is S0 + Base + I,
    X1 is X xor (1 << I),
    byte_bits(X1, Base, S1, S).

% --- Umwandeln ----------------------------------------------------------------

% int_to_bytes(+V, +N, -B): V (0 =< V < 2^N) als Folge aus ceil(N/8)
% Bytes (Big-Endian: bytes_integer/3)
int_to_bytes(V, N, B) :-
    L is (N + 7) // 8,
    bytes_integer(B, L, V).

% --- Messen ---------------------------------------------------------------------

variant(int_msb,        int,   int_msb).
variant(int_scan,       int,   int_scan).
variant(bytes_next,     bytes, bytes_next).
variant(bytes_bits,     bytes, bytes_bits).
variant(bytes_bytewise, bytes, bytes_bytewise).

% bench: N = 20, 60, 100, 200; je 2000 zufällige Vektoren, 5 Runden
bench :- bench([20, 60, 100, 200], 2000, 5).

bench(Ns, M, R) :-
    format("~w Vektoren je n, ~w Runden; Zeit je Vektor in µs~n~n", [M, R]),
    format("~w~t~6|", [n]),
    forall(variant(Name, _, _), format("~t~w~18+", [Name])),
    nl,
    forall(member(N, Ns), bench_n(N, M, R)).

bench_n(N, M, R) :-
    set_random(seed(N)),
    Max is 1 << N,
    findall(V, (between(1, M, _), V is random(Max)), Vs),
    maplist([V, B]>>int_to_bytes(V, N, B), Vs, Bs),
    format("~w~t~6|", [N]),
    findall(Name-Sums,
            ( variant(Name, Kind, P),
              ( Kind == int -> Xs = Vs ; Xs = Bs ),
              run(P, N, Xs, R, Us, Sums),
              format("~t~2f~18+", [Us])
            ),
            Results),
    nl,
    % alle Varianten müssen dieselben Summen liefern
    (   Results = [_-S0|Rest], forall(member(_-S, Rest), S == S0)
    ->  true
    ;   format("  ABWEICHUNG bei n = ~w~n", [N])
    ).

% run(+P, +N, +Xs, +Runden, -µs je Vektor, -Summen)
run(P, N, Xs, R, Us, Sums) :-
    length(Xs, M),
    sums(P, N, Xs, _),                  % warm (JIT, erste Aufrufe)
    statistics(cputime, T0),
    forall(between(1, R, _), sums(P, N, Xs, _)),
    statistics(cputime, T1),
    sums(P, N, Xs, Sums),
    Us is (T1 - T0) * 1.0e6 / (R * M).

sums(int_scan, N, Xs, Ss) :- !, maplist(int_scan(N), Xs, Ss).
sums(P, _, Xs, Ss) :- maplist(P, Xs, Ss).
