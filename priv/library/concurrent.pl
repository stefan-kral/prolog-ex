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
     concurrent_include(:G, +L, -In), concurrent_exclude(:G, +L, -Out),
     concurrent_partition(:G, +L, -In, -Out),
     concurrent_partition(:G, +L, -Less, -Equal, -Greater)
         wie include/3, exclude/3, partition/4,5: die Prüfungen parallel
         (je Element once), die Bindungen der Elemente wie nacheinander
     concurrent_foldl(:G, +L, +V0, -V)
         wie foldl/4 (call(G, X, A0, A)), aber in Abschnitten parallel
         (Map-Reduce): G muss eine assoziative Verknüpfung sein – A = A0 ⊕ X
         mit (A ⊕ X) ⊕ Y = A ⊕ (X ⊕ Y), Elemente und Werte von derselben
         Art; kommutativ muss sie nicht sein
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

     concurrent_statistics(:Goal, -Stats)
         wie once(Goal), Stats: was die parallelen Läufe darin taten
         (Teile, Work Stealing, Auslastung der Arbeiter; siehe unten)

   Options: stats(S) (concurrent/3, concurrent_forall/3, concurrent_and/3,
   first_solution/3): S wie bei concurrent_statistics/2 für den Lauf;
   threads(N) (concurrent_forall/3, concurrent_and/3, wie SWI;
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
                       concurrent_include/3,
                       concurrent_exclude/3,
                       concurrent_partition/4,
                       concurrent_partition/5,
                       concurrent_foldl/4,
                       concurrent_forall/2,
                       concurrent_forall/3,
                       concurrent_findall/3,
                       concurrent_and/2,
                       concurrent_and/3,
                       first_solution/3,
                       concurrent_statistics/2,
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
:- meta_predicate(concurrent_include(1, +, -)).
:- meta_predicate(concurrent_exclude(1, +, -)).
:- meta_predicate(concurrent_partition(1, +, -, -)).
:- meta_predicate(concurrent_partition(2, +, -, -, -)).
:- meta_predicate(concurrent_foldl(3, +, +, -)).
:- meta_predicate(concurrent_forall(0, 0)).
:- meta_predicate(concurrent_forall(0, 0, +)).
:- meta_predicate(concurrent_and(0, 0)).
:- meta_predicate(concurrent_and(0, 0, +)).
:- meta_predicate(concurrent_findall(?, :, -)).
:- meta_predicate(first_solution(?, :, +)).
:- meta_predicate(concurrent_statistics(0, -)).

concurrent(N, M:Goals, Options) :-
    must_be(integer, N),
    (   N >= 1 -> true ; domain_error(positive_integer, N) ),
    must_be(list, Goals),
    must_be(list, Options),
    goals_jobs(Goals, M, Jobs),
    run(Jobs, once, N, Options, R),
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

% --- filtern: je Element eine Prüfung im Kind ---------------------------------
%
% Je Element X ein Ziel once(call(G, X)) mit allen Lösungen (findall):
% [] (gescheitert) oder [X'], X' das Element danach; X = X' übernimmt die
% Bindungen wie nacheinander (include/3 behält sie, exclude/3 ebenso).
concurrent_include(G, L, In) :-
    filter(L, G, Bags),
    split_bags(L, Bags, In, _).

concurrent_exclude(G, L, Out) :-
    filter(L, G, Bags),
    split_bags(L, Bags, _, Out).

concurrent_partition(G, L, In, Out) :-
    filter(L, G, Bags),
    split_bags(L, Bags, In, Out).

filter(L, G, Bags) :-
    must_be(list, L),
    filter_jobs(L, G, Jobs),
    workers(W),
    run(Jobs, findall, W, ok(Bags)).

filter_jobs([], _, []).
filter_jobs([X|Xs], G, [X-once(call(G, X))|Js]) :-
    filter_jobs(Xs, G, Js).

split_bags([], [], [], []).
split_bags([X|Xs], [B|Bs], In, Out) :-
    (   B == []
    ->  In = In1, Out = [X|Out1]
    ;   B = [X],
        In = [X|In1], Out = Out1
    ),
    split_bags(Xs, Bs, In1, Out1).

% partition/5: je Element once(call(G, X, Ord)), Ord eines von <, =, >;
% scheitert eine Prüfung, scheitert alles (wie nacheinander)
concurrent_partition(G, L, Less, Equal, Greater) :-
    must_be(list, L),
    order_jobs(L, G, Jobs),
    workers(W),
    run(Jobs, once, W, ok(Rs)),
    order_split(Rs, L, Less, Equal, Greater).

order_jobs([], _, []).
order_jobs([X|Xs], G, [(X-O)-call(G, X, O)|Js]) :-
    order_jobs(Xs, G, Js).

order_split([], [], [], [], []).
order_split([X-O|XOs], [X|Xs], Ls, Es, Gs) :-
    order_split_(O, X, Ls, Es, Gs, Ls1, Es1, Gs1),
    order_split(XOs, Xs, Ls1, Es1, Gs1).

order_split_(O, _, _, _, _, _, _, _) :-
    var(O), !,
    instantiation_error(O).
order_split_(<, X, [X|Ls], Es, Gs, Ls, Es, Gs) :- !.
order_split_(=, X, Ls, [X|Es], Gs, Ls, Es, Gs) :- !.
order_split_(>, X, Ls, Es, [X|Gs], Ls, Es, Gs) :- !.
order_split_(O, _, _, _, _, _, _, _) :-
    domain_error(order, O).

% --- falten: Map-Reduce -------------------------------------------------------
%
% Die Liste in Abschnitte (bis zu 4 je Kern, damit die Blockung ausgleichen
% kann); jedes Kind faltet seinen Abschnitt X1, ..., Xk zu
% X1 ⊕ X2 ⊕ ... ⊕ Xk (call(G, X2, X1, A1), ...), der Aufrufer dann
% V0 ⊕ R1 ⊕ R2 ⊕ ... in der Reihenfolge der Abschnitte. Bei einer
% assoziativen Verknüpfung dasselbe wie foldl/4. Deterministisch (je
% Schritt die erste Lösung).
concurrent_foldl(G, L, V0, V) :-
    must_be(list, L),
    length(L, N),
    current_prolog_flag(cpu_count, C),
    K is max(1, (N + 4*C - 1) // (4*C)),
    chunks(L, K, Cs),
    fold_jobs(Cs, G, Jobs),
    workers(W),
    run(Jobs, once, W, ok(Rs)),
    fold_(Rs, G, V0, V1),
    V = V1.

chunks([], _, []) :- !.
chunks(L, K, [C|Cs]) :-
    take(K, L, C, Rest),
    chunks(Rest, K, Cs).

take(0, L, [], L) :- !.
take(_, [], [], []) :- !.
take(K, [X|Xs], [X|C], Rest) :-
    K1 is K - 1,
    take(K1, Xs, C, Rest).

fold_jobs([], _, []).
fold_jobs([[X|Xs]|Cs], G, [R-'$fold_chunk'(Xs, G, X, R)|Js]) :-
    fold_jobs(Cs, G, Js).

'$fold_chunk'(Xs, G, A0, A) :-
    fold_(Xs, G, A0, A).

fold_([], _, A, A).
fold_([X|Xs], G, A0, A) :-
    once(call(G, X, A0, A1)),
    fold_(Xs, G, A1, A).

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
    run(Jobs, once, W, Options, ok(_)).

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
    run(Jobs, findall, W, Options, ok(Bags)),
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
    run(Jobs, first(F, O, E), N1, Options, R),
    R = ok([X]).

% so viele wie Scheduler (die Maschine wählt)
workers(default).

% die Grenzen des Aufrufers, dann die Kinder (sie zählen ihre Inferenzen
% im selben Zähler wie der Aufrufer)
run(Jobs, Mode, Max, R) :-
    '$conc_limits'(D, B, Mem),
    '$conc_run'(Jobs, Mode, Max, D, B, Mem, R0),
    R = R0.

% mit Options: stats(S) misst den Lauf (concurrent_statistics/2)
run(Jobs, Mode, Max, Options, R) :-
    (   memberchk(stats(S), Options)
    ->  concurrent_statistics(run(Jobs, Mode, Max, R), S)
    ;   run(Jobs, Mode, Max, R)
    ).

%% concurrent_statistics(:Goal, -Stats)
%
% wie once(Goal); Stats beschreibt die parallelen Läufe darin (Zeiten in
% ms, auf 0.1 gerundet):
%
%   time(T)          die ganze Zeit von Goal
%   parallel(P)      davon in parallelen Läufen (Uhrzeit, mit prepare)
%   serial(S)        T - P: der Aufrufer allein (Vorbereiten, Einsammeln,
%                    der Anfang nacheinander bei clpz_concurrent)
%   serial_phase(Q)  davon der Anfang nacheinander (clpz_concurrent)
%   prepare(R)       in P: den Zustand für die Arbeiter bereitstellen
%                    (die Datenbank teilen; beim ersten Lauf nach einer
%                    Änderung länger)
%   runs(N)          parallele Läufe
%   workers(W)       Arbeiter (der größte Lauf)
%   parts(N)         ausgegebene Arbeit: Elemente bzw. Teile der Suche
%   packets(N)       so oft bekam ein Arbeiter Arbeit (Pakete; beim
%                    Teilen gleich parts)
%   fixed(N)         feste Teile (Teilen)
%   requests(N)      Bitten um Arbeit an laufende Teile (Work Stealing)
%   steals(N)        abgegebene Teile
%   refused(N)       Bitten ohne Teil (none)
%   pruned(N)        weggefallene Teile (rechts einer Lösung)
%   bounds(N)        neue gemeinsame Schranken (Branch and Bound)
%   busy(B)          Arbeiter belegt, zusammen (mit setup)
%   setup(U)         davon der Aufbau des Modells (Teilen)
%   idle(I)          Arbeiter frei: Arbeiter × Dauer der Läufe - busy
%   utilization(P)   busy in Prozent davon
%   phases(N)        Anfänge nacheinander (clpz_concurrent)
%   handovers(N)     davon mit dem Rest an einen parallelen Lauf
%
% Gemessen wird im Aufrufer: was Kinder selbst parallel rechnen
% (verschachtelt), zählt nicht. Scheitert Goal oder wirft es, bleibt
% Stats ungebunden.
concurrent_statistics(Goal, Stats) :-
    '$conc_stats_begin',
    (   catch(Goal, E, ('$conc_stats_end'(none), throw(E)))
    ->  '$conc_stats_end'(Stats0),
        Stats = Stats0
    ;   '$conc_stats_end'(none),
        fail
    ).

% --- ein Element im Arbeiter ------------------------------------------------
%
% '$conc_job'(T, G, Mode, Deadline, Budget, Mem, R): findall(T, G') im
% Bereich ohne Seiteneffekte (G' = once(G) außer bei findall), ohne
% attributierte Variablen und Zyklen im Ergebnis; R = ok(L) | error(E).
% Grenzen: none oder Mikrosekunden / Inferenzen / Bytes. Als Klauseln
% (beim Laden übersetzt), damit nicht jedes Element seine Hülle neu übersetzt.
'$conc_job'(T, G, Mode, D, B, M, R) :-
    catch('$conc_job_'(T, G, Mode, D, B, M, R), E, R = error(E)).

'$conc_job_'(T, G, once, none, none, none, R) :- !,
    (   findall(T, ('$nse_call'(once(G)), '$conc_no_attvars'(T)), L)
    ->  '$conc_result'(L, R)
    ;   R = ok([])
    ).
'$conc_job_'(T, G, findall, none, none, none, R) :- !,
    (   findall(T, ('$nse_call'(G), '$conc_no_attvars'(T)), L)
    ->  '$conc_result'(L, R)
    ;   R = ok([])
    ).
'$conc_job_'(T, G0, Mode, D, B, M, R) :-
    (   Mode == findall -> G1 = G0 ; G1 = once(G0) ),
    F0 = findall(T, ('$nse_call'(G1), '$conc_no_attvars'(T)), L),
    (   M == none -> F1 = F0 ; F1 = iso_ext:call_with_memory_limit(F0, M) ),
    (   B == none -> F2 = F1, LR = none ; F2 = call_with_inference_limit(F1, B, LR) ),
    (   D == none -> F3 = F2 ; F3 = '$call_with_timeout'(F2, D, cumulative, throw) ),
    (   call(F3)
    ->  (   LR == inference_limit_exceeded -> throw(inference_limit_exceeded) ; true ),
        '$conc_result'(L, R)
    ;   R = ok([])
    ).

% Ergebnisse reisen als aufgelöste Terme: ein Zyklus ginge verloren
'$conc_result'(L, R) :-
    (   acyclic_term(L) -> R = ok(L)
    ;   throw(error(representation_error(cyclic_term), _))
    ).
