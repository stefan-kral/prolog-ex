% Beispielprogramm für PrologEx
:- op(700, xfx, ===>).

app([], L, L).
app([H|T], L, [H|R]) :- app(T, L, R).

nrev([], []).
nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R).

max(X, Y, Z) :- ( X >= Y -> Z = X ; Z = Y ).

regel(a ===> b).

% DCG: Grüße wie "hallo welt"
gruss --> [h,a,l,l,o], leer, wort(W), { atom_ok(W) }.
leer --> [' '].
wort([C|Cs]) --> [C], { C \= ' ' }, wort_rest(Cs).
wort_rest([C|Cs]) --> [C], { C \= ' ' }, wort_rest(Cs).
wort_rest([]) --> [].
atom_ok(_).

main :- nrev([1,2,3,4,5], R), write(R), nl,
        max(3, 7, M), write(max=M), nl,
        ( phrase(gruss, "hallo welt") -> write(gruss_ok) ; write(gruss_nicht_ok) ), nl.

:- initialization(main).
