% Skalierung: wächst eine Operation mit der Datengröße so, wie sie soll?
%
% case(Name, N, Daten) baut die Daten für Größe N (ungemessen), go(Name,
% Daten) ist die gemessene Operation. measure(Name, N): beste von 3, ms
% CPU, Ausgabe "Name N ms". run.sh misst jeden Fall bei N, 2N, 4N, ...;
% report.py schätzt daraus den Exponenten k (Zeit ~ N^k): 1 linear,
% etwas über 1 N log N, 2 quadratisch.
%
% Portabel (PrologEx, SWI): nur ISO und verbreitete Bibliotheken (keine
% SWI-Strings, kein setarg/3: PrologEx hat beides nicht).

:- dynamic(fact/2).
:- discontiguous(case/3).
:- discontiguous(go/2).

measure(Name, N) :- measure(Name, N, _).

measure(Name, N, T) :-
    case(Name, N, D),
    best(3, Name, D, 1.0e10, T),
    write(Name), write(' '), write(N), write(' '), write(T), nl.

% sweep(Name, N, K, Grenze): N, 2N, ... (K Größen), Schluss nach der
% ersten Messung über Grenze ms
sweep(_, _, 0, _) :- !.
sweep(Name, N, K, Limit) :-
    measure(Name, N, T),
    (   T > Limit -> true
    ;   N2 is 2 * N, K1 is K - 1, sweep(Name, N2, K1, Limit)
    ).

best(0, _, _, T, T) :- !.
best(K, Name, D, T0, T) :-
    garbage_collect,
    statistics(runtime, _),
    ( go(Name, D) -> true ; true ),
    statistics(runtime, [_, T1]),
    T2 is min(T0, T1),
    K1 is K - 1,
    best(K1, Name, D, T2, T).

