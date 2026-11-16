:- encoding(utf8).
% wie dom.pl für SWI-Prolog (attr_unify_hook/2, nach der Bindung)
:- module(dom, [domain/2]).
:- use_module(library(lists)).

domain(X, List) :-
    sort(List, Set),
    Set = [El|Els],
    (   Els = [] -> X = El
    ;   put_attr(Fresh, dom, Set), X = Fresh
    ).

attr_unify_hook(Da, Other) :-
    (   var(Other) ->
        (   get_attr(Other, dom, Db) ->
            inter(Da, Db, Dc),
            Dc = [El|Els],
            (   Els = [] -> Other = El
            ;   put_attr(Other, dom, Dc)
            )
        ;   put_attr(Other, dom, Da)
        )
    ;   memberchk(Other, Da)
    ).

inter([], _, []).
inter([X|Xs], Ys, Zs) :- ( memberchk(X, Ys) -> Zs = [X|Zs1] ; Zs = Zs1 ), inter(Xs, Ys, Zs1).
