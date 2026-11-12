/* library(types) wie in SICStus Prolog 4: Typprüfungen mit Fehlern im
   SICStus-Format.

   Fehler sind error(ISO, SICStus): der ISO-Teil wie üblich, der zweite mit
   Ziel und Argumentnummer (ArgNo 0: kein bestimmtes Argument), z. B.

     error(type_error(integer, a), type_error(foo(a), 1, integer, a))

   Typen (must_be/4): atom, atomic, boolean (true/false), callable,
   character (Atom der Länge 1), character_code, compound, db_reference
   (gibt es hier nicht), float, float(Bereich), ground, integer,
   integer(Bereich), list, list(Typ), mutable, nonvar, number,
   number(Bereich), oneof(L), order (<, =, >), pair (K-V), pred_spec
   (Name/Stelligkeit, auch M:Spec), pred_spec_tree (pred_spec, (A,B),
   Listen, M:Baum), proper_list, proper_list(Typ), simple (atomar oder
   Variable), term, var, var_or(Typ). Bereiche: between(L,U), >=(L),
   >(L), <(L), =<(L), =:=(L), =\=(L) – arithmetisch verglichen; außerhalb
   ein domain_error mit dem Bereich als Domäne.

   Reihenfolge der Prüfung: nicht genug gebunden – instantiation_error
   (var: gebunden – uninstantiation_error); falscher Typ – type_error;
   richtiger Typ, falscher Bereich – domain_error; character_code
   außerhalb der Zeichen – representation_error(character_code). In
   list(Typ) ist der Schuldige das Element. Ein unbekannter Typ:
   domain_error(typeterm, Typ) für must_be/4 selbst.                     */

:- module(types, [must_be/4,
                  illarg/3,
                  illarg/4]).

:- use_module(library(lists)).
:- use_module(library(mutables)).

%% must_be(+Term, +Type, +Goal, +ArgNo)
%
%  Term ist vom Typ Type; sonst ein Fehler mit Goal und ArgNo.

must_be(X, Type, Goal, ArgNo) :-
        (   var(Type) ->
            ill_inst(must_be(X, Type, Goal, ArgNo), 2)
        ;   check(Type, X, Goal, ArgNo) ->
            true
        ;   throw(error(domain_error(typeterm, Type),
                        domain_error(must_be(X, Type, Goal, ArgNo), 2, typeterm, Type)))
        ).

% check(+Type, ?X, +Goal, +ArgNo): scheitert nur bei unbekanntem Typ
check(term, _, _, _).
check(var, X, G, A) :-
        (   var(X) -> true
        ;   throw(error(uninstantiation_error(X), uninstantiation_error(G, A, X)))
        ).
check(nonvar, X, G, A) :- bound(X, G, A).
check(ground, X, G, A) :- ( ground(X) -> true ; ill_inst(G, A) ).
check(var_or(T), X, G, A) :- known(T), ( var(X) -> true ; check(T, X, G, A) ).
check(simple, X, G, A) :- ( compound(X) -> ill_type(simple, X, G, A) ; true ).
check(atom, X, G, A) :- test(atom, X, G, A).
check(atomic, X, G, A) :- test(atomic, X, G, A).
check(callable, X, G, A) :- test(callable, X, G, A).
check(compound, X, G, A) :- test(compound, X, G, A).
check(float, X, G, A) :- test(float, X, G, A).
check(integer, X, G, A) :- test(integer, X, G, A).
check(number, X, G, A) :- test(number, X, G, A).
check(db_reference, X, G, A) :- bound(X, G, A), ill_type(db_reference, X, G, A).
check(mutable, X, G, A) :- ( var(X) -> ill_inst(G, A) ; mutable(X) -> true ; ill_type(mutable, X, G, A) ).
check(boolean, X, G, A) :-
        bound(X, G, A),
        (   ( X == true ; X == false ) -> true
        ;   ill_type(boolean, X, G, A)
        ).
check(character, X, G, A) :-
        bound(X, G, A),
        (   atom(X), atom_length(X, 1) -> true
        ;   ill_type(character, X, G, A)
        ).
check(character_code, X, G, A) :-
        test(integer, X, G, A),
        (   catch(char_code(_, X), error(representation_error(_), _), fail) -> true
        ;   throw(error(representation_error(character_code),
                        representation_error(G, A, character_code)))
        ).
