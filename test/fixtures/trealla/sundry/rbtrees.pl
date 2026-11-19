% library(rbtrees) loads and works; it used to need prolog-commons'
% library(dialect/commons) for its type declarations.

:- use_module(library(rbtrees)).
:- initialization(main).

main :-
	list_to_rbtree([c-3,a-1,b-2], T),
	rb_insert(T, d, 4, T1),
	rb_lookup(b, V, T1), writeq(V), nl,
	rb_visit(T1, Ps), writeq(Ps), nl,
	rb_size(T1, N), writeq(N), nl,
	rb_delete(T1, a, T2),
	rb_map(T2, succ, T3),
	rb_visit(T3, Ps3), writeq(Ps3), nl,
	( is_rbtree(T3) -> writeq(yes) ; writeq(no) ), nl,
	findall(K-X, rb_in(K, X, T3), In), writeq(In), nl.
