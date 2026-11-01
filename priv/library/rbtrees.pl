/* library(rbtrees) für PrologEx – Rot-Schwarz-Bäume wie SWI-Prolog (und
   YAP; ursprünglich von Vitor Santos Costa)

   Darstellung wie SWI: t(Nil, Wurzel), Nil = black('', _, _, ''), Knoten
   red(L, K, V, R) und black(L, K, V, R). Die Operationen sind in Elixir
   ('$rb_...'/N, PrologEx.Builtins.RbtreePrims) und folgen SWIs Code, die
   Bäume sind Term für Term dieselben. Hier stehen nur die Prädikate, die
   ein Ziel aufrufen.

   Schlüssel nach der Standardordnung. Wie bei SWI: ein Schlüssel darf
   Variablen enthalten, aber sie dürfen nicht so gebunden werden, dass
   sich die Ordnung der Schlüssel im Baum ändert.

   Anders als SWI prüfen list_to_rbtree/2 und ord_list_to_rbtree/2 ihre
   Liste (wie library(assoc)): doppelte Schlüssel
   domain_error(unique_key_pairs, L) bzw. domain_error(key_ordered_pairs,
   L), ungeordnete domain_error(key_ordered_pairs, L).
*/

:- module(rbtrees, [
    rb_new/1, rb_empty/1,
    rb_lookup/3, rb_update/4, rb_update/5, rb_apply/4,
    rb_insert/4, rb_insert_new/4, rb_delete/3, rb_delete/4,
    rb_visit/2, rb_visit_range/4, rb_keys/2,
    rb_map/2, rb_map/3, rb_partial_map/4, rb_fold/4, rb_clone/3,
    rb_min/3, rb_max/3, rb_del_min/4, rb_del_max/4,
    rb_next/4, rb_previous/4,
    list_to_rbtree/2, ord_list_to_rbtree/2,
    is_rbtree/1, rb_size/2, rb_in/3
]).

:- meta_predicate(rb_map(+, 2, -)).
:- meta_predicate(rb_map(?, 1)).
:- meta_predicate(rb_partial_map(+, +, 2, -)).
:- meta_predicate(rb_apply(+, +, 2, -)).
:- meta_predicate(rb_fold(3, +, +, -)).

%% rb_new(-Tree): ein neuer, leerer Baum
rb_new(t(Nil,Nil)) :-
    Nil = black('',_,_,'').

%% rb_empty(?Tree): Tree ist leer
rb_empty(t(Nil,Nil)) :-
    Nil = black('',_,_,'').

%% rb_lookup(+Key, -Value, +Tree)
rb_lookup(Key, Val, Tree) :-
    '$rb_lookup'(Key, Val, Tree).

%% rb_update(+Tree, +Key, ?NewVal, -NewTree): Key muss vorkommen
rb_update(Tree, Key, Val, NewTree) :-
    '$rb_update'(Tree, Key, _, Val, NewTree).

%% rb_update(+Tree, +Key, -OldVal, ?NewVal, -NewTree)
rb_update(Tree, Key, OldVal, Val, NewTree) :-
    '$rb_update'(Tree, Key, OldVal, Val, NewTree).

%% rb_apply(+Tree, +Key, :G, -NewTree): Wert durch call(G, Alt, Neu) ersetzen
rb_apply(Tree, Key, Goal, NewTree) :-
    '$rb_lookup'(Key, Val0, Tree),
    call(Goal, Val0, Val),
    '$rb_update'(Tree, Key, _, Val, NewTree).

%% rb_insert(+Tree, +Key, ?Value, -NewTree): einfügen oder ersetzen
rb_insert(Tree, Key, Val, NewTree) :-
    '$rb_insert'(Tree, Key, Val, NewTree).

%% rb_insert_new(+Tree, +Key, ?Value, -NewTree): scheitert, wenn Key vorkommt
rb_insert_new(Tree, Key, Val, NewTree) :-
    '$rb_insert_new'(Tree, Key, Val, NewTree).

%% rb_delete(+Tree, +Key, -NewTree)
rb_delete(Tree, Key, NewTree) :-
    '$rb_delete'(Tree, Key, _, NewTree).

%% rb_delete(+Tree, +Key, -Val, -NewTree)
rb_delete(Tree, Key, Val, NewTree) :-
    '$rb_delete'(Tree, Key, Val, NewTree).

%% rb_visit(+Tree, -Pairs): alle Paare K-V, aufsteigend
rb_visit(Tree, Pairs) :-
    '$rb_visit'(Tree, Pairs).

%% rb_visit_range(+Tree, +Min, +Max, -Pairs): Paare mit Min =< K =< Max
rb_visit_range(Tree, Min, Max, Pairs) :-
    '$rb_visit_range'(Tree, Min, Max, Pairs).

%% rb_keys(+Tree, -Keys)
rb_keys(Tree, Keys) :-
    '$rb_keys'(Tree, Keys).

