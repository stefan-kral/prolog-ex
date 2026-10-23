% verify_attributes/3 beobachten: Reihenfolge, Zustand der Partner
:- module(spy, [tag/3, mehrfach/1, wirft/1]).
:- use_module(library(atts)).
:- attribute tag/2, mehrfach/0, wirft/0.

tag(V, Name, Partner) :- put_atts(V, tag(Name, Partner)).
mehrfach(V) :- put_atts(V, mehrfach).
wirft(V) :- put_atts(V, wirft).

verify_attributes(V, Wert, [nachher(Name, V)]) :-
    get_atts(V, tag(Name, P)), !,
    ( var(P) -> Z = frei ; Z = gebunden ),
    ( var(V) -> true ; throw(var_schon_gebunden) ),
    write(hook(Name, Wert, Z)), nl.
verify_attributes(V, _, []) :-
    get_atts(V, mehrfach), !,
    ( write(eins) ; write(zwei) ).
verify_attributes(V, _, []) :-
    get_atts(V, wirft), !,
    throw(aus_dem_hook).
verify_attributes(_, _, []).

nachher(Name, V) :- write(goal(Name, V)), nl.
