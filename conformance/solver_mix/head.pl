% Kopf der Fälle für Scryer und PrologEx. Je Fall c(Id, Vs, Typen, Ziel):
% Ziel stellt Bedingungen mehrerer Solver und unifiziert; danach werden
% alle Variablen mit member/2 belegt (Typ b: 0..1, i: 0..3). Ausgabe je
% Fall: "Id L" mit L der Liste der Belegungen in Lösungsreihenfolge, oder
% "Id ex(Fehler)".
:- use_module(library(clpz)).
:- use_module(library(clpb)).
:- use_module(library(dif)).
:- use_module(library(freeze)).
:- use_module(library(when)).
:- use_module(library(lists)).
:- use_module(library(iso_ext)).
:- use_module(dom).
:- use_module(par).

go :- forall(c(Id, _, _, _), run(Id)).

run(Id) :-
    c(Id, Vs, Ts, G),
    write(Id), write(' '),
    catch(( findall(Vs, (G, lab(Vs, Ts)), L), write(L) ),
          E, ( ex_name(E, N), write(ex(N)) )),
    nl.

ex_name(error(F, _), N) :- !, functor(F, N0, A), N = N0/A.
ex_name(B, N) :- functor(B, N0, A), N = N0/A.

vars(_).

lab([], []).
lab([V|Vs], [T|Ts]) :- td(T, D), member(V, D), lab(Vs, Ts).

td(b, [0, 1]).
td(i, [0, 1, 2, 3]).
