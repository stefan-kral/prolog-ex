% library(simplex): Ergebnisse wie in der Dokumentation (Scryer, SWI);
% Brüche numerisch verglichen (=:=), weil Scryer 15 rdiv 2 und SWI/PrologEx
% 15r2 schreiben
expect((radiation(S), values(S, [x1, x2], [A, B]), A =:= 15 rdiv 2, B =:= 9 rdiv 2), ok, [ok]).
expect((knapsack(S), values(S, [x(1), x(2)], [A, B]), A =:= 1, B =:= 1 rdiv 2), ok, [ok]).
expect((knapsack_integral(S), values(S, [x(1), x(2)], [A, B]), A =:= 0, B =:= 2), ok, [ok]).
expect((coins(S), values(S, [c(1), c(5), c(20)], [A, B, C]), A =:= 1, B =:= 2, C =:= 5), ok, [ok]).
expect((named(S), values(S, [x, y], [A, B]), objective(S, O),
        shadow_price(S, c1, P1), shadow_price(S, c2, P2),
        A =:= 3, B =:= 1, O =:= 14, P1 =:= 2, P2 =:= 1), ok, [ok]).
expect(transportation([12,7,14], [3,9,3,18], [[20,40,70,50],[100,60,90,80],[10,110,30,200]], P), P,
       [[[0,0,0,12],[0,1,0,6],[3,8,3,0]]]).
expect(assignment([[1,2,3],[3,1,2],[2,3,1]], A), A, [[[1,0,0],[0,1,0],[0,0,1]]]).
expect(assignment([[10,19,8,15],[10,18,7,17],[13,16,9,14],[12,19,8,18]], A), A,
       [[[0,0,0,1],[1,0,0,0],[0,1,0,0],[0,0,1,0]]]).
expect_count(infeasible, 0).
