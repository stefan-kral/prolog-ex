% Beispiel aus der SICStus-Doku (library(atts)): endliche Bereiche
:- module(domain, [domain/2]).
:- use_module(library(atts)).
:- use_module(library(lists)).
:- attribute dom/1.

verify_attributes(Var, Other, Goals) :-
    get_atts(Var, dom(Da)), !,          % Var hat einen Bereich
    (   var(Other) ->                   % Var = andere Variable
        (   get_atts(Other, dom(Db)) -> % die auch einen hat
            intersection(Da, Db, Dc),
            Dc = [El|Els],              % nicht leer
            (   Els = [] -> Goals = [Other=El]
            ;   Goals = [], put_atts(Other, dom(Dc))
            )
        ;   Goals = [],
            put_atts(Other, dom(Da))    % Bereich übertragen
        )
    ;   Goals = [],
        memberchk(Other, Da)            % Wert im Bereich?
    ).
verify_attributes(_, _, []).            % kein Bereich: nichts zu prüfen

attribute_goal(X, domain(X, List)) :-
    get_atts(X, dom(List)).

domain(X, Dom) :-
    var(Dom), !,
    get_atts(X, dom(Dom)).
domain(X, List) :-
    list_to_set(List, Domain),
    put_atts(Y, dom(Domain)),
    X = Y.
