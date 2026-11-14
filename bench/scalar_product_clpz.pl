/* Geschwindigkeit von scalar_product_eq in clpz: PrologEx - Scryer - SWI

   Lineare Gleichungen mit mindestens vier Variablen oder Koeffizienten
   ungleich ±1 werden in clpz zum Propagator scalar_product_eq/3; die
   Fälle hier bestehen (fast) nur aus solchen Gleichungen, ohne
   all_different/1 und Co. Dieselbe Datei in jedem System, jeder Fall
   dreimal, gezeigt wird die kleinste CPU-Zeit in ms; dahinter eine
   Prüfsumme (Zahl der Lösungen o. Ä.), die in allen Systemen gleich
   sein muss.

     MIX_ENV=prod mix prolog bench/scalar_product_clpz.pl -g main -q
     scryer-prolog -g main -g halt bench/scalar_product_clpz.pl
     swipl -p library=bench/swi -g main -t halt bench/scalar_product_clpz.pl

   Einzelne Fälle: -g "main([coins,narrow])".
*/

:- use_module(library(clpz)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(format)).
:- use_module(library(time)).          % Scryer: statistics/2

% --- Zufallszahlen (LCG, in allen Systemen gleich) -------------------------

rand(S0, Lo, Hi, X, S) :-
        S is (S0 * 1103515245 + 12345) mod 2147483648,
        X is Lo + (S >> 16) mod (Hi - Lo + 1).

rands(0, _, _, S, [], S) :- !.
rands(N, Lo, Hi, S0, [X|Xs], S) :-
        rand(S0, Lo, Hi, X, S1),
        N1 is N - 1,
        rands(N1, Lo, Hi, S1, Xs, S).

% Koeffizienten ungleich 0
coeffs(0, _, S, [], S) :- !.
coeffs(N, M, S0, Cs, S) :-
        Lo is -M,
        rand(S0, Lo, M, C, S1),
        (   C =:= 0 -> coeffs(N, M, S1, Cs, S)
        ;   Cs = [C|Cs1], N1 is N - 1, coeffs(N1, M, S1, Cs1, S)
        ).

dot([], [], 0).
dot([C|Cs], [X|Xs], S) :- dot(Cs, Xs, S0), S is S0 + C*X.

% --- Fälle -----------------------------------------------------------------

% post: 300 Gleichungen mit je 12 Variablen in 0..100, Koeffizienten
% 1..9, rechte Seite aus einer Lösung - nur Aufstellen und erste
% Propagation (keine Beschriftung)
post(Sum) :-
        length(Vs, 12), Vs ins 0..100,
        rands(12, 0, 100, 1, Sol, S0),
        post_(300, Vs, Sol, S0),
        fd_sizes(Vs, Sum).
