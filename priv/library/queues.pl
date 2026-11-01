/* library(queues) für PrologEx: die Vereinigung von Scryer und SICStus 4

   Der erste Teil (queue/1 bis queue_length/2) stammt aus Scryer Prolog
   (Lizenz: priv/library/SCRYER-LICENSE); queue_length/2 kann hier auch,
   wie bei SICStus, eine Warteschlange gegebener Länge erzeugen. Die
   übrigen Prädikate bieten die API von SICStus 4 über derselben
   Darstellung (eigene Implementierung nach SICStus' Dokumentation).
   queue_last/3 hat Scryers Argumentreihenfolge: queue_last(X, Q0, Q)
   hängt X hinten an Q0 an (SICStus: queue_last(Q0, X, Q)).

   Darstellung (Scryer): q(Anzahl, Vorne, Hinten), Anzahl als 0, s(0),
   s(s(0)), ...; die Elemente sind die Differenzliste Vorne\Hinten. Alle
   Operationen an den Enden kosten O(1) und gehen in beide Richtungen
   (anhängen und abnehmen), wie bei Scryer und SICStus. queue_last/3,
   queue_last_list/3 und queue_append/3 binden dabei das Hinten der alten
   Warteschlange (wie dort): eine Warteschlange, an die hinten angehängt
   wurde, sollte danach nicht noch einmal hinten verlängert werden.
*/

:- module(queues, [
    % Scryer
    queue/1, queue/2, queue_head/3, queue_head_list/3,
    queue_last/3, queue_last_list/3, list_queue/2, queue_length/2,
    % SICStus 4
    empty_queue/1, singleton_queue/2, portray_queue/1, is_queue/1,
    queue_head/2, queue_tail/2, queue_cons/3, queue_last/2,
    append_queue/3, queue_append/3, queue_list/2,
    queue_member/2, queue_memberchk/2,
    map_queue/2, map_queue/3, map_queue_list/3, map_list_queue/3,
    some_queue/2, some_queue/3, somechk_queue/2, somechk_queue/3
]).

:- meta_predicate(map_queue(1, ?)).
:- meta_predicate(map_queue(2, ?, ?)).
:- meta_predicate(map_queue_list(2, ?, ?)).
:- meta_predicate(map_list_queue(2, ?, ?)).
:- meta_predicate(some_queue(1, ?)).
:- meta_predicate(some_queue(2, ?, ?)).
:- meta_predicate(somechk_queue(1, ?)).
:- meta_predicate(somechk_queue(2, ?, ?)).

/* --- Aus Scryer Prolog ------------------------------------------------- */

/* true when Queue is a queue with no elements. */
queue(q(0,B,B)).

/* true when Queue is a queue with one element. */
queue(X, q(s(0), [X|B], B)).

/* true when Queue0 and Queue1 have the same elements except that
 * Queue0 has in addition X at the front.  Use it for enqueuing and
 * dequeuing both.
*/
queue_head(X, q(N, F, B), q(s(N), [X|F], B)).

/* true when append(List, Queue1, Queue0) would be true if only Queue1
 * and Queue0 were lists instead of queues.
*/
queue_head_list([], Queue, Queue).
queue_head_list([X|Xs], Queue, Queue0) :-
    queue_head(X, Queue1, Queue0),
    queue_head_list(Xs, Queue, Queue1).

/* true when Queue0 and Queue1 have the same elements except that
 * Queue0 has in addition to X at the end.
*/
queue_last(X, q(N, F, [X|B]), q(s(N), F, B)).

/* true when append(Queue1, List, Queue0) would be true if only Queue1
 * and Queue0 were lists instead of queues.
*/
queue_last_list([], Queue, Queue).
queue_last_list([X|Xs], Queue1, Queue) :-
    queue_last(X, Queue1, Queue2),
    queue_last_list(Xs, Queue2, Queue).

/* true when List is a list and Queue is a queue and they represent
 * the same sequence.
*/
list_queue(List, q(Count, Front, Back)) :-
    list_queue(List, Count, Front, Back).

list_queue([], 0, B, B).
list_queue([X|Xs], s(N), [X|F], B) :-
    list_queue(Xs, N, F, B).

/* is true when Length is (a binary length representing) the number of
 * elements in (the queue represented by) Queue.  PrologEx: with an
 * unbound count and an integer Length it makes a queue of that length
 * (as in SICStus).
*/
queue_length(q(Count, F, B), Length) :-
    (   var(Count), integer(Length) ->
        Length >= 0,
        queue_make(Length, Count, F, B)
    ;   queue_length(Count, F, B, 0, Length)
    ).

queue_length(0, B, B, Length, Length).
queue_length(s(N), [_|Front], Back, L0, Length) :-
    L1 is L0 + 1,
    queue_length(N, Front, Back, L1, Length).

queue_make(0, 0, B, B) :- !.
queue_make(L, s(N), [_|F], B) :-
    L1 is L - 1,
    queue_make(L1, N, F, B).

/* --- SICStus 4 ---------------------------------------------------------- */

%% empty_queue(?Queue): Queue ist leer (prüfen oder erzeugen)
empty_queue(q(0,B,B)).

%% singleton_queue(?X, ?Queue): Queue hat genau das Element X
singleton_queue(X, q(s(0),[X|B],B)).

