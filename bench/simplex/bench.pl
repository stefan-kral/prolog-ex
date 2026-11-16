% Benchmark fuer library(simplex): dieselben Probleme in Scryer, SWI und
% PrologEx (Zufallszahlen aus einem LCG in Prolog, also ueberall gleich).
% Ergebnis je Fall: res(Name, ms, Pruefsumme) - beste Zeit aus 3 Laeufen;
% Pruefsumme: Summe der Zielwerte bzw. Kosten aller Probleme des Falls

rnd(S0, S, Lo, Hi, X) :- S is (S0*1103515245 + 12345) mod 2147483648, X is Lo + (S // 65536) mod (Hi - Lo + 1).

vars(N, Vs) :- vars_(1, N, Vs).
vars_(I, N, []) :- I > N, !.
vars_(I, N, [x(I)|Vs]) :- I1 is I+1, vars_(I1, N, Vs).

coeffs([], S, S, _, _, []).
coeffs([V|Vs], S0, S, Lo, Hi, [C*V|Cs]) :- rnd(S0, S1, Lo, Hi, C), coeffs(Vs, S1, S, Lo, Hi, Cs).

cons(0, _, R, R, St, St) :- !.
cons(K, Vs, R0, R, St0, St) :-
	coeffs(Vs, R0, R1, 0, 9, Cs), rnd(R1, R2, 20, 100, B),
	constraint(Cs =< B, St0, St1),
	K1 is K-1, cons(K1, Vs, R2, R, St1, St).

nonneg([], St, St).
nonneg([V|Vs], St0, St) :- constraint([V] >= 0, St0, St1), nonneg(Vs, St1, St).
integral([], St, St).
integral([V|Vs], St0, St) :- constraint(integral(V), St0, St1), integral(Vs, St1, St).

% LP: maximieren, Bedingungen =<, Variablen >= 0
lp(NV, NC, Seed, Obj) :-
	vars(NV, Vs), gen_state(S0),
	cons(NC, Vs, Seed, R1, S0, S1), nonneg(Vs, S1, S2),
	coeffs(Vs, R1, _, 1, 9, Os), maximize(Os, S2, S), objective(S, Obj).

% ganzzahlig (Branch-and-Bound)
ip(NV, NC, Seed, Obj) :-
	vars(NV, Vs), gen_state(S0),
	cons(NC, Vs, Seed, R1, S0, S1), nonneg(Vs, S1, S2), integral(Vs, S2, S3),
	coeffs(Vs, R1, _, 1, 9, Os), maximize(Os, S3, S), objective(S, Obj).

nums(0, R, R, _, _, []) :- !.
nums(K, R0, R, Lo, Hi, [X|Xs]) :- rnd(R0, R1, Lo, Hi, X), K1 is K-1, nums(K1, R1, R, Lo, Hi, Xs).
rows(0, R, R, _, _, _, []) :- !.
rows(K, R0, R, N, Lo, Hi, [Row|Rows]) :- nums(N, R0, R1, Lo, Hi, Row), K1 is K-1, rows(K1, R1, R, N, Lo, Hi, Rows).

sum([], S, S).
sum([X|Xs], S0, S) :- S1 is S0 + X, sum(Xs, S1, S).
dot([], [], S, S).
dot([X|Xs], [Y|Ys], S0, S) :- S1 is S0 + X*Y, dot(Xs, Ys, S1, S).
mdot([], [], S, S).
mdot([R|Rs], [C|Cs], S0, S) :- dot(R, C, S0, S1), mdot(Rs, Cs, S1, S).

% Transport: N Lieferanten, N Abnehmer, Summen gleich
transport(N, Seed, Cost) :-
	nums(N, Seed, R1, 10, 50, Supplies), sum(Supplies, 0, Total),
	N1 is N-1, nums(N1, R1, R2, 1, 5, Ws0), sum(Ws0, 0, W),
	demands(Ws0, W, Total, Ds0), sum(Ds0, 0, D0), Last is Total - D0,
	append(Ds0, [Last], Demands),
	rows(N, R2, _, N, 1, 20, Costs),
	transportation(Supplies, Demands, Costs, Plan), mdot(Plan, Costs, 0, Cost).
demands([], _, _, []).
demands([X|Xs], W, T, [D|Ds]) :- D is T*X // (W+2), demands(Xs, W, T, Ds).

% Zuordnung: N x N Kosten
assign(N, Seed, Cost) :-
	rows(N, Seed, _, N, 1, 50, Costs), assignment(Costs, As), mdot(As, Costs, 0, Cost).

% beste Zeit aus 3 Laeufen; Pruefsumme: Summe aller Ergebnisse von G
t(G, V, T, Vs) :- statistics(runtime, [T0,_]), findall(V, G, Vs), statistics(runtime, [T1,_]), T is T1-T0.
b(Name, G, V) :-
	catch(( t(G, V, T1, Vs), t(G, V, T2, _), t(G, V, T3, _), T is min(T1, min(T2, T3)) ), E,
	      (write(Name), write(' FEHLER '), write(E), nl, fail)),
	!, sum(Vs, 0, Chk),
	write(res(Name, T, Chk)), write('.'), nl.
b(Name, _, _) :- write(Name), write(' gescheitert'), nl.

suite :-
	b(lp_5x4, (between(1, 50, I), lp(5, 4, I, O)), O),
	b(lp_12x8, (between(1, 20, I), lp(12, 8, I, O)), O),
	b(lp_25x15, (between(1, 5, I), lp(25, 15, I, O)), O),
	b(ip_6x4, (between(1, 20, I), ip(6, 4, I, O)), O),
	b(ip_10x5, (between(1, 5, I), ip(10, 5, I, O)), O),
	b(transport_6, (between(1, 10, I), transport(6, I, O)), O),
	b(transport_12, (between(1, 3, I), transport(12, I, O)), O),
	b(assign_6, (between(1, 10, I), assign(6, I, O)), O),
	b(assign_12, (between(1, 3, I), assign(12, I, O)), O).
