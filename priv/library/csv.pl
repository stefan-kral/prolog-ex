/* Scryer Prologs library(csv) (Quelltext unverändert), für PrologEx
   ergänzt um die Prädikate von SWI-Prologs library(csv) am Ende der
   Datei (Kern in Elixir: PrologEx.Csv); die Namen überschneiden sich
   nicht. */

/** Predicates for parsing CSV data

## Read CSV files.

Only two options with default values:

- `token_separator(',')`
- `with_header(true)`

### Examples:

Parsing a CSV string:

```
?- use_module(library(csv)).
?- use_module(library(dcgs)).
?- phrase(parse_csv(Data), "col1,col2,col3,col4\none,2,,three").
   Data = frame(["col1","col2","col3","col4"],[["one",2,[],"three"]]).
```

With some options:

```
?- phrase(parse_csv(Data, [with_header(false), token_separator(';')]), "one;2;;three").
   Data = frame([],[["one",2,[],"three"]]).
```

Parsing a CSV file:

```
?- use_module(library(csv)).
?- use_module(library(pio)).
?- phrase_from_file(parse_csv(frame(Header, Rows)), './test.csv').
```

## Write CSV files

Four options with default values :

- `line_separator('\n')`
- `token_separator(',')`
- `with_header(true)`
- `null_value(empty)`

### Examples

Writing a CSV file:

```
?- use_module(library(csv)).
?- write_csv('./test.csv', frame(["col1","col2","col3","col4"], [["one",2,[],"three"]])).
```

With some options

```
?- use_module(library(csv)).
?- write_csv('./test.csv', frame(
      ["col1","col2","col3","col4"],
      [["one",2,[],"three"]]
    ),
    [with_header(false), line_separator('\r\n'), token_separator(';'), null_value('\\N')]).
```
*/

:- module(csv, [
  parse_csv//1,
  parse_csv//2,
  write_csv/2,
  write_csv/3,
  % SWI-Prolog (PrologEx)
  csv//1,
  csv//2,
  csv_read_file/2,
  csv_read_file/3,
  csv_read_stream/3,
  csv_read_file_row/3,
  csv_read_row/3,
  csv_options/2,
  csv_write_file/2,
  csv_write_file/3,
  csv_write_stream/3
]).

:- use_module(library(format)).
:- use_module(library(dcgs)).
:- use_module(library(iso_ext)).
:- use_module(library(lists)).
:- use_module(library(error)).


option(W, O) :-
  ( member(W, O) -> true
  ; throw(error(domain_error(csv_option, W), option/2))).


option_extends([], Opt, Opt).
option_extends([X | Y], Opt0, Opt) :-
  functor(X, Name, 1),
  F0 =.. [Name, _],
  ( select(F0, Opt0, R) ->
    option_extends(Y, [X | R], Opt)
  ; option_extends(Y, [X | Opt0], Opt) ).


%% -- write --


escaped_field([], []).
escaped_field(['"' | Y], ['"', '"' | R]) :-
  escaped_field(Y, R).
escaped_field([X | Y], [X | R]) :-
  X \== '"',
  escaped_field(Y, R).


ensure_escaped(Field, Field) :-
  (atom(Field); integer(Field); float(Field)).
ensure_escaped([X | Y], Field) :-
  escaped_field([X | Y], Field).


write_field(Out, Field, Opt) :-
  ( Field \== [] ->
    ensure_escaped(Field, Field0),
    format(Out, "~w", [Field0])
  ; option(null_value(Null_Value), Opt),
    ( Null_Value == empty -> true
    ; format(Out, "~w", [Null_Value]))).


write_row(Out, [Field], Opt) :-
  write_field(Out, Field, Opt).
write_row(Out, [Field, X | Y], Opt) :-
  write_field(Out, Field, Opt),
  option(token_separator(Tk_Sep), Opt),
  format(Out, "~w", [Tk_Sep]),
  write_row(Out, [X | Y], Opt).


write_rows(Out, [Row], Opt) :-
  write_row(Out, Row, Opt).
write_rows(Out, [Row, X | Y], Opt) :-
  option(line_separator(Line_Sep), Opt),
  write_row(Out, Row, Opt),
  format(Out, "~w", [Line_Sep]),
  write_rows(Out, [X | Y], Opt).


write_csv_(Out, frame(Header, Rows), Opt) :-
  option(with_header(With_Header), Opt),
  ( With_Header == true -> 
    write_row(Out, Header, Opt),
    option(line_separator(Line_Sep), Opt),
    format(Out, "~w", [Line_Sep])
  ; true),
  write_rows(Out, Rows, Opt).


