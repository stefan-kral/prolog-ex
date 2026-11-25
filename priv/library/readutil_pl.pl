% library(readutil_pl): Zeilen, Streams und Dateien lesen wie SWI-Prologs
% library(readutil) – in reinem Prolog, Aufbau wie dessen Prolog-Fassung
% (Zeichen für Zeichen über get_code/2). Dieselbe Bibliothek in Elixir:
% library(readutil). Statt read_line_to_string/2 und
% read_file_to_string/3 (PrologEx kennt keine Strings):
% read_line_to_chars/2 und read_file_to_chars/3 (Zeichenlisten).
%
%   read_line_to_codes(+S, -Codes)       ohne \n, jedes \r fällt weg;
%                                        am Ende end_of_file
%   read_line_to_codes(+S, -Codes, ?R)   Differenzliste, \n bleibt; am
%                                        Ende Codes = R = []
%   read_line_to_chars(+S, -Chars)       ohne \n, \r an den Enden fällt
%                                        weg; am Ende end_of_file
%   read_stream_to_codes(+S, -Codes [, ?R])
%   read_file_to_codes(+F, -Codes, +Os)  Option tail(T)
%   read_file_to_chars(+F, -Chars, +Os)
%   read_file_to_terms(+F, -Terme, +Os)  Option tail(T), dazu Optionen von
%                                        read_term/3; andere übergangen

:- module(readutil_pl, [read_line_to_codes/2, read_line_to_codes/3,
                        read_line_to_chars/2,
                        read_stream_to_codes/2, read_stream_to_codes/3,
                        read_file_to_codes/3, read_file_to_chars/3,
                        read_file_to_terms/3]).

:- use_module(library(lists)).

% --- Zeilen -----------------------------------------------------------------

read_line_to_codes(Stream, Codes) :-
    get_code(Stream, C0),
    (   C0 == -1
    ->  Codes0 = end_of_file
    ;   line_codes(C0, Stream, Codes0)
    ),
    Codes = Codes0.

line_codes(-1, _, []) :- !.
line_codes(10, _, []) :- !.
line_codes(13, Stream, L) :-
    !,
    get_code(Stream, C),
    line_codes(C, Stream, L).
line_codes(C, Stream, [C|T]) :-
    get_code(Stream, C2),
    line_codes(C2, Stream, T).

read_line_to_codes(Stream, Codes, Tail) :-
    get_code(Stream, C0),
    line_codes(C0, Stream, Codes0, Tail),
    Codes = Codes0.

line_codes(-1, _, Tail, Tail) :- !, Tail = [].
line_codes(10, _, [10|Tail], Tail) :- !.
line_codes(C, Stream, [C|T], Tail) :-
    get_code(Stream, C2),
    line_codes(C2, Stream, T, Tail).

% wie read_line_to_string/2: \r an den Enden fällt weg, end_of_file nur,
% wenn am Ende nichts mehr gelesen wurde
read_line_to_chars(Stream, Chars) :-
    get_char(Stream, C0),
    (   C0 == end_of_file
    ->  Chars0 = end_of_file
    ;   line_chars(C0, Stream, Cs),
        trim_cr(Cs, Chars0)
    ),
    Chars = Chars0.

line_chars(end_of_file, _, []) :- !.
line_chars('\n', _, []) :- !.
line_chars(C, Stream, [C|T]) :-
    get_char(Stream, C2),
    line_chars(C2, Stream, T).

trim_cr(Cs0, Cs) :-
    drop_cr(Cs0, Cs1),
    reverse(Cs1, R0),
    drop_cr(R0, R1),
    reverse(R1, Cs).

drop_cr(['\r'|Cs0], Cs) :- !, drop_cr(Cs0, Cs).
drop_cr(Cs, Cs).

% --- Streams ------------------------------------------------------------------

read_stream_to_codes(Stream, Codes) :-
    read_stream_to_codes(Stream, Codes, []).

read_stream_to_codes(Stream, Codes, Tail) :-
    get_code(Stream, C0),
    stream_codes(C0, Stream, Codes0, Tail),
    Codes = Codes0.

stream_codes(-1, _, Tail, Tail) :- !.
stream_codes(C, Stream, [C|T], Tail) :-
    get_code(Stream, C2),
    stream_codes(C2, Stream, T, Tail).

% --- Dateien ------------------------------------------------------------------

read_file_to_codes(Spec, Codes, Options) :-
    split_options(Options, Tail, _),
    setup_call_cleanup(open(Spec, read, S),
                       read_stream_to_codes(S, Codes, Tail),
                       close(S)).

read_file_to_chars(Spec, Chars, Options) :-
    split_options(Options, _, _),
    setup_call_cleanup(open(Spec, read, S),
                       stream_chars(S, Chars),
                       close(S)).

stream_chars(S, Cs) :-
    get_char(S, C),
    (   C == end_of_file
    ->  Cs = []
    ;   Cs = [C|Cs1],
        stream_chars(S, Cs1)
    ).

read_file_to_terms(Spec, Terms, Options) :-
    split_options(Options, Tail, ReadOptions),
    setup_call_cleanup(open(Spec, read, S),
                       stream_terms(S, Terms, Tail, ReadOptions),
                       close(S)).

stream_terms(S, Ts, Tail, Os) :-
    read_term(S, T, Os),
    (   T == end_of_file
    ->  Ts = Tail
    ;   Ts = [T|Ts1],
        stream_terms(S, Ts1, Tail, Os)
    ).

% tail(T) heraus (sonst []), die Optionen von read_term/3; der Rest
% (absolute_file_name/3, open/4 in SWI) wird übergangen
split_options(Options, Tail, ReadOptions) :-
    must_be_list(Options),
    (   memberchk(tail(T), Options) -> Tail = T ; Tail = [] ),
    findall(O, (member(O, Options), read_option(O)), ReadOptions0),
    ReadOptions = ReadOptions0.

% (findall/3 kopiert: Ausgabeoptionen wie variable_names(Vs) müssen die
% Variablen des Aufrufers behalten)
read_option(O) :-
    compound(O),
    functor(O, N, 1),
    memberchk(N, [variables, variable_names, singletons, syntax_errors,
                  double_quotes, back_quotes, module, term_position,
                  subterm_positions, comments]).

must_be_list(L) :-
    '$skip_list'(_, L, T),
    (   T == []
    ->  true
    ;   var(T)
    ->  throw(error(instantiation_error, _))
    ;   throw(error(type_error(list, L), _))
    ).
