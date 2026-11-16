% Hook mit Alternativen: wird X gebunden, nimmt Y nacheinander 1 und 2 an
:- module(ch, [choice/2]).
:- use_module(library(atts)).
:- attribute ch/1.
choice(X, Y) :- put_atts(X, ch(Y)).
verify_attributes(Var, _, Goals) :-
    get_atts(Var, ch(Y)), !,
    ( Goals = [Y = 1] ; Goals = [Y = 2] ).
verify_attributes(_, _, []).
