% read_term/3 unified the term last and without dereferencing it. A term that is only a variable could be bound by then,
% by one of the options: variables([a]) left T unbound, and a variables list escaping its frame took the variable away.

:- initialization(main).

rd(Atom, T, Opts) :- read_term_from_atom(Atom, T, Opts).

main :-
	rd('A', T1, [variables(V1)]), ( V1 == [T1] -> write(same) ; write(different) ), nl,
	rd('A', T2, [variable_names(N2)]), ( N2 = ['A'=X2], X2 == T2 -> write(same) ; write(different) ), nl,
	read_term_from_atom('A', T3, [variables([a])]), write(T3), nl,
	read_term_from_atom('A', T4, [variable_names(['A'=b])]), write(T4), nl.
