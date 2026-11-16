:- use_module(library(simplex)).

% Beispiele aus der Dokumentation von library(simplex) (Markus Triska),
% dazu benannte Bedingungen, Transport- und Zuordnungsproblem

radiation(S) :- gen_state(S0), post_constraints(S0, S1), minimize([0.4*x1, 0.5*x2], S1, S).
post_constraints -->
	constraint([0.3*x1, 0.1*x2] =< 2.7),
	constraint([0.5*x1, 0.5*x2] = 6),
	constraint([0.6*x1, 0.4*x2] >= 6),
	constraint([x1] >= 0),
	constraint([x2] >= 0).

knapsack(S) :- knapsack_constraints(S0), maximize([7*x(1), 4*x(2)], S0, S).
knapsack_constraints(S) :-
	gen_state(S0),
	constraint([6*x(1), 4*x(2)] =< 8, S0, S1),
	constraint([x(1)] =< 1, S1, S2),
	constraint([x(2)] =< 2, S2, S).
knapsack_integral(S) :-
	knapsack_constraints(S0),
	constraint(integral(x(1)), S0, S1),
	constraint(integral(x(2)), S1, S2),
	maximize([7*x(1), 4*x(2)], S2, S).

coins(S) :- gen_state(S0), coins(S0, S).
coins -->
	constraint([c(1), 5*c(5), 20*c(20)] = 111),
	constraint([c(1)] =< 3),
	constraint([c(5)] =< 20),
	constraint([c(20)] =< 10),
	constraint([c(1)] >= 0),
	constraint([c(5)] >= 0),
	constraint([c(20)] >= 0),
	constraint(integral(c(1))),
	constraint(integral(c(5))),
	constraint(integral(c(20))),
	minimize([c(1), c(5), c(20)]).

named(S) :-
	gen_state(S0),
	constraint(c1, [x, y] =< 4, S0, S1),
	constraint(c2, [x, 3*y] =< 6, S1, S2),
	constraint([x] >= 0, S2, S3),
	constraint([y] >= 0, S3, S4),
	maximize([3*x, 5*y], S4, S).

values(S, Vars, Vals) :- values_(Vars, S, Vals).
values_([], _, []).
values_([V|Vs], S, [X|Xs]) :- variable_value(S, V, X), values_(Vs, S, Xs).

infeasible :-
	gen_state(G0), constraint([x] >= 3, G0, G1), constraint([x] =< 2, G1, G2),
	maximize([x], G2, _).
