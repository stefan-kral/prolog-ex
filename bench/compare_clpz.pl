/* Geschwindigkeitsvergleich clpz: PrologEx – Scryer Prolog – SWI-Prolog

   Dieselbe Datei in jedem System; jeder Fall läuft dreimal, gezeigt
   wird die kleinste CPU-Zeit in ms (statistics(runtime, _)). SWI hat
   kein library(clpz): bench/swi/clpz.pl reicht dort library(clpfd)
   unter diesem Namen weiter.

     MIX_ENV=prod mix prolog bench/compare_clpz.pl -g main -q
     scryer-prolog -g main -g halt bench/compare_clpz.pl
     swipl -p library=bench/swi -g main -t halt bench/compare_clpz.pl
*/

:- use_module(library(clpz)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(format)).
:- use_module(library(time)).          % Scryer: statistics/2

% --- Fälle -----------------------------------------------------------------

queens(N, Qs) :- length(Qs, N), Qs ins 1..N, safe(Qs), labeling([ff], Qs).
safe([]).
safe([Q|Qs]) :- no_attack(Q, Qs, 1), safe(Qs).
no_attack(_, [], _).
no_attack(Q, [Q1|Qs], D) :- Q #\= Q1, abs(Q - Q1) #\= D, D1 is D + 1, no_attack(Q, Qs, D1).

puzzle([S,E,N,D] + [M,O,R,E] = [M,O,N,E,Y]) :-
   Vars = [S,E,N,D,M,O,R,Y], Vars ins 0..9, all_different(Vars),
   S*1000 + E*100 + N*10 + D + M*1000 + O*100 + R*10 + E #=
   M*10000 + O*1000 + N*100 + E*10 + Y, M #\= 0, S #\= 0, label(Vars).

sudoku(Rows) :-
   length(Rows, 9), maplist(same_length(Rows), Rows),
   append(Rows, Vs), Vs ins 1..9,
   maplist(all_distinct, Rows),
   transpose(Rows, Columns), maplist(all_distinct, Columns),
   Rows = [As,Bs,Cs,Ds,Es,Fs,Gs,Hs,Is],
   blocks(As, Bs, Cs), blocks(Ds, Es, Fs), blocks(Gs, Hs, Is).
blocks([], [], []).
blocks([N1,N2,N3|Ns1], [N4,N5,N6|Ns2], [N7,N8,N9|Ns3]) :-
   all_distinct([N1,N2,N3,N4,N5,N6,N7,N8,N9]), blocks(Ns1, Ns2, Ns3).
problem(1, [[_,_,_,_,_,_,_,_,_],[_,_,_,_,_,3,_,8,5],[_,_,1,_,2,_,_,_,_],
            [_,_,_,5,_,7,_,_,_],[_,_,4,_,_,_,1,_,_],[_,9,_,_,_,_,_,_,_],
            [5,_,_,_,_,_,_,7,3],[_,_,2,_,1,_,_,_,_],[_,_,_,_,4,_,_,_,9]]).

magic(N, Rows) :-
   NN is N*N, S is N*(NN+1)//2, length(Rows, N), maplist(same_length(Rows), Rows),
   append(Rows, Vs), Vs ins 1..NN, all_different(Vs),
   maplist(sum_eq(S), Rows), transpose(Rows, Cols), maplist(sum_eq(S), Cols),
   diag(Rows, 0, D1), sum(D1, #=, S), maplist(reverse, Rows, RR), diag(RR, 0, D2), sum(D2, #=, S),
   labeling([ff], Vs).
sum_eq(S, L) :- sum(L, #=, S).
diag([], _, []).
diag([R|Rs], I, [X|Xs]) :- nth0(I, R, X), I1 is I + 1, diag(Rs, I1, Xs).

q20 :- queens(20, _).
q40 :- queens(40, _).
q8all :- findall(Q, queens(8, Q), L), length(L, 92).
send :- puzzle(_).
sud :- problem(1, Rows), sudoku(Rows), maplist(labeling([ff]), Rows).
mag :- magic(4, _).
q100 :- queens(100, _).
mag5 :- magic(5, _).

% --- Messen ----------------------------------------------------------------

run(G, T) :-
        statistics(runtime, [T0|_]),
        (   call(G) -> true ; true ),
        statistics(runtime, [T1|_]),
        D is T1 - T0,
        (   integer(D) -> T = D ; T is round(D) ).   % Scryer: Float

best(G, Best) :-
        findall(T, (between(1, 3, _), run(G, T)), Ts),
        sort(Ts, [Best|_]).

main :-
        (   member(G, [send, q20, q40, q8all, sud, mag, mag5, q100]),
            best(G, T),
            format("~w~t~10|~t~d~8+ ms~n", [G, T]),
            fail
        ;   true
        ).
