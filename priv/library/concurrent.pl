/* library(concurrent): Ziele parallel in BEAM-Prozessen (PrologEx)

   Jedes Ziel läuft in einem eigenen Prozess mit einer Kopie des
   Interpreter-Zustands, super-strikt ohne Seiteneffekte (wie
   call_with_no_side_effects/1). Darum ist Parallelität hier gefahrlos: die
   Reihenfolge spielt keine Rolle, und ein Kind kann jederzeit beendet
   werden, ohne etwas halb getan zu haben.

     concurrent(+N, :Goals, +Options)
         alle Ziele, höchstens N gleichzeitig; jedes wie once/1; gelingt,
         wenn alle gelingen (die Bindungen werden zusammengeführt)
     concurrent_maplist(:G, ?L1), concurrent_maplist(:G, ?L1, ?L2),
     concurrent_maplist(:G, ?L1, ?L2, ?L3)
         wie maplist/2,3,4, je Element ein Prozess (once)
     concurrent_forall(:Cond, :Action), concurrent_forall(:Cond, :Action, +Options)
         für jede Lösung von Cond (im Aufrufer berechnet) Action parallel;
         gelingt, wenn jede gelingt
     concurrent_findall(?Template, :Goals, -Bags)
         je Ziel alle Lösungen: Bags = [findall(Template, G1), ...]
     concurrent_and(:Gen, :Test), concurrent_and(:Gen, :Test, +Options)
         wie (Gen, Test), die Tests parallel: Gen läuft im Aufrufer (vorab
         alle Lösungen, also endlich), je Lösung ein Kind mit allen
         Lösungen von Test; zurück per Backtracking in der Reihenfolge von
         (Gen, Test) – SWI liefert sie in beliebiger Reihenfolge und
         erzeugt Gen nebenher
     first_solution(?X, :Goals, +Options)
         wer zuerst eine Lösung hat, gewinnt; die anderen werden beendet

   Options: threads(N) (concurrent_forall/3, concurrent_and/3, wie SWI;
   es sind Prozesse der BEAM, keine Threads) und chunk(K) (ebenda, siehe
   Blockung); first_solution/3:
   on_fail(stop) (Vorgabe: das erste Scheitern beendet alles) oder
   on_fail(continue) (scheitern, wenn alle gescheitert sind);
   on_error(stop) (Vorgabe: die erste Ausnahme beendet alles und kommt
   an) oder on_error(continue) (wie ein Scheitern; haben alle geworfen
   oder sind gescheitert, scheitert first_solution/3, wie SWI);
   output(winner) (Vorgabe) oder output(all) (siehe unten). Höchstens so
   viele Prozesse gleichzeitig wie Scheduler, außer bei concurrent/3.

   Blockung (wie schedule(dynamic) bei OpenMP mit guided-Paketen): höchstens
   so viele Arbeiter wie Scheduler (bzw. threads(N)); ein Arbeiter bekommt
   ein Paket von Elementen, bearbeitet sie nacheinander und holt sich dann
   das nächste – Rest / (2·Arbeiter) Elemente, mindestens eines, oder K mit
   chunk(K). Jedes Element läuft auf einem frischen Zustand (eigener
   Zufall, eigene Ausgabe, concurrent_child/1); für das Programm sieht es
   aus wie ein Kind je Element. first_solution/3: ein Arbeiter je Ziel (sie
   laufen gegeneinander).

   Ausgabe: jedes Kind schreibt in einen eigenen Puffer (auf die aktuelle
   Ausgabe; andere Streams bleiben verboten). Ausgegeben wird hier, wenn
   alles entschieden ist: nach Erfolg alle Puffer in der Reihenfolge der
   Ziele (wie bei maplist nacheinander), bei first_solution/3 der des
   Gewinners; bei Scheitern oder Ausnahme nichts. Mit output(all) gibt
   first_solution/3 zusätzlich die übrigen auf user_error aus, je mit einer
   Kopfzeile (% Ziel I: abgebrochen | gescheitert | Ausnahme) – auch, wenn
   es scheitert oder wirft. Im Kind sind außerdem erlaubt: Zufall (eigener
   Generator, siehe README), memo/tabling (Kopie der Tabellen) und
   b_setval/2. Wer bin ich: concurrent_child(I/N) gibt im Kind die
   Position I seines Ziels (1-basiert) und die Anzahl N der Ziele.

   Eine Ausnahme in einem Kind – auch der Seiteneffekt-Fehler
   permission_error(perform, side_effect, Ziel) – beendet alle anderen
   sofort und kommt hier an; welche, wenn mehrere werfen, entscheidet der
   Scheduler. Zeit-, Inferenz- und Speichergrenzen des Aufrufers gelten
   weiter: die Deadline für alle, das Inferenzbudget für alle zusammen (die
   Kinder zählen im selben Zähler), die Speichergrenze je Kind.

   Die Ziele rechnen auf Kopien: teilen sie Variablen, bindet jedes seine
   eigene, und erst das Zusammenführen prüft, ob es passt – bei abhängigen,
   nichtdeterministischen Zielen kann das Ergebnis vom sequentiellen
   abweichen. Attributierte Variablen in Zielen oder Ergebnissen:
   representation_error(concurrent_attributed_variable); zyklische Terme:
   representation_error(cyclic_term).
*/

