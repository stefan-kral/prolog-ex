% Bell-Zahlen (OEIS A000110): die Zerlegungen der Menge {1..N} in
% Bloecke. Jedes Element kommt in einen neuen Block oder in einen der
% vorhandenen.
set_partition(N, Bs) :-
    upto(1, N, Xs),
    partition(Xs, Bs).

partition([], []).
partition([X|Xs], Bs) :-
    partition(Xs, Bs0),
    add(X, Bs0, Bs).

add(X, Bs, [[X]|Bs]).
add(X, Bs0, Bs) :- into(X, Bs0, Bs).

into(X, [B|Bs], [[X|B]|Bs]).
into(X, [B|Bs], [B|Bs1]) :- into(X, Bs, Bs1).

upto(I, N, []) :- I > N, !.
upto(I, N, [I|Is]) :- I1 is I + 1, upto(I1, N, Is).
