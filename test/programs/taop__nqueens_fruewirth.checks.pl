% N-Damen nach Thom Fruehwirth (Diagonalen als Listen Ups/Downs, ohne
% Arithmetik beim Platzieren), aus "The Art of Prolog" (Sterling/Shapiro).
% Anzahlen: OEIS A000170; Reihenfolge der Loesungen: wie SWI-Prolog 9.0.4
% und Scryer (b7066b4).
expect_count(queens(1, _), 1).
expect_count(queens(2, _), 0).
expect_count(queens(3, _), 0).
expect_count(queens(4, _), 2).
expect_count(queens(5, _), 10).
expect_count(queens(6, _), 4).
expect_count(queens(7, _), 40).
expect_count(queens(8, _), 92).
expect(queens(4, Qs), Qs, [[3,1,4,2],[2,4,1,3]]).
expect(queens(5, Qs), Qs, [[1,4,2,5,3],[1,3,5,2,4],[3,1,4,2,5],[4,1,3,5,2],[2,4,1,3,5],
                           [5,3,1,4,2],[2,5,3,1,4],[5,2,4,1,3],[4,2,5,3,1],[3,5,2,4,1]]).
expect_first(queens(8, Qs), Qs, [1,7,5,8,2,4,6,3]).
