% aus Logtalk, examples/dcgs/sentences.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
% Kategorien (determiners, nouns, verbs) zusammengelegt, ::NT -> NT.
:- set_prolog_flag(double_quotes, codes).

% private category non-terminals become private
% non-terminals of the objects importing the category

determiner --> [the].
determiner --> [a].

noun --> [boy].
noun --> [girl].

verb --> [likes].
verb --> [hates].


parse(List, true) :-
	phrase(sentence, List).
parse(_, false).

sentence --> noun_phrase, verb_phrase.

% the /1 control construct is used to call grammar
% rules encapsulated on the imported categories
noun_phrase --> determiner, noun.
noun_phrase --> noun.

verb_phrase --> verb.
verb_phrase --> verb, noun_phrase.
