/* Geschwindigkeitsvergleich PrologEx – Scryer Prolog (– SWI-Prolog)

   Dieselbe Datei in jedem System; jeder Fall läuft fünfmal, gezeigt
   wird die kleinste CPU-Zeit in ms (statistics(runtime, _)).

     MIX_ENV=prod mix prolog bench/compare.pl -g main -q
     scryer-prolog -g main -g halt bench/compare.pl
     swipl -g main -t halt bench/compare.pl
*/

:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(format)).
:- use_module(library(clpb)).
:- use_module(library(time)).

% --- Fälle -----------------------------------------------------------------

% naive reverse, 30 Elemente (496 Inferenzen je Durchlauf)
app([], L, L).
app([H|T], L, [H|R]) :- app(T, L, R).
nrev([], []).
nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R).
nrev_bench(0) :- !.
nrev_bench(N) :- numlist(1, 30, L), nrev(L, _), N1 is N - 1, nrev_bench(N1).

% deterministische Schleife mit Arithmetik
loop(0) :- !.
loop(N) :- N1 is N - 1, loop(N1).

% Takeuchi
tak(X, Y, Z, A) :- X =< Y, !, Z = A.
tak(X, Y, Z, A) :-
        X1 is X - 1, Y1 is Y - 1, Z1 is Z - 1,
        tak(X1, Y, Z, A1), tak(Y1, Z, X, A2), tak(Z1, X, Y, A3),
        tak(A1, A2, A3, A).

% acht Damen, alle Lösungen (Erzeugen und Prüfen)
queens(N, Qs) :- numlist(1, N, Ns), permq(Ns, [], Qs).
permq([], Qs, Qs).
permq(Ns, Placed, Qs) :-
        select(Q, Ns, Rest), safe(Placed, Q, 1),
        permq(Rest, [Q|Placed], Qs).
safe([], _, _).
safe([Q|Qs], Q0, D) :-
        Q0 =\= Q + D, Q0 =\= Q - D,
        D1 is D + 1, safe(Qs, Q0, D1).

% symbolisches Ableiten
d(U+V, X, DU+DV) :- !, d(U, X, DU), d(V, X, DV).
d(U-V, X, DU-DV) :- !, d(U, X, DU), d(V, X, DV).
d(U*V, X, DU*V+U*DV) :- !, d(U, X, DU), d(V, X, DV).
d(X, X, 1) :- !.
d(_, _, 0).
deriv(0) :- !.
deriv(N) :- d(x*x*x + 3*x*x - x*(x+1) + 7, x, _), N1 is N - 1, deriv(N1).

% Fakten, Backtracking
p(1). p(2). p(3). p(4). p(5). p(6). p(7). p(8). p(9). p(10).
facts(N) :- between(1, N, _), p(_), fail.
facts(_).

% foldl/4 und dieselbe Schleife von Hand
add(X, A0, A) :- A is A0 + X.
sum([], A, A).
sum([X|Xs], A0, A) :- A1 is A0 + X, sum(Xs, A1, A).

% findall, sort
fa(N, L) :- findall(X-Y, (between(1, N, X), Y is X mod 7), L0), sort(L0, L).

% clpb: kleine Formeln, BDDs bauen
clpb_it :- sat(A=:=B), sat(C#D), sat(E+F), sat(((((A=:=B)#C)+D)*E)=:=F).
clpb_n(N) :- between(1, N, _), clpb_it, fail.
clpb_n(_).

cases([
    nrev    - nrev_bench(2000),
    loop    - loop(1000000),
    tak     - tak(18, 12, 6, _),
    queens  - (queens(8, _), fail ; true),
    deriv   - deriv(20000),
    facts   - facts(100000),
    foldl   - (numlist(1, 300000, L1), foldl(add, L1, 0, _)),
    sum     - (numlist(1, 300000, L2), sum(L2, 0, _)),
    findall - fa(200000, _),
    clpb    - clpb_n(100)
]).

% --- Messen ----------------------------------------------------------------

run(G, T) :-
        statistics(runtime, [T0|_]),
        (   call(G) -> true ; true ),
        statistics(runtime, [T1|_]),
        D is T1 - T0,
        (   integer(D) -> T = D ; T is round(D) ).   % Scryer: Float

best(G, Best) :-
        findall(T, (between(1, 5, _), run(G, T)), Ts),
        sort(Ts, [Best|_]).

main :-
        cases(Cs),
        (   member(Name-G, Cs),
            best(G, T),
            format("~w~t~10|~t~d~8+ ms~n", [Name, T]),
            fail
        ;   true
        ).
