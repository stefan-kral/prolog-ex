% copy_term/2 told variables apart by ctx*100+var_num, so a frame with more than a hundred variables had one share its
% number with the next frame's: t's 151st slot (length/2 made 150) and p's Y came out as one variable in the copy.

:- initialization(main).

t(N) :- length(L, N), p(L).

p(L) :-
	Y = _,
	copy_term(L-Y, L2-Y2),
	term_variables(L2-Y2, Vs), length(Vs, K),
	( member(E, L2), E == Y2 -> write(merged(K)) ; write(distinct(K)) ), nl.

main :-
	t(150), t(1000).
