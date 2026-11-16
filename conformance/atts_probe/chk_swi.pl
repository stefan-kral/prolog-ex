:- use_module(library(clpfd)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(assoc)).
go :- forall(c(N, Vs, G), run(N, Vs, G)).
run(N, Vs, G) :-
    write(N), write(' '),
    catch(( findall(Vs, G, L), write(L) ), E, write(ex(E))), nl.
c(memberchk,    X,     (X in 1..3, memberchk(X, [5, 2]))).
c(memberchk_fz, X,     (freeze(X, X \== a), memberchk(X, [a, b]))).
c(memberchk_d,  X,     (dif(X, a), memberchk(X, [a, b]))).
c(memberchk_s,  X-Y,   (X in 1..3, memberchk(f(X, Y), [f(5, p), f(2, q)]))).
c(selectchk,    X-R,   (X in 1..3, selectchk(X, [5, 2, 7], R))).
c(select,       X-R,   (X in 1..3, select(X, [5, 2, 7], R))).
c(select3b,     R,     (X in 1..3, select(5, [X, 5], R))).
c(subtract,     X-R,   (X in 1..3, subtract([5, 2, 7], [X], R))).
c(intersection, X-R,   (X in 1..3, intersection([5, 2, 7], [X], R))).
c(union,        X-R,   (X in 1..3, union([5, 2], [X], R))).
c(delete,       X-R,   (X in 1..3, delete([5, X, 2], 5, R))).
c(exclude,      X-R,   (X in 1..3, exclude(=(X), [5, 2, 7], R))).
c(partition,    X-I-O, (X in 1..3, partition(=(X), [5, 2, 7], I, O))).
c(include,      X-R,   (X in 1..3, include(=(X), [5, 2, 7], R))).
c(nth0_var,     I-X,   (X in 1..3, nth0(I, [5, 2, 7], X))).
c(nth1_var,     I-X,   (X in 1..3, nth1(I, [5, 2, 7], X))).
c(nth0_det,     X,     (X in 1..3, nth0(0, [5, 2], X))).
c(last,         X,     (X in 1..3, last([2, 5], X))).
c(member,       X,     (X in 1..3, member(X, [5, 2, 7, 3]))).
c(sumlist,      X,     (X in 1..3, sum_list([2, 5], X))).
c(max_list,     X,     (X in 1..9, max_list([2, 5], X))).
c(numlist,      L,     (X in 1..3, numlist(1, 2, [_, X]), L = X)).
c(pkv,          K-V,   (K in 1..3, pairs_keys_values([K-a, 5-b], [5, 2], V))).
c(keysort,      X,     (X in 1..3, keysort([b-1], [X-_]))).
c(msort,        X,     (X in 1..3, msort([5], [X]))).
c(sort_dedup,   X-L,   (X in 1..3, sort([X, 2], L))).
c(list_to_set,  X-L,   (X in 1..3, list_to_set([X, 2, X], L))).
c(permutation,  X-L,   (X in 1..3, permutation([X, 5], [5, 2]), L = ok)).
c(reverse,      X,     (X in 1..3, reverse([5, 2], [X, _]))).
c(append3,      X,     (X in 1..3, append(_, [X|_], [5, 2, 7]))).
c(get_assoc,    X,     (X in 1..3, list_to_assoc([k-5], A), get_assoc(k, A, X))).
c(get_assoc2,   X,     (X in 1..3, list_to_assoc([k-2], A), get_assoc(k, A, X))).
c(arg_var,      N-X,   (X in 1..3, arg(N, f(5, 2), X))).
c(between,      X,     (X in 2..9, between(1, 3, X))).
c(foldl,        X,     (X in 1..3, foldl([E, A0, A]>>(A is A0 + E), [1, 1], 0, X))).
c(eqq,          X,     (X in 1..3, ( ?=(X, 5) -> true ; X = none ))).
c(copy_term,    D,     (X in 1..3, copy_term(X, Y), ( var(Y), fd_dom(Y, D0) -> D = D0 ; D = nodom ))).
c(findall_bind, X,     (X in 1..3, findall(Y, member(Y, [5, 2]), [_, X]))).
c(term_vars,    X,     (X in 1..3, term_variables(f(X), [Y]), Y = 2)).
c(atom_length,  X,     (X in 4..9, atom_length(abc, X))).
c(univ,         X,     (X in 1..3, f(5) =.. [_, X])).
c(succ,         X,     (X in 1..3, succ(X, 5))).
c(plus,         X,     (X in 1..3, plus(X, 1, 5))).
c(number_codes, X,     (X in 1..3, number_codes(X, [0'5]))).
c(char_code,    X,     (X in 1..3, char_code(a, X))).
c(sub_atom,     X,     (X in 1..2, sub_atom(abc, X, 1, _, c))).
c(atom_concat,  X,     (freeze(X, X \== a), atom_concat(X, _, ab))).
c(nb_getval,    X,     (X in 1..3, nb_setval(k, 5), nb_getval(k, X))).
c(bagof,        X,     (X in 1..3, bagof(Y, member(Y, [5]), [X]))).
c(setof,        X,     (X in 1..3, setof(Y, member(Y, [5]), [X]))).
c(catch_ball,   X,     (X in 1..3, catch(throw(5), X, true))).
c(catch_ball2,  X,     (X in 1..3, catch(throw(b(5)), b(X), true))).
c(once_unify,   X,     (X in 1..3, once(member(X, [5, 2])))).
c(forall,       ok,    (X in 1..3, forall(member(Y, [1]), Y = X))).

