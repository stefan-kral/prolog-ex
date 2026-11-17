:- use_module(library(lists)).
:- use_module(library(pio)).
:- use_module(library(dcgs)).
:- use_module(library(format)).
:- use_module(library(charsio)).
lines([L|Ls]) --> line(L), !, lines(Ls).
lines([]) --> [].
line([C|Cs]) --> [C], { C \== '\n' }, !, line(Cs).
line([]) --> ['\n'].
run(F) :- open(F, read, S), loop(S), close(S).
loop(S) :- get_line_to_chars(S, L, []), ( L == [] -> true ; one(L), loop(S) ).
one(L0) :- ( append(L, ['\n'], L0) -> true ; L = L0 ), append(H, [' '|T], L), !,
    catch(( number_chars(X, T) -> true ; X = fail ), E, X = error(E)),
    format("~s ", [H]), ( X = error(error(F,_)) -> writeq(error(F)) ; write(X) ), nl.
