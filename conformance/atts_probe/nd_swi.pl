:- use_module(ch_swi).
:- use_module(library(lists)).
go :- forall(c(N, Vs, G), run(N, Vs, G)).
run(N, Vs, G) :-
    write(N), write(' '),
    catch(( findall(Vs, G, L), write(L) ), E, write(ex(E))), nl.
c(one,        Y,     (choice(X, Y), X = a)).
c(two_vars,   Y-Z,   (choice(X, Y), choice(W, Z), f(X, W) = f(a, b))).
c(alias,      Y-Z,   (choice(X, Y), choice(W, Z), X = W)).
c(alias_bind, Y-Z,   (choice(X, Y), choice(W, Z), X = W, X = a)).
c(once,       Y,     (choice(X, Y), once(X = a))).
c(naf,        Y,     (choice(X, Y), \+ X = a, Y = 0 ; Y = none)).
c(ite,        Y-R,   (choice(X, Y), ( X = a -> R = t ; R = e ))).
c(cut_after,  Y,     (choice(X, Y), X = a, !)).
c(fail_first, Y,     (choice(X, Y), X = a, Y > 1)).
c(member,     X-Y,   (choice(X, Y), member(X, [a, b]))).
c(findall_in, L,     (choice(X, Y), findall(Y, X = a, L))).
c(two_hooks,  Y-Z,   (choice(X, Y), choice(X, Z), X = a)).
c(neq,        Y,     (choice(X, Y), X \= a ; Y = none)).
c(memberchk,  Y,     (choice(X, Y), memberchk(X, [a, b]))).
