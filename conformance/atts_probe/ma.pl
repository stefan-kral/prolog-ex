% Attributmodul a: protokolliert jeden Aufruf von verify_attributes/3
:- module(ma, [a/2, ga/2, log/1, st/1]).
:- use_module(library(atts)).
:- attribute av/1.

a(X, T) :- put_atts(X, av(T)).
ga(X, T) :- get_atts(X, av(T)).

log(T) :- write(T), nl.
% Zustand einer Variablen: var, attv oder ihr Wert
st(X) :- ( var(X) -> write(var) ; write(X) ).

verify_attributes(Var, Value, Goals) :-
    (   get_atts(Var, av(T)) ->
        write(verify(a, T)), write(' var='), st(Var), write(' value='), st(Value),
        ( var(Value), get_atts(Value, av(T2)) -> write(' value_a='), write(T2) ; true ),
        nl,
        hook_mode(T, Var, Value, Goals)
    ;   write(verify(a, none)), write(' value='), st(Value), nl,
        Goals = []
    ).

% je nach Kennung T verschiedenes Verhalten
hook_mode(fail, _, _, _) :- !, fail.
hook_mode(throw, _, _, _) :- !, throw(hook_ball).
hook_mode(nd, _, _, Goals) :- !, ( Goals = [log(nd1)] ; Goals = [log(nd2)] ).
hook_mode(merge, Var, Value, [log(merged(T))]) :- !,
    ( var(Value) -> get_atts(Var, av(T)), put_atts(Value, av(T)) ; T = none ).
hook_mode(T, _, _, [log(goal(a, T))]).

attribute_goal(X, a(X, T)) :- get_atts(X, av(T)).
