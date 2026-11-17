% DCG-Uebersetzung: die Faelle aus Logtalk, tests/logtalk/dcgs/tests.lgt
% (Paulo Moura, SPDX-License-Identifier: Apache-2.0), hier gegen das
% eingebaute expand_term/2 statt gegen den Uebersetzer von Logtalk.
% case(Name, Regel, Erwartung): true (uebersetzt) oder error.
% (\+)//1 und (->)//2 ohne Else sind im Entwurf fuer DCGs
% implementierungsabhaengig; Scryer lehnt sie ab.

case(dcgs_terminal_list_01, ((p --> [])), true).
case(dcgs_terminal_list_02, ((p --> [b])), true).
case(dcgs_terminal_list_03, ((p --> [abc, xyz])), true).
case(dcgs_terminal_list_04, ((p --> [abc | xyz])), error).
case(dcgs_terminal_list_05, ((p --> [[], {}, 3, 3.2, a(b)])), true).
case(dcgs_terminal_list_06, ((p --> [_])), true).
case(dcgs_terminal_string_01, ((p --> "b")), true).
case(dcgs_terminal_string_02, ((p --> "abc", "q")), true).
case(dcgs_terminal_string_03, ((p --> "abc" ; "q")), true).
case(dcgs_non_terminal_01, ((p --> b)), true).
case(dcgs_non_terminal_02, ((p --> 3)), error).
case(dcgs_non_terminal_03, ((p(X) --> b(X))), true).
case(dcgs_conjunction_01, ((p --> b, c)), true).
case(dcgs_conjunction_02, ((p --> true, c)), true).
case(dcgs_conjunction_03, ((p --> fail, c)), true).
case(dcgs_conjunction_04, ((p(X) --> call(X), c)), true).
case(dcgs_disjunction_01, ((p --> b ; c)), true).
case(dcgs_disjunction_02, ((p --> q ; [])), true).
case(dcgs_disjunction_03, ((p --> [a] ; [b])), true).
case(dcgs_if_the_else_01, ((p --> b -> c)), true).
case(dcgs_if_the_else_02, ((p --> b -> c; d)), true).
case(dcgs_if_the_else_03, ((p --> b -> c1, c2 ; d)), true).
case(dcgs_if_the_else_04, ((p --> b -> c ; d1, d2)), true).
case(dcgs_if_the_else_05, ((p --> b1, b2 -> c ; d)), true).
case(dcgs_if_the_else_06, ((p --> [x] -> [] ; q)), true).
case(dcgs_negation_01, ((p --> \+ b, c)), true).
case(dcgs_negation_02, ((p --> b, \+ c, d)), true).
case(dcgs_cut_01, ((p --> !, [a])), true).
case(dcgs_cut_02, ((p --> b, !, c, d)), true).
case(dcgs_cut_03, ((p --> b, !, c ; d)), true).
case(dcgs_cut_04, ((p --> [a], !, {fail})), true).
case(dcgs_cut_05, ((p(a), [X] --> !, [X, a], q)), true).
case(dcgs_cut_06, ((p --> a, ! ; b)), true).
case(dcgs_bypass_01, ((p --> {b})), true).
% Logtalk: error. SWI, Scryer und PrologEx uebersetzen (expand_term/2
% prueft den Rumpf nicht); beim Laden lehnen alle drei die Klausel ab
% (type_error(callable, (3, S0 = S))).
case(dcgs_bypass_02, ((p --> {3})), true).
case(dcgs_bypass_03, ((p --> {c,d})), true).
case(dcgs_bypass_04, ((p --> '{}'((c,d)))), true).
case(dcgs_bypass_05, ((p --> {a}, {b}, {c})), true).
case(dcgs_bypass_06, ((p --> {q} -> [a] ; [b])), true).
case(dcgs_bypass_07, ((p --> {q} -> [] ; b)), true).
case(dcgs_bypass_08, ((p --> [foo], {write(x)}, [bar])), true).
case(dcgs_bypass_09, ((p --> [foo], {write(hello)},{nl})), true).
case(dcgs_bypass_10, ((p --> [foo], {write(hello), nl})), true).
case(dcgs_metacall_01, ((p --> _)), true).
case(dcgs_metacall_02, ((p(X) --> X)), true).
case(dcgs_graphic_01, (('[' --> b, c)), true).
case(dcgs_graphic_02, (((=) --> b, c)), true).
case(dcgs_push_back_list_01, ((p, [t] --> b, c)), true).
case(dcgs_push_back_list_002, ((p, [t] --> b, [t])), true).
case(dcgs_push_back_list_003, ((p, [t] --> b, [s, t])), true).
case(dcgs_push_back_list_004, ((p, [t] --> b, [s], [t])), true).
case(dcgs_push_back_list_005, ((p(X), [X] --> [X])), true).
case(dcgs_push_back_list_006, ((p(X, Y), [X, Y] --> [X, Y])), true).
case(dcgs_push_back_list_007, ((p(a), [X] --> !, [X, a], q)), true).
case(dcgs_push_back_list_008, ((p, [a,b] --> [foo], {write(hello), nl})), true).
case(dcgs_push_back_list_09, ((p, [t1], [t2] --> b, c)), error).
case(dcgs_push_back_list_10, ((p, b --> b)), error).
case(dcgs_push_back_list_11, (([t], p --> b)), error).
case(dcgs_push_back_list_12, (([t1], p, [t2] --> b)), error).

outcome(Rule, R) :-
    catch(( expand_term(Rule, _) -> R = true ; R = fail ), error(_, _), R = error).

% die Faelle, deren Ausgang nicht stimmt
wrong(Bad) :- findall(N-R, (case(N, Rule, E), outcome(Rule, R), R \== E), Bad).

% Logtalk examples/dcgs/tests.lgt, dcgs_28/29: ein Cut im ersten Argument
% von phrase/2,3 bleibt dort
cut_local2(Xs) :- findall(X, (in(X, [1, 2, 3]), phrase(!, _)), Xs).
cut_local3(Xs) :- findall(X, (in(X, [1, 2, 3]), phrase(!, _, _)), Xs).

in(X, [X|_]).
in(X, [_|Xs]) :- in(X, Xs).
