% concurrent_labelings/3,4: alle Lösungen, genau wie findall mit labeling/2
% (auch die Reihenfolge), die Teile parallel.
%
%   ../../start_ex clpz_alle.pl -g main -g halt          (oder: run.sh)
%
% 16 feste Teile, concurrent_maplist/3 verteilt sie; sind es weniger als 4
% je Kern, holen sich freie Kerne am Ende Arbeit aus laufenden Teilen (Work
% Stealing). parts(N) zeigt beides auf jedem Rechner: parts(16) gegen
% parts(K) mit K = Zahl der Kerne.

:- use_module(library(clpz)).
:- use_module(library(clpz_concurrent)).
:- use_module(library(concurrent)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(format)).
:- use_module(library(iso_ext)).
:- include(hilfen).

main :- main(klein).

main(G) :-
    titel('alle Lösungen: concurrent_labelings/4'),
    current_prolog_flag(cpu_count, K),
    groesse(G, 9, 10, 11, N),
    format(atom(A), "~d Damen, ff", [N]),
    vergleich(A, alle, damen_ff(N), []),
    format(atom(B), "~d Damen, leftmost", [N]),
    vergleich(B, alle, damen_ohne_ff(N), []),
    format(atom(C), "~d Damen, enum", [N]),
    vergleich(C, alle, damen_enum(N), []),
    groesse(G, 11, 12, 13, M),
    format(atom(D), "~d Damen, Q1 #> ~d, Q2 #< 3", [M, M // 2]),
    vergleich(D, alle, damen_rechts(M), []),
    format(atom(E), "  ebenso, parts(~d): ein Teil je Kern", [K]),
    vergleich(E, alle, damen_rechts(M), [parts(K)]),
    format(atom(F), "  ebenso, parts(~d), steal(0.001)", [K]),
    vergleich(F, alle, damen_rechts(M), [parts(K), steal(0.001)]),
    vergleich('magisches Quadrat 3x3', alle, magisch(3), []),
    vergleich('SEND+MORE=MONEY', alle, send_more, []).

damen_ff(N, Qs, [ff]) :- damen(N, Qs).
damen_ohne_ff(N, Qs, []) :- damen(N, Qs).
damen_enum(N, Qs, [enum]) :- damen(N, Qs).
damen_rechts(N, Qs, []) :- damen(N, Qs), Qs = [A, B|_], A #> N // 2, B #< 3.

% magisches Quadrat N x N: 1..N², Zeilen, Spalten, Diagonalen gleiche Summe
magisch(N, Vs, [ff]) :-
    N2 is N * N, length(Vs, N2), Vs ins 1..N2, all_different(Vs),
    S is N * (N2 + 1) // 2,
    zeilen(Vs, N, Zs), transpose(Zs, Ss),
    maplist(summe(S), Zs), maplist(summe(S), Ss),
    diagonale(Zs, 0, 1, D1), diagonale(Zs, N, -1, D2),
    summe(S, D1), summe(S, D2).

zeilen([], _, []) :- !.
zeilen(Vs, N, [Z|Zs]) :- length(Z, N), append(Z, Rest, Vs), zeilen(Rest, N, Zs).

summe(S, Xs) :- sum(Xs, #=, S).

diagonale([], _, _, []).
diagonale([Z|Zs], I0, Schritt, [X|Xs]) :-
    ( Schritt > 0 -> I = I0 ; I is I0 - 1 ),
    nth0(I, Z, X),
    I1 is I0 + Schritt, diagonale(Zs, I1, Schritt, Xs).

transpose([], []).
transpose([[]|_], []) :- !.
transpose(Zs, [S|Ss]) :- maplist(kopf_rest, Zs, S, Rs), transpose(Rs, Ss).
kopf_rest([H|T], H, T).

send_more([S,E,N,D,M,O,R,Y], []) :-
    [S,E,N,D,M,O,R,Y] ins 0..9, all_different([S,E,N,D,M,O,R,Y]),
    S #\= 0, M #\= 0,
    1000*S + 100*E + 10*N + D + 1000*M + 100*O + 10*R + E
        #= 10000*M + 1000*O + 100*N + 10*E + Y.
