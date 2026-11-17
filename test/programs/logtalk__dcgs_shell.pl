% aus Logtalk, examples/dcgs/shell.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
:- set_prolog_flag(double_quotes, codes).

parse(Sequence, Commands) :-
	phrase(commands(Commands), Sequence).

commands([C| Cs]) -->
	command(C), separator, commands(Cs).
commands([C]) -->
	command(C).

separator --> ";".

whitespace --> " ", whitespace.
whitespace --> [].

command(Cd) -->
	whitespace, "cd", whitespace, cdargs(Args), whitespace,
	{atom_concat(cd, Args, Cd)}.
command(Ls) -->
	whitespace, "ls", whitespace, lsargs(Args), whitespace,
	{atom_concat(ls, Args, Ls)}.
command(pwd) -->
	whitespace, "pwd", whitespace.

cdargs(' ~') --> "~".
cdargs(' ..') --> "..".
cdargs(' .') --> ".".
cdargs('') --> [].

lsargs(' -l') --> "-l".
lsargs(' -a') --> "-a".
lsargs('') --> [].