:- module(concurrent, [concurrent/3,
                       concurrent_maplist/2,
                       concurrent_maplist/3,
                       concurrent_maplist/4,
                       concurrent_forall/2,
                       concurrent_forall/3,
                       concurrent_findall/3,
                       concurrent_and/2,
                       concurrent_and/3,
                       first_solution/3,
                       concurrent_child/1,
                       concurrent_child_stack/1]).

%% concurrent_child(-I/N)
%
% Im Kind: I ist die Position seines Ziels (1-basiert) unter den N Zielen
% des Aufrufs (bei Verschachtelung des innersten); außerhalb eines Kinds
% scheitert es. Bei concurrent_maplist/2,3,4 die Position in der Liste,
% bei first_solution/3 die des Ziels in Goals, bei concurrent/3 die in der
% Zielliste. Wer den Index sichtbar mitgeben will, nimmt numlist/3:
% numlist(1, N, Is), concurrent_maplist(G, Is, Xs).
concurrent_child(P) :-
    '$conc_child'(P).

%% concurrent_child_stack(-Stack)
%
% Stack ist der Stapel der Aufrufe als Liste I/N, der innerste oben:
% concurrent_child(P) ist concurrent_child_stack([P|_]).
% Außerhalb jedes Kinds ist Stack = []; length(Stack, D) ist also die
% Schachtelungstiefe.
concurrent_child_stack(Stack) :-
    '$conc_child_stack'(Stack).

:- use_module(library(lists)).
:- use_module(library(error)).

:- meta_predicate(concurrent(+, :, +)).
:- meta_predicate(concurrent_maplist(1, ?)).
:- meta_predicate(concurrent_maplist(2, ?, ?)).
:- meta_predicate(concurrent_maplist(3, ?, ?, ?)).
:- meta_predicate(concurrent_forall(0, 0)).
:- meta_predicate(concurrent_forall(0, 0, +)).
:- meta_predicate(concurrent_and(0, 0)).
:- meta_predicate(concurrent_and(0, 0, +)).
:- meta_predicate(concurrent_findall(?, :, -)).
:- meta_predicate(first_solution(?, :, +)).

concurrent(N, M:Goals, _Options) :-
    must_be(integer, N),
    (   N >= 1 -> true ; domain_error(positive_integer, N) ),
    must_be(list, Goals),
    goals_jobs(Goals, M, Jobs),
    run(Jobs, once, N, R),
    R = ok(Results),
    Goals = Results.

goals_jobs([], _, []).
goals_jobs([G|Gs], M, [G-(M:G)|Js]) :-
    goals_jobs(Gs, M, Js).

concurrent_maplist(G, L1) :-
    must_be(list, L1),
    maplist_jobs1(L1, G, Jobs),
    workers(W),
    run(Jobs, once, W, ok(Rs)),
    L1 = Rs.

concurrent_maplist(G, L1, L2) :-
    same_len(L1, L2),
    maplist_jobs2(L1, L2, G, Jobs),
    workers(W),
    run(Jobs, once, W, ok(Rs)),
    pairs2(L1, L2, Rs).

concurrent_maplist(G, L1, L2, L3) :-
    same_len(L1, L2),
    same_len(L1, L3),
    maplist_jobs3(L1, L2, L3, G, Jobs),
    workers(W),
    run(Jobs, once, W, ok(Rs)),
    pairs3(L1, L2, L3, Rs).

