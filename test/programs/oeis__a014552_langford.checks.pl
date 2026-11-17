% Anzahlen: OEIS A014552 (Langford, Umkehrung einmal gezaehlt), n = 1..8.
expect_count(langford(1, _), 0).
expect_count(langford(2, _), 0).
expect_count(langford(3, _), 1).
expect_count(langford(4, _), 1).
expect_count(langford(5, _), 0).
expect_count(langford(6, _), 0).
expect_count(langford(7, _), 26).
expect_count(langford(8, _), 150).
% die eine Folge fuer 3 (3,1,2,1,3,2) und 4 (4,1,3,1,2,4,3,2): erste Stellen
expect(langford(3, Ps), Ps, [[2,3,1]]).
expect(langford(4, Ps), Ps, [[2,5,3,1]]).