write_csv(File_Name, Frm, Opt) :-
  option_extends(Opt, [
    null_value(empty),
    token_separator(','),
    with_header(true),
    line_separator('\n')
  ], Opt0),
  setup_call_cleanup(
    open(File_Name, write, Out),
    write_csv_(Out, Frm, Opt0),
    close(Out)).
write_csv(File_Name, Frm) :-
  write_csv(File_Name, Frm, []).


%% -- read --


tokens([], Opt), [Tk_Sep] -->
  { option(token_separator(Tk_Sep), Opt) },
  [Tk_Sep],
  !.
tokens([], _), "\r\n" -->
  "\r\n",
  !.
tokens([], _), "\n" -->
  "\n",
  !.
tokens([], _), "\r" -->
  "\r",
  !.
tokens([X | Y], Opt) -->
  [X],
  !,
  tokens(Y, Opt).
tokens([], _) --> [].


field(R, Opt) -->
  "\"",
  !,
  string_tokens(R, Opt).
field(R, Opt) -->
  tokens(R0, Opt),
  { R0 \== [],
    catch(number_chars(R, R0), _, R = R0)
  }.
field([], _) --> [].


string_tokens(R, Opt) -->
  [X],
  ( { X == '"' } ->
    ( "\"" ->
      { R = [X | Y] },
      string_tokens(Y, Opt)
    ; { R = [] })
  ; { R = [X | Y] },
    string_tokens(Y, Opt)).


end_token --> "\r\n".
end_token --> "\n".
end_token --> "\r".
end_token --> [].


separator(Opt) -->
    { option(token_separator(Tk_Sep), Opt) },
    [Tk_Sep].


row([X | Y], Opt) -->
  field(X, Opt),
  !,
  ( separator(Opt) ->
    row(Y, Opt)
  ; end_token,
    { Y = [] }).


rows(R, Opt) -->
  row(X, Opt),
  !,
  ( { X \== [[]] } ->
    rows(Y, Opt),
    { R = [X | Y] }
  ; { R = [] }).


parse_csv(frame(Header, Rows), Opt) --> 
  { option_extends(Opt, [
      with_header(true),
      token_separator(',')
    ], Opt0)
  },
  ( { option(with_header(With_Header), Opt0),
      With_Header == true } ->
    row(Header, Opt0),
    { Header \== [[]] },
    end_token
  ; { Header = [] }),
  rows(Rows, Opt0).
parse_csv(R) -->
  parse_csv(R, []).


%% =====================================================================
%% SWI-Prolog: csv//1,2, csv_read_file/2,3, csv_read_stream/3,
%% csv_read_file_row/3, csv_read_row/3, csv_options/2, csv_write_file/2,3,
%% csv_write_stream/3 (wie SWI 9; Zeilen row(A, B, ...), Felder als Atome
%% oder Zahlen). Optionen: separator(Code) (auch ein Zeichen), strip/1,
%% ignore_quotes/1, convert/1, case(down|preserve|up), functor/1, arity/1,
%% match_arity/1, skip_header(Präfix); bei Dateien mit Endung .tsv ist
%% der Trenner der Tab. Unterschied: der Text darf Codes oder Zeichen
%% sein, beim Schreiben ist ein Feld auch eine Zeichen- oder Codeliste.
%% =====================================================================

csv(Rows) -->
  csv(Rows, []).

csv(Rows, Options) -->
  { csv_make_options(Options, Record, _) },
  csv_roptions(Rows, Record).

% Schreiben (Rows ground), Lesen einer fertigen Liste in Elixir, sonst
% (faule Liste von phrase_from_file/2) als DCG
csv_roptions(Rows, Record, S0, S) :-
  ground(Rows),
  !,
  arg(1, Record, Sep),
  '$csv_emit'(Rows, Sep, Codes),
  append(Codes, S, S0).
csv_roptions(Rows, Record, S0, S) :-
  '$skip_list'(_, S0, T), T == [], ground(S0),
  !,
  '$csv_parse'(text(S0), Record, Rows),
  S = [].
csv_roptions(Rows, Record) -->
  csv_skip_header(Record),
  csv_data(Rows, Record).

csv_read_file(File, Rows) :-
  csv_read_file(File, Rows, []).

csv_read_file(File, Rows, Options) :-
  csv_default_separator(File, Options, Options1),
  csv_make_options(Options1, Record, _),
  setup_call_cleanup(
    open(File, read, In),
    '$csv_parse'(stream(In), Record, Rows),
    close(In)).

