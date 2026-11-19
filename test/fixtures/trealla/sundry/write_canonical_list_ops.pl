% write_canonical/1 wrote a list element that is an operator term in parentheses, as list notation would need it,
% though the element was itself written without operators: '.'((','(1,2)),[]) for '.'(','(1,2),[]).

:- initialization(main).

w(T) :- write_canonical(T), nl.

main :-
	w([(1,2,3)]), w([a,(1,2,3)]), w([(a:-b),c]), w([(a->b;c)]), w([[(a,b)]]), w([-(1)]), w([\+a]).
