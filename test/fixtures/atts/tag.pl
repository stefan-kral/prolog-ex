% Attributmodul im Stil von Scryer/SWI: Restziele über attribute_goals//1,
% ohne Modul (die Bibliothek setzt tag: davor)
:- module(tag, [tag/2, tagged/2]).
:- use_module(library(atts)).
:- attribute tag/1.

tag(V, T) :- put_atts(V, tag(T)).
tagged(V, T) :- tag(V, T).

attribute_goals(V) --> { get_atts(V, tag(T)) }, [tagged(V, T)].
