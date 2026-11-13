:- use_module(library(iso_ext)).
:- use_module(library(csv)).
:- use_module(library(lists)).
:- use_module(library(pio)).
file('@DIR@/t.csv').
wf(A) :- file(F), open(F, write, S), write(S, A), close(S).
t(A, O) :- wf(A), file(F), ( catch(phrase_from_file(csv(Rows, O), F), error(E, _), (writeq(A-O-err(E)), nl, fail)) -> writeq(A-O-Rows), nl ; writeq(A-O-fail), nl ), fail.
t(_, _).
cases(['a,b,c\n1,2,3\n', 'a,b', '', '\n', 'a\n\nb\n', 'x,"y ""q"" z",w\n', '"multi\nline",x\r\n', '"bad"x,1\n', '"unterminated', ' 12,+5,-3,0x1A,1e10, -5,12abc\n', '  x  ,  "y"  ,z \n', 'a,b\n1\n', 'a\rb\rc', ',,\n', '#h1\n#h2\n\na,b\n']).
opts([[], [separator(0';)], [convert(false)], [strip(true)], [arity(2)], [match_arity(false)], [ignore_quotes(true)], [skip_header('#')]]).
go :- cases(Cs), opts(Os), forall((member(C, Cs), member(O, Os)), t(C, O)), rest.
rest :-
  wf('a,b\n"x\ny",2\n3,"q""q"\nlast,1'), file(F),
  csv_read_file(F, R1), writeq(r1(R1)), nl,
  findall(L-R, csv_read_file_row(F, R, [line(L)]), Rs), writeq(rows(Rs)), nl,
  open(F, read, S), csv_read_stream(S, R2, [functor(f)]), close(S), writeq(r2(R2)), nl,
  csv_options(Opts, []), open(F, read, S2), csv_read_row(S2, X1, Opts), csv_read_row(S2, X2, Opts), close(S2), writeq(rr(X1, X2)), nl,
  phrase(csv([row(a, 'b,c', 'say "hi"', 1, 2.5, 'x\ny', ''), row(z)]), Codes), atom_codes(At, Codes), writeq(gen(At)), nl,
  phrase(csv([row(a, 'b;c')], [separator(0';)]), Codes2), atom_codes(At2, Codes2), writeq(gen2(At2)), nl,
  F2 = '@DIR@/o.tsv',
  csv_write_file(F2, [row(a, 'b\tc', 3), row(x, y, z)]), read_file(F2, T2), writeq(tsv(T2)), nl,
  csv_read_file(F2, R3), writeq(r3(R3)), nl,
  csv_write_stream(current_output, [row(1,2), row(a,'"')], []),
  catch(csv_read_file(F, _, [arity(1)]), error(E, _), (writeq(E), nl)),
  catch(csv_write_file(F2, foo), error(E2, _), (writeq(E2), nl)),
  catch(csv_options(_, [case(foo)]), error(E3, _), (writeq(E3), nl)).
read_file(F, A) :- open(F, read, S), read_chars(S, Cs), close(S), atom_codes(A, Cs).
read_chars(S, L) :- get_code(S, C), ( C == -1 -> L = [] ; L = [C|T], read_chars(S, T) ).