post_(0, _, _, _) :- !.
post_(N, Vs, Sol, S0) :-
        rands(12, 1, 9, S0, Cs, S1),
        dot(Cs, Sol, R),
        scalar_product(Cs, Vs, #=, R),
        N1 is N - 1,
        post_(N1, Vs, Sol, S1).

fd_sizes(Vs, Sum) :- fd_sizes_(Vs, 0, Sum).
fd_sizes_([], S, S).
fd_sizes_([V|Vs], S0, S) :- fd_size(V, N), S1 is S0 + N, fd_sizes_(Vs, S1, S).

% posteach: 2000 Gleichungen über je eigene 6 Variablen (Aufstellen und
% Wegwerfen, viele kleine Propagatoren)
posteach(2000) :-
        posteach_(2000, 7).
posteach_(0, _) :- !.
posteach_(N, S0) :-
        length(Vs, 6), Vs ins 0..50,
        coeffs(6, 9, S0, Cs, S1),
        rands(6, 0, 50, S1, Sol, S2),
        dot(Cs, Sol, R),
        scalar_product(Cs, Vs, #=, R),
        N1 is N - 1,
        posteach_(N1, S2).

% coins: auf wie viele Arten lassen sich 100 aus Münzen 1, 2, 5, 10, 20,
% 50 legen (alle Lösungen beschriften; 4562)
coins(N) :-
        Vs = [A,B,C,D,E,F],
        Vs ins 0..100,
        1*A + 2*B + 5*C + 10*D + 20*E + 50*F #= 100,
        findall(x, label(Vs), L), length(L, N).

% knap: Gewichte mit großen Koeffizienten, jedes Stück 0..5-mal, Summe
% genau 400 (alle Lösungen zählen)
knap(N) :-
        Ws = [13,17,23,31,37,41,53],
        length(Vs, 7), Vs ins 0..5,
        scalar_product(Ws, Vs, #=, 400),
        findall(x, label(Vs), L), length(L, N).

% linsys: 4 Gleichungen, 6 Unbekannte in -10..10, Koeffizienten -6..6,
% Lösung versteckt; alle Lösungen beschriften (ff)
linsys(N) :-
        length(Vs, 6), Vs ins -10..10,
        rands(6, -10, 10, 11, Sol, S0),
        linsys_(4, Vs, Sol, S0),
        findall(Vs, labeling([ff], Vs), L), length(L, N).
linsys_(0, _, _, _) :- !.
linsys_(K, Vs, Sol, S0) :-
        coeffs(6, 6, S0, Cs, S1),
        dot(Cs, Sol, R),
        scalar_product(Cs, Vs, #=, R),
        K1 is K - 1,
        linsys_(K1, Vs, Sol, S1).

% narrow: eine Gleichung über 60 Variablen in 0..1000, dann 60 Runden,
% in denen jede Variable ein Stück enger wird - jedes #=< weckt den
% Propagator (Kosten des Aufwachens und Durchlaufens)
narrow(Sum) :-
        length(Vs, 60), Vs ins 0..1000,
        rands(60, 1, 9, 3, Cs, _),
        sum_list(Cs, CS), R is CS * 400,
        scalar_product(Cs, Vs, #=, R),
        numlist(1, 60, Ks),
        narrow_(Ks, Vs),
        fd_sizes(Vs, Sum).
narrow_([], _).
narrow_([K|Ks], Vs) :-
        Hi is 1000 - 5*K,
        Lo is 5*K,
        maplist(tighten(Lo, Hi), Vs),
        narrow_(Ks, Vs).
tighten(Lo, Hi, V) :- V #=< Hi, V #>= Lo.

% --- wie in magic_square(N): 2N+2 Summen über je N Variablen ---------------

% Quadrat N×N mit Zeilen-, Spalten- und Diagonalsummen Sum, Zahlen in
% Lo..Hi (ohne Verschiedenheit)
square(N, Lo, Hi, Sum, Rows, Vs) :-
        length(Rows, N), maplist(same_length(Rows), Rows),
        append(Rows, Vs), Vs ins Lo..Hi,
        maplist(sum_eq(Sum), Rows),
        transpose(Rows, Cols), maplist(sum_eq(Sum), Cols),
        diag(Rows, 0, D1), sum_eq(Sum, D1),
        maplist(reverse, Rows, RR), diag(RR, 0, D2), sum_eq(Sum, D2).
sum_eq(S, L) :- sum(L, #=, S).
diag([], _, []).
diag([R|Rs], I, [X|Xs]) :- nth0(I, R, X), I1 is I + 1, diag(Rs, I1, Xs).

% magic_square(N) wie in Triskas Beispiel: Zahlen 1..N², verschieden
magic_square(N, Rows, Vs) :-
        NN is N*N, S is N*(NN+1)//2,
        square(N, 1, NN, S, Rows, Vs),
        all_different(Vs).

% ms3all: 20-mal alle 8 magischen Quadrate 3×3 (label)
ms3all(N) :-
        findall(x, (between(1, 20, _), magic_square(3, _, Vs), label(Vs)), L),
        length(L, N).

% ms4: 20-mal das erste magische Quadrat 4×4 (label)
ms4(N) :-
        findall(Vs, (between(1, 20, _), once((magic_square(4, _, Vs), label(Vs)))), L),
        length(L, N).

% ms5ff: das erste magische Quadrat 5×5 (labeling([ff]))
ms5ff(Vs) :- magic_square(5, _, Vs), labeling([ff], Vs).

% sq3: alle 3×3-Quadrate mit Summe 30 aus 1..20, Zahlen dürfen sich
% wiederholen
sq3(N) :- findall(x, (square(3, 1, 20, 30, _, Vs), label(Vs)), L), length(L, N).

% sq4: alle 4×4-Quadrate mit Summe 10 aus 1..4
sq4(N) :- findall(x, (square(4, 1, 4, 10, _, Vs), label(Vs)), L), length(L, N).

% sqpost: 300-mal die Summen eines 6×6-Quadrats aufstellen (14 Gleichungen
% mit je 6 Variablen, 1..36), ohne Beschriftung
sqpost(300) :- sqpost_(300).
sqpost_(0) :- !.
sqpost_(K) :- square(6, 1, 36, 111, _, _), K1 is K - 1, sqpost_(K1).

% --- Messen ----------------------------------------------------------------

run(G, T, R) :-
        statistics(runtime, [T0|_]),
        (   call(G, R0) -> R = R0 ; R = failed ),
        statistics(runtime, [T1|_]),
        D is T1 - T0,
        (   integer(D) -> T = D ; T is round(D) ).   % Scryer: Float

best(G, Best, R) :-
        findall(T-R0, (between(1, 3, _), run(G, T, R0)), TRs),
        keysort(TRs, [Best-R|_]).

main :- main([post, posteach, coins, knap, linsys, narrow,
               ms3all, ms4, ms5ff, sq3, sq4, sqpost]).

main(Gs) :-
        (   member(G, Gs),
            best(G, T, R),
            format("~w~t~10|~t~d~8+ ms   ~w~n", [G, T, R]),
            fail
        ;   true
        ).
