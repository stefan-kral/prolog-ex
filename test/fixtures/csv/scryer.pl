:- use_module(library(csv)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(iso_ext)).
:- use_module(library(format)).
:- use_module(library(pio)).
c("col1,col2,col3,col4\none,2,,three", []).
c("one;2;;three", [with_header(false), token_separator(';')]).
c("a,b\n\"x,y\",\"q\"\"q\"\r\n3.5, 7\n", []).
c("a\n", []).
c("", []).
c("h1,h2\n1,2\n\n3,4\n", []).
t(S, O) :- ( catch(phrase(parse_csv(D, O), S), E, (write(err(E)), nl, fail)) -> write_canonical(D), nl ; write(fail), nl ).
go :- forall(c(S, O), t(S, O)),
  F = "@DIR@/s.csv",
  write_csv(F, frame(["col1","col2","col3","col4"], [["one",2,[],"three"], ["a\"b", 1.5, x, []]])),
  phrase_from_file(parse_csv(Fr), F), write_canonical(Fr), nl,
  write_csv(F, frame([], [["one",2,[],"three"]]), [with_header(false), line_separator('\r\n'), token_separator(';'), null_value('\\N')]),
  phrase_from_file(seq(Cs), F), write_canonical(Cs), nl.
