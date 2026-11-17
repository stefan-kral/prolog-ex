% Unabhaengige Mengen im N x N-Gitter (OEIS A006506: 0/1-Matrizen ohne
% zwei benachbarte Einsen) mit clpb: sat_count/2 zaehlt, ohne
% aufzuzaehlen.
:- use_module(library(clpb)).

grid_count(N, C) :-
    matrix(N, Rows),
    rows_ok(Rows),
    cols_ok(Rows),
    flat(Rows, Vs),
    sat_count(+[1|Vs], C).

matrix(N, Rows) :- length(Rows, N), lengths(Rows, N).
lengths([], _).
lengths([R|Rs], N) :- length(R, N), lengths(Rs, N).

rows_ok([]).
rows_ok([R|Rs]) :- row_ok(R), rows_ok(Rs).

row_ok([]).
row_ok([_]).
row_ok([A,B|T]) :- sat(~(A*B)), row_ok([B|T]).

cols_ok([]).
cols_ok([_]).
cols_ok([R1,R2|Rs]) :- pairs_ok(R1, R2), cols_ok([R2|Rs]).

pairs_ok([], []).
pairs_ok([A|As], [B|Bs]) :- sat(~(A*B)), pairs_ok(As, Bs).

flat([], []).
flat([R|Rs], Vs) :- flat(Rs, Vs0), app(R, Vs0, Vs).

app([], L, L).
app([X|Xs], L, [X|Ys]) :- app(Xs, L, Ys).