check(order, X, G, A) :-
        bound(X, G, A),
        (   ( X == (<) ; X == (=) ; X == (>) ) -> true
        ;   atom(X) -> ill_domain(order, X, G, A)
        ;   ill_type(atom, X, G, A)
        ).
check(oneof(L), X, G, A) :-
        is_list(L),
        bound(X, G, A),
        (   \+ \+ ( member(Y, L), Y == X ) -> true
        ;   ill_domain(oneof(L), X, G, A)
        ).
check(pair, X, G, A) :-
        bound(X, G, A),
        (   X = _-_ -> true
        ;   ill_type(pair, X, G, A)
        ).
check(integer(R), X, G, A) :- range(R), test(integer, X, G, A), in_range(R, X, G, A).
check(float(R), X, G, A) :- range(R), test(float, X, G, A), in_range(R, X, G, A).
check(number(R), X, G, A) :- range(R), test(number, X, G, A), in_range(R, X, G, A).
check(list, X, G, A) :- proper(X, G, A).
check(proper_list, X, G, A) :- proper(X, G, A).
check(list(T), X, G, A) :- known(T), proper(X, G, A), elements(X, T, G, A).
check(proper_list(T), X, G, A) :- known(T), proper(X, G, A), elements(X, T, G, A).
check(pred_spec, X, G, A) :-
        spec_status(X, S),
        status(S, pred_spec, X, G, A).
check(pred_spec_tree, X, G, A) :-
        tree_status(X, S),
        status(S, pred_spec_tree, X, G, A).

% bekannter Typ (für die Elemente von list(T), var_or(T)): die Prüfung
% auf einen Unbekannten scheitert sonst erst beim ersten Element
known(T) :-
        nonvar(T),
        (   simple_type(T) -> true
        ;   T = list(U) -> known(U)
        ;   T = proper_list(U) -> known(U)
        ;   T = var_or(U) -> known(U)
        ;   T = oneof(L) -> is_list(L)
        ;   ( T = integer(R) ; T = float(R) ; T = number(R) ) -> range(R)
        ).

simple_type(T) :-
        memberchk(T, [term, var, nonvar, ground, simple, atom, atomic, callable,
                      compound, float, integer, number, db_reference, mutable,
                      boolean, character, character_code, order, pair, list,
                      proper_list, pred_spec, pred_spec_tree]).

range(R) :-
        nonvar(R),
        (   R = between(L, U) -> number(L), number(U)
        ;   R =.. [Op, L], memberchk(Op, [>=, >, <, =<, =:=, =\=]), number(L)
        ).

test(Test, X, G, A) :-
        bound(X, G, A),
        (   call(Test, X) -> true
        ;   ill_type(Test, X, G, A)
        ).

bound(X, G, A) :- ( var(X) -> ill_inst(G, A) ; true ).

in_range(R, X, G, A) :-
        (   in_range(R, X) -> true
        ;   ill_domain(R, X, G, A)
        ).

in_range(between(L, U), X) :- X >= L, X =< U.
in_range(>=(L), X) :- X >= L.
in_range(>(L), X) :- X > L.
in_range(<(L), X) :- X < L.
in_range(=<(L), X) :- X =< L.
in_range(=:=(L), X) :- X =:= L.
in_range(=\=(L), X) :- X =\= L.

% Liste: offener Rest – instantiation_error, sonst keine Liste – type_error
proper(X, G, A) :-
        '$skip_list'(_, X, Rest),
        (   Rest == [] -> true
        ;   var(Rest) -> ill_inst(G, A)
        ;   ill_type(list, X, G, A)
        ).

elements([], _, _, _).
elements([E|Es], T, G, A) :-
        check(T, E, G, A),
        elements(Es, T, G, A).

% pred_spec: ok, inst (zu wenig gebunden) oder bad
spec_status(X, S) :-
        (   var(X) -> S = inst
        ;   X = M:P ->
            (   var(M) -> S = inst
            ;   atom(M) -> spec_status(P, S)
            ;   S = bad
            )
        ;   X = N/Ar ->
            (   ( var(N) ; var(Ar) ) -> S = inst
            ;   atom(N), integer(Ar), Ar >= 0 -> S = ok
            ;   S = bad
            )
        ;   S = bad
        ).

