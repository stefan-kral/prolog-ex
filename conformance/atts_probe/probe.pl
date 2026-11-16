% Sonden für verify_attributes/3 (SICStus-Stil) und das Zusammenspiel
% mit freeze/dif/when, clpz und Builtins, die Variablen binden.
% Ausgabe: je Fall die Protokollzeilen der Hooks, "sol" je Lösung, am Ende
% "end" oder "ex(Ball)". Läuft in Scryer und PrologEx.
:- use_module(ma).
:- use_module(mb).
:- use_module(library(lists)).
:- use_module(library(iso_ext)).
:- use_module(library(dif)).
:- use_module(library(freeze)).
:- use_module(library(when)).
:- use_module(library(clpz)).

go :- forall(c(N, G), run(N, G)).

run(N, G) :-
    write('== '), write(N), nl,
    catch(( G, write(sol), nl, fail ; write(end), nl ),
          E, ( write(ex(E)), nl )).

% --- Grundlagen -----------------------------------------------------------
c(bind_const,      (a(X, t), X = 1)).
c(bind_struct,     (a(X, t), X = f(_))).
c(two_vars,        (a(X, x), a(Y, y), f(X, Y) = f(1, 2))).
c(two_vars_rev,    (a(X, x), a(Y, y), f(Y, X) = f(2, 1))).
c(three_vars,      (a(X, x), a(Y, y), a(Z, z), [X, Y, Z] = [1, 2, 3])).
c(two_mods,        (a(X, t), b(X, t), X = 1)).
c(two_mods_rev,    (b(X, t), a(X, t), X = 1)).
c(other_mod_only,  (b(X, t), X = 1)).
c(attv_attv,       (a(X, x), a(Y, y), X = Y)).
c(attv_attv_rev,   (a(X, x), a(Y, y), Y = X)).
c(attv_attv_mods,  (a(X, x), b(Y, y), X = Y)).
c(attv_plain,      (a(X, x), X = Y, log(after(Y)))).
c(plain_attv,      (a(X, x), Y = X, log(after), Y = 1)).
c(attv_self,       (a(X, x), X = X)).
c(hook_fails,      (a(X, fail), X = 1)).
c(hook_fails_2nd,  (a(X, x), a(Y, fail), f(X, Y) = f(1, 2))).
c(hook_throws,     (a(X, throw), X = 1)).
c(hook_nd,         (a(X, nd), X = 1)).
c(hook_nd_two,     (a(X, nd), a(Y, nd), f(X, Y) = f(1, 2))).
c(merge,           (a(X, merge), a(Y, y), X = Y, ( ga(Y, T) -> log(y_has(T)) ; log(y_none) ))).
c(merge_bind,      (a(X, merge), b(Y, y), X = Y, Y = 5)).
c(sees_other,      (a(X, x), a(Y, y), freeze(Y, log(fz_y)), f(X, Y) = f(1, 2))).
c(nested,          (a(X, x), a(Y, y), freeze(X, Y = 7), X = 1, log(y(Y)))).
c(backtrack_attr,  (a(X, x), ( X = 1 ; log(alt), X = 2 ))).
c(unify_wo_occurs, (a(X, x), unify_with_occurs_check(X, f(1)))).
c(eq_fail_early,   (a(X, x), f(X, a) = f(1, b))).
c(dif_attv,        (a(X, x), dif(X, 1), X = 2)).
c(dif_attv_fail,   (a(X, x), dif(X, 1), X = 1)).
c(freeze_order,    (freeze(X, log(fz1)), a(X, x), freeze(X, log(fz2)), b(X, y), X = 1)).
c(when_order,      (when(nonvar(X), log(wh)), a(X, x), X = 1)).
c(clpz_order,      (a(X, x), X in 1..3, X = 2, log(ok))).
c(clpz_first,      (X in 1..3, a(X, x), X = 2, log(ok))).
c(clpz_reject,     (a(X, x), X in 1..3, X = 5)).
c(clpz_vv,         (a(X, x), X in 1..3, Y in 2..5, X = Y, fd_dom(X, D), log(D))).
c(clpz_label,      (a(X, x), X in 1..2, label([X]))).
c(clpz_prop,       (a(X, x), a(Y, y), X #= Y + 1, Y = 3, log(X))).
c(copy_term3,      (a(X, x), b(X, y), copy_term(X, C, Gs), log(Gs), ( var(C) -> log(c_var) ; true ))).
c(frozen_atts,     (a(X, x), freeze(X, true), frozen(X, G), log(G))).
% --- Builtins, die binden --------------------------------------------------
c(b_is,            (a(X, x), X is 1 + 2)).
c(b_univ,          (a(X, x), X =.. [f, 1])).
c(b_univ_list,     (a(L, x), f(1) =.. L)).
c(b_functor,       (a(X, x), functor(X, f, 1))).
c(b_functor_name,  (a(N, x), functor(f(1), N, _))).
c(b_arg,           (a(X, x), arg(1, f(7), X))).
c(b_atom_codes,    (a(X, x), atom_codes(X, "ab"))).
c(b_atom_length,   (a(X, x), atom_length(abc, X))).
c(b_length_n,      (a(N, x), length([a, b], N))).
c(b_length_l,      (a(L, x), length(L, 2))).
c(b_length_open,   once((a(N, x), length(L, N), N >= 1, log(L)))).
c(b_between,       (a(X, x), between(1, 2, X))).
c(b_nth0,          (a(X, x), nth0(1, [a, b, c], X))).
c(b_nth1_idx,      (a(I, x), nth1(I, [a, b], b))).
c(b_member,        (a(X, x), member(X, [p, q]))).
c(b_append,        (a(X, x), append([1], [2], X))).
c(b_append_split,  (a(X, x), append(X, [c], [a, b, c]))).
c(b_msort,         (a(X, x), msort([b, a], X))).
c(b_sort4,         (a(X, x), sort(0, @>=, [1, 2], X))).
c(b_keysort,       (a(X, x), keysort([b-1, a-2], X))).
c(b_findall,       (a(X, x), findall(Y, member(Y, [1, 2]), X))).
c(b_copy_term,     (a(X, x), copy_term(f(_), X))).
c(b_number_codes,  (a(X, x), number_codes(X, "42"))).
c(b_atom_concat,   (a(X, x), atom_concat(X, b, ab))).
c(b_sub_atom,      (a(X, x), sub_atom(abc, 1, 1, _, X))).
c(b_succ,          (a(X, x), succ(X, 3))).
c(b_char_code,     (a(X, x), char_code(X, 0'a))).
c(b_read_term,     (a(X, x), read_term_from_atom('f(Y)', X, []))).
c(b_term_variables,(a(X, x), term_variables(f(_, _), X))).
c(b_reverse,       (a(X, x), reverse([1, 2], X))).
c(b_last,          (a(X, x), last([1, 2], X))).
c(b_sum_list,      (a(X, x), sum_list([1, 2], X))).
c(b_max_list,      (a(X, x), max_list([1, 3, 2], X))).
c(b_maplist,       (a(X, x), maplist(=(1), [X]))).
c(b_select,        (a(X, x), select(X, [p, q], _))).
c(b_list_attv,     (a(X, x), a(Y, y), msort([2, 1], [X, Y]))).
c(b_struct_two,    (a(X, x), a(Y, y), arg(1, f(g(1, 2)), g(X, Y)))).
c(b_setof,         (a(X, x), setof(Y, member(Y, [b, a]), X))).
c(b_catch_bind,    (a(X, x), catch(X = 1, _, true))).
c(b_not_unify,     (a(X, x), \+ X = 1, log(unbound_after_naf))).
c(b_not_unify2,    (a(X, fail), \+ X = 1, log(naf_ok))).
c(b_dif_unify,     (a(X, x), X \= 1)).
c(b_compare_eq,    (a(X, x), a(Y, y), X == Y)).
c(b_subsumes,      (a(X, x), subsumes_term(X, 1), log(no_binding))).
