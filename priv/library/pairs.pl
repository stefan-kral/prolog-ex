/* Aus Scryer Prolog (Lizenz: priv/library/SCRYER-LICENSE), für PrologEx
   um transpose_pairs/2 aus SWI-Prolog ergänzt (damit wie SWIs
   library(pairs)).
*/

/** Reasoning about pairs.

    Pairs are Prolog terms with principal functor `(-)/2`. A pair
    often has the form `Key-Value`. The predicates of this library
    relate pairs to keys and values.
*/

:- module(pairs, [pairs_keys_values/3,
		  pairs_keys/2,
		  pairs_values/2,
		  group_pairs_by_key/2,
		  transpose_pairs/2,
		  map_list_to_pairs/3]).


:- meta_predicate(map_list_to_pairs(2, ?, ?)).

%% pairs_keys_values(?Pairs, ?Keys, ?Values)
%
%  The first argument is a list of Pairs, the second the corresponding
%  Keys, and the third argument the corresponding values.

pairs_keys_values([], [], []).
pairs_keys_values([A-B|ABs], [A|As], [B|Bs]) :-
        pairs_keys_values(ABs, As, Bs).

%% pairs_keys(?Pairs, ?Keys)
%
%  Same as `pairs_keys_values(Pairs, Keys, _)`.

pairs_keys(Ps, Ks) :- pairs_keys_values(Ps, Ks, _).

%% pairs_values(?Pairs, ?Values)
%
%  Same as `pairs_keys_values(Pairs, _, Values)`.

pairs_values(Ps, Vs) :- pairs_keys_values(Ps, _, Vs).

%% map_list_to_pairs(:Pred, +List, -Keyed)
%
%  Keyed is a list of K-E pairs, one for each element E of List, where
%  call(Pred, E, K) holds. Useful to sort by a computed key:
%  `map_list_to_pairs(length, Lists, Ps), keysort(Ps, Sorted)`.

map_list_to_pairs(Pred, Ls, Ps) :-
        map_list_to_pairs2(Ls, Pred, Ps).

map_list_to_pairs2([], _, []).
map_list_to_pairs2([H|T0], Pred, [K-H|T]) :-
        call(Pred, H, K),
        map_list_to_pairs2(T0, Pred, T).


%% group_pairs_by_key(+Pairs, -Joined)
%
%  Groups adjacent pairs with identical (==) keys: [a-1,a-2,b-3] gives
%  [a-[1,2],b-[3]]. Pairs is usually keysorted, so that each key
%  appears once in Joined.

group_pairs_by_key([], []).
group_pairs_by_key([K-V|KVs0], [K-[V|Vs]|KVs]) :-
        same_key(K, KVs0, Vs, KVs1),
        group_pairs_by_key(KVs1, KVs).

same_key(K0, [K1-V|KVs0], [V|Vs], KVs) :-
        K0 == K1, !,
        same_key(K0, KVs0, Vs, KVs).
same_key(_, KVs, [], KVs).

%% transpose_pairs(+Pairs, -Transposed)
%
%  Swaps each Key-Value to Value-Key and keysorts the result on the new
%  key (as in SWI-Prolog).

transpose_pairs(Pairs, Transposed) :-
        flip_pairs_(Pairs, Flipped),
        keysort(Flipped, Transposed).

flip_pairs_([], []).
flip_pairs_([K-V|KVs], [V-K|VKs]) :-
        flip_pairs_(KVs, VKs).
