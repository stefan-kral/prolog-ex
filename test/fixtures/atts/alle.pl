% verify_attributes/3, der bei jeder gebundenen attributierten Variablen
% etwas ausgibt (auch ohne eigene Attribute)
:- module(alle, [alle/1]).
:- use_module(library(atts)).
:- attribute alle/0.

alle(V) :- put_atts(V, alle).

verify_attributes(_, _, []) :- write(h).
