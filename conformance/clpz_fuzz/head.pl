:- initialization(catch(set_prolog_flag(clpz_residuals, scryer), _, true)).
:- use_module(library(clpz)).
:- use_module(library(lists)).
:- use_module(library(iso_ext)).
:- use_module(library(terms)).

% je Fall: p(Id, Vs) stellt die Bedingungen (übersetzt, mit Goal-Expansion),
% o(Id, Optionen) für labeling/2
go :- forall(o(Id, _), (catch(run(Id), E, (write(Id), write(' crash '), pp(E), nl)))).

run(Id) :-
    o(Id, Opts),
    write(Id), write(' post '),
    (   catch((p(Id, Vs) -> R = ok(Vs) ; R = fail), error(E, C), err(E, C, R)) ->
        true
    ;   R = fail
    ),
    (   R = ok(Vs1) -> state(Vs1)
    ;   pp(R)
    ),
    nl,
    write(Id), write(' lab '),
    catch(( findall(Vs2, (p(Id, Vs2), labeling(Opts, Vs2)), L), length(L, N),
            first(L, 40, F), pp(N-F) ),
          error(E2, C2), (err(E2, C2, R2), pp(R2))),
    nl.

% Fehler; aus is/2 mit Kontext (in Scryer Fehler von library(clpz) mit
% gebundenen attributierten Variablen in übersetzten Klauseln)
err(E, C, R) :- ( nonvar(C), C = (is)/2 -> R = err(E, is) ; R = err(E) ).

% Domänen und Restbedingungen
% freeze/2 schreibt PrologEx wie SWI (unqualifiziert, vor den Zielen von
% clpz): die freeze-Ziele getrennt, in ihrer Reihenfolge
state(Vs) :-
    copy_term(Vs, Vs, Gs0),
    split_freeze(Gs0, Gs, Fs),
    maplist(dom, Vs, Ds),
    copy_term(Vs-Ds-Gs-Fs, T, _),
    copy_term(T, T2, _),
    numbervars(T, 0, _),
    pp(T),
    % dieselben Ziele ohne Reihenfolge: Hilfsvariablen anonym, sortiert
    T2 = Vs2-_-Gs2-Fs2,
    numbervars(Vs2, 0, _),
    term_variables(Gs2-Fs2, Aux), maplist(=('_'), Aux),
    % Scryer: put_atts/2 für Attribute ohne attribute_goals (Relations-
    % variablen von tuples_in/2) weg; freeze(V, (A,B)) wie freeze(V,A),
    % freeze(V,B); Modulqualifikation weg
    no_atts(Gs2, Gs2a), maplist(unqual, Gs2a, Gs3),
    flat_freeze(Fs2, Fs3),
    msort_(Gs3, N1), msort_(Fs3, N2),
    write(' NORM '), pp(N1-N2).

unqual(G, U) :- ( G = _:U0 -> unqual(U0, U) ; U = G ).
no_atts([], []).
no_atts([G|Gs], Os) :-
    unqual(G, U),
    (   U = put_atts(_, _) -> no_atts(Gs, Os)
    ;   Os = [G|Os1], no_atts(Gs, Os1)
    ).
flat_freeze([], []).
flat_freeze([freeze(V, G)|Fs], Os) :-
    conj_list(G, Gs, []), freezes(Gs, V, Os, Os1), flat_freeze(Fs, Os1).
conj_list(G, L, L0) :- unqual(G, U),
    (   U = (A, B) -> conj_list(A, L, L1), conj_list(B, L1, L0)
    ;   L = [U|L0]
    ).
freezes([], _, Os, Os).
freezes([G|Gs], V, [freeze(V, G)|Os], Os0) :- freezes(Gs, V, Os, Os0).
dom(V, D) :- ( var(V) -> fd_dom(V, D) ; D = V ).

first(L, N, F) :- ( length(F, N), append(F, _, L) -> true ; F = L ).

pp(T) :- var(T), !, write('_').
pp('$VAR'(N)) :- integer(N), !, write('_V'), write(N).
pp([]) :- !, write('[]').
pp([H|T]) :- !, write('['), pp(H), pp_tail(T), write(']').
pp(T) :- compound(T), !, T =.. [F|As], pp(F), write('('), pp_args(As), write(')').
pp(T) :- atom(T), !, write(''''), write(T), write('''').
pp(T) :- write(T).
pp_tail([]) :- !.
pp_tail([H|T]) :- !, write(','), pp(H), pp_tail(T).
pp_tail(T) :- write('|'), pp(T).
pp_args([A]) :- !, pp(A).
pp_args([A|As]) :- pp(A), write(','), pp_args(As).

split_freeze([], [], []).
split_freeze([G|Gs], Os, Fs) :-
    (   ( G = freeze(V, F) ; G = freeze:freeze(V, F) ) ->
        Fs = [freeze(V, F)|Fs1], split_freeze(Gs, Os, Fs1)
    ;   Os = [G|Os1], split_freeze(Gs, Os1, Fs)
    ).
msort_(L, S) :- maplist(pk, L, Ps), keysort(Ps, Ss), maplist(pk, S, Ss).
pk(G, G-x).
