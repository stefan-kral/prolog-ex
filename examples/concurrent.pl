% Rundgang durch library(concurrent): Vielfalt, Vorteile, Grenzen
%
%   mix prolog examples/concurrent.pl -g main -q
%
% Jedes Kind läuft in einem eigenen BEAM-Prozess mit einer Kopie des
% Zustands, super-strikt ohne Seiteneffekte. Darum ist Parallelität
% gefahrlos: die Reihenfolge spielt keine Rolle, und ein Kind kann jederzeit
% beendet werden, ohne etwas halb getan zu haben. Die Zeiten hängen von der
% Zahl der Kerne ab (erlang:system_info(schedulers_online)).

:- use_module(library(concurrent)).
:- use_module(library(iso_ext)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(lambda)).
:- use_module(library(format)).
:- use_module(library(random)).
:- use_module(library(memo)).
:- use_module(library(time)).
:- use_module(library(swi), [nb_setval/2]).
:- dynamic(log/1).

% --- Hilfen ---------------------------------------------------------------

titel(T) :- format("~n=== ~w ===~n", [T]).

% Ziel ausführen, Ergebnis (oder Scheitern, Ausnahme) zeigen
zeige(Text, G) :-
    format("~w~n    ", [Text]),
    catch(( call(G) -> R = gelungen ; R = gescheitert ), E, R = ausnahme(E)),
    format("~q~n", [R]).

zeige(Text, T, G) :-
    format("~w~n    ", [Text]),
    catch(( call(G) -> R = T ; R = gescheitert ), E, R = ausnahme(E)),
    format("~q~n", [R]).

ms(G, T) :-
    statistics(walltime, [T0|_]), call(G), statistics(walltime, [T1|_]),
    T is T1 - T0.

% --- Beispielprädikate -------------------------------------------------------

fib(0, 0).
fib(1, 1).
fib(N, F) :- N > 1, N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.

prime(N) :-
    N > 1,
    M is floor(sqrt(N)),
    \+ ( between(2, M, D), N mod D =:= 0 ).

loop :- loop.

quadrat(X, Y) :- Y is X * X.

% ab 3 ein (verbotener) Seiteneffekt
protokolliere(X) :- ( X > 2 -> assertz(log(X)) ; true ).

% Las Vegas: würfeln, bis eine Sechs kommt; wie oft?
bis_sechs(N) :- bis_sechs(1, N).
bis_sechs(K, N) :- random_between(1, 6, W), ( W =:= 6 -> N = K ; K1 is K+1, bis_sechs(K1, N) ).

:- memo mfib/2.
mfib(N, F) :- N < 2 -> F = N ; N1 is N-1, N2 is N-2, mfib(N1, F1), mfib(N2, F2), F is F1+F2.

% Suchraum aufteilen: das Kind I von N prüft jede N-te Zahl ab I
teilsuche(Max, Treffer) :-
    concurrent_child(I/N),
    findall(X, ( between(1, Max, X), X mod N =:= I mod N, prime(X), X mod 1000 =:= 7 ), Treffer).

% Term mit geteilten Teilbäumen: 2^K Blätter, aber nur K Knoten
dag(0, blatt) :- !.
dag(K, f(T, T)) :- K1 is K-1, dag(K1, T).

% --- (1) Vielfalt ----------------------------------------------------------

vielfalt :-
    titel('(1) Vielfalt'),
    zeige('concurrent_maplist/3: je Element ein Prozess', Ys,
          concurrent_maplist(quadrat, [1, 2, 3, 4], Ys)),
    zeige('concurrent_maplist/4 mit Lambda', Ps,
          concurrent_maplist(\X^Y^P^(P is X * Y), [1, 2, 3], [4, 5, 6], Ps)),
    zeige('concurrent/3: Ziele teilen Variablen, die Bindungen werden zusammengeführt', X-Y,
          concurrent(2, [X = f(Y, _), Y = 7], [])),
    zeige('concurrent_forall/3: für jede Lösung der Bedingung', gelungen,
          concurrent_forall(between(1, 10, N), ( prime(N) ; N mod 2 =:= 0 ; N =:= 9 ; N =:= 1 ), [threads(2)])),
    zeige('concurrent_findall/3: je Ziel alle Lösungen', Bags,
          concurrent_findall(Z, [member(Z, [a, b]), between(1, 3, Z), fail], Bags)),
    zeige('concurrent_and/2: wie (Gen, Test), Tests parallel, Reihenfolge wie nacheinander', Pr,
          findall(P, concurrent_and(between(1, 40, P), prime(P)), Pr)),
    zeige('first_solution/3: der Schnellste gewinnt, die Endlosschleife wird beendet', W,
          first_solution(W, [(loop, W = schleife), (fib(18, _), W = fib), W = schnell], [])),
    format("first_solution/3 mit output(all): die Verlierer auf user_error~n"),
    zeige('    (Ziel 1 rechnet noch, Ziel 3 ist gescheitert)', W2,
          first_solution(W2, [(write(a1), nl, loop), (fib(19, _), W2 = b), (write(c1), nl, fail)],
                         [on_fail(continue), output(all)])),
    zeige('first_solution/3 mit on_error(continue): eine Ausnahme zählt wie ein Scheitern', W3,
          first_solution(W3, [throw(kaputt), (fib(17, _), W3 = heil)], [on_error(continue)])),
    zeige('concurrent_child/1 und concurrent_child_stack/1: wer bin ich?', Ss,
          concurrent_maplist(\_^S^concurrent_maplist(\_^T^concurrent_child_stack(T), [x, y], S),
                             [a, b], Ss)),
    zeige('Ausgabe der Kinder: gepuffert, in der Reihenfolge der Ziele', gelungen,
          ( concurrent_maplist(\E^format("<~w>", [E]), [3, 1, 2]), nl )),
    nl,
    zeige('Zufall: jedes Kind hat einen eigenen Generator, mit festem Startwert reproduzierbar', L1-L2,
          ( set_random(seed(42)), concurrent_maplist(\_^R^random_between(1, 100, R), [a, b, c], L1),
            set_random(seed(42)), concurrent_maplist(\_^R^random_between(1, 100, R), [a, b, c], L2) )),
    zeige('memo im Kind: auf einer Kopie der Tabellen', Fs,
          concurrent_maplist(\K^F^mfib(K, F), [60, 70, 80], Fs)).

