% gemeinsamer Teil der Köpfe (nach den Fällen angehängt)
go :- forall(case(Id), run(Id)).
% ab Fall K (nach einem Absturz neu gestartet)
go_from(K) :- forall((case(Id), Id >= K), run(Id)).

inputs([[], [a], [b], [a,a], [a,b], [b,a], [b,b], [a,a,a], [a,a,b], [a,b,a], [a,b,b],
        [b,a,a], [b,a,b], [b,b,a], [b,b,b]]).

run(Id) :-
    inputs(Is),
    write(Id), write(' '),
    parse_all(Id, Is, Rs),
    gen_all(Id, [0, 1, 2], Gs),
    pr(Rs-Gs), nl.

parse_all(_, [], []).
parse_all(Id, [I|Is], [R|Rs]) :-
    catch(( findall(A-Rest, c(Id, A, I, Rest), L), named(L, R) ), E, ex_name(E, R)),
    parse_all(Id, Is, Rs).

gen_all(_, [], []).
gen_all(Id, [N|Ns], [R|Rs]) :-
    catch(( length(I, N), findall(I-A, g(Id, A, I), L), named(L, R) ), E, ex_name(E, R)),
    gen_all(Id, Ns, Rs).

% Lösungen mit benannten Variablen; zyklische (ohne Occurs-Check
% entstanden) als cyclic – sie auszugeben endete nicht
named(L, L2) :- copy_term(L, L1), acyc(L1, L2), term_variables(L2, Vs), number_vars(Vs, 0).

acyc([], []).
acyc([X|Xs], [Y|Ys]) :- ( acyclic_term(X) -> Y = X ; Y = cyclic ), acyc(Xs, Ys).

number_vars([], _).
number_vars([v(N)|Vs], N) :- N1 is N + 1, number_vars(Vs, N1).

ex_name(error(F, _), ex(N/A)) :- !, functor(F, N, A).
ex_name(B, ex(N/A)) :- functor(B, N, A).

% Ausgabe wie writeq, aber Listen immer als [..] (writeq schreibt
% Zeichenlisten je nach System als "ab")
pr(T) :- var(T), !, write('_').
pr([]) :- !, write('[]').
pr([X|Xs]) :- !, write('['), pr(X), pr_tail(Xs), write(']').
pr(T) :- atomic(T), !, writeq(T).
pr(A-B) :- !, pr(A), write('-'), pr(B).
pr(T) :- T =.. [F|As], writeq(F), write('('), pr_args(As), write(')').

pr_tail(T) :- var(T), !, write('|_').
pr_tail([]) :- !.
pr_tail([X|Xs]) :- !, write(','), pr(X), pr_tail(Xs).
pr_tail(T) :- write('|'), pr(T).

pr_args([A]) :- !, pr(A).
pr_args([A|As]) :- pr(A), write(','), pr_args(As).
