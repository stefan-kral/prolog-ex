% b(Name, Ziel, N): beste Zeit aus 3 Laeufen von N-mal Ziel (alle Loesungen)
t(G, N, T) :- statistics(runtime, [T0,_]), ( between(1, N, _), call(G), fail ; true ), statistics(runtime, [T1,_]), T is T1-T0.
b(Name, G, N) :-
    catch(( t(G, N, T1), t(G, N, T2), t(G, N, T3), T is min(T1, min(T2, T3)) ), E, (write(Name), write(' FEHLER '), write(E), nl, fail)),
    !, Ti is integer(T), U is integer(T * 1000 / N), write(res(Name, N, Ti, U)), write('.'), nl.
b(_, _, _).
l30(L) :- range(1, 30, L).
suite(Vs) :-
    l30(L),
    b(nrev-direct, nrev(L, _), 5000),
    ( member(v, Vs) -> b(nrev-vanilla, s_v(nrev(L, _)), 1000) ; true ),
    b(nrev-built_in, s_bi(nrev(L, _)), 1000),
    ( member(dyn, Vs) -> b(nrev-dyn, s_dyn(nrev(L, _)), 1000) ; true ),
    ( member(soft, Vs) -> b(nrev-catch_softcut, s_soft(nrev(L, _)), 1000) ; true ),
    ( member(cx, Vs) -> b(nrev-clausex, s_cx(nrev(L, _)), 1000) ; true ),
    b(queens8-direct, queens(8, _), 60),
    b(queens8-built_in, s_bi(queens(8, _)), 6),
    ( member(dyn, Vs) -> b(queens8-dyn, s_dyn(queens(8, _)), 6) ; true ),
    ( member(soft, Vs) -> b(queens8-catch_softcut, s_soft(queens(8, _)), 6) ; true ),
    ( member(cx, Vs) -> b(queens8-clausex, s_cx(queens(8, _)), 6) ; true ).