csv_read_stream(Stream, Rows, Options) :-
  csv_make_options(Options, Record, _),
  '$csv_parse'(stream(Stream), Record, Rows).

csv_read_file_row(File, Row, Options) :-
  csv_default_separator(File, Options, Options1),
  csv_make_options(Options1, Record, Options2),
  ( memberchk(line(Line), Options2) -> true ; true ),
  setup_call_cleanup(
    open(File, read, In),
    csv_read_stream_row(In, Row, Line, Record),
    close(In)).

csv_read_stream_row(In, Row, Line, Record) :-
  ( integer(Line) -> true ; csv_nat(1, Line) ),
  ( csv_read_row(In, Row0, Record),
    Row0 \== end_of_file
  -> Row = Row0
  ; !,
    fail ).

csv_nat(N, N).
csv_nat(N0, N) :- N1 is N0 + 1, csv_nat(N1, N).

csv_read_row(Stream, Row, Record0) :-
  ( is_list(Record0) -> csv_make_options(Record0, Record, _) ; Record = Record0 ),
  '$csv_read_record'(Stream, Record, Fields),
  ( Fields == end_of_file ->
    Row = end_of_file
  ; arg(6, Record, Functor),
    Row0 =.. [Functor|Fields],
    functor(Row0, _, Arity),
    csv_check_arity(Record, Arity),
    Row = Row0 ).

csv_options(Compiled, Options) :-
  csv_make_options(Options, Compiled, _).

csv_write_file(File, Data) :-
  csv_write_file(File, Data, []).

csv_write_file(File, Data, Options) :-
  must_be(list, Data),
  csv_default_separator(File, Options, Options1),
  csv_make_options(Options1, Record, _),
  arg(1, Record, Sep),
  setup_call_cleanup(
    open(File, write, Out),
    '$csv_write'(Out, Data, Sep),
    close(Out)).

csv_write_stream(Stream, Data, Options) :-
  must_be(list, Data),
  csv_make_options(Options, Record, _),
  arg(1, Record, Sep),
  '$csv_write'(Stream, Data, Sep).

% --- Optionen: csv_options(Trenner, Strip, IgnoreQuotes, Convert, Case,
%     Functor, Arity, MatchArity, SkipHeader) wie SWIs Record

