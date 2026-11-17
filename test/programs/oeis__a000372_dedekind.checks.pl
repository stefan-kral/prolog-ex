% Werte: OEIS A000372 (Dedekind), n = 0..5 (n = 6, 7828354, braucht in
% PrologEx 23 s, in SWI 87 s: nicht in der Batterie).
expect(dedekind(0, C), C, [2]).
expect(dedekind(1, C), C, [3]).
expect(dedekind(2, C), C, [6]).
expect(dedekind(3, C), C, [20]).
expect(dedekind(4, C), C, [168]).
expect(dedekind(5, C), C, [7581]).
