% Gemeinsame Hilfen der Demos in examples/parallel (mit include/1 geladen;
% die Bibliotheken lädt jede Demo vorher selbst – include/1 liest die Datei
% ganz, bevor ihre Direktiven laufen, Operatoren wie ins fehlten sonst).
%
% Ein Modell ist ein Prädikat Modell(Vars, Opts): es stellt die Constraints
% auf und gibt die Optionen für labeling/2 (auch min/max). vergleich/4 baut
% es zweimal auf – einmal für labeling/2 nacheinander, einmal parallel –,
% misst beides und prüft, ob dasselbe herauskommt.

% Ausgabe: lesbar (Vorgabe) oder, nach csv/0, je Zeile @@... für run.sh -t
% (das Skript baut daraus eine Tabelle über mehrere Kernzahlen)
:- dynamic(ausgabe/1).

csv :- assertz(ausgabe(csv)).

titel(T) :-
    current_prolog_flag(cpu_count, K),
    (   ausgabe(csv)
    ->  format("@@titel;~w;~d~n", [T, K])
    ;   format("~n=== ~w (Kerne: ~d) ===~n", [T, K]),
        format("~w~t~44|~t~w~14+~t~w~10+~t~w~9+~n", ['', nacheinander, parallel, faktor])
    ).

% vor einer Messung: im csv-Modus melden, was jetzt läuft (run.sh zeigt es)
start(Name) :-
    ( ausgabe(csv) -> format("@@start;~w~n", [Name]), flush_output ; true ).

% eine Zeile: Name, Zeit nacheinander und parallel (ms), Ergebnis, gleich?
zeile(Name, T1, T2, Text, Gleich) :-
    (   ausgabe(csv)
    ->  ( Gleich == true -> G = gleich ; G = anders ),
        format("@@zeile;~w;~d;~d;~w~n", [Name, T1, T2, G])
    ;   ( Gleich == true -> Gl = '' ; Gl = '  VERSCHIEDEN!' ),
        F is T1 / max(T2, 1),
        format("~w~t~44|~t~d ms~14+~t~d ms~10+~t~2f x~9+  ~w~w~n", [Name, T1, T2, F, Text, Gl])
    ).

% (once/1: offene Choice Points einer Messung blieben sonst bis zum Ende von
% main/1 und machten jede spätere Speicherbereinigung teurer)
ms(G, T) :-
    statistics(walltime, [T0|_]), once(G), statistics(walltime, [T1|_]),
    T is T1 - T0.

% vergleich(+Name, +Art, :Modell, +COpts): Art eine (once(labeling/2) gegen
% concurrent_labeling/3) oder alle (findall mit labeling/2 gegen
% concurrent_labelings/4)
vergleich(Name, Art, Modell, COpts) :-
    start(Name),
    call(Modell, V1, O1),
    ms(seriell(Art, O1, V1, R1), T1),
    call(Modell, V2, O2),
    ms(parallel(Art, O2, V2, COpts, R2), T2),
    ( R1 == R2 -> Gleich = true ; Gleich = false ),
    ergebnis(Art, R1, Text),
    zeile(Name, T1, T2, Text, Gleich).

seriell(eine, O, V, R) :- ( once(labeling(O, V)) -> R = V ; R = keine ).
seriell(alle, O, V, S) :- findall(V, labeling(O, V), S).

parallel(eine, O, V, CO, R) :- ( concurrent_labeling(O, V, CO) -> R = V ; R = keine ).
parallel(alle, O, V, CO, S) :- concurrent_labelings(O, V, S, CO).

ergebnis(eine, keine, 'keine Lösung') :- !.
ergebnis(eine, R, R).
ergebnis(alle, S, Text) :- length(S, N), format(atom(Text), "~d Lösungen", [N]).

% Größe der Aufgaben: klein (je wenige Sekunden), mittel, gross
groesse(G, Klein, Mittel, Gross, X) :-
    (   G == klein -> X = Klein
    ;   G == mittel -> X = Mittel
    ;   G == gross -> X = Gross
    ;   domain_error(groesse, G)
    ).

% --- Modelle ---------------------------------------------------------------

% n Damen: Qs ins 1..N, keine zwei in einer Zeile oder Diagonale
damen(N, Qs) :-
    length(Qs, N), Qs ins 1..N, sicher(Qs).

sicher([]).
sicher([Q|Qs]) :- kein_angriff(Q, Qs, 1), sicher(Qs).

kein_angriff(_, [], _).
kein_angriff(Q, [Q1|Qs], D) :-
    Q #\= Q1, abs(Q - Q1) #\= D, D1 is D + 1, kein_angriff(Q, Qs, D1).

skalar([], [], 0).
skalar([C|Cs], [X|Xs], S) :- skalar(Cs, Xs, S0), S #= S0 + C*X.
