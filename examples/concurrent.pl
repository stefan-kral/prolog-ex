% call_with_no_side_effects/1 und library(concurrent) zum Ausprobieren
%
%   mix prolog examples/concurrent.pl -g main -q
%
% Jedes Kind läuft in einem eigenen BEAM-Prozess, super-strikt ohne
% Seiteneffekte. Versucht eines doch einen, werden alle beendet, und die
% Ausnahme kommt beim Aufrufer an.

:- use_module(library(concurrent)).
:- use_module(library(iso_ext)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(lambda)).
:- use_module(library(format)).
:- dynamic(log/1).

fib(0, 0).
fib(1, 1).
fib(N, F) :- N > 1, N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.

loop :- loop.

quadrat(X, Y) :- Y is X * X.

% ab 3 ein (verbotener) Seiteneffekt
protokolliere(X) :- ( X > 2 -> assertz(log(X)) ; true ).

zeige(Titel, G) :-
    format("~w~n    ", [Titel]),
    catch(( call(G) -> R = gelungen ; R = gescheitert ), E, R = ausnahme(E)),
    format("~q~n", [R]).

ms(G, T) :-
    statistics(walltime, [T0|_]), call(G), statistics(walltime, [T1|_]),
    T is T1 - T0.

main :-
    zeige('call_with_no_side_effects: rein ist erlaubt',
          call_with_no_side_effects((X is 6 * 7, X =:= 42))),
    zeige('call_with_no_side_effects: assertz ist es nicht (und geschieht nicht)',
          call_with_no_side_effects(assertz(log(1)))),
    zeige('... auch nicht über findall/3',
          call_with_no_side_effects(findall(_, write(hallo), _))),
    zeige('... und Ausgabe in ein Atom ist auch Stream-Verkehr',
          call_with_no_side_effects(format(atom(_), "~w", [x]))),
    zeige('concurrent_maplist: je Element ein Prozess',
          ( concurrent_maplist(quadrat, [1, 2, 3, 4], Ys), format("~w ", [Ys]) )),
    zeige('ein Kind versucht einen Seiteneffekt: alle werden beendet',
          concurrent_maplist(protokolliere, [1, 2, 3, 4])),
    zeige('first_solution: der Schnellste gewinnt, die Endlosschleife wird beendet',
          ( first_solution(W, [(loop, W = schleife), (fib(18, _), W = fib), W = schnell], []),
            format("~w ", [W]) )),
    numlist(1, 8, L),
    ms(concurrent_maplist(\_^F^fib(21, F), L, _), Tp),
    ms(maplist(\_^F^fib(21, F), L, _), Ts),
    format("8 x fib(21): parallel ~w ms, nacheinander ~w ms~n", [Tp, Ts]),
    (   log(_) -> format("log/1 hat Einträge?!~n") ; format("log/1 ist leer, wie es sein soll~n") ).
