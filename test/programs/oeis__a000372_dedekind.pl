% Dedekind-Zahlen (OEIS A000372): monotone Boolesche Funktionen von N
% Variablen, mit clpb. Eine Variable F(S) je Teilmenge S von {1..N}
% (als Bitmaske); monoton: F(S) =< F(S mit einem Element mehr).
:- use_module(library(clpb)).

dedekind(N, C) :-
    M is 1 << N,
    length(Fs, M),
    monotone(Fs, Fs, 0, N),
    sat_count(+[1|Fs], C).

% fuer jede Maske S (von 0 an) und jedes Bit I, das in S fehlt
monotone([], _, _, _).
monotone([F|Fs], All, S, N) :-
    bits(0, N, S, F, All),
    S1 is S + 1,
    monotone(Fs, All, S1, N).

bits(I, N, _, _, _) :- I >= N, !.
bits(I, N, S, F, All) :-
    (   S /\ (1 << I) =:= 0 ->
        T is S \/ (1 << I),
        nth(T, All, G),
        sat(F =< G)
    ;   true
    ),
    I1 is I + 1,
    bits(I1, N, S, F, All).

nth(0, [X|_], X) :- !.
nth(K, [_|Xs], X) :- K1 is K - 1, nth(K1, Xs, X).