tree_status(X, S) :-
        (   var(X) -> S = inst
        ;   X = M:T, atom(M) -> tree_status(T, S)
        ;   X = (T1, T2) -> tree_status(T1, S1), tree_status(T2, S2), worst(S1, S2, S)
        ;   X == [] -> S = ok
        ;   X = [_|_] -> list_status(X, S)
        ;   spec_status(X, S)
        ).

list_status(L, S) :-
        (   var(L) -> S = inst
        ;   L == [] -> S = ok
        ;   L = [T|Ts] -> tree_status(T, S1), list_status(Ts, S2), worst(S1, S2, S)
        ;   S = bad
        ).

% der schlimmere: bad vor inst vor ok (ein Fehler, der sicher ist, zuerst)
worst(S1, S2, S) :-
        (   ( S1 == bad ; S2 == bad ) -> S = bad
        ;   ( S1 == inst ; S2 == inst ) -> S = inst
        ;   S = ok
        ).

status(ok, _, _, _, _).
status(inst, _, _, G, A) :- ill_inst(G, A).
status(bad, T, X, G, A) :- ill_type(T, X, G, A).

ill_inst(G, A) :- throw(error(instantiation_error, instantiation_error(G, A))).
ill_type(T, X, G, A) :- throw(error(type_error(T, X), type_error(G, A, T, X))).
ill_domain(D, X, G, A) :- throw(error(domain_error(D, X), domain_error(G, A, D, X))).

%% illarg(+ErrorTerm, +Goal, +ArgNo)
%
%  Wie illarg/4, der Schuldige ist das Argument ArgNo von Goal (ArgNo 0:
%  keiner).

illarg(E, Goal, ArgNo) :-
        (   integer(ArgNo), ArgNo > 0, compound(Goal), functor(Goal, _, N), ArgNo =< N ->
            arg(ArgNo, Goal, Culprit)
        ;   true
        ),
        illarg(E, Goal, ArgNo, Culprit).

%% illarg(+ErrorTerm, +Goal, +ArgNo, +Culprit)
%
%  Wirft den Fehler, den ErrorTerm beschreibt (type/1 und domain/2 prüfen
%  erst den Typ wie must_be/4 – passt er bei type/1, kein Fehler).

illarg(E, G, A, C) :-
        (   var(E) ->
            ill_inst(illarg(E, G, A, C), 1)
        ;   illarg_(E, G, A, C) ->
            true
        ;   throw(error(domain_error(illarg_error, E),
                        domain_error(illarg(E, G, A, C), 1, illarg_error, E)))
        ).

illarg_(var, G, A, _) :- ill_inst(G, A).
illarg_(type(T), G, A, C) :- must_be(C, T, G, A).
illarg_(domain(T, D), G, A, C) :- must_be(C, T, G, A), ill_domain(D, C, G, A).
illarg_(force_type(T), G, A, C) :- ill_type(T, C, G, A).
illarg_(context(CT, CmdT), G, _, _) :-
        throw(error(context_error(CT, CmdT), context_error(G, CT, CmdT))).
illarg_(existence(OT, C, Msg), G, A, _) :-
        throw(error(existence_error(OT, C), existence_error(G, A, OT, C, Msg))).
illarg_(permission(Op, OT, Msg), G, _, C) :-
        throw(error(permission_error(Op, OT, C), permission_error(G, Op, OT, C, Msg))).
illarg_(representation(R), G, A, _) :-
        throw(error(representation_error(R), representation_error(G, A, R))).
illarg_(evaluation(Ev), G, A, C) :-
        throw(error(evaluation_error(Ev), evaluation_error(G, A, Ev, C))).
illarg_(consistency(C1, C2, Msg), G, _, _) :-
        throw(error(consistency_error(C1, C2, Msg), consistency_error(G, C1, C2, Msg))).
illarg_(syntax(Pos, Msg, Tokens, After), G, _, _) :-
        throw(error(syntax_error(Msg), syntax_error(G, Pos, Msg, Tokens, After))).
illarg_(resource(R), G, _, _) :-
        throw(error(resource_error(R), resource_error(G, R))).
illarg_(system(Msg), _, _, _) :-
        throw(error(system_error, system_error(Msg))).
