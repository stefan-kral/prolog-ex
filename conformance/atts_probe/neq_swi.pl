:- use_module(library(clpfd)).
:- use_module(library(lists)).
go :- forall(c(N, G), (write(N), write(' '), ( catch(G, E, (write(ex(E)), nl, fail)) -> write(yes) ; write(no) ), nl)).
c(fz_neq,   (freeze(X, fail), X \= 1)).
c(fz_neq2,  (freeze(X, fail), \+ X = 1)).
c(clpz_neq, (X in 1..3, X \= 5)).
c(clpz_neq2,(X in 1..3, \+ X = 5)).
c(dif_neq,  (dif(X, 1), X \= 1)).
c(fz_sub,   (freeze(X, fail), subsumes_term(X, 1))).
c(clpz_sub, (X in 1..3, subsumes_term(X, 5))).
c(clpz_sub2,(X in 1..3, subsumes_term(X, 2))).
c(dif_sub,  (dif(X, 1), subsumes_term(X, 1))).
c(fz_neq_s, (freeze(X, fail), f(X, Y) \= f(1, Y))).
c(fz_uoc,   (freeze(X, fail), \+ unify_with_occurs_check(X, 1))).
