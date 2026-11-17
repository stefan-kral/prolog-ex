% aus Logtalk, examples/dcgs/tokenizer.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
% char_type/2 heisst ctype/2 (SWI: eingebautes Praedikat).
:- set_prolog_flag(double_quotes, codes).

tokens(String, Tokens) :-
	phrase(token_list(Tokens), String).

% A token list is a series of zero or more tokens.
% Its argument consists of the list of tokens, as atoms and numbers.
% The cut ensures that the maximum number of characters is gathered into each token.

token_list([T| Rest]) --> blank0, token(T), !, token_list(Rest).
token_list([]) --> blank0.

% blank0 is a series of zero or more blanks.

blank0 --> [C], {ctype(C, blank)}, !, blank0.
blank0 --> [].

% Several kinds of tokens.
% This is where lists of characters get converted into atoms or numbers.

token(T) --> special(L), {atom_codes(T, L)}.
token(T) --> word(W), {atom_codes(T, W)}.
token(T) --> numeral(N), {number_codes(T, N)}.

% A word is a series of one or more letters.
% The rules are ordered so that we first try to gather as many
% characters into one digit_string as possible.

word([L| Rest]) --> letter(L), word(Rest).
word([L]) --> letter(L).

% A numeral is a list of characters that constitute a number.
% The argument of numeral(...) is the list of character codes.

numeral([C1, C2, C3| N]) --> ",", digit(C1), digit(C2), digit(C3), numeral(N).
numeral([C1, C2, C3]) --> ",", digit(C1), digit(C2), digit(C3).
% multiple digits
numeral([C| N]) --> digit(C), numeral(N).
% single digit
numeral([C]) --> digit(C).
% decimal point and more digits
numeral(N) --> decimal_part(N).

decimal_part([46| Rest]) --> ".", digit_string(Rest).

digit_string([D| N]) --> digit(D), digit_string(N).
digit_string([D]) --> digit(D).

% Various kinds of characters...

digit(C) --> [C], {ctype(C, numeric)}.

special([C]) --> [C], {ctype(C, special)}.

% Conversion to lowercase
letter(C) --> [C], {ctype(C, lowercase)}.
letter(C) --> [U], {ctype(U, uppercase), C is U + 32}.

% ctype(+Code, ?Type)
% Classifies a character (ASCII code) as blank, numeric, uppercase, lowercase, or special.
% Adapted from Covington 1994.

% blanks, other ctrl codes
ctype(Code, Type) :-
	Code =< 32,
	!,
	Type = blank.

% digits
ctype(Code, Type) :-
	48 =< Code, Code =< 57,
	!,
	Type = numeric.

% lowercase letters
ctype(Code, Type) :-
	97 =< Code, Code =< 122,
	!,
	Type = lowercase.

% uppercase letters
ctype(Code, Type) :-
	65 =< Code, Code =< 90,
	!,
	Type = uppercase.

% all others
ctype(_, special).
