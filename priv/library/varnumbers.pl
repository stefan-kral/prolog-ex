/* library(varnumbers): '$VAR'(N)-Terme hin und zurück (wie SICStus/SWI)

   numbervars/3 selbst ist eingebaut; diese Bibliothek ergänzt:

     numbervars(+T)                 wie numbervars(T, 0, _)
     max_var_number(+T, +Start, -Max)
         Max: das größte ganzzahlige N in einem '$VAR'(N) von T, mindestens
         Start
     varnumbers(+T, -Copy), varnumbers(+T, +Start, -Copy)
         Umkehrung von numbervars/3: Copy ist T, in dem jedes '$VAR'(N) mit
         ganzzahligem N >= Start (Vorgabe 0) einheitlich durch eine frische
         Variable ersetzt ist; die Variablen von T bleiben dieselben
     varnumbers_names(+T, -Copy, -Bindings)
         wie varnumbers/2, aber für jedes '$VAR'(X) (X auch ein Name wie
         'Foo'); Bindings = [X = Var, ...], nach X in der Standardordnung

   T muss azyklisch sein (sonst domain_error(acyclic_term, _); SWI
   nennt dort T).
*/

:- module(varnumbers, [numbervars/1,
                       max_var_number/3,
                       varnumbers/2,
                       varnumbers/3,
                       varnumbers_names/3]).

:- use_module(library(error)).
:- use_module(library(assoc)).

% (der Term selbst kommt nicht in den Fehler: zyklische Terme lassen sich
% noch nicht werfen)
acyclic_(T) :-
    (   acyclic_term(T) -> true ; throw(error(domain_error(acyclic_term, _), _)) ).

numbervars(T) :-
    numbervars(T, 0, _).

max_var_number(T, Start, Max) :-
    acyclic_(T),
    must_be(integer, Start),
    max_(T, Start, Max).

max_(V, M, M) :-
    var(V), !.
max_('$VAR'(N), M0, M) :-
    integer(N), !,
    M is max(M0, N).
max_(T, M0, M) :-
    compound(T), !,
    functor(T, _, A),
    max_args(1, A, T, M0, M).
max_(_, M, M).

max_args(I, A, T, M0, M) :-
    (   I > A -> M = M0
    ;   arg(I, T, X),
        max_(X, M0, M1),
        I1 is I + 1,
        max_args(I1, A, T, M1, M)
    ).

varnumbers(T, Copy) :-
    varnumbers(T, 0, Copy).

varnumbers(T, Start, Copy) :-
    acyclic_(T),
    must_be(integer, Start),
    S1 is Start - 1,
    max_(T, S1, Max),
    N is Max - S1,
    (   N =:= 0
    ->  Copy = T
    ;   functor(Vs, v, N),          % Vs: Arg. I für '$VAR'(Start+I-1)
        copy_(T, S1, Vs, Copy)
    ).

copy_(V, _, _, C) :-
    var(V), !,
    C = V.
copy_('$VAR'(N), S1, Vs, C) :-
    integer(N), N > S1, !,
    I is N - S1,
    arg(I, Vs, C).
copy_(T, S1, Vs, C) :-
    compound(T), !,
    functor(T, F, A),
    functor(C, F, A),
    copy_args(1, A, T, S1, Vs, C).
copy_(T, _, _, T).

copy_args(I, A, T, S1, Vs, C) :-
    (   I > A -> true
    ;   arg(I, T, X),
        arg(I, C, Y),
        copy_(X, S1, Vs, Y),
        I1 is I + 1,
        copy_args(I1, A, T, S1, Vs, C)
    ).

varnumbers_names(T, Copy, Bindings) :-
    acyclic_(T),
    empty_assoc(A0),
    names_(T, Copy, A0, A),
    assoc_to_list(A, Ps),
    pairs_eqs(Ps, Bindings).

names_(V, C, A, A) :-
    var(V), !,
    C = V.
names_('$VAR'(X), C, A0, A) :-
    nonvar(X), !,
    (   get_assoc(X, A0, C0)
    ->  C = C0,
        A = A0
    ;   put_assoc(X, A0, C, A)
    ).
names_(T, C, A0, A) :-
    compound(T), !,
    functor(T, F, Ar),
    functor(C, F, Ar),
    names_args(1, Ar, T, C, A0, A).
names_(T, T, A, A).

names_args(I, Ar, T, C, A0, A) :-
    (   I > Ar -> A = A0
    ;   arg(I, T, X),
        arg(I, C, Y),
        names_(X, Y, A0, A1),
        I1 is I + 1,
        names_args(I1, Ar, T, C, A1, A)
    ).

pairs_eqs([], []).
pairs_eqs([K-V|Ps], [K = V|Es]) :-
    pairs_eqs(Ps, Es).
