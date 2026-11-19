% Issue #1164: a string key orders as the list it is, not as an atom of the same text.

:- initialization(main).

:- dynamic(k/2).
:- dynamic(j/2).

key(I, K) :- J is I mod 4, nth0(J, [ab, "ab", [a], c], K).
key2(I, K) :- J is I mod 6, nth0(J, ["A", 'A', f(a,b), "ab", g(a), 1], K).

main :-
	forall(between(1, 600, I), (key(I, K), assertz(k(K, I)))),
	findall(I, (between(1, 600, I), key(I, K), \+ k(K, I)), L), length(L, N), writeq(missing(N)), nl,
	( k(ab, 136) -> writeq(found(k(ab,136))) ; writeq(not_found(k(ab,136))) ), nl,
	forall(between(1, 600, I), (key2(I, K), assertz(j(K, I)))),
	findall(I, (between(1, 600, I), key2(I, K), \+ j(K, I)), L2), length(L2, N2), writeq(missing(N2)), nl.
