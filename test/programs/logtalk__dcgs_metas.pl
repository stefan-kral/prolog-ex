% aus Logtalk, examples/dcgs/metas.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
% list//2 aus dem Objekt library; das dortige phrase//2 (phrase/4) als
% call//2 eingesetzt, print//1 und print/0 weggelassen (schreiben nur).
:- set_prolog_flag(double_quotes, codes).

list(_, []) --> [].
list(X, [T|Ts]) --> call(X, T), list(X, Ts).

successors(Elements, Successors) :-
    phrase(list(next, Successors), Elements).

next(Next, [Element| Result], Result) :-
    Next is Element + 1.
