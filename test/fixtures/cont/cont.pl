% Tests für library(cont) (test/cont_test.exs)
:- use_module(library(cont)).
:- use_module(library(lists)).


% Iterator/Generator
fromList([]).
fromList([X|Xs]) :- shift(yield(X)), fromList(Xs).
enumerate(G, L) :- reset(G, Ball, Cont), ( Cont == none -> L = [] ; Ball = yield(X), Cont = cont(K), L = [X|T], enumerate(K, T) ).
t1 :- enumerate(fromList([a,b,c]), L), write_term(L, [quoted(true), double_quotes(false)]), nl.

% Effekt-Handler: Zustand
get(S) :- shift(get(S)).
put(S) :- shift(put(S)).
run_state(G, S0, S) :- reset(G, Cmd, Cont), ( Cont == none -> S = S0 ; Cont = cont(K), ( Cmd = get(S0) -> run_state(K, S0, S) ; Cmd = put(S1) -> run_state(K, S1, S) ) ).
incr :- get(X), Y is X + 1, put(Y).
t2 :- run_state((incr, incr, get(V), W is V * 10, put(W)), 1, S), writeq(S), nl.

% kein shift
t3 :- reset(true, B, C), var(B), writeq(C), nl.
% shift ohne reset
t4 :- catch(shift(x), E, true), print(E), nl.
% Backtracking in Ziel vor shift
t5 :- findall(X-C, (reset((member(X, [1,2]), shift(X)), _, C0), (C0 = cont(_) -> C = k ; C = C0)), L), writeq(L), nl.
% Cut in Fortsetzung: lokal
p(X) :- shift(a), member(X, [1,2,3]), !.
t6 :- reset(p(X), _, cont(K)), findall(X, call(K), L), writeq(L), nl.
% catch um shift: danach nicht mehr aktiv
t7 :- reset(catch(shift(a), _, (write(caught), nl)), _, _), catch(throw(oops), E, (writeq(outer(E)), nl)).
% Fortsetzung zweimal aufrufen, kopierbar
t8 :- reset((shift(a), X = 1, Y is X + 2, write(Y), nl), _, cont(K)), call(K), copy_term(K, K2), call(K2), writeq(ok), nl.
t9 :- reset((shift(a), shift(b), write(end), nl), B1, cont(K1)), reset(K1, B2, cont(K2)), call(K2), writeq(B1/B2), nl.
