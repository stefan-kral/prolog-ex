/* library(pcre) für PrologEx: reguläre Ausdrücke wie in SWI-Prolog

   Schnittstelle nach SWI-Prologs library(pcre) (Jan Wielemaker, Peter
   Ludemann); die Arbeit macht Erlangs :re (ab OTP 28 PCRE2), siehe
   PrologEx.Builtins.Pcre. Abweichungen von SWI:
     - eine kompilierte Regex ist der Term '$regex'(Muster, Optionen)
       (statt eines Blobs), das Kompilat liegt in einem Cache;
     - statt eines Dicts eine Paarliste [0-Text, Name-Wert, ...]: 0, dann
       nicht benannte Gruppen nach Nummer, dann benannte nach Name; nicht
       gesetzte Gruppen fehlen;
     - der Ergebnistyp string ist die Textart des Subjekts (Atom, Zeichen-
       oder Codeliste), dazu atom, chars, codes, range, term;
     - unbekannte Optionen sind domain_error(re_option, O).
*/

:- module(pcre, [
    re_match/2, re_match/3, re_matchsub/3, re_matchsub/4, re_foldl/6,
    re_split/3, re_split/4, re_replace/4, re_replace/5, re_compile/3,
    re_flush/0, re_config/1
]).

:- use_module(library(lists)).
:- use_module(library(apply)).

:- meta_predicate(re_foldl(3, ?, ?, ?, ?, ?)).

%% re_match(+Regex, +Text), re_match(+Regex, +Text, +Options)
re_match(Re, Text) :-
    '$re_match'(Re, Text, []).
re_match(Re, Text, Options) :-
    '$re_match'(Re, Text, Options).

%% re_matchsub(+Regex, +Text, -Sub), re_matchsub(+Regex, +Text, -Sub, +Options)
re_matchsub(Re, Text, Sub) :-
    '$re_matchsub'(Re, Text, [], Sub).
re_matchsub(Re, Text, Sub, Options) :-
    '$re_matchsub'(Re, Text, Options, Sub).

%% re_foldl(:Goal, +Regex, +Text, ?V0, ?V, +Options): call(Goal, Sub, V0, V1)
%% für jeden Treffer
re_foldl(Goal, Re, Text, V0, V, Options) :-
    '$re_matches'(Re, Text, Options, Subs),
    foldl(Goal, Subs, V0, V).

%% re_split(+Pattern, +Text, -Splits), re_split(+Pattern, +Text, -Splits, +Options)
re_split(Re, Text, Splits) :-
    '$re_split'(Re, Text, [], Splits).
re_split(Re, Text, Splits, Options) :-
    '$re_split'(Re, Text, Options, Splits).

%% re_replace(+Pattern, +With, +Text, -New), re_replace/5 mit Optionen
re_replace(Re, With, Text, New) :-
    '$re_replace'(Re, With, Text, [], New).
re_replace(Re, With, Text, New, Options) :-
    '$re_replace'(Re, With, Text, Options, New).

%% re_compile(+Pattern, -Regex, +Options)
re_compile(Pattern, Regex, Options) :-
    '$re_compile'(Pattern, Options, Regex).

%% re_flush: den Cache der Kompilate leeren
re_flush :-
    '$re_flush'.

%% re_config(?Term): version(V), unicode(B), utf8(B), unicode_properties(B), jit(B)
re_config(Term) :-
    '$re_config'(Terms),
    member(Term, Terms).
