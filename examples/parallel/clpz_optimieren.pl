% concurrent_labeling/3 mit min(E)/max(E): genau die Lösung von
% once(labeling/2) – Branch and Bound erst nacheinander, solange ein
% Schritt billig ist, dann parallel mit Work Stealing und gemeinsamer
% Schranke (jede bessere Lösung schränkt sofort alle Teile ein).
%
%   ../../start_ex clpz_optimieren.pl -g main -g halt     (oder: run.sh)

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
    titel('optimieren: concurrent_labeling/3 mit min/max'),
    groesse(G, 16, 18, 20, N),
    format(atom(A), "Rucksack, ~d Gegenstände, max(Wert)", [N]),
    vergleich(A, eine, rucksack(N), []),
    groesse(G, 8, 9, 10, Q),
    format(atom(B), "~d Damen, ff, min(Σ i·Qi)", [Q]),
    vergleich(B, eine, damen_summe(Q), []),
    format(atom(C), "~d Damen, min(Q2), max(Q3) (lexikographisch)", [Q]),
    vergleich(C, eine, damen_lex(Q), []),
    groesse(G, 7, 8, 9, M),
    format(atom(D), "Golomb-Lineal, ~d Marken, min(Länge)", [M]),
    vergleich(D, eine, golomb(M), []).

% 0/1-Rucksack: Gewichte und Werte aus einer festen Formel
rucksack(N, Xs, [max(Wert)]) :-
    findall(W-V, ( between(1, N, I), W is (I*37) mod 23 + 5, V is (I*53) mod 29 + 3 ), Ps),
    pairs_keys_values(Ps, Ws, Vs),
    length(Xs, N), Xs ins 0..1,
    skalar(Ws, Xs, Gewicht), Gewicht #=< 5*N,
    skalar(Vs, Xs, Wert).

damen_summe(N, Qs, [ff, min(S)]) :- damen(N, Qs), numlist(1, N, Is), skalar(Is, Qs, S).

damen_lex(N, Qs, [min(A), max(B)]) :- damen(N, Qs), Qs = [_, A, B|_].

% Golomb-Lineal: N Marken ab 0, alle Abstände verschieden, möglichst kurz
golomb(N, Ms, [min(L)]) :-
    length(Ms, N), Ms = [0|_], last(Ms, L),
    Max is N * N, Ms ins 0..Max,
    aufsteigend(Ms),
    findall(I-J, ( between(1, N, J), between(1, J, I), I < J ), Paare),
    abstaende(Paare, Ms, Ds),
    all_different(Ds),
    % Symmetrie: der erste Abstand kleiner als der letzte
    Ms = [_, M1|_], append(_, [Mv, L], Ms), M1 #< L - Mv.

aufsteigend([_]).
aufsteigend([A, B|Ms]) :- A #< B, aufsteigend([B|Ms]).

abstaende([], _, []).
abstaende([I-J|Ps], Ms, [D|Ds]) :-
    nth1(I, Ms, A), nth1(J, Ms, B), D #= B - A,
    abstaende(Ps, Ms, Ds).

pairs_keys_values([], [], []).
pairs_keys_values([K-V|Ps], [K|Ks], [V|Vs]) :- pairs_keys_values(Ps, Ks, Vs).
