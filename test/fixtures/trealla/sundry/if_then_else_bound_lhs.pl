% A disjunction whose left side is a variable bound to (C -> T) or
% (C *-> T) at run time must still act as if-then-else: once C succeeds,
% a failing T fails the whole goal instead of trying the else branch.

:- initialization(main).

rebuild((L0 ; R0), (L ; R)) :- !, rebuild(L0, L), rebuild(R0, R).
rebuild((I0 -> T0), (I -> T)) :- !, rebuild(I0, I), rebuild(T0, T).
rebuild(G, G).

t_rebuilt(R) :- rebuild((true -> fail ; R = else), G), ( call(G) -> true ; R = failed ).
t_bound(R) :- X = (true -> fail), G = (X ; R = else), ( call(G) -> true ; R = failed ).
t_cond_fails(R) :- X = (fail -> true), G = (X ; R = else), call(G).
t_soft(R) :- X = (member(A, [1,2]) *-> true), G = (X ; A = 3), findall(A, G, R).
t_soft_fails(R) :- X = (fail *-> true), G = (X ; R = else), call(G).
t_commit(R) :- X = (member(A, [1,2]) -> true), findall(A, (X ; A = 3), R).

main :-
	forall(
		member(T, [t_rebuilt, t_bound, t_cond_fails, t_soft, t_soft_fails, t_commit]),
		(	G =.. [T, R],
			(	catch(G, E, R = uncaught(E)) -> true ; R = failed ),
			format("~w: ~q~n", [T, R])
		)
	).
