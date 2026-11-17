% Motzkin-Zahlen (OEIS A001006) als DCG: Wege der Laenge N aus den
% Schritten f (flach), u (hoch) und d (runter), die nie unter die
% Grundlinie gehen und auf ihr enden. Eindeutige Grammatik; die Laenge
% steht vorher fest.
motzkin(N, L) :-
    length(L, N),
    phrase(path, L).

path --> [].
path --> [f], path.
path --> [u], path, [d], path.
