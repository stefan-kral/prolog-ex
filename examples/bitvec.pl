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

% --- mit Hilfstabellen -----------------------------------------------------------
%
% Statt zu rechnen, nachschlagen. Zwei Arten von Tabellen:
%
%  * ein Tupel t(A1, ..., Ak), gelesen mit arg/3. In PrologEx liegen die
%    Argumente einer Struktur als Liste vor: arg(K, T, A) braucht K
%    Schritte, im Mittel über ein 255-Tupel also 128. Dazu für den JIT
%    integer/1 nach arg/3 (sonst weiß er nicht, dass eine Zahl kommt, und
%    übersetzt das Prädikat nicht).
%  * eine Byte-Folge, gelesen mit bytes_at/3: O(1), im JIT direkt – für
%    Werte 0..255 (msb eines Bytes, das Byte ohne sein höchstes Bit).
%
%   pow_table(N, P)   P = p(1<<0, ..., 1<<(N-1)): Bit i als Ganzzahl
%   msb_table(M)      M = m(msb(1), ..., msb(255))
%   clr_table(C)      C = c(...): Byte X ohne sein höchstes Bit
%   bits_table(T)     T = b(...): die gesetzten Bits eines Bytes, absteigend

pow_table(N, P) :-
    N1 is N - 1,
    findall(W, (between(0, N1, I), W is 1 << I), Ws),
    P =.. [p|Ws].

msb_table(M) :-
    findall(I, (between(1, 255, X), I is msb(X)), Is),
    M =.. [m|Is].

clr_table(C) :-
    findall(Y, (between(1, 255, X), Y is X xor (1 << msb(X))), Ys),
    C =.. [c|Ys].

% dieselben als Byte-Folgen: Eintrag X-1 für das Byte X
msb_bytes(M) :-
    findall(I, (between(1, 255, X), I is msb(X)), Is),
    bytes_list(M, Is).

clr_bytes(C) :-
    findall(Y, (between(1, 255, X), Y is X xor (1 << msb(X))), Ys),
    bytes_list(C, Ys).

bits_table(T) :-
    findall(L, (between(1, 255, X), byte_list(X, L)), Ls),
    T =.. [b|Ls].

byte_list(0, []) :- !.
byte_list(X, [I|Is]) :- I is msb(X), X1 is X xor (1 << I), byte_list(X1, Is).

% int_pow(+P, +V, -Sum): wie int_msb, das Bit aus dem Tupel statt 1 << I
% (für große I eine neue Ganzzahl je Schritt weniger)
int_pow(P, V, S) :- int_pow(V, P, 0, S).
int_pow(0, _, S, S) :- !.
int_pow(V, P, S0, S) :-
    I is msb(V),
    S1 is S0 + I,
    K is I + 1,
    arg(K, P, W),
    integer(W),                         % für den JIT: W ist eine Zahl
    V1 is V xor W,
    int_pow(V1, P, S1, S).

% bytes_msbtab(+M-C, +B, -Sum): Byte für Byte, im Byte msb und Löschen
% nachgeschlagen (msb_table/1, clr_table/1) statt gerechnet
bytes_msbtab(M-C, B, S) :-
    bytes_length(B, L),
    bytes_msbtab(0, L, B, M, C, 0, S).
bytes_msbtab(K, L, _, _, _, S, S) :- K >= L, !.
bytes_msbtab(K, L, B, M, C, S0, S) :-
    bytes_at(K, B, X),
    Base is 8 * (L - 1 - K),
    byte_tab(X, Base, M, C, S0, S1),
    K1 is K + 1,
    bytes_msbtab(K1, L, B, M, C, S1, S).

byte_tab(0, _, _, _, S, S) :- !.
byte_tab(X, Base, M, C, S0, S) :-
    arg(X, M, I),
    integer(I),
    arg(X, C, X1),
    integer(X1),
    S1 is S0 + Base + I,
    byte_tab(X1, Base, M, C, S1, S).

% bytes_bytetab(+M-C, +B, -Sum): wie bytes_msbtab, die Tabellen als
% Byte-Folgen (msb_bytes/1, clr_bytes/1)
bytes_bytetab(M-C, B, S) :-
    bytes_length(B, L),
    bytes_bytetab(0, L, B, M, C, 0, S).
bytes_bytetab(K, L, _, _, _, S, S) :- K >= L, !.
bytes_bytetab(K, L, B, M, C, S0, S) :-
    bytes_at(K, B, X),
    Base is 8 * (L - 1 - K),
    byte_btab(X, Base, M, C, S0, S1),
    K1 is K + 1,
    bytes_bytetab(K1, L, B, M, C, S1, S).

byte_btab(0, _, _, _, S, S) :- !.
byte_btab(X, Base, M, C, S0, S) :-
    J is X - 1,
    bytes_at(J, M, I),
    bytes_at(J, C, X1),
    S1 is S0 + Base + I,
    byte_btab(X1, Base, M, C, S1, S).

% int_bytetab(+M-C, +N, +V, -Sum): die Ganzzahl Byte für Byte von oben
% ((V >> 8k) /\ 255), im Byte wie bytes_bytetab
int_bytetab(M-C, N, V, S) :-
    K is (N + 7) // 8 - 1,
    int_bytetab(K, V, M, C, 0, S).
