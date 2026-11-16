% Attributmodul a: protokolliert jeden Aufruf von verify_attributes/3
:- module(mb, [b/2]).
:- use_module(library(atts)).
:- use_module(ma, [log/1, st/1]).
:- attribute bv/1.

b(X, T) :- put_atts(X, bv(T)).


verify_attributes(Var, Value, Goals) :-
    (   get_atts(Var, bv(T)) ->
        write(verify(b, T)), write(' var='), st(Var), write(' value='), st(Value),
        ( var(Value), get_atts(Value, bv(T2)) -> write(' value_a='), write(T2) ; true ),
        nl,
        hook_mode(T, Var, Value, Goals)
    ;   write(verify(b, none)), write(' value='), st(Value), nl,
        Goals = []
    ).

% je nach Kennung T verschiedenes Verhalten
hook_mode(fail, _, _, _) :- !, fail.
hook_mode(throw, _, _, _) :- !, throw(hook_ball).
hook_mode(nd, _, _, Goals) :- !, ( Goals = [log(nd1)] ; Goals = [log(nd2)] ).
hook_mode(merge, Var, Value, [log(merged(T))]) :- !,
    ( var(Value) -> get_atts(Var, bv(T)), put_atts(Value, bv(T)) ; T = none ).
hook_mode(T, _, _, [log(goal(b, T))]).

attribute_goal(X, b(X, T)) :- get_atts(X, bv(T)).