maplist_jobs1([], _, []).
maplist_jobs1([X|Xs], G, [X-call(G, X)|Js]) :-
    maplist_jobs1(Xs, G, Js).

maplist_jobs2([], [], _, []).
maplist_jobs2([X|Xs], [Y|Ys], G, [(X-Y)-call(G, X, Y)|Js]) :-
    maplist_jobs2(Xs, Ys, G, Js).

maplist_jobs3([], [], [], _, []).
maplist_jobs3([X|Xs], [Y|Ys], [Z|Zs], G, [t(X, Y, Z)-call(G, X, Y, Z)|Js]) :-
    maplist_jobs3(Xs, Ys, Zs, G, Js).

pairs2([], [], []).
pairs2([X|Xs], [Y|Ys], [X-Y|Rs]) :-
    pairs2(Xs, Ys, Rs).

pairs3([], [], [], []).
pairs3([X|Xs], [Y|Ys], [Z|Zs], [t(X, Y, Z)|Rs]) :-
    pairs3(Xs, Ys, Zs, Rs).

% wie maplist: Listen gleicher Länge (eine darf offen sein, wenn die andere
% fertig ist)
same_len(L1, L2) :-
    (   is_list(L1) -> length(L1, N), length(L2, N)
    ;   is_list(L2) -> length(L2, N), length(L1, N)
    ;   instantiation_error(L1)
    ).

concurrent_forall(Cond, Action) :-
    concurrent_forall(Cond, Action, []).

concurrent_forall(Cond, Action, Options) :-
    threads_option(Options, W),
    findall(Action-Action, Cond, Jobs),
    run(Jobs, once, W, ok(_)).

% threads(N) und chunk(K) als sched(N, K) für '$conc_run'/7
threads_option(Options, sched(W, K)) :-
    must_be(list, Options),
    (   memberchk(threads(W), Options)
    ->  must_be(integer, W),
        (   W >= 1 -> true ; domain_error(positive_integer, W) )
    ;   workers(W)
    ),
    (   memberchk(chunk(K), Options)
    ->  must_be(integer, K),
        (   K >= 1 -> true ; domain_error(positive_integer, K) )
    ;   K = auto
    ).

concurrent_and(Gen, Test) :-
    concurrent_and(Gen, Test, []).

% die Lösungen von Gen im Aufrufer (vorab, alle), je eine Prüfung Test im
% Kind mit allen ihren Lösungen; zurück per Backtracking in der Reihenfolge
% von (Gen, Test)
concurrent_and(Gen, Test, Options) :-
    threads_option(Options, W),
    term_variables(Gen-Test, Vs),
    findall(Vs-Test, Gen, Jobs),
    run(Jobs, findall, W, ok(Bags)),
    member(Bag, Bags),
    member(Vs, Bag).

concurrent_findall(T, M:Goals, Bags) :-
    must_be(list, Goals),
    findall_jobs(Goals, T, M, Jobs),
    workers(W),
    run(Jobs, findall, W, ok(Bags)).

findall_jobs([], _, _, []).
findall_jobs([G|Gs], T, M, [T-(M:G)|Js]) :-
    findall_jobs(Gs, T, M, Js).

first_solution(X, M:Goals, Options) :-
    must_be(list, Goals),
    must_be(list, Options),
    (   memberchk(on_fail(F), Options)
    ->  (   F == stop -> true ; F == continue -> true ; domain_error(on_fail, F) )
    ;   F = stop
    ),
    (   memberchk(output(O), Options)
    ->  (   O == winner -> true ; O == all -> true ; domain_error(output, O) )
    ;   O = winner
    ),
    (   memberchk(on_error(E), Options)
    ->  (   E == stop -> true ; E == continue -> true ; domain_error(on_error, E) )
    ;   E = stop
    ),
    findall_jobs(Goals, X, M, Jobs),
    length(Jobs, N),
    N1 is max(N, 1),
    run(Jobs, first(F, O, E), N1, R),
    R = ok([X]).

% so viele wie Scheduler (die Maschine wählt)
workers(default).

% die Grenzen des Aufrufers, dann die Kinder (sie zählen ihre Inferenzen
% im selben Zähler wie der Aufrufer)
run(Jobs, Mode, Max, R) :-
    '$conc_limits'(D, B, Mem),
    '$conc_run'(Jobs, Mode, Max, D, B, Mem, R0),
    R = R0.
