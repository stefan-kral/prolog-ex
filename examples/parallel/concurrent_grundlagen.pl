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
    current_prolog_flag(cpu_count, K),
    groesse(G, 20, 22, 24, F),
    Anzahl is 2 * K,
    length(Ns, Anzahl), maplist(=(F), Ns),
    format(atom(A), "maplist fib(~d), ~d mal", [F, Anzahl]),
    zeit(A, maplist(fib, Ns, _), concurrent_maplist(fib, Ns, _)),
    groesse(G, 100000, 300000, 1000000, P),
    format(atom(B), "Primzahlen bis ~d, Blöcke zu 10000", [P]),
    zeit(B, primzahlen_seriell(P, N1), primzahlen_parallel(P, N2)),
    format("~t~44|  ~d bzw. ~d Primzahlen~n", [N1, N2]),
    F4 is F + 4,
    zeige_ergebnis('first_solution: das schnellere Ziel gewinnt',
                   first_solution(X, [(fib(F4, _), X = langsam), (fib(F, _), X = schnell)], []), X),
    zeige_ergebnis('concurrent_and: Paare mit Summe 10',
                   findall(A1-B1, concurrent_and(paar(A1, B1), A1 + B1 =:= 10), Ps), Ps),
    zeige_ergebnis('concurrent_child/1: Stelle und Anzahl',
                   concurrent_maplist(\_^I^concurrent_child(I), [x, y, z], Is), Is),
    zeige_ergebnis('Seiteneffekt im Kind (assertz) abgelehnt',
                   catch(concurrent_maplist(\_^assertz(foo), [1]), error(E, _), true), E).

fib(0, 0).
fib(1, 1).
fib(N, F) :- N > 1, N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.

prim(N) :- N > 1, M is floor(sqrt(N)), \+ ( between(2, M, D), N mod D =:= 0 ).

block(Von, Anz) :- Bis is Von + 9999, findall(x, ( between(Von, Bis, X), prim(X) ), L), length(L, Anz).

bloecke(P, Bs) :- Hoch is P // 10000 - 1, findall(V, ( between(0, Hoch, I), V is I * 10000 ), Bs).

primzahlen_seriell(P, N) :- bloecke(P, Bs), maplist(block, Bs, Ns), sum_list(Ns, N).
primzahlen_parallel(P, N) :- bloecke(P, Bs), concurrent_maplist(block, Bs, Ns), sum_list(Ns, N).

paar(A, B) :- between(0, 10, A), between(0, 10, B).

zeit(Name, G1, G2) :-
    ms(G1, T1), ms(G2, T2), F is T1 / max(T2, 1),
    format("~w~t~44|~t~d ms~14+~t~d ms~10+~t~2f x~9+~n", [Name, T1, T2, F]).

zeige_ergebnis(Name, G, X) :-
    ( call(G) -> true ; X = gescheitert ),
    format("~w~t~44|  ~q~n", [Name, X]).
