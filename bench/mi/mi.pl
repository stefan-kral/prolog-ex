% Meta-Interpreter
% vanilla: alles ueber clause/2 (nur ohne Builtins)
s_v(true) :- !.
s_v((A,B)) :- !, s_v(A), s_v(B).
s_v(G) :- clause(G, B), s_v(B).
% klassisch: Builtins ueber predicate_property(G, built_in)
s_bi(true) :- !.
s_bi((A,B)) :- !, s_bi(A), s_bi(B).
s_bi(G) :- predicate_property(G, built_in), !, call(G).
s_bi(G) :- clause(G, B), s_bi(B).
% nur dynamische Praedikate interpretieren (wie in Scryer/SICStus noetig)
s_dyn(true) :- !.
s_dyn((A,B)) :- !, s_dyn(A), s_dyn(B).
s_dyn(G) :- predicate_property(G, dynamic), !, clause(G, B), s_dyn(B).
s_dyn(G) :- call(G).
