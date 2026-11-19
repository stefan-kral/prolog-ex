% Counted values a discarded frame still holds go with it: see `make leaks`. A head binding a string's tail to a fresh
% variable, then a failing body, kept the reference, as did heap cells built since a recovered frame's mark in the
% same page. Loading library(format) did both, its goal expansion running if-then-else before the file is compiled.

:- use_module(library(format)).
:- initialization(main).

g([_|T]) :- T == x.
k("0123456789abcdef").

main :-
	( \+ g("0123456789") -> write(head_tail_released) ; true ), nl,
	forall(between(1, 100, _), \+ (k(S), g(S))),
	write(repeated), nl,
	format("~d~n", [42]).
