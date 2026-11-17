% Peano-Arithmetik: Vergleich mit is/2 fuer alle Paare aus 0..12 (add, mul,
% le, mod, gcd, minimum; jeweils auch die Anzahl der Loesungen)
expect(mismatches(12, Bad), Bad, [[]]).
% Werte
expect((int_peano(5, N), fact(N, F), peano_int(F, C)), C, [120]).
expect((int_peano(10, N), int_peano(2, X), pow(N, X, Y), peano_int(Y, C)), C, [1024]).
expect((int_peano(2, M), int_peano(3, N), ack(M, N, V), peano_int(V, C)), C, [9]).
expect((int_peano(3, M), int_peano(3, N), ack(M, N, V), peano_int(V, C)), C, [61]).
% relational: add(X, Y, n) hat n+1 Loesungen, in dieser Reihenfolge
expect(add(X, Y, s(s(0))), X-Y, [0-s(s(0)), s(0)-s(0), s(s(0))-0]).
expect(splits_of(10, C), C, [11]).
expect(add(X, s(0), s(s(s(0)))), X, [s(s(0))]).
% mul/3 rueckwaerts nur mit Schranke (sonst endet es nach der Loesung nicht)
expect((le(X, s(s(s(s(s(s(0))))))), mul(X, s(s(0)), s(s(s(s(s(s(0)))))))), X, [s(s(s(0)))]).
% minimum/3 aus dem Buch: zwei Loesungen bei gleichen Zahlen
expect(minimum(s(0), s(0), M), M, [s(0), s(0)]).
% Teiler (OEIS A000005), n = 1..30
expect(divisors_of(1, C), C, [1]).
expect(divisors_of(2, C), C, [2]).
expect(divisors_of(3, C), C, [2]).
expect(divisors_of(4, C), C, [3]).
expect(divisors_of(5, C), C, [2]).
expect(divisors_of(6, C), C, [4]).
expect(divisors_of(7, C), C, [2]).
expect(divisors_of(8, C), C, [4]).
expect(divisors_of(9, C), C, [3]).
expect(divisors_of(10, C), C, [4]).
expect(divisors_of(11, C), C, [2]).
expect(divisors_of(12, C), C, [6]).
expect(divisors_of(16, C), C, [5]).
expect(divisors_of(24, C), C, [8]).
expect(divisors_of(25, C), C, [3]).
expect(divisors_of(28, C), C, [6]).
expect(divisors_of(30, C), C, [8]).
% Kompositionen (OEIS A011782), n = 0..10
expect(compositions_of(0, C), C, [1]).
expect(compositions_of(1, C), C, [1]).
expect(compositions_of(2, C), C, [2]).
expect(compositions_of(3, C), C, [4]).
expect(compositions_of(4, C), C, [8]).
expect(compositions_of(5, C), C, [16]).
expect(compositions_of(10, C), C, [512]).
% tiefe Terme
expect(deep_add(100000, C), C, [200000]).
expect(deep_le(100000), ok, [ok]).
