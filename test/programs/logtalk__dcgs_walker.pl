% aus Logtalk, examples/dcgs/walker.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
:- set_prolog_flag(double_quotes, codes).

walk(Moves, Ending) :-
	phrase(walk(Ending), Moves).

walk(Ending) -->
	moves((0, 0), Ending).

moves(Start, Ending) -->
	move(Start, Temp), moves(Temp, Ending).
moves(Ending, Ending) -->
	[].

move((X0, Y0), (X, Y)) --> [ n(S)], {X is X0, Y is Y0 + S}.
move((X0, Y0), (X, Y)) --> [ne(S)], {X is X0 + S / sqrt(2), Y is Y0 + S / sqrt(2)}.
move((X0, Y0), (X, Y)) --> [ e(S)], {X is X0 + S, Y = Y0}.
move((X0, Y0), (X, Y)) --> [se(S)], {X is X0 + S / sqrt(2), Y is Y0 - S / sqrt(2)}.
move((X0, Y0), (X, Y)) --> [ s(S)], {X is X0, Y is Y0 - S}.
move((X0, Y0), (X, Y)) --> [sw(S)], {X is X0 - S / sqrt(2), Y is Y0 - S / sqrt(2)}.
move((X0, Y0), (X, Y)) --> [ w(S)], {X is X0 - S, Y = Y0}.
move((X0, Y0), (X, Y)) --> [nw(S)], {X is X0 - S / sqrt(2), Y is Y0 + S / sqrt(2)}.