csv_make_options(Options, Record, Rest) :-
  must_be(list, Options),
  Record = csv_options(Sep, Strip, IQ, Conv, Case, Fun, _Arity, MA, _Skip),
  csv_opts(Options, Record, Rest),
  csv_default(Sep, 0',),
  csv_default(Strip, false),
  csv_default(IQ, false),
  csv_default(Conv, true),
  csv_default(Case, preserve),
  csv_default(Fun, row),
  csv_default(MA, true).

csv_default(X, D) :- ( var(X) -> X = D ; true ).

csv_opts([], _, []).
csv_opts([O|Os], Record, Rest) :-
  ( nonvar(O), csv_opt(O, N, V) ->
    arg(N, Record, V0),
    ( var(V0) -> V0 = V ; true ),
    Rest = Rest1
  ; Rest = [O|Rest1] ),
  csv_opts(Os, Record, Rest1).

csv_opt(separator(S), 1, C) :-
  ( atom(S), atom_length(S, 1) -> char_code(S, C) ; must_be(integer, S), C = S ).
csv_opt(strip(B), 2, B) :- must_be(boolean, B).
csv_opt(ignore_quotes(B), 3, B) :- must_be(boolean, B).
csv_opt(convert(B), 4, B) :- must_be(boolean, B).
csv_opt(case(C), 5, C) :-
  ( memberchk(C, [down, preserve, up]) -> true
  ; must_be(atom, C), type_error(oneof([down, preserve, up]), C) ).
csv_opt(functor(F), 6, F) :- must_be(atom, F).
csv_opt(arity(A), 7, A) :- must_be(integer, A).
csv_opt(match_arity(B), 8, B) :- must_be(boolean, B).
csv_opt(skip_header(P), 9, P) :- must_be(atom, P).

csv_default_separator(File, Options0, Options) :-
  ( memberchk(separator(_), Options0) ->
    Options = Options0
  ; csv_file_ext(File, Ext),
    downcase_atom(Ext, Ext1),
    csv_ext_separator(Ext1, Sep) ->
    Options = [separator(Sep)|Options0]
  ; Options = Options0 ).

csv_file_ext(File, Ext) :-
  ( atom(File) -> atom_chars(File, Cs) ; Cs = File ),
  append(_, ['.'|E], Cs),
  \+ memberchk('.', E),
  \+ memberchk('/', E),
  !,
  atom_chars(Ext, E).

csv_ext_separator(csv, 0',).
csv_ext_separator(tsv, 0'\t).

csv_check_arity(Record, Arity) :-
  arg(7, Record, Arity),
  !.
csv_check_arity(Record, _) :-
  arg(8, Record, false),
  !.
csv_check_arity(Record, Arity) :-
  arg(7, Record, Expected),
  domain_error(row_arity(Expected), Arity).

% --- Lesen als DCG (faule Listen; Elemente Codes oder Zeichen)

csv_c(C) --> [X], { integer(X) -> C = X ; atom(X), char_code(X, C) }.

csv_eos([], []).

csv_skip_header(Record) -->
  { arg(9, Record, P), atom(P), atom_codes(P, Pc) },
  !,
  csv_skip_header_lines(Pc),
  csv_skip_blank_lines.
csv_skip_header(_) --> [].

csv_skip_header_lines(Pc) -->
  csv_prefix(Pc),
  !,
  ( csv_rest_of_line ->
    csv_skip_header_lines(Pc)
  ).
csv_skip_header_lines(_) --> [].

csv_rest_of_line --> csv_eor, !.
csv_rest_of_line --> [_], csv_rest_of_line.

csv_prefix([]) --> [].
csv_prefix([C|Cs]) --> csv_c(C), csv_prefix(Cs).

csv_skip_blank_lines --> csv_eos, !.
csv_skip_blank_lines --> csv_eor, !, csv_skip_blank_lines.
csv_skip_blank_lines --> [].

csv_data([], _) --> csv_eos, !.
csv_data([Row|More], Record) -->
  csv_row(Row, Record),
  !,
  csv_data(More, Record).

csv_row(Row, Record) -->
  csv_fields(Fields, Record),
  { arg(6, Record, Functor),
    Row =.. [Functor|Fields],
    functor(Row, _, Arity),
    csv_check_arity(Record, Arity) }.

csv_fields([F|T], Record) -->
  csv_field(F, Record),
  ( csv_sep(Record) ->
    csv_fields(T, Record)
  ; csv_eor ->
    { T = [] } ).

csv_field(Value, Record) -->
  csv_c(0'"),
  { arg(3, Record, false) },
  !,
  csv_string_codes(Codes),
  { '$csv_value'(Codes, Record, Value) }.
csv_field(Value, Record) -->
  { arg(2, Record, true) },
  !,
  csv_ws,
  { arg(1, Record, Sep) },
  csv_field_codes(Codes0, Sep),
  { csv_strip_trailing(Codes0, Codes),
    '$csv_value'(Codes, Record, Value) }.
csv_field(Value, Record) -->
  { arg(1, Record, Sep) },
  csv_field_codes(Codes, Sep),
  { '$csv_value'(Codes, Record, Value) }.

csv_ws --> csv_c(0' ), !, csv_ws.
csv_ws --> csv_c(0'\t), !, csv_ws.
csv_ws --> [].

csv_strip_trailing(Codes0, Codes) :-
  append(Codes, WS, Codes0),
  csv_all_ws(WS),
  !.

csv_all_ws([]).
csv_all_ws([C|Cs]) :- memberchk(C, [0' , 0'\t]), csv_all_ws(Cs).

csv_string_codes(List) -->
  csv_c(H),
  ( { H == 0'" } ->
    ( csv_c(0'") ->
      { List = [H|T] },
      csv_string_codes(T)
    ; { List = [] } )
  ; { List = [H|T] },
    csv_string_codes(T) ).

csv_field_codes([], Sep), [Sep] --> csv_c(Sep), !.
csv_field_codes([], _), [0'\n] --> csv_c(0'\r), csv_c(0'\n), !.
csv_field_codes([], _), [0'\n] --> csv_c(0'\n), !.
csv_field_codes([], _), [0'\n] --> csv_c(0'\r), !.
csv_field_codes([H|T], Sep) --> csv_c(H), !, csv_field_codes(T, Sep).
csv_field_codes([], _) --> [].

csv_sep(Record) --> { arg(1, Record, Sep) }, csv_c(Sep).

csv_eor --> csv_c(0'\n).
csv_eor --> csv_c(0'\r), csv_c(0'\n).
csv_eor --> csv_c(0'\r).
csv_eor --> csv_eos.
