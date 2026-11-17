% Sudokus mit eindeutiger Lösung (puzzle/2: Name, 81 Ziffern als Atom, 0 =
% leer): clpz muss genau eine Lösung finden; die prüft check/2 ohne clpz
:- use_module(library(clpz)).
:- use_module(library(lists)).

sudoku(Rows) :-
    length(Rows, 9), maplist(same_length(Rows), Rows),
    append(Rows, Vs), Vs ins 1..9,
    maplist(all_distinct, Rows),
    transpose(Rows, Columns), maplist(all_distinct, Columns),
    Rows = [As,Bs,Cs,Ds,Es,Fs,Gs,Hs,Is],
    blocks(As, Bs, Cs), blocks(Ds, Es, Fs), blocks(Gs, Hs, Is).

blocks([], [], []).
blocks([N1,N2,N3|Ns1], [N4,N5,N6|Ns2], [N7,N8,N9|Ns3]) :-
    all_distinct([N1,N2,N3,N4,N5,N6,N7,N8,N9]),
    blocks(Ns1, Ns2, Ns3).

rows([], []).
rows(Ds, [R|Rs]) :- length(R, 9), append(R, Ds1, Ds), rows(Ds1, Rs).

given(0, _) :- !.
given(D, D).

grid(P, Rows) :-
    atom_chars(P, Cs), digits(Cs, Ds), rows(Ds, Rows0),
    length(Rows, 9), maplist(same_length(Rows), Rows),
    maplist(maplist(given), Rows0, Rows).

digits([], []).
digits([C|Cs], [D|Ds]) :- number_chars(D, [C]), digits(Cs, Ds).

% ohne clpz: Ziffern 1..9, Zeilen, Spalten, Blöcke je 1..9, Vorgaben gehalten
check(P, Rows) :-
    grid(P, G), G = Rows,
    maplist(ok9, Rows),
    transpose(Rows, Cols), maplist(ok9, Cols),
    Rows = [A,B,C,D,E,F,H,I,J], bl(A,B,C), bl(D,E,F), bl(H,I,J).
% neun Einträge, sortiert ohne Doppelte 1..9: jede Ziffer genau einmal
ok9(L) :- length(L, 9), sort(L, [1,2,3,4,5,6,7,8,9]).
bl([], [], []).
bl([A,B,C|R1], [D,E,F|R2], [G,H,I|R3]) :- ok9([A,B,C,D,E,F,G,H,I]), bl(R1, R2, R3).

% alle Lösungen: bei eindeutigem Sudoku genau eine (die Suche muss für den
% Beweis ohnehin bis zum Ende)
verdict(N, V) :-
    puzzle(N, P),
    findall(Rows, ( grid(P, Rows), sudoku(Rows), append(Rows, Vs), labeling([ff], Vs) ), Sols),
    (   Sols = [S] -> ( check(P, S) -> V = ok ; V = falsche_loesung )
    ;   length(Sols, K), V = loesungen(K)
    ).
