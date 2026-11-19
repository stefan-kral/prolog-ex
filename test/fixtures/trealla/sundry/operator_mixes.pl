% Names that are operators of more than one kind. Tokens left over in an
% argument, list element or {} term are a syntax error, not dropped or
% taken for the next argument or the tail; a name that is both prefix
% and postfix is read as the one that fits; and writeq/1 brackets an
% operand whose operator would otherwise take the neighbouring one in.

:- initialization(main).

r(A) :-
	catch(( read_term_from_atom(A, T, []), write_canonical(T) ), error(syntax_error(_), _), write(syntax_error)),
	nl.

w(T) :-
	with_output_to(atom(A), writeq(T)),
	read_term_from_atom(A, T2, []),
	write(A), write(' '), ( T2 == T -> write(same) ; write(differs) ), nl.

main :-
	setup_call_cleanup((op(9,fy,p), op(9,yfx,p)),
		forall(member(A, ['f(1 p p 2)', 'f(1 p p p 2, x)', '[1 p p 2]', '[x, 1 p p 2, y]', '{1 p p 2}', 'f(1 p q)', '[a,b|c]']),
			( write(A), write(' '), r(A) )),
		(op(0,fy,p), op(0,yfx,p))),
	setup_call_cleanup((op(9,fy,f), op(9,yf,f)),
		forall(member(A, ['0 f f', '0 f', '(0 f) f', 'f f 0', 'f f']), ( write(A), write(' '), r(A) )),
		(op(0,fy,f), op(0,yf,f))),
	setup_call_cleanup((op(9,fy,fy), op(9,yfx,yfx), op(9,yf,yf), op(9,xfy,xfy)),
		forall(member(T, [yfx(fy(1),2), fy(yfx(1,2)), yf(xfy(1,2)), xfy(1,yf(2)), yf(fy(1)), yf(yf), -a+b, - (1)+2]), w(T)),
		(op(0,fy,fy), op(0,yfx,yfx), op(0,yf,yf), op(0,xfy,xfy))),
	setup_call_cleanup(op(9,yf,'.'), w('.'('.')), op(0,yf,'.')).
