/*  JSON wie SWI-Prologs library(http/json), klassische Darstellung (ohne
    Dicts): Objekt json([Name=Wert, ...]), Array als Liste, String als
    Atom, true/false/null als @(true), @(false), @(null). Lesen und
    Schreiben in Elixir (PrologEx.Json), mit SWIs Verhalten (9.0.4) und
    Layout; siehe dort.

    Anders als SWI: ohne eigenen Stringtyp liefert value_string_as(string)
    bzw. as(string) eine Zeichen- oder Codeliste nach dem Flag
    double_quotes; dazu value_string_as(codes) und value_string_as(chars).
*/

:- module(json, [ json_read/2, json_read/3,
                  json_write/2, json_write/3,
                  atom_json_term/3,
                  is_json_term/1, is_json_term/2 ]).

:- use_module(library(error)).
:- use_module(library(lists)).

%!  json_read(+Stream, -Term) is det.
%!  json_read(+Stream, -Term, +Options) is det.
%
%   Den nächsten JSON-Wert von Stream lesen. Optionen: null(T), true(T),
%   false(T), end_of_file(Action), value_string_as(Type).
json_read(Stream, Term) :-
    '$json_read'(Stream, Term, []).
json_read(Stream, Term, Options) :-
    '$json_read'(Stream, Term, Options).

%!  json_write(+Stream, +Term) is det.
%!  json_write(+Stream, +Term, +Options) is det.
%
%   Term als JSON schreiben. Optionen: width(W), step(S), tab(T),
%   indent(I), serialize_unknown(Bool), null(T), true(T), false(T).
json_write(Stream, Term) :-
    '$json_write'(Stream, Term, []).
json_write(Stream, Term, Options) :-
    '$json_write'(Stream, Term, Options).

%!  atom_json_term(?Atom, ?Term, +Options) is det.
%
%   Atom (auch Code- oder Zeichenliste) als JSON lesen, oder – ist Atom
%   ungebunden – Term als JSON-Text schreiben (Option as(Type): atom,
%   string, codes, chars).
atom_json_term(Atom, Term, Options) :-
    ground(Atom),
    !,
    '$json_read_text'(Atom, Term, Options).
atom_json_term(Result, Term, Options) :-
    (   memberchk(as(Type), Options)
    ->  true
    ;   Type = atom
    ),
    (   var(Type)
    ->  instantiation_error(Type)
    ;   memberchk(Type, [atom,string,codes,chars])
    ->  true
    ;   type_error(oneof([atom,string,codes,chars]), Type)
    ),
    '$json_write_text'(Term, Type, Result, Options).

%!  is_json_term(@Term) is semidet.
%!  is_json_term(@Term, +Options) is semidet.
%
%   Term ist ein JSON-Term (true/false/null nach den Optionen).
is_json_term(Term) :-
    is_json_term2([], Term).
is_json_term(Term, Options) :-
    is_json_term2(Options, Term).

is_json_term2(_, Var) :-
    var(Var), !, fail.
is_json_term2(Options, json(Pairs)) :-
    !,
    '$skip_list'(_, Pairs, T), T == [],
    is_json_pairs(Pairs, Options).
is_json_term2(Options, List) :-
    '$skip_list'(_, List, T), T == [],
    !,
    is_json_list(List, Options).
is_json_term2(_, Primitive) :-
    atomic(Primitive),
    !.
is_json_term2(Options, Term) :-
    json_constant(true, Options, Term).
is_json_term2(Options, Term) :-
    json_constant(false, Options, Term).
is_json_term2(Options, Term) :-
    json_constant(null, Options, Term).

json_constant(Name, Options, Term) :-
    Opt =.. [Name, C],
    (   memberchk(Opt, Options)
    ->  true
    ;   C = @(Name)
    ),
    Term = C.

is_json_list([], _).
is_json_list([H|T], Options) :-
    is_json_term2(Options, H),
    is_json_list(T, Options).

is_json_pairs([], _).
is_json_pairs([P|Ps], Options) :-
    nonvar(P),
    P = (Name=Value),
    atom(Name),
    is_json_term2(Options, Value),
    is_json_pairs(Ps, Options).
