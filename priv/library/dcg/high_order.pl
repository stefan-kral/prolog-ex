/* library(dcg/high_order) wie SWI-Prolog: Nichtterminale höherer Ordnung.
   Sie geben die Elemente nur weiter – ob die Liste aus Zeichen oder Codes
   besteht, ist ihnen gleich (anders als bei library(dcg/chars)).

     * sequence(:Element, ?List)//: null oder mehr Element, eines je Glied
       von List (call(Element, X)).
     * sequence(:Element, :Sep, ?List)//: wie oben, getrennt durch den
       DCG-Rumpf Sep (wie bei SWI wird ein Trenner am Ende mitgelesen:
       "1,2," gibt [1,2]; beim Erzeugen entsteht deshalb "1,2,").
     * sequence(:Start, :Element, :Sep, :End, ?List)//: dazu Anfang und Ende
       (deterministisch: erste vollständige Zerlegung).
     * optional(:Match, :Default)//: Match, sonst Default (je erste Lösung).
     * foreach(:Generator, :Element)//, foreach(:Generator, :Element, :Sep)//:
       für jede Lösung von Generator Element (eine Kopie), getrennt durch Sep.
*/

:- module(dcg_high_order,
          [ sequence//2,
            sequence//3,
            sequence//5,
            optional//2,
            foreach//2,
            foreach//3
          ]).

:- meta_predicate(sequence(3, ?, ?, ?)).
:- meta_predicate(sequence(3, //, ?, ?, ?)).
:- meta_predicate(sequence(//, 3, //, //, ?, ?, ?)).
:- meta_predicate(optional(//, //, ?, ?)).
:- meta_predicate(foreach(0, //, ?, ?)).
:- meta_predicate(foreach(0, //, //, ?, ?)).

sequence(OnElem, List) -->
        sequence_(List, OnElem).

sequence_([H|T], P) -->
        call(P, H),
        sequence_(T, P).
sequence_([], _) -->
        [].

sequence(OnElem, OnSep, List) -->
        sequence_(List, OnElem, OnSep).

sequence_([H|T], P, Sep) -->
        call(P, H),
        (   Sep
        ->  !,
            sequence_(T, P, Sep)
        ;   { T = [] }
        ).
sequence_([], _, _) -->
        [].

sequence(Start, OnElem, OnSep, End, List) -->
        Start,
        sequence_(List, OnElem, OnSep),
        End, !.

optional(Match, _Default) -->
        Match, !.
optional(_, Default) -->
        Default, !.

foreach(Generator, Element) -->
        foreach(Generator, Element, []).

foreach(Generator, Element, Sep) -->
        { findall(Element, Generator, Elements) },
        emit_list(Elements, Sep).

emit_list([], _) -->
        [].
emit_list([H|T], Sep) -->
        H,
        emit_list_(T, Sep).

emit_list_([], _) -->
        [].
emit_list_([H|T], Sep) -->
        Sep,
        H,
        emit_list_(T, Sep).
