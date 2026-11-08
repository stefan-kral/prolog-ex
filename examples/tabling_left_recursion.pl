% Links-Rekursion mit Tabling: transitive Hülle über einem Ring aus N Knoten
%
%   mix prolog examples/tabling_left_recursion.pl -g "run(100)" -q
%
% path/2 ist so geschrieben, wie man es ohne Tabling nicht schreiben dürfte
% (links-rekursiv, Zyklen im Graphen). Zum Vergleich dieselbe Regel als
% Fixpunkt von Hand: naiv (jede Runde verbindet alle bisherigen Pfade mit
% allen Kanten, n Runden à n² Pfade: n³) und semi-naiv (nur die in der
% letzten Runde neuen Pfade: n²). library(tabling) liest unvollständige
% Tabellen live – die Hülle schließt in einer Runde. Auf einem
% Entwicklungsrechner etwa:
%
%   N=100   table: ~0,07 s   von Hand naiv: ~1,4 s   von Hand semi-naiv: ~0,17 s
%   N=150   table: ~0,16 s   von Hand naiv: ~5 s     von Hand semi-naiv: ~0,6 s

:- use_module(library(tabling)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(iso_ext)).
:- use_module(library(ordsets)).
:- use_module(library(format)).
:- dynamic(edge/2).

ring(N) :-
    retractall(edge(_, _)),
    forall(between(1, N, I), ( J is I mod N + 1, assertz(edge(I, J)) )).

% --- mit Tabling -----------------------------------------------------------
:- table path/2.
path(X, Y) :- path(X, Z), edge(Z, Y).
path(X, Y) :- edge(X, Y).

% --- von Hand: naiv --------------------------------------------------------
naive(All) :-
    findall(X-Y, edge(X, Y), E0), sort(E0, E),
    naive_(E, All).
naive_(P, All) :-
    findall(X-Y, ( member(X-Z, P), edge(Z, Y) ), New0),
    sort(New0, New), ord_union(P, New, P1),
    (   P1 == P -> All = P ; naive_(P1, All) ).

% --- von Hand: semi-naiv (nur das Delta der letzten Runde) -----------------
semi(All) :-
    findall(X-Y, edge(X, Y), E0), sort(E0, E),
    semi_(E, E, All).
semi_(P, [], P) :- !.
semi_(P, D, All) :-
    findall(X-Y, ( member(X-Z, D), edge(Z, Y) ), New0),
    sort(New0, New), ord_subtract(New, P, D1), ord_union(P, D1, P1),
    semi_(P1, D1, All).

ms(G, T) :-
    statistics(runtime, [T0|_]), call(G), statistics(runtime, [T1|_]),
    T is T1 - T0.

run(N) :-
    ring(N), abolish_all_tables,
    ms(findall(X-Y, path(X, Y), L), Tt), length(L, K),
    table_statistics(S),
    ms(naive(A), Tn), length(A, K1),
    ms(semi(B), Ts), length(B, K2),
    format("N=~w  Paare=~w/~w/~w  table: ~w ms ~w  naiv: ~w ms  semi-naiv: ~w ms~n",
           [N, K, K1, K2, Tt, S, Tn, Ts]).