% Daten
nums(N, L) :- numlist(1, N, L).
perm(N, L) :- findall(X, (between(1, N, I), X is (I * 7919) mod 1000003), L).
pairs(N, Ps) :- findall(K-I, (between(1, N, I), K is (I * 7919) mod 1000003), Ps).
atom_n(N, A) :- length(Cs, N), maplist(=(0'a), Cs), atom_codes(A, Cs).
csv_atom(N, A) :- nums(N, L), atomic_list_concat(L, ',', A).
digits_n(N, Cs) :- length(Cs, N), maplist(=(0'7), Cs).

% --- Listen
case(findall, N, N).
go(findall, N) :- findall(X, between(1, N, X), L), length(L, N).

case(numlist, N, N).
go(numlist, N) :- numlist(1, N, _).

case(length_gen, N, N).
go(length_gen, N) :- length(L, N), L = [_|_].

case(append, N, L-L) :- nums(N, L).
go(append, A-B) :- append(A, B, _).

case(reverse, N, L) :- nums(N, L).
go(reverse, L) :- reverse(L, _).

case(nth1_last, N, N-L) :- nums(N, L).
go(nth1_last, N-L) :- nth1(N, L, _).

case(msort, N, L) :- perm(N, L).
go(msort, L) :- msort(L, _).

case(sort_dedup, N, L) :- perm(N, L).
go(sort_dedup, L) :- sort(L, _).

case(keysort, N, Ps) :- pairs(N, Ps).
go(keysort, Ps) :- keysort(Ps, _).

case(ord_union, N, A-B) :- findall(X, (between(1, N, I), X is 2 * I), A), findall(X, (between(1, N, I), X is 2 * I + 1), B).
go(ord_union, A-B) :- ord_union(A, B, _).

case(maplist_succ, N, L) :- nums(N, L).
go(maplist_succ, L) :- maplist(succ, L, _).

case(foldl_plus, N, L) :- nums(N, L).
go(foldl_plus, L) :- foldl(plus, L, 0, _).

case(partition, N, L) :- nums(N, L).
go(partition, L) :- partition(odd, L, _, _).
odd(X) :- X mod 2 =:= 1.

case(len_body, N, L) :- nums(N, L).
go(len_body, L) :- len(L, _).
len([], 0).
len([_|T], N) :- len(T, M), N is M + 1.

case(sum_list, N, L) :- nums(N, L).
go(sum_list, L) :- sum_list(L, _).

% --- Terme
case(copy_ground, N, L) :- nums(N, L).
go(copy_ground, L) :- copy_term(L, _).

case(copy_vars, N, L) :- length(L, N).
go(copy_vars, L) :- copy_term(L, _).

case(univ, N, L) :- nums(N, L).
go(univ, L) :- T =.. [f|L], T =.. [_|_].

case(arg_scan, N, N-T) :- functor(T, f, N).
go(arg_scan, N-T) :- forall(between(1, N, I), arg(I, T, _)).

case(term_to_atom, N, L) :- nums(N, L).
go(term_to_atom, L) :- term_to_atom(L, A), term_to_atom(_, A).

case(format_atom, N, L) :- nums(N, L).
go(format_atom, L) :- format(atom(_), '~w', [L]).

case(with_output, N, N).
go(with_output, N) :- with_output_to(codes(_), forall(between(1, N, I), (write(I), nl))).

% --- Atome und Strings
case(atom_codes, N, A) :- atom_n(N, A).
go(atom_codes, A) :- atom_codes(A, Cs), atom_codes(_, Cs).

case(sub_atom_scan, N, N-A) :- atom_n(N, A).
go(sub_atom_scan, N-A) :- M is N - 1, forall(between(0, M, B), sub_atom(A, B, 1, _, _)).

case(sub_atom_enum, N, A) :- atom_n(N, A).
go(sub_atom_enum, A) :- forall(sub_atom(A, _, 1, _, _), true).



case(alc_join, N, L) :- nums(N, L).
go(alc_join, L) :- atomic_list_concat(L, ',', _).

case(alc_split, N, A) :- csv_atom(N, A).
go(alc_split, A) :- atomic_list_concat(_, ',', A).


case(dcg_digits, N, Cs) :- digits_n(N, Cs).
go(dcg_digits, Cs) :- phrase(digits(_), Cs).
digits([D|Ds]) --> [D], { code_type(D, digit(_)) }, !, digits(Ds).
digits([]) --> [].

% --- Datenbank, globale Variablen
case(assert_lookup, N, N).
go(assert_lookup, N) :-
    retractall(fact(_, _)),
    forall(between(1, N, I), assertz(fact(I, I))),
    forall(between(1, N, I), fact(I, _)),
    retractall(fact(_, _)).

case(retract_each, N, N).
go(retract_each, N) :-
    retractall(fact(_, _)),
    forall(between(1, N, I), assertz(fact(I, I))),
    forall(between(1, N, I), retract(fact(I, _))).

% retract im Wechsel mit Aufrufen (Graphensuche: retract(unbesucht(X)))
case(retract_call, N, N).
go(retract_call, N) :-
    retractall(fact(_, _)),
    forall(between(1, N, I), assertz(fact(I, I))),
    forall(between(1, N, I), (retract(fact(I, _)), J is N + 1 - I, ( fact(J, _) -> true ; true ))).

% Warteschlange aus Fakten (Breitensuche): vorn retract, hinten assertz,
% N Elemente lang, N Runden
case(retract_queue, N, N).
go(retract_queue, N) :-
    retractall(fact(_, _)),
    forall(between(1, N, I), assertz(fact(q, I))),
    forall(between(1, N, _), (retract(fact(q, X)), Y is X + N, assertz(fact(q, Y)))).

% ebenso, eigenes Prädikat, erstes Argument ungebunden: retract(q(X))
:- dynamic(qu/1).
case(retract_queue1, N, N).
go(retract_queue1, N) :-
    retractall(qu(_)),
    forall(between(1, N, I), assertz(qu(I))),
    forall(between(1, N, _), (retract(qu(X)), Y is X + N, assertz(qu(Y)))).

case(nb_counter, N, N).
go(nb_counter, N) :-
    nb_setval(scaling_c, 0),
    forall(between(1, N, _), (nb_getval(scaling_c, V), V1 is V + 1, nb_setval(scaling_c, V1))).

case(assoc_build, N, Ps) :- pairs(N, Ps).
go(assoc_build, Ps) :- list_to_assoc(Ps, A), forall(member(K-_, Ps), get_assoc(K, A, _)).

case(assoc_put, N, Ps) :- pairs(N, Ps).
go(assoc_put, Ps) :- empty_assoc(A0), foldl(put, Ps, A0, _).
put(K-V, A0, A) :- put_assoc(K, A0, V, A).

% --- Steuerung
case(between_fail, N, N).
go(between_fail, N) :- ( between(1, N, _), fail ; true ).

case(catch_throw, N, N).
go(catch_throw, N) :- forall(between(1, N, _), catch(throw(x), _, true)).

case(catch_nested, N, N).
go(catch_nested, N) :- cn(N).
cn(0) :- !.
cn(N) :- M is N - 1, catch(cn(M), _, true).

case(dif_many, N, N).
go(dif_many, N) :- length(L, N), maplist(dif(a), L), L = [b|_].

case(freeze_many, N, N).
go(freeze_many, N) :- length(L, N), maplist(fz, L), maplist(=(1), L).
fz(X) :- freeze(X, true).
