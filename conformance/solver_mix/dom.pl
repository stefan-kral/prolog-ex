% Endliche Bereiche (Beispiel aus der SICStus-Doku zu library(atts)),
% ohne intersection/3 und list_to_ord_set/2 (fehlen in Scryer)
:- module(dom, [domain/2]).
:- use_module(library(atts)).
:- use_module(library(lists)).
:- attribute dom/1.

domain(X, List) :-
    sort(List, Set),
    Set = [El|Els],
    (   Els = [] -> X = El
    ;   put_atts(Fresh, dom(Set)), X = Fresh
    ).

verify_attributes(Var, Other, Goals) :-
    get_atts(Var, dom(Da)), !,
    (   var(Other) ->
        (   get_atts(Other, dom(Db)) ->
            inter(Da, Db, Dc),
            Dc = [El|Els],
            (   Els = [] -> Goals = [Other = El]
            ;   Goals = [], put_atts(Other, dom(Dc))
            )
        ;   Goals = [], put_atts(Other, dom(Da))
        )
    ;   Goals = [], memberchk(Other, Da)
    ).
verify_attributes(_, _, []).

attribute_goal(X, domain(X, D)) :- get_atts(X, dom(D)).

inter([], _, []).
inter([X|Xs], Ys, Zs) :- ( memberchk(X, Ys) -> Zs = [X|Zs1] ; Zs = Zs1 ), inter(Xs, Ys, Zs1).
