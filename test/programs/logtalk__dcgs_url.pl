% aus Logtalk, examples/dcgs/url.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
:- set_prolog_flag(double_quotes, codes).

parse(URL, [protocol(Protocol), address(Address), path(Path), file(File)]) :-
	phrase(url(Protocol, Address, Path, File), URL).

url(Protocol, Address, Path, File) --> protocol(Protocol), "://", address(Address), path(Path), file(File).

protocol(ftp) --> "ftp".
protocol(http) --> "http".
protocol(https) --> "https".
protocol(rtsp) --> "rtsp".

address(Address) --> ip_number(Address).
address([Identifier| Identifiers]) --> identifier(Identifier), dot_identifiers(Identifiers).

ip_number([N1, N2, N3, N4]) --> ip_subnumber(N1), ".", ip_subnumber(N2), ".", ip_subnumber(N3), ".", ip_subnumber(N4).

ip_subnumber(N) --> [N1, N2, N3], {N is N3 - 0'0 + 10*(N2 - 0'0) + 100*(N1 - 0'0), N >= 0, N =< 255}.
ip_subnumber(N) --> [N1, N2], {N is N2 - 0'0 + 10*(N1 - 0'0), N >= 0, N =< 255}.
ip_subnumber(N) --> [N1], {N is N1 - 0'0, N >= 0, N =< 255}.

identifier(Identifier) --> characters(Codes), {atom_codes(Identifier, Codes)}.

characters([]) --> [].
characters([Code| Codes]) --> [Code], {character(Code)}, characters(Codes).

character(Code) :- Code @>= 0'a, Code @=< 0'z, !.
character(Code) :- Code @>= 0'A, Code @=< 0'Z.

dot_identifiers([]) --> [].
dot_identifiers([Identifier| Identifiers]) --> ".", identifier(Identifier), dot_identifiers(Identifiers).

path([]) --> [].
path([Identifier| Path]) --> "/", identifier(Identifier), path(Path).

file('') --> [].
file(File) --> "/", identifier(Name), ".", identifier(Extension), {atom_concat(Name, '.', Aux), atom_concat(Aux, Extension, File)}.
