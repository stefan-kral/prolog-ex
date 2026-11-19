% With ignore_ops(true) a list is written as '.'/2 terms, and the . and
% the elements are quoted only when quoted(true) is given too, as any
% other functor is (s#380 of #1099).

:- initialization(main).

main :-
	forall(member(T, [[' '], [a,'B c'], "a b", [1,2|t]]),
		( write_term(T, [ignore_ops(true)]), nl,
		  write_term(T, [ignore_ops(true), quoted(true)]), nl )),
	write_canonical([a,'B c']), nl.
