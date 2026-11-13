:- use_module(library(iso_ext)).
:- use_module(library(csv)).
:- use_module(library(lists)).
t(A, O) :- atom_codes(A, Cs), ( catch(phrase(csv(Rows, O), Cs), error(E, _), (writeq(A-O-err(E)), nl, fail)) -> writeq(A-O-Rows), nl ; writeq(A-O-fail), nl ), fail.
t(_, _).
cases(['a,b,c\n1,2,3\n', 'a,b\n', 'a,b', '', '\n', 'a\n\nb\n', 'x,"y ""q"" z",w\n', '"multi\nline",x\r\n', '"bad"x,1\n', '"unterminated', 'a;b\n', ' 12,+5,-3,0x1A,1e10,1.5E3,007,1_000, -5,- 5,12abc,inf\n', '  x  ,  "y"  ,z \n', 'a,b\n1\n', 'a\rb\rc', 'a,b\r\nc,d\r\n', ',,\n', '"",x\n', '#h1\n#h2\n\na,b\n']).
opts([[], [separator(0';)], [convert(false)], [case(down)], [case(up)], [strip(true)], [functor(r)], [arity(2)], [match_arity(false)], [ignore_quotes(true)], [skip_header('#')]]).
go :- cases(Cs), opts(Os), forall((member(C, Cs), member(O, Os)), t(C, O)).
