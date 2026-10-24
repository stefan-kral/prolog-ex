:- module(m_lambda_pl, [doubled/2, scaled/3]).
:- use_module(library(apply)).
:- use_module(library(lambda_pl)).

% twice/2 ist privat: das Lambda läuft trotzdem in diesem Modul
twice(X, Y) :- Y is 2 * X.

doubled(L, L2) :- maplist(\X^Y^twice(X, Y), L, L2).
scaled(F, L, L2) :- maplist(F+\X^Y^(Y is F * X), L, L2).