int_bytetab(K, _, _, _, S, S) :- K < 0, !.
int_bytetab(K, V, M, C, S0, S) :-
    X is (V >> (8 * K)) /\ 255,
    Base is 8 * K,
    byte_btab(X, Base, M, C, S0, S1),
    K1 is K - 1,
    int_bytetab(K1, V, M, C, S1, S).

% bytes_listtab(+T, +B, -Sum): Byte für Byte, die gesetzten Bits des
% Bytes als Liste aus bits_table/1
bytes_listtab(T, B, S) :-
    bytes_length(B, L),
    bytes_listtab(0, L, B, T, 0, S).
bytes_listtab(K, L, _, _, S, S) :- K >= L, !.
bytes_listtab(K, L, B, T, S0, S) :-
    bytes_at(K, B, X),
    (   X =:= 0
    ->  S1 = S0
    ;   Base is 8 * (L - 1 - K),
        arg(X, T, Is),
        add_bits(Is, Base, S0, S1)
    ),
    K1 is K + 1,
    bytes_listtab(K1, L, B, T, S1, S).

add_bits([], _, S, S).
add_bits([I|Is], Base, S0, S) :- S1 is S0 + Base + I, add_bits(Is, Base, S1, S).

% --- Umwandeln ----------------------------------------------------------------

% int_to_bytes(+V, +N, -B): V (0 =< V < 2^N) als Folge aus ceil(N/8)
% Bytes (Big-Endian: bytes_integer/3)
int_to_bytes(V, N, B) :-
    L is (N + 7) // 8,
    bytes_integer(B, L, V).

% --- Messen ---------------------------------------------------------------------

variant(int_msb,        int,   int_msb).
variant(int_scan,       int,   int_scan).
variant(int_pow,        int,   int_pow).
variant(int_bytetab,    int,   int_bytetab).
variant(bytes_next,     bytes, bytes_next).
variant(bytes_bits,     bytes, bytes_bits).
variant(bytes_bytewise, bytes, bytes_bytewise).
variant(bytes_msbtab,   bytes, bytes_msbtab).
variant(bytes_bytetab,  bytes, bytes_bytetab).
variant(bytes_listtab,  bytes, bytes_listtab).

% bench: N = 20, 60, 100, 200; je 2000 zufällige Vektoren, 5 Runden
bench :- bench([20, 60, 100, 200], 2000, 5).

bench(Ns, M, R) :-
    format("~w Vektoren je n, ~w Runden; Zeit je Vektor in µs~n~n", [M, R]),
    findall(N-Rs, (member(N, Ns), bench_n(N, M, R, Rs)), Table),
    format("~w~t~16|", [variante]),
    forall(member(N, Ns), format("~t~w~9+", [N])),
    nl,
    forall(variant(Name, _, _),
           ( format("~w~t~16|", [Name]),
             forall(member(_-Rs, Table),
                    ( memberchk(Name-Us, Rs), format("~t~1f~9+", [Us]) )),
             nl )).

% bench_n(+N, +M, +R, -[Variante-µs]): alle Varianten müssen dieselben
% Summen liefern
bench_n(N, M, R, Rs) :-
    set_random(seed(N)),
    Max is 1 << N,
    findall(V, (between(1, M, _), V is random(Max)), Vs),
    maplist([V, B]>>int_to_bytes(V, N, B), Vs, Bs),
    findall(Name-(Us-Sums),
            ( variant(Name, Kind, P),
              ( Kind == int -> Xs = Vs ; Xs = Bs ),
              run(P, N, Xs, R, Us, Sums)
            ),
            Results),
    (   Results = [_-(_-S0)|Rest], forall(member(_-(_-S), Rest), S == S0)
    ->  true
    ;   format("ABWEICHUNG bei n = ~w~n", [N])
    ),
    findall(Name-Us, member(Name-(Us-_), Results), Rs).

% run(+P, +N, +Xs, +Runden, -µs je Vektor, -Summen)
run(P, N, Xs, R, Us, Sums) :-
    length(Xs, M),
    sums(P, N, Xs, _),                  % warm (JIT, erste Aufrufe)
    statistics(cputime, T0),
    forall(between(1, R, _), sums(P, N, Xs, _)),
    statistics(cputime, T1),
    sums(P, N, Xs, Sums),
    Us is (T1 - T0) * 1.0e6 / (R * M).

% die Tupel einmal je Runde (2000 Vektoren; ein paar µs)
sums(int_scan, N, Xs, Ss) :- !, maplist(int_scan(N), Xs, Ss).
sums(int_pow, N, Xs, Ss) :- !, pow_table(N, P), maplist(int_pow(P), Xs, Ss).
sums(int_bytetab, N, Xs, Ss) :- !,
    msb_bytes(M), clr_bytes(C), maplist(int_bytetab(M-C, N), Xs, Ss).
sums(bytes_bytetab, _, Xs, Ss) :- !,
    msb_bytes(M), clr_bytes(C), maplist(bytes_bytetab(M-C), Xs, Ss).
sums(bytes_msbtab, _, Xs, Ss) :- !,
    msb_table(M), clr_table(C), maplist(bytes_msbtab(M-C), Xs, Ss).
sums(bytes_listtab, _, Xs, Ss) :- !, bits_table(T), maplist(bytes_listtab(T), Xs, Ss).
sums(P, _, Xs, Ss) :- maplist(P, Xs, Ss).
