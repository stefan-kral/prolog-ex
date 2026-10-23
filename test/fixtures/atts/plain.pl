:- module(plain, [p/2, g/2]).
:- use_module(library(atts)).
:- attribute a/1, b/2.
p(V, Spec) :- put_atts(V, Spec).
g(V, Spec) :- get_atts(V, Spec).
