/* library(dcgs) aus Scryer Prolog (src/lib/dcgs.pl; BSD-Lizenz, siehe
   SCRYER-LICENSE): die Nichtterminale seq//1, seqq//1 und ...//0.

   phrase/2,3 und die DCG-Übersetzung sind bei PrologEx eingebaut (und
   unterscheiden sich von Scryers: \+ und -> sind im Rumpf erlaubt, wie in
   SWI und dem Entwurf des DCG-Standards); phrase/2,3 stehen hier nur in der
   Exportliste (die eingebauten gelten).

   phrase//2 und phrase//3 (phrase/4,5) wie Scryer: phrase(G, A) als
   Nichtterminal ist G mit dem zusätzlichen Argument A (wie call//N), etwa
   phrase(seq, Xs) für seq(Xs).
*/

/** Support for Definite Clause Grammars.

A Prolog definite clause grammar (DCG) describes a sequence. Operationally, DCGs
can be used to parse, generate, complete and check sequences manifested as lists.

Check [The Power of Prolog chapter on DCGs](https://www.metalevel.at/prolog/dcg)
to learn more about them.
*/

:- module(dcgs,
          [phrase/2,
           phrase/3,
           phrase//2,
           phrase//3,
           call_dcg/3,
           seq//1,
           seqq//1,
           ... //0
          ]).

:- use_module(library(lists), [append/3]).

% G läuft im Modul des Aufrufers (wie Scryer)
:- meta_predicate(phrase(3, ?, ?, ?)).
:- meta_predicate(phrase(4, ?, ?, ?, ?)).
:- meta_predicate(call_dcg(//, ?, ?)).

%% call_dcg(:Body, ?S0, ?S) wie SWI: den DCG-Rumpf Body über S0/S
%  aufrufen. Bei PrologEx dasselbe wie phrase/3 (das S0 und S ebenfalls
%  nicht als Listen prüft).
call_dcg(G, S0, S) :-
        phrase(G, S0, S).

%% seq(Seq)//
%
% Describes a sequence
seq(Xs, Cs0,Cs) :-
   var(Xs),
   Cs0 == [],
   !,
   Xs = [],
   Cs0 = Cs.
phrase(G, A, S0, S) :-
        phrase_args(G, [A], G1),
        phrase(G1, S0, S).

phrase(G, A1, A2, S0, S) :-
        phrase_args(G, [A1,A2], G1),
        phrase(G1, S0, S).

% G um Argumente erweitert (auch M:G); ungebunden: instantiation_error
phrase_args(G, _, _) :-
        var(G), !,
        throw(error(instantiation_error, phrase/4)).
phrase_args(M:G, As, M:G1) :- !,
        phrase_args(G, As, G1).
phrase_args(G, As, G1) :-
        (   callable(G) -> true
        ;   throw(error(type_error(callable, G), phrase/4))
        ),
        G =.. L0,
        append(L0, As, L),
        G1 =.. L.

seq([]) --> [].
seq([E|Es]) --> [E], seq(Es).

%% seqq(SeqOfSeqs)//
%
% Describes a sequence of sequences
seqq([]) --> [].
seqq([Es|Ess]) --> seq(Es), seqq(Ess).

%% ...//
%
% Describes an arbitrary number of elements
...(Cs0,Cs) :-
   Cs0 == [],
   !,
   Cs0 = Cs.
... --> [] | [_], ... .
