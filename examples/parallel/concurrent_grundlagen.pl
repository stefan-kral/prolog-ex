% library(concurrent): die Prädikate im Überblick, mit Zeiten.
%
%   ../../start_ex concurrent_grundlagen.pl -g main -g halt   (oder: run.sh)
%
% Jedes Kind läuft in einem eigenen BEAM-Prozess mit einer Kopie des
% Zustands, ohne Seiteneffekte. fib/2 dient als Rechenarbeit; ohne
% jit=false übersetzte der JIT es in BEAM-Code, und es gäbe nichts mehr zu
% verteilen. Mehr (Grenzen, Ausgabe, Zufall, Tabellen): ../concurrent.pl

:- set_prolog_flag(jit, false).
:- use_module(library(clpz)).
:- use_module(library(clpz_concurrent)).
:- use_module(library(concurrent)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(format)).
:- use_module(library(iso_ext)).
:- use_module(library(lambda)).
:- include(hilfen).

main :- main(klein).

main(G) :-
    titel('library(concurrent)'),
    groesse(G, 18, 20, 22, F),
    Anzahl = 16,
    length(Ns, Anzahl), maplist(=(F), Ns),
    format(atom(A), "maplist fib(~d), ~d mal", [F, Anzahl]),
    zeit(A, maplist(fib, Ns, _), concurrent_maplist(fib, Ns, _)),
    groesse(G, 100000, 200000, 250000, P),
    format(atom(B), "Primzahlen bis ~d, Blöcke zu 10000", [P]),
    zeit(B, primzahlen_seriell(P, N1), primzahlen_parallel(P, N2)),
    ( ausgabe(csv) -> true ; format("~t~44|  ~d bzw. ~d Primzahlen~n", [N1, N2]) ),
    F4 is F + 4,
    zeige_ergebnis('first_solution: das schnellere Ziel gewinnt',
                   first_solution(X, [(fib(F4, _), X = langsam), (fib(F, _), X = schnell)], []), X),
    zeige_ergebnis('concurrent_and: Paare mit Summe 10',
                   findall(A1-B1, concurrent_and(paar(A1, B1), A1 + B1 =:= 10), Ps), Ps),
    zeige_ergebnis('concurrent_child/1: Stelle und Anzahl',
                   concurrent_maplist(\_^I^concurrent_child(I), [x, y, z], Is), Is),
    zeige_ergebnis('Seiteneffekt im Kind (assertz) abgelehnt',
                   catch(concurrent_maplist(\_^assertz(foo), [1]), error(E, _), true), E).

% deterministisch: mit den Klauseln fib(0, 0), fib(1, 1), fib(N, F) :- N > 1, ...
% bliebe bei jedem fib(0, _) und fib(1, _) ein Choice Point offen (beide
% Klauseln passen) – 16 x fib(22) nacheinander: fast eine Million, gut 850 MB,
% und jede Speicherbereinigung kopiert sie; nacheinander war das so doppelt
% so langsam, die Primzahlen danach 25-mal (die Kinder räumen ihre mit ab)
fib(N, F) :- N < 2, !, F = N.
fib(N, F) :- N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.

prim(N) :- N > 1, M is floor(sqrt(N)), \+ ( between(2, M, D), N mod D =:= 0 ).

block(Von, Anz) :- Bis is Von + 9999, findall(x, ( between(Von, Bis, X), prim(X) ), L), length(L, Anz).

bloecke(P, Bs) :- Hoch is P // 10000 - 1, findall(V, ( between(0, Hoch, I), V is I * 10000 ), Bs).

primzahlen_seriell(P, N) :- bloecke(P, Bs), maplist(block, Bs, Ns), sum_list(Ns, N).
primzahlen_parallel(P, N) :- bloecke(P, Bs), concurrent_maplist(block, Bs, Ns), sum_list(Ns, N).

paar(A, B) :- between(0, 10, A), between(0, 10, B).

zeit(Name, G1, G2) :-
    start(Name),
    ms(G1, T1), ms(G2, T2),
    zeile(Name, T1, T2, '', true).

% (ohne Zeiten: nicht in der Tabelle von run.sh -t)
zeige_ergebnis(Name, G, X) :-
    ( call(G) -> true ; X = gescheitert ),
    ( ausgabe(csv) -> true ; format("~w~t~44|  ~q~n", [Name, X]) ).
