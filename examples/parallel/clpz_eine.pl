% concurrent_labeling/2,3 ohne min/max: dieselbe Lösung wie
% once(labeling/2), die Suche parallel mit Work Stealing.
%
%   ../../start_ex clpz_eine.pl -g main -g halt          (oder: run.sh)
%   ... -g 'main(gross)'                                  (klein, mittel, gross)
%
% Was es bringt, hängt davon ab, wie viel der Suche links der ersten
% Lösung liegt: das teilen sich die Kerne; was rechts davon gerechnet wird,
% war vergeblich. Mit ff sind die Damen fast immer gleich gelöst – da gibt
% es nichts zu teilen (serial(S): erst S Sekunden nacheinander).

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
    titel('eine Lösung: concurrent_labeling/3'),
    groesse(G, 18, 20, 22, N),
    format(atom(A), "~d Damen, leftmost", [N]),
    vergleich(A, eine, damen_ohne_ff(N), []),
    groesse(G, 20, 22, 24, M),
    format(atom(B), "~d Damen, Q1 #> ~d, Q2 #< 3", [M, M // 2]),
    vergleich(B, eine, damen_rechts(M), []),
    format(atom(C), "~d Damen, Q1 #> ~d, Q2 #< 3, bisect", [M, M // 2]),
    vergleich(C, eine, damen_rechts_bisect(M), []),
    vergleich('8 Damen (klein: bleibt nacheinander)', eine, damen_ohne_ff(8), []),
    vergleich('40 Damen, ff (sofort gelöst)', eine, damen_ff(40), []),
    groesse(G, 7, 8, 8, P),
    format(atom(D), "~d+1 Tauben in ~d Löchern (keine Lösung)", [P, P]),
    vergleich(D, eine, tauben(P), []),
    format(atom(E), "~d Damen, solution(any): irgendeine", [N]),
    vergleich_any(E, N).

damen_ohne_ff(N, Qs, []) :- damen(N, Qs).
damen_ff(N, Qs, [ff]) :- damen(N, Qs).
damen_rechts(N, Qs, []) :- damen(N, Qs), Qs = [A, B|_], A #> N // 2, B #< 3.
damen_rechts_bisect(N, Qs, [bisect]) :- damen_rechts(N, Qs, _).

% Taubenschlag: all_different/1 sieht es nicht, die Suche muss alles prüfen
tauben(N, Vs, []) :- N1 is N + 1, length(Vs, N1), Vs ins 1..N, all_different(Vs).

% solution(any): feste Teile gegeneinander, die erste gefundene gilt
vergleich_any(Name, N) :-
    damen(N, Q1), ms(once(labeling([], Q1)), T1),
    damen(N, Q2), ms(concurrent_labeling([], Q2, [solution(any)]), T2),
    F is T1 / max(T2, 1),
    ( Q1 == Q2 -> W = 'dieselbe' ; W = 'eine andere (erlaubt)' ),
    format("~w~t~44|~t~d ms~14+~t~d ms~10+~t~2f x~9+  ~w~n", [Name, T1, T2, F, W]).
