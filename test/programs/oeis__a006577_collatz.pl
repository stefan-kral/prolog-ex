% Collatz (3x+1, Hailstone): Schritte bis 1 (OEIS A006577), groesster
% Wert unterwegs (A025586), die Startwerte mit neuem Rekord an Schritten
% (A006877) samt Schrittzahl (A006878), die Folge selbst.
steps(N, S) :- steps(N, 0, S).

steps(1, S, S) :- !.
steps(N, S0, S) :- next(N, M), S1 is S0 + 1, steps(M, S1, S).

next(N, M) :- ( N mod 2 =:= 0 -> M is N // 2 ; M is 3 * N + 1 ).

peak(N, P) :- peak(N, N, P).

peak(1, P, P) :- !.
peak(N, P0, P) :- next(N, M), ( M > P0 -> P1 = M ; P1 = P0 ), peak(M, P1, P).

hailstone(1, [1]) :- !.
hailstone(N, [N|Ns]) :- next(N, M), hailstone(M, Ns).

% Schrittzahlen bzw. Hoechstwerte fuer 1..N
steps_upto(N, L) :- map_upto(1, N, steps, L).
peaks_upto(N, L) :- map_upto(1, N, peak, L).

map_upto(I, N, _, []) :- I > N, !.
map_upto(I, N, P, [X|Xs]) :- G =.. [P, I, X], call(G), I1 is I + 1, map_upto(I1, N, P, Xs).

% die Rekordhalter bis N als Liste Start-Schritte
records(N, Rs) :- records(1, N, -1, Rs).

records(I, N, _, []) :- I > N, !.
records(I, N, Best, Rs) :-
    steps(I, S),
    I1 is I + 1,
    (   S > Best -> Rs = [I-S|Rs1], records(I1, N, S, Rs1)
    ;   records(I1, N, Best, Rs)
    ).
last_of([X], X) :- !.
last_of([_|Xs], X) :- last_of(Xs, X).
