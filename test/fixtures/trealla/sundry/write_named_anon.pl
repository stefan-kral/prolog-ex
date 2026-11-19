% write_term/2 with variable_names/1 gave up on a variable written '_' without following it, so a name the list gave
% the variable it was bound to went unused: f(_1) for f(A).

:- initialization(main).

main :-
	T = f(_), term_variables(T, [V]), write_term(T, [variable_names(['A'=V])]), nl,
	U = g(_, X), X = Y, term_variables(U, [W|_]), write_term(U-Y, [variable_names(['A'=W, 'B'=Y])]), nl.
