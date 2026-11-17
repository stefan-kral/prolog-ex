% aus Logtalk, examples/dcgs/morse.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
:- set_prolog_flag(double_quotes, codes).

morse([Word| Words]) --> word(Characters), {atom_chars(Word, Characters)}, "  ", morse(Words).
morse([Word]) --> word(Characters), {atom_chars(Word, Characters)}.

word([Character| Characters]) --> symbols(Symbols), {atom_chars(Atom, Symbols), character(Atom, Character)}, " ", word(Characters).
word([Character]) --> symbols(Symbols), {atom_chars(Atom, Symbols), character(Atom, Character)}.

symbols([Symbol| Symbols]) --> symbol(Symbol), symbols(Symbols).
symbols([Symbol]) --> symbol(Symbol).

symbol('.') --> ".".
symbol('-') --> "-".

character('.-',   a).
character('-...', b).
character('-.-.', c).
character('-..',  d).
character('.',    e).
character('..-.', f).
character('--.',  g).
character('....', h).
character('..',   i).
character('.---', j).
character('-.-',  k).
character('.-..', l).
character('--',   m).
character('-.',   n).
character('---',  o).
character('.--.', p).
character('--.-', q).
character('.-.',  r).
character('...',  s).
character('-',    t).
character('..-',  u).
character('...-', v).
character('.--',  w).
character('-..-', x).
character('-.--', y).
character('--..', z).

character('.----', '1').
character('..---', '2').
character('...--', '3').
character('....-', '4').
character('.....', '5').
character('-....', '6').
character('--...', '7').
character('---..', '8').
character('----.', '9').
character('-----', '0').

character('.-.-.-',  '.').
character('--..--',  ',').
character('..--..',  '?').
character('.----.', '''').
character('-.-.--',  '!').
character('-..-.',   '/').
character('-.--.',   '(').
character('-.--.-',  ')').
character('.-...',   '&').
character('---...',  ':').
character('-.-.-.',  ';').
character('-...-',   '=').
character('.-.-.',   '+').
character('-....-',  '-').
character('..--.-',  '_').
character('.-..-.',  '"').
character('...-..-', '$').
character('.--.-',   '@').
