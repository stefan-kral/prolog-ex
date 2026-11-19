% Goal expansion prints its result and parses it back, renaming a fresh variable whose printed name collides with an
% earlier expansion's. A second such rename in a row reused the first one's variable number, so the last two
% constraints here shared a variable and the clause failed.

:- initialization(main).
:- use_module(library(clpz)).

g(NT, NC, NR) :- NT #= NC*NR, NC #>= 1, NR #>= 1, NR #>= 0.

main :-
	( g(_, _, _) -> write(ok) ; write(failed) ), nl.
