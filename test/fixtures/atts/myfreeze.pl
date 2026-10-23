% Beispiel aus der SICStus-Doku: freeze mit Attributen
:- module(myfreeze, [myfreeze/2]).
:- use_module(library(atts)).
:- attribute frozen/1.

verify_attributes(Var, Other, Goals) :-
    get_atts(Var, frozen(Fa)), !,       % Var hat ein Ziel
    (   var(Other) ->                   % Var = andere Variable
        (   get_atts(Other, frozen(Fb)) % auch mit Ziel
        ->  put_atts(Other, frozen((Fa,Fb)))
        ;   put_atts(Other, frozen(Fa))
        ),
        Goals = []
    ;   Goals = [Fa]                    % Var = Wert: Ziel aufrufen
    ).
verify_attributes(_, _, []).

attribute_goal(Var, myfreeze(Var, Goal)) :-
    get_atts(Var, frozen(Goal)).

myfreeze(X, Goal) :-
    put_atts(Fresh, frozen(Goal)),
    Fresh = X.
