:- module(ch, [choice/2]).
choice(X, Y) :- put_attr(X, ch, Y).
attr_unify_hook(Y, _) :- ( Y = 1 ; Y = 2 ).
