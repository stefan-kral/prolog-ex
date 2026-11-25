% Scryer Prolog: Bibliotheken, die SICStus/SWI ohne Laden kennen,
% dynamic als Praefixoperator und name/2 (fehlen in Scryer). Verworfen: :- ensure_loaded/1 (dort keine
% Direktive; harness.pl laedt der Driver) und das SICStus-Flag
% single_var_warnings (chat_parser.pl; ein unbekanntes Flag bricht in
% Scryer das Laden ab)
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(format)).
:- use_module(library(time)).   % statistics/2

% :- dynamic p/1 (ohne Klammern; dynamic_unit_clause.pl)
:- op(1150, fx, dynamic).

term_expansion((:- ensure_loaded(harness)), []).
term_expansion((:- set_prolog_flag(single_var_warnings, _)), []).

name(X, Codes) :-
    var(X), !,
    (   catch(number_codes(X, Codes), _, fail) -> true
    ;   atom_codes(X, Codes)
    ).
name(X, Codes) :- number(X), !, number_codes(X, Codes).
name(X, Codes) :- atom_codes(X, Codes).

% format/2 nimmt in Scryer kein Atom als Formatangabe (harness.pl: bench/1)
term_expansion((bench(C) :- B0), (bench(C) :- B)) :- sb_fmt(B0, B), B0 \== B.

sb_fmt((A0, B0), (A, B)) :- !, sb_fmt(A0, A), sb_fmt(B0, B).
sb_fmt(format(F0, As), format(F, As)) :- atom(F0), !, atom_chars(F0, F).
sb_fmt(G, G).

% statistics(runtime, _) gibt in Scryer Millisekunden als Gleitkommazahl;
% harness.pl schreibt die Zeit mit ~d
term_expansion((cputime(T) :- statistics(runtime, [T, _])),
               (cputime(T) :- statistics(runtime, [T0, _]), T is round(T0))).
