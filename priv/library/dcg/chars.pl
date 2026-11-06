/* library(dcg/chars): die Nichtterminale von SWIs library(dcg/basics),
   aber auf Zeichen statt Codes – passend zu double_quotes=chars,
   phrase_from_file/2 und library(dcgs). Wer Code aus SWI übernimmt: was
   dort eine Codeliste ist (digits//1, string//1, nonblanks//1, ...), ist
   hier eine Zeichenliste; integer//1, number//1, xdigit//1 usw. liefern
   wie dort Zahlen. Die Zeichenklassen sind die von code_type/2 (SWI).

     * Leerraum: blank//0, blanks//0, white//0, whites//0, blanks_to_nl//0
       (bis einschließlich Zeilenende oder Ende der Eingabe),
       nonblank//1, nonblanks//1.
     * Zahlen: digit//1, digits//1, integer//1, float//1, number//1,
       xdigit//1 (Wert), xdigits//1 (Werte), xinteger//1. integer, float,
       number, xinteger, csym und atom erzeugen auch, wenn das Argument
       gebunden ist.
     * Text: string//1 (kürzeste zuerst), string_without//2 (Ende als
       Zeichenliste oder Atom), remainder//1, eos//0, eol//0 (\n, \r\n
       oder Ende), alpha_to_lower//1, csym//1, csyms//1,
       prolog_symbol//1, atom//1 (nur erzeugen).
*/

:- module(dcg_chars,
          [ blank//0,
            blanks//0,
            nonblank//1,
            nonblanks//1,
            blanks_to_nl//0,
            white//0,
            whites//0,
            alpha_to_lower//1,
            digits//1,
            digit//1,
            integer//1,
            float//1,
            number//1,
            xdigits//1,
            xdigit//1,
            xinteger//1,
            prolog_symbol//1,
            csym//1,
            csyms//1,
            eol//0,
            eos//0,
            remainder//1,
            string//1,
            string_without//2,
            atom//1
          ]).

:- use_module(library(lists), [append/2, memberchk/2]).
:- use_module(library(error), [must_be/2]).
:- use_module(library(swi), [code_type/2]).

% C ist ein Zeichen der Klasse T (code_type/2)
ctype(C, T) :-
        atom(C),
        atom_length(C, 1),
        char_code(C, X),
        code_type(X, T).

% --- Leerraum -----------------------------------------------------------

blank --> [C], { ctype(C, space) }.

blanks --> blank, !, blanks.
blanks --> [].

white --> [C], { ctype(C, white) }.

whites --> white, !, whites.
whites --> [].

nonblank(C) --> [C], { ctype(C, graph) }.

nonblanks([H|T]) --> [H], { ctype(H, graph) }, !, nonblanks(T).
nonblanks([]) --> [].

blanks_to_nl --> ['\n'], !.
blanks_to_nl --> blank, !, blanks_to_nl.
blanks_to_nl --> eos.

alpha_to_lower(L) -->
        [C],
        { ctype(C, alpha),
          char_code(C, X),
          code_type(X, to_lower(Y)),
          char_code(L, Y) }.

% --- Zahlen -------------------------------------------------------------

digits([H|T]) --> digit(H), !, digits(T).
digits([]) --> [].

digit(C) --> [C], { ctype(C, digit(_)) }.

integer(I, Head, Tail) :-
        nonvar(I), !,
        format(chars(Head, Tail), "~d", [I]).
integer(I) -->
        int_chars(Cs),
        { number_from_chars(Cs, I) }.

int_chars([C,D0|D]) --> sign(C), !, digit(D0), digits(D).
int_chars([D0|D]) --> digit(D0), digits(D).

sign(-) --> [-].
sign(+) --> [+].

% number_chars/2 ohne führendes +
number_from_chars([+|Cs], N) :- !, number_chars(N, Cs).
number_from_chars(Cs, N) :- number_chars(N, Cs).

float(F, Head, Tail) :-
        float(F), !,
        format(chars(Head, Tail), "~w", [F]).
float(F) -->
        number(F),
        { float(F) }.

number(N, Head, Tail) :-
        number(N), !,
        format(chars(Head, Tail), "~w", [N]).
number(N) -->
        { var(N) }, !,
        int_chars(I),
        (   dot, digit(DF0), digits(DF)
        ->  { F = ['.',DF0|DF] }
        ;   { F = [] }
        ),
        (   exp
        ->  int_chars(DI),
            { E = [e|DI] }
        ;   { E = [] }
        ),
        { (   F == [], E \== []           % 1e10: ISO verlangt 1.0e10
          ->  F1 = ['.','0']
          ;   F1 = F
          ),
          append([I, F1, E], Cs),
          number_from_chars(Cs, N) }.

dot --> ['.'].

exp --> [e].
exp --> ['E'].

xinteger(Val, Head, Tail) :-
        integer(Val), !,
        format(chars(Head, Tail), "~16r", [Val]).
xinteger(Val) -->
        xdigit(D0),
        xdigits(D),
        { mkval([D0|D], 16, Val) }.

xdigits([D0|D]) --> xdigit(D0), !, xdigits(D).
xdigits([]) --> [].

xdigit(W) --> [C], { ctype(C, xdigit(W)) }.

mkval([W0|Weights], Base, Val) :-
        mkval(Weights, Base, W0, Val).

mkval([], _, W, W).
mkval([H|T], Base, W0, W) :-
        W1 is W0*Base+H,
        mkval(T, Base, W1, W).

% --- Text ---------------------------------------------------------------

eol --> ['\n'], !.
eol --> ['\r','\n'], !.
eol --> eos.

eos([], []).

remainder(List, List, []).

string([]) --> [].
string([H|T]) --> [H], string(T).

string_without(End, Cs) -->
        { end_chars(End, Not) },
        list_string_without(Not, Cs).

end_chars(End, Not) :-
        (   atom(End) -> atom_chars(End, Not)
        ;   must_be(list, End), Not = End
        ).

list_string_without(Not, [C|T]) -->
        [C],
        { \+ memberchk(C, Not) }, !,
        list_string_without(Not, T).
list_string_without(_, []) --> [].

csym(Name, Head, Tail) :-
        nonvar(Name), !,
        format(chars(Head, Tail), "~w", [Name]).
csym(Name) -->
        [F], { ctype(F, csymf) },
        csyms(Rest),
        { atom_chars(Name, [F|Rest]) }.

csyms([H|T]) --> [H], { ctype(H, csym) }, !, csyms(T).
csyms([]) --> [].

prolog_symbol(Name) -->
        [C], { symbol_char(C) },
        prolog_symbols(Rest),
        { atom_chars(Name, [C|Rest]) }.

prolog_symbols([H|T]) --> [H], { symbol_char(H) }, !, prolog_symbols(T).
prolog_symbols([]) --> [].

symbol_char(C) :-
        atom(C),
        memberchk(C, ['#','$','&','*','+','-','.','/',':','<','=','>','?','@','\\','^','~']).

atom(A, Head, Tail) :-
        (   ground(A) -> true
        ;   throw(error(instantiation_error, atom//1))
        ),
        format(chars(Head, Tail), "~w", [A]).