%% queue_head(+Queue, -Head): das erste Element (bleibt in der Schlange)
queue_head(q(s(_),[Head|_],_), Head).

%% queue_tail(?Queue, ?Tail): Tail ist Queue ohne das erste Element
queue_tail(q(s(N),[_|F],B), q(N,F,B)).

%% queue_cons(?Head, ?Tail, ?Queue): Queue ist Head vor Tail (beide Richtungen)
queue_cons(Head, q(N,F,B), q(s(N),[Head|F],B)).

%% queue_last(?Last, ?Queue): Last ist das letzte Element (O(n))
queue_last(Last, q(s(N),F,B)) :-
    queue_last_(N, F, B, Last).

queue_last_(0, [Last|B], B, Last).
queue_last_(s(N), [_|F], B, Last) :-
    queue_last_(N, F, B, Last).

%% append_queue(?List, ?Queue0, ?Queue): List vorn vor Queue0 (beide Richtungen)
append_queue(List, Queue0, Queue) :-
    queue_head_list(List, Queue0, Queue).

%% queue_append(+Queue0, +List, -Queue): List hinten an Queue0
queue_append(Queue0, List, Queue) :-
    queue_last_list(List, Queue0, Queue).

%% queue_list(?Queue, ?List): wie list_queue/2, Argumente getauscht
queue_list(Queue, List) :-
    list_queue(List, Queue).

%% is_queue(+Queue): Queue ist eine Warteschlange (erzeugt keine)
is_queue(Q) :-
    nonvar(Q),
    Q = q(N, F, B),
    is_queue_(N, F, B).

is_queue_(N, F, B) :-
    (   var(N) -> fail
    ;   N == 0 -> F == B
    ;   N = s(N1), nonvar(F), F = [_|F1],
        is_queue_(N1, F1, B)
    ).

%% queue_member(?Element, +Queue): Element ist in Queue (aufzählend)
queue_member(X, q(N,F,_)) :-
    queue_member_(N, F, X).

queue_member_(s(_), [X|_], X).
queue_member_(s(N), [_|F], X) :-
    queue_member_(N, F, X).

%% queue_memberchk(+Element, +Queue): das erste passende Element
queue_memberchk(X, Q) :-
    queue_member(X, Q),
    !.

%% map_queue(:P, +Queue): P(X) für jedes Element
map_queue(P, q(N,F,_)) :-
    map_queue_(N, F, P).

map_queue_(0, _, _).
map_queue_(s(N), [X|F], P) :-
    call(P, X),
    map_queue_(N, F, P).

%% map_queue(:P, +Queue[X..], ?Queue[Y..]): P(Xi, Yi) für alle i
map_queue(P, q(N,F1,_), q(N,F2,B2)) :-
    map_queue_(N, F1, F2, B2, P).

map_queue_(0, _, B, B, _).
map_queue_(s(N), [X|F1], [Y|F2], B, P) :-
    call(P, X, Y),
    map_queue_(N, F1, F2, B, P).

%% map_queue_list(:P, ?Queue[X..], ?[Y..]): P(Xi, Yi), beide Richtungen
map_queue_list(P, q(N,F,B), L) :-
    map_queue_list_(N, F, B, L, P).

map_queue_list_(0, B, B, [], _).
map_queue_list_(s(N), [X|F], B, [Y|L], P) :-
    call(P, X, Y),
    map_queue_list_(N, F, B, L, P).

%% map_list_queue(:P, ?[X..], ?Queue[Y..]): P(Xi, Yi), beide Richtungen
map_list_queue(P, L, q(N,F,B)) :-
    map_list_queue_(L, N, F, B, P).

map_list_queue_([], 0, B, B, _).
map_list_queue_([X|L], s(N), [Y|F], B, P) :-
    call(P, X, Y),
    map_list_queue_(L, N, F, B, P).

%% some_queue(:P, +Queue): P(X) für ein Element (alle Lösungen)
some_queue(P, q(N,F,_)) :-
    some_queue_(N, F, P).

some_queue_(s(_), [X|_], P) :-
    call(P, X).
some_queue_(s(N), [_|F], P) :-
    some_queue_(N, F, P).

%% some_queue(:P, +Queue[X..], ?Queue[Y..]): P(Xi, Yi) für ein i
some_queue(P, q(N,F1,_), q(N,F2,_)) :-
    some_queue_(N, F1, F2, P).

some_queue_(s(_), [X|_], [Y|_], P) :-
    call(P, X, Y).
some_queue_(s(N), [_|F1], [_|F2], P) :-
    some_queue_(N, F1, F2, P).

%% somechk_queue(:P, +Queue): wie some_queue/2, die erste Lösung
somechk_queue(P, Q) :-
    some_queue(P, Q),
    !.

somechk_queue(P, Q1, Q2) :-
    some_queue(P, Q1, Q2),
    !.

%% portray_queue(+Queue): lesbar ausgeben, Queue[a,b,c] (nicht einlesbar)
portray_queue(q(N,F,_)) :-
    write('Queue['),
    portray_queue_(N, F, ''),
    write(']').

portray_queue_(N, _, _) :-
    var(N), !,
    write('...').
portray_queue_(0, _, _) :- !.
portray_queue_(s(N), [X|F], Sep) :-
    write(Sep), print(X),
    portray_queue_(N, F, ',').
