% Negation über getablte Prädikate: stratifiziert gegen nicht stratifiziert
%
%   mix prolog examples/tabling_negation.pl -g main -q
%
% 1. Stratifiziert: unreach/2 hängt von reach/2 nur negativ ab, reach/2 nicht
%    von unreach/2. Dann ist reach/2 fertig berechnet, bevor die Negation es
%    sieht – tnot/1 (und hier auch \+) ist korrekt.
% 2. Nicht stratifiziert: win/1 hängt über einen Zyklus negativ von sich
%    selbst ab. Mit \+ hinge die Antwort von der Reihenfolge der Aufrufe ab;
%    tnot/1 meldet stattdessen einen Fehler. (Richtig wäre nach der
%    Well-Founded Semantics: p3 verliert, p2 gewinnt, p1 verliert, q1 und q2
%    sind unbestimmt – das berechnet PrologEx nicht.)

:- use_module(library(tabling)).
:- use_module(library(lists)).
:- use_module(library(iso_ext)).
:- use_module(library(format)).

% --- 1. unerreichbare Knoten in einem Graphen mit Zyklus ------------------
edge(a, b). edge(b, c). edge(c, a). edge(c, d). edge(e, a).
node(N) :- member(N, [a, b, c, d, e]).

:- table reach/2.
reach(X, Y) :- edge(X, Y).
reach(X, Y) :- reach(X, Z), edge(Z, Y).

unreach(X, Y) :- node(X), node(Y), tnot(reach(X, Y)).

% --- 2. ein Spiel mit Zyklen ------------------------------------------------
% Wer am Zug ist und in eine Verluststellung ziehen kann, gewinnt.
move(p1, p2). move(p2, p1).          % p1 <-> p2
move(p2, p3).                        % p3: keine Züge, verloren
move(q1, q2). move(q2, q1).          % q1 <-> q2 ohne Ausweg

:- table win/1.
win(X) :- move(X, Y), tnot(win(Y)).

main :-
    findall(X-Y, unreach(X, Y), L),
    format("unerreichbar: ~w~n", [L]),
    forall(member(P, [p3, p1, q1]),
           (   catch(( win(P) -> R = gewinnt ; R = verliert ), error(E, _), R = E),
               format("~w: ~w~n", [P, R])
           )).
