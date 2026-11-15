% Kopf der Fälle für SWI-Prolog (library(clpfd)): wie head.pl, aber nach
% dem Aufstellen nur die Domänen (SWI schreibt die Restziele anders),
% als " DOMS " wie in head.pl
:- encoding(utf8).
:- use_module(library(clpfd), except([chain/2])).

% clpz: chain(Relation, Zs), SWI: chain(Zs, Relation)
chain(R, Zs) :- clpfd:chain(Zs, R).
:- use_module(library(lists)).
:- style_check(-singleton).

go :- forall(o(Id, _, _), (catch(run(Id), E, (write(Id), write(' crash '), pp(E), nl)))).

run(Id) :-
    o(Id, OVs, Opts0),
    Opts = OVs^Opts0,
    run(Id, Opts, post, lab, state, =, Vs^p(Id, Vs)),
    run(Id, Opts, postc, labc, doms, msort_, Vs^(g(Id, Vs, G), call(G))).

run(Id, Opts, TP, TL, Show, Sort, Post) :-
    write(Id), write(' '), write(TP), write(' '),
    (   catch((post(Post, Vs) -> R = ok(Vs) ; R = fail), error(E, C), err(E, C, R)) ->
        true
    ;   R = fail
    ),
    (   R = ok(Vs1) -> call(Show, Vs1)
    ;   pp(R)
    ),
    nl,
    write(Id), write(' '), write(TL), write(' '),
    catch(( findall(Vs2, (post(Post, Vs2), copy_term(Opts, Vs2^Opts2), labeling(Opts2, Vs2)), L0),
            call(Sort, L0, L), length(L, N),
            first(L, 40, F), pp(N-F) ),
          error(E2, C2), (err(E2, C2, R2), pp(R2))),
    nl.

post(Vs0^G0, Vs) :- copy_term(Vs0^G0, Vs^G), call(G).

err(E, C, R) :-
    (   nonvar(C), C = context(P, _), nonvar(P), ( P = (is)/2 ; P = _:(is)/2 ) -> R = err(E, is)
    ;   R = err(E)
    ).

state(Vs) :-
    maplist(dom, Vs, Ds),
    copy_term(Vs-Ds, T, _), numbervars(T, 0, _),
    write(' DOMS '), pp(T).

doms(Vs) :- maplist(dom, Vs, Ds), copy_term(Ds, T, _), numbervars(T, 0, _), pp(T).

dom(V, D) :- ( var(V) -> fd_dom(V, D) ; D = V ).

first(L, N, F) :- ( length(F, N), append(F, _, L) -> true ; F = L ).

pp(T) :- var(T), !, write('_').
pp('$VAR'(N)) :- integer(N), !, write('_V'), write(N).
pp([]) :- !, write('[]').
pp([H|T]) :- !, write('['), pp(H), pp_tail(T), write(']').
pp(T) :- compound(T), !, T =.. [F|As], pp(F), write('('), pp_args(As), write(')').
pp(T) :- atom(T), !, write(''''), write(T), write('''').
pp(T) :- write(T).
pp_tail([]) :- !.
pp_tail([H|T]) :- !, write(','), pp(H), pp_tail(T).
pp_tail(T) :- write('|'), pp(T).
pp_args([A]) :- !, pp(A).
pp_args([A|As]) :- pp(A), write(','), pp_args(As).

msort_(L, S) :- maplist(pk, L, Ps), keysort(Ps, Ss), maplist(pk, S, Ss).
pk(G, G-x).
