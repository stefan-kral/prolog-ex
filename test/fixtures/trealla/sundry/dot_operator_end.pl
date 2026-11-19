% An unquoted . followed by layout or % is the end token even once . is
% declared an operator, as in Scryer; a quoted '.' never is.

:- initialization(main).

r(A) :-
	catch(( read_term_from_atom(A, T, []), write_canonical(T) ), error(syntax_error(_), _), write(syntax_error)),
	nl.

t(Op, As) :-
	setup_call_cleanup(Op,
		forall(member(A, As), ( write(A), write(' '), r(A) )),
		( Op = op(_, Type, Name) -> op(0, Type, Name) ; true )).

main :-
	t(op(9,yf,'.'), ['a. ', 'a ''.''. ', 'a. % c', 'a ''.''', 'a.']),
	t(op(1,fy,'.'), ['''.''1', '.1', '''.''  1.2', '. 1']),
	t(op(100,xfy,'.'), ['a.b', '1 .2', 'a. ']).
