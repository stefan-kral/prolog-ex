% Fixpunktfreie Permutationen (OEIS A000166) von 1..N, zweimal:
% derangement/2 erzeugt und prueft (=\=), derangement_dif/2 stellt erst
% dif/2 fuer jede Stelle und erzeugt dann (Coroutining beim Aufzaehlen).
:- use_module(library(dif)).

derangement(N, P) :-
    upto(1, N, L),
    perm(L, P),
    no_fixpoint(P, 1).

derangement_dif(N, P) :-
    upto(1, N, L),
    length(P, N),
    difs(P, 1),
    perm(L, P).

perm([], []).
perm(L, [X|Xs]) :- sel(X, L, R), perm(R, Xs).

sel(X, [X|Xs], Xs).
sel(X, [Y|Ys], [Y|Zs]) :- sel(X, Ys, Zs).

no_fixpoint([], _).
no_fixpoint([X|Xs], I) :- X =\= I, I1 is I + 1, no_fixpoint(Xs, I1).

difs([], _).
difs([X|Xs], I) :- dif(X, I), I1 is I + 1, difs(Xs, I1).

upto(I, N, []) :- I > N, !.
upto(I, N, [I|Is]) :- I1 is I + 1, upto(I1, N, Is).
