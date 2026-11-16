% verify_attributes/3, das bei jedem Aufruf "laut" schreibt: wird es auch
% für Variablen ohne Attribut in diesem Modul gerufen?
:- module(laut, [laut/1]).
:- use_module(library(atts)).
:- attribute l/0.

laut(V) :- put_atts(V, l).

verify_attributes(_, _, []) :- write(laut), nl.
