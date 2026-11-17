% Lateinische Quadrate der Ordnung N (OEIS A002860) mit clpz: jede Zeile
% und jede Spalte enthaelt 1..N genau einmal.
:- use_module(library(clpz)).
:- use_module(library(lists)).

latin(N, Rows) :-
    length(Rows, N),
    rows(Rows, N),
    all_rows(Rows),
    transp(Rows, Cols),
    all_rows(Cols),
    label_rows(Rows).

rows([], _).
rows([R|Rs], N) :- length(R, N), R ins 1..N, rows(Rs, N).

all_rows([]).
all_rows([R|Rs]) :- all_different(R), all_rows(Rs).

label_rows([]).
label_rows([R|Rs]) :- label(R), label_rows(Rs).

transp([], []).
transp([[]|_], []) :- !.
transp(Rows, [Col|Cols]) :- firsts(Rows, Col, Rest), transp(Rest, Cols).

firsts([], [], []).
firsts([[X|Xs]|Rs], [X|Col], [Xs|Rest]) :- firsts(Rs, Col, Rest).
