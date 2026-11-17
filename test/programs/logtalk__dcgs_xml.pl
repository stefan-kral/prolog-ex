% aus Logtalk, examples/dcgs/xml.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
:- set_prolog_flag(double_quotes, codes).

convert(Term, Interpretation, XML) :-
	var(XML) ->
		phrase(term(Term, Interpretation), List),
		atom_codes(XML, List)
		;
		atom_codes(XML, List),
		phrase(term(Term, Interpretation), List).

term(Term, Interpretation) -->
	{	nonvar(Term), nonvar(Interpretation),
		Interpretation =.. [Functor| Tags], Term =.. [Functor| Args]
	},
	open_tag(Functor),
	arguments(Tags, Args),
	close_tag(Functor).
term(Term, Interpretation) -->
	{var(Term), var(Interpretation)},
	open_tag(Functor),
	arguments(Tags, Args),
	close_tag(Functor),
	{Interpretation =.. [Functor| Tags], Term =.. [Functor| Args]}.

arguments([], []) -->
	[].
arguments([Tag| Tags], [Arg| Args]) -->
	open_tag(Tag),
	value(Arg),
	close_tag(Tag),
	arguments(Tags, Args).

open_tag(Tag) -->
	"<", value(Tag), ">".

close_tag(Tag) -->
	"</", value(Tag), ">".

value(Value) -->
	{nonvar(Value), atom_codes(Value, Codes)}, characters(Codes).
value(Value) -->
	{var(Value)}, characters(Codes), {atom_codes(Value, Codes)}.

characters([]) --> [].
characters([Code| Codes]) --> [Code], {character(Code)}, characters(Codes).

character(Code) :- Code >= 0'a, Code =< 0'z, !.
character(Code) :- Code >= 0'A, Code =< 0'Z.
