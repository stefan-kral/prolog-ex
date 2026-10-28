/* library(dcgs) aus Scryer Prolog (src/lib/dcgs.pl; BSD-Lizenz, siehe
   SCRYER-LICENSE): die Nichtterminale seq//1, seqq//1 und ...//0.

   phrase/2,3 und die DCG-Übersetzung sind bei PrologEx eingebaut (und
   unterscheiden sich von Scryers: \+ und -> sind im Rumpf erlaubt, wie in
   SWI und dem Entwurf des DCG-Standards); phrase/2,3 stehen hier nur in der
   Exportliste (die eingebauten gelten).
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
           seq//1,
           seqq//1,
           ... //0
          ]).

%% seq(Seq)//
%
% Describes a sequence
seq(Xs, Cs0,Cs) :-
   var(Xs),
   Cs0 == [],
   !,
   Xs = [],
   Cs0 = Cs.
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
