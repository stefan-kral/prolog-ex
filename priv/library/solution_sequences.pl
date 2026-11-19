/* library(solution_sequences) wie SWI: Lösungen eines Ziels begrenzen,
   überspringen, ohne Duplikate oder sortiert.

     limit(+N, :G)      höchstens die ersten N Lösungen (N = inf: alle)
     offset(+N, :G)     ohne die ersten N Lösungen
     distinct(:G)       jede Lösung (als Variante von G) nur einmal
     distinct(?W, :G)   jede Variante von W nur einmal
     order_by(+Spec, :G) alle Lösungen, sortiert nach Spec: Liste aus
                        asc(T) und desc(T) (stabil; wie SWI)

   limit/2 und offset/2 zählen mit call_nth/2 (library(iso_ext)); distinct merkt sich die
   Varianten in einer Tabelle, die nicht beim Backtracking zurückgeht und
   mit dem Ziel verschwindet (setup_call_cleanup/3).                    */

:- module(solution_sequences, [limit/2, offset/2, distinct/1, distinct/2,
                               order_by/2]).

:- use_module(library(iso_ext), [call_nth/2, setup_call_cleanup/3]).
:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(pairs)).

:- meta_predicate(limit(+, 0)).
:- meta_predicate(offset(+, 0)).
:- meta_predicate(distinct(0)).
:- meta_predicate(distinct(?, 0)).
:- meta_predicate(order_by(+, 0)).

limit(N, G) :-
    (   N == inf -> call(G)
    ;   N == infinite -> call(G)
    ;   must_be(integer, N),
        N > 0,
        call_nth(G, I),
        (   I =:= N -> ! ; true )
    ).

offset(N, G) :-
    must_be(integer, N),
    (   N > 0 -> call_nth(G, I), I > N
    ;   call(G)
    ).

distinct(G) :- distinct(G, G).

distinct(W, G) :-
    setup_call_cleanup('$distinct_new'(T),
                       ( call(G), '$distinct_add'(T, W) ),
                       '$distinct_free'(T)).

order_by(Spec, G) :-
    must_be(list, Spec),
    Spec \== [],
    order_keys_(Spec, Ks),
    term_variables(G, Vs),
    findall(Ks-Vs, G, Ps0),
    length(Spec, L),
    order_sort_(L, Spec, Ps0, Ps),
    member(Ks-Vs, Ps).

order_keys_([], []).
order_keys_([S|Ss], [K|Ks]) :-
    (   var(S) -> instantiation_error(S)
    ;   S = asc(K) -> true
    ;   S = desc(K) -> true
    ;   domain_error(order_specifier, S)
    ),
    order_keys_(Ss, Ks).

% von hinten nach vorn stabil sortieren: der erste Schlüssel entscheidet;
% absteigend und stabil: umgekehrt aufsteigend sortiert, wieder umgekehrt
order_sort_(0, _, Ps, Ps) :- !.
order_sort_(I, Spec, Ps0, Ps) :-
    nth1(I, Spec, S),
    functor(S, Dir, 1),
    map_list_to_pairs(order_key_(I), Ps0, KPs0),
    (   Dir == asc -> keysort(KPs0, KPs)
    ;   reverse(KPs0, RPs), keysort(RPs, KPs1), reverse(KPs1, KPs)
    ),
    pairs_values(KPs, Ps1),
    I1 is I - 1,
    order_sort_(I1, Spec, Ps1, Ps).

order_key_(I, Ks-_, K) :- nth1(I, Ks, K).
