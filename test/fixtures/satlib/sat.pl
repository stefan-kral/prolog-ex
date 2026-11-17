% SATLIB-Formeln (cnf/3, expected/3) mit library(clpb): jede Klausel ein
% sat/1; erfüllbar heißt labeling/1 findet eine Belegung, die (hier ohne
% clpb nachgerechnet) jede Klausel wahr macht; Modelle zählt sat_count/2.
% Läuft auch in SWI-Prolog und Scryer (conformance/satlib/run.sh).
:- use_module(library(clpb)).
:- use_module(library(lists)).

post([], _).
post([C|Cs], Vs) :- clause_expr(C, Vs, E), sat(E), post(Cs, Vs).

clause_expr([L], Vs, E) :- !, lit(L, Vs, E).
clause_expr([L|Ls], Vs, E + F) :- lit(L, Vs, E), clause_expr(Ls, Vs, F).

lit(L, Vs, X) :- L > 0, !, nth1(L, Vs, X).
lit(L, Vs, ~X) :- M is -L, nth1(M, Vs, X).

true_clause(C, Vs) :-
    member(L, C),
    ( L > 0 -> nth1(L, Vs, 1) ; M is -L, nth1(M, Vs, 0) ), !.

all_true([], _).
all_true([C|Cs], Vs) :- true_clause(C, Vs), all_true(Cs, Vs).

% R: sat, unsat oder falsche_belegung
solve(N, Cls, R) :-
    length(Vs, N),
    (   post(Cls, Vs)
    ->  labeling(Vs), ( all_true(Cls, Vs) -> R = sat ; R = falsche_belegung )
    ;   R = unsat
    ).

count(N, Cls, K) :- length(Vs, N), ( post(Cls, Vs) -> sat_count(+[1|Vs], K) ; K = 0 ).

% V = ok oder das abweichende Ergebnis-Modelle
verdict(F, V) :-
    cnf(F, N, Cls), expected(F, E, C),
    once(solve(N, Cls, R)),
    ( C == none -> K = none ; count(N, Cls, K) ),
    ( R-K == E-C -> V = ok ; V = R-K ).
