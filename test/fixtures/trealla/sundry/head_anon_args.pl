% A '_' just inside a head argument is matched without being bound, which must not lose a binding made through another argument.

:- initialization(main).

p(f(_), X, X).
q([_|T], T).
r(f(_, X, _), X).
s(f(_), f(_)).
u([_|_]).
m(X, [X|_]).
m(X, [_|T]) :- m(X, T).

:- dynamic(d/2).

yes_no(G, R) :- ( G -> R = yes ; R = no ).

main :-
	p(V1, V1, f(a)), write(through_head_var(V1)), nl,
	q([1,2,3], T2), write(tail(T2)), nl,
	r(f(1,2,3), X3), write(middle(X3)), nl,
	yes_no(r(g(1,2,3), _), R4), write(other_functor(R4)), nl,
	yes_no(s(f(a), f(b)), R5), write(two_anons(R5)), nl,
	yes_no(u("abc"), R6), write(string_goal(R6)), nl,
	findall(X7, m(X7, [a,b,c]), L7), write(member(L7)), nl,
	functor(H, f, 2), assertz(d(H, t(H))),
	yes_no(d(f(1,2), t(f(3,4))), R8), write(functor_vars_differ(R8)), nl,
	yes_no(d(f(1,2), t(f(1,2))), R9), write(functor_vars_same(R9)), nl.
