% Durchprobieren (SWI-Prolog): erst alle Variablen belegen, dann die
% Bedingungen stellen – nur für monotone Fälle (m/1). Die Lösungsmenge
% muss dieselbe sein wie beim Stellen vor dem Belegen.
:- encoding(utf8).
:- use_module(library(clpfd)).
:- use_module(library(clpb)).
:- use_module(library(lists)).
:- use_module(dom_swi).
:- use_module(par_swi).
:- style_check(-singleton).

:- dynamic(m/1).

go :- forall(m(Id), run(Id)).

run(Id) :-
    c(Id, Vs, Ts, G),
    write(Id), write(' '),
    catch(( findall(Vs, (lab(Vs, Ts), G), L0), sort(L0, L), write(L) ),
          E, ( ex_name(E, N), write(ex(N)) )),
    nl.

ex_name(error(F, _), N) :- !, functor(F, N0, A), N = N0/A.
ex_name(B, N) :- functor(B, N0, A), N = N0/A.

vars(_).

lab([], []).
lab([V|Vs], [T|Ts]) :- td(T, D), member(V, D), lab(Vs, Ts).

td(b, [0, 1]).
td(i, [0, 1, 2, 3]).
