% Testprogramme: nur Konjunktionen, Builtins und eigene Praedikate (kein
% Schnitt, kein if-then-else), damit jeder Meta-Interpreter sie ausfuehrt
nrev([], []).
nrev([X|Xs], R) :- nrev(Xs, R0), app(R0, [X], R).
app([], L, L).
app([X|Xs], L, [X|R]) :- app(Xs, L, R).

range(M, N, []) :- M > N.
range(M, N, [M|Ns]) :- M =< N, M1 is M+1, range(M1, N, Ns).
sel(X, [X|Xs], Xs).
sel(X, [Y|Ys], [Y|Zs]) :- sel(X, Ys, Zs).
queens(N, Qs) :- range(1, N, Ns), queens(Ns, [], Qs).
queens([], Qs, Qs).
queens([U|Us], Safe, Qs) :- sel(Q, [U|Us], R), safe(Q, 1, Safe), queens(R, [Q|Safe], Qs).
safe(_, _, []).
safe(X, N, [Y|Ys]) :- X =\= Y+N, X =\= Y-N, N1 is N+1, safe(X, N1, Ys).
