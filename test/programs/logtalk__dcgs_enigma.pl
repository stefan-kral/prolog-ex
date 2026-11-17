% aus Logtalk, examples/dcgs/enigma.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
:- set_prolog_flag(double_quotes, codes).

solve(Enigma, Message) :-
	phrase(message(Message), Enigma).

message([Word| Words]) --> separator, word(Chars), {atom_chars(Word, Chars), dictionary(Word)}, !, message(Words).
message([]) --> separator.

word([Char| Chars]) --> character(Char), word(Chars).
word([]) --> [].

separator --> " ", !, separator.
separator --> [].

character(a) --> "2".
character(b) --> "2".
character(c) --> "2".

character(d) --> "3".
character(e) --> "3".
character(f) --> "3".

character(g) --> "4".
character(h) --> "4".
character(i) --> "4".

character(j) --> "5".
character(k) --> "5".
character(l) --> "5".

character(m) --> "6".
character(n) --> "6".
character(o) --> "6".

character(p) --> "7".
character(q) --> "7".
character(r) --> "7".
character(s) --> "7".

character(t) --> "8".
character(u) --> "8".
character(v) --> "8".

character(w) --> "9".
character(x) --> "9".
character(y) --> "9".
character(z) --> "9".

dictionary(dinner).
dictionary(have).
dictionary(i).
dictionary(love).
dictionary(miss).
dictionary(much).
dictionary(me).
dictionary(you).
dictionary(so).
dictionary(to).
dictionary(tonight).
dictionary(with).
dictionary(would).
