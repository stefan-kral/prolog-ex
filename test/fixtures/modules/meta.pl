:- module(meta, [zweimal/1, alle/2, sammle/3]).
:- meta_predicate zweimal(0), alle(1, ?), sammle(?, 0, -).

zweimal(G) :- call(G), call(G).
alle(_, []).
alle(G, [X|Xs]) :- call(G, X), alle(G, Xs).
sammle(T, G, L) :- findall(T, G, L).
hilfe(meta).                                % gleichnamig wie in user, privat
