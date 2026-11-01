/* library(commalist) für PrologEx (Schnittstelle nach XSB Prolog)

   Eine Commaliste ist ein Term aus ','/2, etwa ein Klauselrumpf. Ihre
   Elemente sind die Blätter des ','-Baums von links nach rechts, gleich
   wie er geschachtelt ist: (A,(B,C),D), ((A,B),C,D) und (A,B,C,D) haben
   dieselben Elemente [A,B,C,D]. Jeder andere Term ist ein Element, auch
   eine Variable als Blatt; ein Nicht-Komma-Term ist also eine
   Commaliste der Länge 1. Ist die ganze Commaliste eine Variable, gibt es
   instantiation_error: Bäume werden nicht aufgezählt (dafür length/2 und
   nonemptylist_to_commalist/2).

   Achtung: Variablen als Elemente machen das nicht monoton:
   commalist_to_list((A,b), L) gibt [A,b], nach A = (x,y) aber [x,y,b].

   Erzeugte Commalisten sind rechts geschachtelt, wie ein gelesenes
   (a,b,c). Leere Commalisten gibt es nicht.
*/

:- module(commalist, [
    commalist_to_list/2, nonemptylist_to_commalist/2, commalist_append/3,
    commalist_length/2, commalist_member/2, commalist_memberchk/2
]).

:- use_module(library(error)).

%% commalist_to_list(+C, ?L): L sind die Elemente von C
commalist_to_list(C, L) :-
    must_be_commalist(C, commalist_to_list/2),
    elements(C, L0, []),
    L = L0.

%% nonemptylist_to_commalist(+L, ?C): C ist (E1,(E2,...)) aus der echten,
%% nicht-leeren Liste L; [] ist domain_error(non_empty_list, [])
nonemptylist_to_commalist(L, C) :-
    '$skip_list'(_, L, Rest),
    (   Rest == [] -> true
    ;   var(Rest) -> instantiation_error(nonemptylist_to_commalist/2)
    ;   type_error(list, L, nonemptylist_to_commalist/2)
    ),
    (   L = [X|Xs] -> nest(Xs, X, C0), C = C0
    ;   domain_error(non_empty_list, L, nonemptylist_to_commalist/2)
    ).

%% commalist_append(+A, +B, ?C): C hat die Elemente von A, dann die von B
commalist_append(A, B, C) :-
    must_be_commalist(A, commalist_append/3),
    must_be_commalist(B, commalist_append/3),
    elements(A, [X|Xs], Mid),
    elements(B, Mid, []),
    nest(Xs, X, C0),
    C = C0.

%% commalist_length(+C, ?N): C hat N Elemente
commalist_length(C, N) :-
    must_be_commalist(C, commalist_length/2),
    (   var(N) -> true
    ;   integer(N) ->
        (   N >= 0 -> true
        ;   domain_error(not_less_than_zero, N, commalist_length/2)
        )
    ;   type_error(integer, N, commalist_length/2)
    ),
    count(C, 0, N0),
    N = N0.

%% commalist_member(?X, +C): X ist ein Element von C
commalist_member(X, C) :-
    must_be_commalist(C, commalist_member/2),
    member_(C, X).

%% commalist_memberchk(?X, +C): das erste Element von C, das sich mit X
%% unifizieren lässt
commalist_memberchk(X, C) :-
    must_be_commalist(C, commalist_memberchk/2),
    once(member_(C, X)).

% --- intern -------------------------------------------------------------

must_be_commalist(C, Ctx) :-
    (   var(C) -> instantiation_error(Ctx)
    ;   true
    ).

% Elemente als Differenzliste
elements(C, L0, L) :-
    (   nonvar(C), C = (A,B) ->
        elements(A, L0, L1),
        elements(B, L1, L)
    ;   L0 = [C|L]
    ).

nest([], X, X).
nest([Y|Ys], X, (X,C)) :-
    nest(Ys, Y, C).

count(C, N0, N) :-
    (   nonvar(C), C = (A,B) ->
        count(A, N0, N1),
        count(B, N1, N)
    ;   N is N0 + 1
    ).

member_(C, X) :-
    (   nonvar(C), C = (A,B) ->
        (   member_(A, X)
        ;   member_(B, X)
        )
    ;   X = C
    ).
