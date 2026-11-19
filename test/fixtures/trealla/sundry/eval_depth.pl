% Arithmetic limits how deeply an expression nests, not how many operations it has, and past the limit raises resource_error(stack)

:- initialization(main).

lsum(0, 1) :- !.
lsum(N, G+1) :- N1 is N-1, lsum(N1, G).
rsum(0, 1) :- !.
rsum(N, 1+G) :- N1 is N-1, rsum(N1, G).
% A balanced tree of additions with 2^D leaves, D deep
tree(0, 1) :- !.
tree(D, A+B) :- D1 is D-1, tree(D1, A), tree(D1, B).

% Whether a deep sum is evaluated or refused depends on the stack, but nothing else may happen
deep(Name, E, Want) :-
	catch((X is E, (X =:= Want -> R = ok ; R = wrong(X))), error(Err, _), (Err == resource_error(stack) -> R = ok ; R = Err)),
	format("~w: ~w~n", [Name, R]).

main :-
	tree(17, T), X is T, format("wide 128k sum: ~w~n", [X]),
	( T =:= 131072 -> C = yes ; C = no ), format("wide 128k comparison: ~w~n", [C]),
	% Under the smallest limits: Windows ARM64's 1MB stack, and an ASan build's ~10KB a level in 8MB
	lsum(200, L2), Y is L2, format("left 200 sum: ~w~n", [Y]),
	lsum(100000, L), deep('left 100k sum', L, 100001),
	rsum(100000, R), deep('right 100k sum', R, 100001),
	Z is 1+2, format("evaluated afterwards: ~w~n", [Z]),
	catch(_ is 1+(1+(1/0)), error(E1, _), true), format("deep error: ~w~n", [E1]),
	with_output_to(atom(Tab), tab(1+1)), atom_length(Tab, TL), format("tab(1+1) after it: ~w~n", [TL]).
