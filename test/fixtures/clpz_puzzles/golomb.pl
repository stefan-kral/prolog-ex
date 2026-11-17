% Golomb-Lineale: N Marken, alle Abstände verschieden; kürzeste Länge
% bekannt (OEIS A003022). clpz sucht das kürzeste (labeling min); geprüft
% wird ohne clpz, dass die Abstände verschieden sind
:- use_module(library(clpz)).
:- use_module(library(lists)).

optimal(1, 0). optimal(2, 1). optimal(3, 3). optimal(4, 6). optimal(5, 11).
optimal(6, 17). optimal(7, 25). optimal(8, 34). optimal(9, 44). optimal(10, 55).
optimal(11, 72). optimal(12, 85). optimal(13, 106). optimal(14, 127).

golomb(N, Ms, L) :-
    length(Ms, N), Ms = [0|_], last_(Ms, L),
    Max is N * N, Ms ins 0..Max,
    increasing(Ms),
    diffs(Ms, Ds), all_distinct(Ds),
    (   N >= 3 -> Ms = [_, M1|_], append(_, [Mp, L], Ms), M1 #< L - Mp
    ;   true
    ),
    labeling([min(L)], Ms).

last_([X], X) :- !.
last_([_|Xs], X) :- last_(Xs, X).

increasing([_]).
increasing([A,B|Ms]) :- A #< B, increasing([B|Ms]).

diffs([], []).
diffs([M|Ms], Ds) :- ds(Ms, M, Ds, Ds1), diffs(Ms, Ds1).
ds([], _, Ds, Ds).
ds([X|Xs], M, [D|Ds], Ds1) :- D #= X - M, ds(Xs, M, Ds, Ds1).

% ohne clpz
plain_diffs([], []).
plain_diffs([M|Ms], Ds) :- pds(Ms, M, Ds, Ds1), plain_diffs(Ms, Ds1).
pds([], _, Ds, Ds).
pds([X|Xs], M, [D|Ds], Ds1) :- D is X - M, pds(Xs, M, Ds, Ds1).

g_verdict(N, V) :-
    optimal(N, Opt),
    (   once(golomb(N, Ms, L))
    ->  plain_diffs(Ms, Ds), length(Ds, K), sort(Ds, S), length(S, KS),
        (   K =:= KS, L =:= Opt -> V = ok ; V = falsch(Ms) )
    ;   V = keine_loesung
    ).