%% rb_map(+Tree, :G): call(G, V) für jeden Wert (Reihenfolge wie SWI)
rb_map(Tree, Goal) :-
    '$rb_values_pre'(Tree, Vs),
    rb_map_(Vs, Goal).

rb_map_([], _).
rb_map_([V|Vs], Goal) :-
    call(Goal, V),
    rb_map_(Vs, Goal).

%% rb_map(+Tree, :G, -NewTree): jeder Wert V durch NV mit call(G, V, NV)
rb_map(Tree, Goal, NewTree) :-
    '$rb_values_pre'(Tree, Vs),
    rb_map_(Vs, Goal, NVs),
    '$rb_set_values'(Tree, pre, NVs, NewTree).

rb_map_([], _, []).
rb_map_([V|Vs], Goal, [NV|NVs]) :-
    call(Goal, V, NV),
    rb_map_(Vs, Goal, NVs).

%% rb_partial_map(+Tree, +Keys, :G, -NewTree): G auf die Werte der
%  (aufsteigend sortierten) Keys; scheitert G, bleibt der Wert. Wie SWI
%  scheitert es, wenn nicht alle Keys vorkommen.
rb_partial_map(Tree, Keys, Goal, NewTree) :-
    '$rb_visit'(Tree, Pairs),
    rb_partial_map_(Pairs, Keys, Goal, NVs),
    '$rb_set_values'(Tree, in, NVs, NewTree).

rb_partial_map_([], [], _, []).
rb_partial_map_([_-V|Ps], [], _, [V|Vs]) :-
    rb_values_(Ps, Vs).
rb_partial_map_([K-V|Ps], [K1|Ks], Goal, [NV|NVs]) :-
    (   K == K1
    ->  (   call(Goal, V, NV0) -> NV = NV0 ; NV = V ),
        rb_partial_map_(Ps, Ks, Goal, NVs)
    ;   NV = V,
        rb_partial_map_(Ps, [K1|Ks], Goal, NVs)
    ).

rb_values_([], []).
rb_values_([_-V|Ps], [V|Vs]) :-
    rb_values_(Ps, Vs).

%% rb_fold(:G, +Tree, +S0, -S): call(G, K-V, S0, S1) über alle Paare, aufsteigend
rb_fold(Goal, Tree, S0, S) :-
    '$rb_visit'(Tree, Pairs),
    rb_fold_(Pairs, Goal, S0, S).

rb_fold_([], _, S, S).
rb_fold_([P|Ps], Goal, S0, S) :-
    call(Goal, P, S0, S1),
    rb_fold_(Ps, Goal, S1, S).

%% rb_clone(+Tree, -NewTree, -Pairs): gleiche Schlüssel, frische Werte;
%  Pairs = die Paare K-NeuerWert
rb_clone(Tree, NewTree, Pairs) :-
    '$rb_clone'(Tree, NewTree, Pairs).

%% rb_min(+Tree, -Key, -Value), rb_max(+Tree, -Key, -Value)
rb_min(Tree, Key, Val) :-
    '$rb_min'(Tree, Key, Val).
rb_max(Tree, Key, Val) :-
    '$rb_max'(Tree, Key, Val).

%% rb_del_min(+Tree, -Key, -Val, -NewTree), rb_del_max(+Tree, -Key, -Val, -NewTree)
rb_del_min(Tree, Key, Val, NewTree) :-
    '$rb_del_min'(Tree, Key, Val, NewTree).
rb_del_max(Tree, Key, Val, NewTree) :-
    '$rb_del_max'(Tree, Key, Val, NewTree).

%% rb_next(+Tree, +Key, -Next, -Value): nächster Schlüssel (Key muss vorkommen)
rb_next(Tree, Key, Next, Val) :-
    '$rb_next'(Tree, Key, Next, Val).

%% rb_previous(+Tree, +Key, -Previous, -Value)
rb_previous(Tree, Key, Prev, Val) :-
    '$rb_previous'(Tree, Key, Prev, Val).

%% list_to_rbtree(+Pairs, -Tree): Paare K-V in beliebiger Reihenfolge
list_to_rbtree(List, Tree) :-
    '$rb_from_list'(List, true, Tree).

%% ord_list_to_rbtree(+Pairs, -Tree): Paare nach Schlüssel aufsteigend
ord_list_to_rbtree(List, Tree) :-
    '$rb_from_list'(List, false, Tree).

%% is_rbtree(@Term): Term ist ein gültiger Rot-Schwarz-Baum
is_rbtree(T) :-
    nonvar(T),
    '$rb_is_rbtree'(T).

%% rb_size(+Tree, -Size)
rb_size(Tree, Size) :-
    '$rb_size'(Tree, Size).

%% rb_in(?Key, ?Value, +Tree): alle Paare, aufsteigend
rb_in(Key, Val, Tree) :-
    '$rb_in'(Key, Val, Tree).
