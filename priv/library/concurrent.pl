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
     first_solution(?X, :Goals, +Options)
         wer zuerst eine Lösung hat, gewinnt; die anderen werden beendet

   Options: workers(N) (concurrent_forall/3); first_solution/3:
   on_fail(stop) (Vorgabe: das erste Scheitern beendet alles) oder
   on_fail(continue) (scheitern, wenn alle gescheitert sind). Höchstens so
   viele Prozesse gleichzeitig wie Scheduler, außer bei concurrent/3.

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
   representation_error(concurrent_attributed_variable).
*/

:- module(concurrent, [concurrent/3,
                       concurrent_maplist/2,
                       concurrent_maplist/3,
                       concurrent_maplist/4,
                       concurrent_forall/2,
                       concurrent_forall/3,
                       concurrent_findall/3,
                       first_solution/3]).

:- use_module(library(lists)).
:- use_module(library(error)).

:- meta_predicate(concurrent(+, :, +)).
:- meta_predicate(concurrent_maplist(1, ?)).
:- meta_predicate(concurrent_maplist(2, ?, ?)).
:- meta_predicate(concurrent_maplist(3, ?, ?, ?)).
:- meta_predicate(concurrent_forall(0, 0)).
:- meta_predicate(concurrent_forall(0, 0, +)).
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
    must_be(list, Options),
    (   memberchk(workers(W), Options)
    ->  must_be(integer, W),
        (   W >= 1 -> true ; domain_error(positive_integer, W) )
    ;   workers(W)
    ),
    findall(Action-Action, Cond, Jobs),
    run(Jobs, once, W, ok(_)).

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
    findall_jobs(Goals, X, M, Jobs),
    length(Jobs, N),
    N1 is max(N, 1),
    run(Jobs, first(F), N1, R),
    R = ok([X]).

% so viele wie Scheduler (die Maschine wählt)
workers(default).

% die Grenzen des Aufrufers, dann die Kinder (sie zählen ihre Inferenzen
% im selben Zähler wie der Aufrufer)
run(Jobs, Mode, Max, R) :-
    '$conc_limits'(D, B, Mem),
    '$conc_run'(Jobs, Mode, Max, D, B, Mem, R0),
    R = R0.
