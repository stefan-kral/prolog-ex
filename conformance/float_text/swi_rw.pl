% je Zeile "HEX Text": Text mit number_codes lesen, Ergebnis mit write
% ausgeben ("HEX Ausgabe" bzw. "HEX error(...)")
:- initialization(main, main).
main :- current_prolog_flag(argv, [In|_]), open(In, read, S), loop(S), close(S).
loop(S) :- read_line_to_codes(S, L), ( L == end_of_file -> true ; one(L), loop(S) ).
one(L) :- append(H, [0' |T], L), !,
    catch(( number_codes(X, T) -> true ; X = fail ), E, X = error(E)),
    format("~s ", [H]), ( X = error(error(F,_)) -> writeq(error(F)) ; write(X) ), nl.
