% ops.pl – nach Scryers src/tests/clpz/test_clpz2.pl (BSD-3-Clause,
% LICENSE.scryer), verallgemeinert: run(Op, N) prüft für Z #= X Op Y mit
% Schranken L =< X =< U über -N-1..N, dass clpz genau die Lösungen
% findet, für die Z is X Op Y gilt (Orakel: is/2). Statt copy_term/2
% (kopiert hier keine Attribute) copy_term/3 mit den Restzielen.
% go(Ops, Max): alle Ops für N = 0..Max; Abweichungen als errorK([...]).
:- use_module(library(iso_ext)).
:- use_module(library(debug)).
:- use_module(library(clpz)).
% :- use_module('../../lib/clpz').
:- use_module(library(format)).
:- use_module(library(lists)).
:- use_module(library(time)).
:- use_module(combination).
:- use_module(permutation).

nat(N) :-
    nat(0, N).

nat(N, N).
nat(N0, N) :-
    N1 is N0 + 1,
    nat(N1, N).

bound(X, L, U) :- L #=< X, X #=< U.

/*
 * This test stops only if there is an mistake in the propagator.
 * This test is general enough to quickly test other operators.
 * This test does not test if permutating the clause changes the final result.
 */
run(Op, N) :-
    Vs = [X0, X1, X2, L0, L1, L2, U0, U1, U2],

    Xs = [X0, X1, X2],
    Ls = [L0, L1, L2],
    Us = [U0, U1, U2],

    Bs = [L0, L1, L2, U0, U1, U2],

    % maplist(#=<, Ls, Us),
    maplist(#\=(0), [X1, L1, U1]),
    maplist(bound, Xs, Ls, Us),

    % nat(N),
    NegN is -N - 1,
    Domain = NegN..N,

    I in 0..6,
    indomain(I),
    length(Is, I),
    combination(Bs, Is),
    Is ins Domain,
    labeling([], Is),

    (   % Every solution is generated and only solution.
        cz(Op, X0, X1, X2),
        Xs ins Domain,
        labeling([], Xs),
        (   catch(ar(Op, X0, X1, X2), _, false) ->
            true
        ;   format("~q\n", [error0([Op, N, Vs, Ys])]) % Found a non-solution.
        )
    ;   % Every solution is found and only solution.
        copy_term(Xs, Ys, Gs0), maplist(call, Gs0),
        Ys = [Y0, Y1, Y2],
        Ys ins Domain,
        labeling([], Ys),
        (   catch(ar(Op, Y0, Y1, Y2), _, false) ->
            (   cz(Op, X0, X1, X2) ->
                (   maplist(=, Ys, Xs) ->
                    % Find a specific solution.
                    true
                ;   format("~q\n", [error1([Op, N, Vs, Ys])])
                )
            ;   format("~q\n", [error2([Op, N, Vs, Ys])])
            )
        ;   cz(Op, X0, X1, X2),
            (   maplist(=, Ys, Xs) ->
                % Found a non-solution.
                format("~q\n", [error3([Op, N, Vs, Ys])])
            ;   true
            )
        )
    ),
    false.

cz(Op, X, Y, Z) :- E =.. [Op, X, Y], Z #= E.
ar(Op, X, Y, Z) :- E =.. [Op, X, Y], Z is E.
go(Ops, Max) :- member(Op, Ops), between(0, Max, N), format("~w ~d~n", [Op, N]), \+ run(Op, N), fail.
go(_, _).
:- use_module(library(between)).
