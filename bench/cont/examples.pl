% Beispiele für begrenzte Fortsetzungen (reset/3, shift/1), portabel für
% PrologEx, Scryer, Trealla und SWI (je System ein Vorspann prelude_*.pl,
% run.sh). Unterschied der Systeme: endet das Ziel ohne shift/1, ist die
% Fortsetzung none (PrologEx, Scryer, Trealla) bzw. 0 (SWI); sonst ist sie
% cont(G) bzw. direkt aufrufbar (SWI). k/2 und done/1 gleichen das aus.

done(C) :- ( C == none ; C == 0 ), !.
k(cont(G), G) :- !.
k(G, G).

% --- Generatoren -----------------------------------------------------------

% nat(N): N, N+1, N+2, ... (unendlich, wie [n..] in Haskell)
nat(N) :- shift(yield(N)), N1 is N + 1, nat(N1).

% fib(A, B): 0, 1, 1, 2, 3, 5, ...
fib(A, B) :- shift(yield(A)), C is A + B, fib(B, C).

% from_list(L): die Elemente einer Liste
from_list([]).
from_list([X|Xs]) :- shift(yield(X)), from_list(Xs).

% take(N, G, L): die ersten N Werte des Generators G
take(N, G, L) :-
    (   N =:= 0 -> L = []
    ;   reset(G, Ball, C),
        (   done(C) -> L = []
        ;   Ball = yield(X), L = [X|T], N1 is N - 1, k(C, K), take(N1, K, T)
        )
    ).

% Transducer: Generatoren aus Generatoren
% filter(P, G): nur die Werte X von G mit call(P, X)
filter(P, G) :-
    reset(G, Ball, C),
    (   done(C) -> true
    ;   Ball = yield(X),
        ( call(P, X) -> shift(yield(X)) ; true ),
        k(C, K), filter(P, K)
    ).

% map(F, G): call(F, X, Y) für jeden Wert X von G
map(F, G) :-
    reset(G, Ball, C),
    (   done(C) -> true
    ;   Ball = yield(X), call(F, X, Y), shift(yield(Y)), k(C, K), map(F, K)
    ).

% --- Primzahlsieb als Strom ----------------------------------------------
% primes = sieve [2..]; sieve (p:xs) = p : sieve [x | x <- xs, x mod p /= 0]
sieve(G) :-
    reset(G, Ball, C),
    (   done(C) -> true
    ;   Ball = yield(P), shift(yield(P)), k(C, K), sieve(filter(not_div(P), K))
    ).

not_div(P, X) :- X mod P =\= 0.

primes(N, Ps) :- take(N, sieve(nat(2)), Ps).

% --- List Comprehension über einem unendlichen Strom ------------------------
% take 5 [x*x | x <- [1..], x `mod` 3 == 0]
div3(X) :- X mod 3 =:= 0.
square(X, Y) :- Y is X * X.
lc(L) :- take(5, map(square, filter(div3, nat(1))), L).

% --- Same Fringe: dieselbe Blattfolge? Bricht beim ersten Unterschied ab -----
leaves(leaf(X)) :- shift(yield(X)).
leaves(node(L, R)) :- leaves(L), leaves(R).

same_fringe(T1, T2) :- same_gen(leaves(T1), leaves(T2)).

same_gen(G1, G2) :-
    reset(G1, B1, C1),
    reset(G2, B2, C2),
    (   done(C1) -> done(C2)
    ;   \+ done(C2), B1 == B2, k(C1, K1), k(C2, K2), same_gen(K1, K2)
    ).

% Baum mit den Blättern L..H, Form abhängig von S (links- oder rechtslastig)
tree(L, L, _, leaf(L)) :- !.
tree(L, H, S, node(A, B)) :-
    ( S == left -> M is H - 1 ; S == right -> M = L ; M is (L + H) // 2 ),
    M1 is M + 1, tree(L, M, S, A), tree(M1, H, S, B).

% --- Effekt-Handler: Zustand -----------------------------------------------
st_get(S) :- shift(get(S)).
st_put(S) :- shift(put(S)).

run_state(G, S0, S) :-
    reset(G, Cmd, C),
    (   done(C) -> S = S0
    ;   k(C, K),
        (   Cmd = get(S0) -> run_state(K, S0, S)
        ;   Cmd = put(S1) -> run_state(K, S1, S)
        )
    ).

incr :- st_get(X), Y is X + 1, st_put(Y).
incr_n(0) :- !.
incr_n(N) :- incr, N1 is N - 1, incr_n(N1).

% --- Ergebnisse --------------------------------------------------------------
show(Name, Goal, X) :-
    ( catch(Goal, E, (X = error(E))) -> true ; X = failed ),
    write(Name), write(': '), writeq(X), nl.

main :-
    show(nat, take(10, nat(0), L1), L1),
    show(fib, take(12, fib(0, 1), L2), L2),
    show(primes, primes(15, L3), L3),
    show(lc, lc(L4), L4),
    show(same_fringe_yes, (tree(1, 6, left, A1), tree(1, 6, right, B1), (same_fringe(A1, B1) -> R1 = yes ; R1 = no)), R1),
    show(same_fringe_no, (tree(1, 6, left, A2), A2 = node(X2, _), tree(1, 6, right, B2), B2 = node(_, Y2), (same_fringe(node(X2, leaf(0)), node(leaf(1), Y2)) -> R2 = yes ; R2 = no)), R2),
    show(state, run_state(incr_n(5), 10, S), S),
    show(no_shift, (reset(true, _, C0), (done(C0) -> R0 = done ; R0 = C0)), R0).

% --- Laufzeit ----------------------------------------------------------------
% sum_gen(N): Summe der ersten N Werte von nat/1 (eine Fortsetzung je Wert)
sum_gen(N, S) :- sum_take(N, nat(1), 0, S).
sum_take(N, G, A, S) :-
    (   N =:= 0 -> S = A
    ;   reset(G, yield(X), C), k(C, K), A1 is A + X, N1 is N - 1, sum_take(N1, K, A1, S)
    ).
% dasselbe ohne Fortsetzungen, zum Vergleich
sum_loop(N, S) :- sum_loop(N, 1, 0, S).
sum_loop(0, _, S, S) :- !.
sum_loop(N, X, A, S) :- A1 is A + X, X1 is X + 1, N1 is N - 1, sum_loop(N1, X1, A1, S).
% dasselbe mit findall (die ganze Liste im Speicher)
sum_findall(N, S) :- findall(X, between(1, N, X), L), sum_list(L, S).

bench(sum_gen, N) :- sum_gen(N, _).
bench(sum_loop, N) :- sum_loop(N, _).
bench(sum_findall, N) :- sum_findall(N, _).
bench(primes, N) :- primes(N, _).
bench(same_fringe, N) :- tree(1, N, bal, A), tree(1, N, right, B), same_fringe(A, B).
% links tief gegen rechts tief: die erste Fortsetzung hält alle N - 1 offenen Teilbäume
bench(same_fringe_left, N) :- tree(1, N, left, A), tree(1, N, right, B), same_fringe(A, B).
bench(state, N) :- run_state(incr_n(N), 0, _).

% time(Name, N): Laufzeit in ms (CPU), eine Zeile "Name N ms"
time(Name, N) :-
    statistics(runtime, [T0|_]),
    ( bench(Name, N) -> true ; true ),
    statistics(runtime, [T1|_]),
    T is T1 - T0,
    write(Name), write(' '), write(N), write(' '), write(T), nl.
