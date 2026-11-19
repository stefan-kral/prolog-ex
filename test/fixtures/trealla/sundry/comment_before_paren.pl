% A comment between a name and ( is layout, as a space is, so it is not
% functional notation: with f a prefix operator f/**/(1,2) is f((1,2)),
% and with g no operator g/**/(1) is a syntax error.

:- initialization(main).

r(A) :-
	catch(( read_term_from_atom(A, T, []), write_canonical(T) ), error(syntax_error(_), _), write(syntax_error)),
	nl.

main :-
	setup_call_cleanup(op(400, fx, f),
		forall(member(A, ['f(1,2)', 'f (1,2)', 'f/**/(1,2)', 'f/*.*/(1,2)', 'f%c\n(1,2)', 'g/**/(1)', '''g''(1)', '- /**/(1)']),
			( write(A), write(' '), r(A) )),
		op(0, fx, f)).
