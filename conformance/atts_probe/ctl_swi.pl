% Wecken in Kontrollkonstrukten (freeze, dif, clpz); Ausgabe je Fall
% "Name Lösungen" oder "Name ex(Fehler)". Läuft in Scryer und PrologEx;
% ctl_swi.pl ist dieselbe Datei für SWI (clpfd).
:- use_module(library(clpfd)).
:- use_module(library(lists)).

:- dynamic(tmp/1).

go :- forall(c(N, Vs, G), run(N, Vs, G)).
run(N, Vs, G) :-
    write(N), write(' '),
    catch(( findall(Vs, G, L), write(L) ), E, ( E = error(F, _) -> functor(F, FN, FA), write(ex(FN/FA)) ; write(ex(E)) )),
    nl.

c(ite_cond_fail,   X,     (freeze(X, fail), ( X = 1 -> Y = a ; Y = b ), X-Y = X-Y)).
c(ite_cond_y,      Y,     (freeze(X, fail), ( X = 1 -> Y = a ; Y = b ))).
c(ite_cond_dif,    Y,     (dif(X, 1), ( X = 1 -> Y = a ; Y = b ))).
c(ite_cond_clpz,   Y,     (X in 2..3, ( X = 1 -> Y = a ; Y = b ))).
c(naf_wake,        ok,    (freeze(X, fail), \+ X = 1)).
c(naf_wake2,       ok,    (X in 1..3, \+ X = 4)).
c(cut_in_frozen,   X-Y,   (freeze(X, (member(Y, [1, 2]), !)), member(X, [a, b]))).
c(cut_in_frozen2,  X-Y,   (freeze(X, (member(Y, [1, 2]), !, Y > 0)), X = a)).
c(frozen_nondet,   X-Y,   (freeze(X, member(Y, [1, 2])), member(X, [a, b]))).
c(findall_wake,    L,     (freeze(X, member(X, [1, 2, 3])), findall(X, member(X, [2, 3, 4]), L))).
c(findall_outer,   X-L,   (findall(Y, (freeze(Y, Y > 1), member(Y, [1, 2, 3])), L), X = 1)).
c(once_wake,       X,     (freeze(X, X > 1), once(member(X, [1, 2, 3])))).
c(catch_wake,      X-E,   (freeze(X, throw(oops)), catch(X = 1, E, true))).
c(catch_wake2,     X,     (freeze(X, (X > 1 -> true ; throw(small))), catch(member(X, [1, 2]), small, fail))).
c(call_wake,       X,     (freeze(X, X > 1), call(member, X, [1, 2]))).
c(forall_wake,     ok,    (freeze(X, X > 0), forall(member(X, [1, 2]), true))).
c(forall_wake2,    ok,    (freeze(X, X > 1), forall(member(X, [1, 2]), true))).
c(nested_freeze,   X-Y,   (freeze(X, freeze(Y, Y > X)), X = 1, member(Y, [0, 1, 2]))).
c(chain,           X-Y-Z, (freeze(X, Y = X), freeze(Y, Z = Y), X = 5)).
c(chain_dif,       X-Y,   (dif(X, Y), freeze(X, Y = 1), member(X, [1, 2]))).
c(dif_chain,       X-Y-Z, (dif(X, Y), X = Z, member(Y, [1, 2]), member(Z, [1, 2]))).
c(clpz_freeze,     X-Y,   (X #= Y + 1, freeze(Y, (Y > 0)), member(X, [1, 2, 3]))).
c(clpz_dif,        X-Y,   ([X, Y] ins 0..2, dif(X, Y), X #= 2 * Y, label([X, Y]))).
c(clpz_alias,      X-Y,   (X in 0..5, Y in 3..9, X = Y, X #\= 4, label([X]))).
c(clpz_alias_fz,   X,     (X in 0..5, freeze(Y, Y > 3), X = Y, label([X]))).
c(clpz_struct,     X-Y,   (X in 0..2, Y in 1..3, f(X, a) = f(Y, a), label([X]))).
c(bind_two_fz,     X-Y,   (freeze(X, write(x)), freeze(Y, write(y)), f(X, Y) = f(1, 2))).
c(bind_two_rev,    X-Y,   (freeze(X, write(x)), freeze(Y, write(y)), f(Y, X) = f(2, 1))).
c(bind_alias_fz,   X-Y,   (freeze(X, write(x)), freeze(Y, write(y)), X = Y, write(-), X = 1)).
c(bind_alias_fz2,  X-Y,   (freeze(Y, write(y)), freeze(X, write(x)), X = Y, write(-), X = 1)).
c(dif_bind_pair,   X-Y,   (dif(f(X, Y), f(1, 2)), member(X-Y, [1-2, 1-3, 2-2]))).
c(dif_partial,     X-Y,   (dif(f(X, Y), f(1, 2)), X = 1, member(Y, [2, 3]))).
c(wake_in_assert,  X,     (freeze(X, X > 1), assertz(tmp(X)), retract(tmp(Y)), Y = 1, X = Y ; X = none)).
c(univ_bind,       X,     (freeze(X, X \== f(1)), member(A, [1, 2]), X =.. [f, A])).
c(length_bind,     L,     (freeze(L, L \== []), between(0, 2, N), length(L, N))).
c(sort_bind,       X,     (freeze(X, X \== [1]), member(A, [[1], [2, 1]]), sort(A, X))).
c(arg_bind,        X,     (freeze(X, X > 1), arg(_, f(1, 2, 3), X))).
c(between_bind,    X,     (freeze(X, X mod 2 =:= 0), between(1, 6, X))).
c(nth_bind,        X-I,   (freeze(X, X > 1), nth0(I, [1, 2, 3], X))).
c(atom_bind,       X,     (freeze(X, X \== ab), member(A, [ab, cd]), atom_codes(X, A))).
c(number_bind,     X,     (freeze(X, X > 10), member(Cs, [['5'], ['1', '5']]), number_chars(X, Cs))).
c(sub_atom_bind,   X,     (freeze(X, X \== b), sub_atom(abc, _, 1, _, X))).
c(copy_bind,       X,     (freeze(X, fail), copy_term(f(_), X) ; X = none)).
c(keysort_bind,    X,     (freeze(X, X \== [a-1]), member(L, [[a-1], [b-2]]), keysort(L, X))).
