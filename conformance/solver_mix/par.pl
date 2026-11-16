% Parität: Attribut p(P), P in {0,1}; Bindung prüft X mod 2, zwei
% Variablen: gleiche Parität, sonst wird sie übertragen
:- module(par, [parity/2]).
:- use_module(library(atts)).
:- attribute p/1.

parity(X, P) :-
    (   var(X) ->
        (   get_atts(X, p(Q)) -> Q == P ; put_atts(X, p(P)) )
    ;   integer(X), X mod 2 =:= P
    ).

verify_attributes(Var, Other, []) :-
    get_atts(Var, p(P)), !,
    (   var(Other) ->
        (   get_atts(Other, p(Q)) -> P == Q ; put_atts(Other, p(P)) )
    ;   integer(Other), Other mod 2 =:= P
    ).
verify_attributes(_, _, []).

attribute_goal(X, parity(X, P)) :- get_atts(X, p(P)).
