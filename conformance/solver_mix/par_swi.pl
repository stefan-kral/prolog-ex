:- encoding(utf8).
% wie par.pl für SWI-Prolog
:- module(par, [parity/2]).

parity(X, P) :-
    (   var(X) ->
        (   get_attr(X, par, Q) -> Q == P ; put_attr(X, par, P) )
    ;   integer(X), X mod 2 =:= P
    ).

attr_unify_hook(P, Other) :-
    (   var(Other) ->
        (   get_attr(Other, par, Q) -> P == Q ; put_attr(Other, par, P) )
    ;   integer(Other), Other mod 2 =:= P
    ).
