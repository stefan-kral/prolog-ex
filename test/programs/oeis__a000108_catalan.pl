% Catalan-Zahlen (OEIS A000108) als DCG: ausgeglichene Klammerfolgen aus
% N Klammerpaaren. Die Grammatik ist eindeutig, also hat jede Folge genau
% eine Ableitung; length/2 legt die Laenge vorher fest, damit die Suche
% endet.
parens(N, L) :-
    M is 2 * N,
    length(L, M),
    phrase(balanced, L).

balanced --> [].
balanced --> ['('], balanced, [')'], balanced.
