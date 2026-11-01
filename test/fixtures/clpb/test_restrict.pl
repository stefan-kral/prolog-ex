% aus github.com/triska/clpb (tests/test_restrict.pl), Markus Triska; nur use_module angepasst
:- use_module(library(clpb)).
:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(between)).

clpb:validation.

sat( _)  --> [].
sat(X*Y) --> [_], sat(X), sat(Y).
sat(X+Y) --> [_], sat(X), sat(Y).
sat(X#Y) --> [_], sat(X), sat(Y).

run(N) :-
        length(Ls, N),
        portray_clause(N),
        phrase(sat(Sat), Ls),
        term_variables(Sat, Vs0),
        sat(Sat),
        permutation(Vs0, Vs),
        labeling(Vs),
        false.

run :- run(_).