% --- (2) Vorteile ----------------------------------------------------------

vorteile :-
    titel('(2) Vorteile'),
    numlist(1, 8, L),
    ms(concurrent_maplist(\_^F^fib(21, F), L, _), Tp),
    ms(maplist(\_^F^fib(21, F), L, _), Ts),
    format("Rechenarbeit verteilt: 8 x fib(21) parallel ~w ms, nacheinander ~w ms~n", [Tp, Ts]),
    ms(concurrent_maplist(\_^T^teilsuche(50000, T), [a, b, c, d], Tss), Tq),
    append(Tss, T0), msort(T0, Treffer),
    format("Suchraum per concurrent_child/1 aufgeteilt (4 Kinder, je jede 4. Zahl):~n    Primzahlen mit Rest 7 mod 1000 in 1..50000: ~w (~w ms)~n",
           [Treffer, Tq]),
    zeige('Portfolio: eine Strategie hängt, eine andere findet die Antwort', W,
          first_solution(W, [(loop, W = tiefensuche), (between(1, inf, K), K*K > 2000, W = quadrat(K))], [])),
    zeige('Las Vegas: vier unabhängige Würfelserien, die kürzeste gewinnt', N,
          first_solution(N, [bis_sechs(N), bis_sechs(N), bis_sechs(N), bis_sechs(N)], [])),
    zeige('Deadline für alle: call_with_time_limit beendet auch die Kinder', gelungen,
          catch(call_with_time_limit(0.2, concurrent_maplist(\_^loop, [a, b, c])),
                time_limit_exceeded, true)),
    zeige('Sicher: ein Kind versucht einen Seiteneffekt, alle werden beendet', gelungen,
          concurrent_maplist(protokolliere, [1, 2, 3, 4])),
    (   log(_) -> format("    log/1 hat Einträge?!~n") ; format("    log/1 ist leer: nichts ist halb geschehen~n") ).

% --- (3) Grenzen -----------------------------------------------------------

grenzen :-
    titel('(3) Grenzen'),
    numlist(1, 500, L),
    ms(concurrent_maplist(quadrat, L, _), Tp),
    ms(maplist(quadrat, L, _), Ts),
    format("Zu feine Körnung: 500 x quadrat parallel ~w ms, nacheinander ~w ms~n", [Tp, Ts]),
    format("    (je Element ein Prozess mit einer Kopie des Zustands)~n"),
    zeige('Keine Wirkung nach außen: assertz im Kind', gelungen,
          concurrent_maplist(\X^assertz(log(X)), [1])),
    zeige('... auch nb_setval/2 (gemeint ist eine Wirkung über das Kind hinaus)', gelungen,
          concurrent_maplist(\X^nb_setval(k, X), [1])),
    zeige('... und Ausgabe auf einen anderen Stream als die aktuelle Ausgabe', gelungen,
          concurrent_maplist(\X^write(user_error, X), [1])),
    zeige('Attributierte Variablen reisen nicht (dif, freeze, clpz)', gelungen,
          ( dif(A, a), concurrent_maplist(\V^(V = b), [A]) )),
    zeige('Zyklische Terme auch nicht', gelungen,
          ( C = f(C), concurrent_maplist(\_^true, [C]) )),
    zeige('Jedes Ziel rechnet auf seiner Kopie: der Widerspruch fällt erst am Ende auf', gelungen,
          concurrent(2, [X = 1, (fib(18, _), X = 2)], [])),
    zeige('first_solution mit on_fail(stop): ein schnelles Scheitern beendet auch den Langsamen', gelungen,
          first_solution(_, [fail, (fib(18, _), true)], [])),
    ms(concurrent_maplist(\_^F^mfib(2000, F), [a], _), Tc),
    ms(mfib(2000, _), Tp1),
    ms(mfib(2000, _), Tp2),
    format("Was ein Kind lernt (memo), ist danach weg: mfib(2000) im Kind ~w ms,~n    danach im Aufrufer ~w ms (rechnet neu) und noch einmal ~w ms~n", [Tc, Tp1, Tp2]),
    dag(16, D),
    ms(concurrent_maplist(\_^R^(R = D), [a], _), Td),
    format("Geteilte Teilbäume werden beim Zurückkopieren ausgerollt: 2^16 Blätter, 16 Knoten: ~w ms~n", [Td]),
    format("concurrent_and/2 rechnet den Erzeuger vorab aus: between(1, inf, X) liefe endlos~n").

main :-
    vielfalt,
    vorteile,
    grenzen.
