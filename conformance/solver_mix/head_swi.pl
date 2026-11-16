:- encoding(utf8).
% wie head.pl für SWI-Prolog (clpfd statt clpz)
:- use_module(library(clpfd)).
:- use_module(library(clpb)).
:- use_module(library(lists)).
:- use_module(dom_swi).
:- use_module(par_swi).
:- style_check(-singleton).

go :- forall(c(Id, _, _, _), run(Id)).

run(Id) :-
    c(Id, Vs, Ts, G),
    write(Id), write(' '),
    catch(( findall(Vs, (G, lab(Vs, Ts)), L), write(L) ),
          E, ( ex_name(E, N), write(ex(N)) )),
    nl.

ex_name(error(F, _), N) :- !, functor(F, N0, A), N = N0/A.
ex_name(B, N) :- functor(B, N0, A), N = N0/A.

vars(_).

lab([], []).
lab([V|Vs], [T|Ts]) :- td(T, D), member(V, D), lab(Vs, Ts).

td(b, [0, 1]).
td(i, [0, 1, 2, 3]).
