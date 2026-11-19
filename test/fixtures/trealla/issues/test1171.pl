% Issue #1171: abolish/1 of a predicate with an open choice point put its
% clauses where purging after 512+ retracts freed them under the reader.

:- initialization(main).
:- dynamic(p/1).

p(1). p(2).

main :-
	forall(between(1, 600, I), assertz(q(I))),
	p(X), abolish(p/1), retractall(q(_)),
	write(X), nl,
	X >= 2.
