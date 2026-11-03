:- use_module(library(clpz)).
:- use_module(library(lists)).
:- use_module(library(iso_ext)).
:- use_module(library(terms)).

% q(Vs, Goal): Lösungen (höchstens 4) mit Restzielen
h(N, Vs, G) :-
    catch(call_with_inference_limit(
              findall(R, (call(G), copy_term(Vs, Vs1, Gs0), gl(Gs0, Gs), R = Vs1-Gs), Rs1),
              20000000, Lim),
          E, (Rs1 = ex(E), Lim = x)),
    ( Lim == inference_limit_exceeded -> Rs0 = ex(limit) ; Rs0 = Rs1 ),
    (   Rs0 = ex(E0) -> E1 = E0, numbervars(E1, 0, _), writeq(N-error(E1))
    ;   length(Rs0, Len), take4(Rs0, Rs2), maplist(norm, Rs2, Rs), writeq(N-Len-Rs)
    ),
    nl.

take4(L, P) :- length(L, N), ( N =< 4 -> P = L ; length(P, 4), append(P, _, L) ).

gl(G, G) :- G = [], !.
gl(G, G) :- G = [_|_], !.
gl(true, []) :- !.
gl((A, B), [A|L]) :- !, gl(B, L).
gl(A, [A]).

t :- clpz:asserta(goal_expansion(false)), forall(q(N, Vs, G), h(N, Vs, G)).

% Normalform: Anfragevariablen benannt, Ziele ohne Modul, ohne put_atts,
% interne Variablen anonym, sortiert
norm(Vs-Gs0, Vs-Gs) :-
    numbervars(Vs, 0, _),
    strip(Gs0, Gs1),
    term_variables(Gs1, Fs), anon(Fs),
    findall(G-x, member(G, Gs1), Ps), keysort(Ps, Ss), findall(G, member(G-x, Ss), Gs).
anon([]).
anon(['_v'|Fs]) :- anon(Fs).
strip([], []).
strip([G0|Gs0], Gs) :-
    unq(G0, G),
    (   G = put_atts(_, _) -> Gs = Gs1 ; Gs = [G|Gs1] ),
    strip(Gs0, Gs1).
unq(G0, G) :- nonvar(G0), G0 = _:G1, !, unq(G1, G).
unq(G, G).
