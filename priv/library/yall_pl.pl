% library(yall_pl): Lambda-Ausdrücke wie SWI-Prologs library(yall) („Yet
% Another Lambda Library“, Paulo Moura, Jan Wielemaker), in reinem Prolog
% – Aufbau wie dort. Dieselbe Bibliothek in Elixir: library(yall).
%
%   [X1,...]>>Rumpf        Lambda: beim Aufruf mit A1, ... eine Kopie, Xi =
%                          Ai, übrige Argumente an den Rumpf angehängt
%   Free/[X1,...]>>Rumpf   die Variablen von Free ({V1,...}) werden nicht
%                          kopiert: nur sie tragen Bindungen nach außen
%   Free/Rumpf             wie Free/[]>>Rumpf
%
% Weniger Argumente als Parameter: domain_error(lambda_parameters, Ps).
% copy_term/2 kopiert hier keine Attribute, entspricht also copy_term_nat/2.
% Anders als SWI übersetzt PrologEx Lambdas nicht beim Laden: sie kopieren
% immer (in SWI teilt ein übersetztes Lambda ohne Free seine Variablen mit
% der Klausel).

:- module(yall_pl, [
       (>>)/2, (>>)/3, (>>)/4, (>>)/5, (>>)/6, (>>)/7, (>>)/8, (>>)/9,
       (/)/2, (/)/3, (/)/4, (/)/5, (/)/6, (/)/7, (/)/8, (/)/9,
       is_lambda/1]).

:- meta_predicate
       >>(?, 0),
       >>(?, :, ?),
       >>(?, :, ?, ?),
       >>(?, :, ?, ?, ?),
       >>(?, :, ?, ?, ?, ?),
       >>(?, :, ?, ?, ?, ?, ?),
       >>(?, :, ?, ?, ?, ?, ?, ?),
       >>(?, :, ?, ?, ?, ?, ?, ?, ?),
       /(?, 0),
       /(?, 1, ?),
       /(?, 2, ?, ?),
       /(?, 3, ?, ?, ?),
       /(?, 4, ?, ?, ?, ?),
       /(?, 5, ?, ?, ?, ?, ?),
       /(?, 6, ?, ?, ?, ?, ?, ?),
       /(?, 7, ?, ?, ?, ?, ?, ?, ?).

'>>'(Ps, L) :-
    lambda_call(Ps, L, []).
'>>'(Ps, L, A1) :-
    lambda_call(Ps, L, [A1]).
'>>'(Ps, L, A1, A2) :-
    lambda_call(Ps, L, [A1,A2]).
'>>'(Ps, L, A1, A2, A3) :-
    lambda_call(Ps, L, [A1,A2,A3]).
'>>'(Ps, L, A1, A2, A3, A4) :-
    lambda_call(Ps, L, [A1,A2,A3,A4]).
'>>'(Ps, L, A1, A2, A3, A4, A5) :-
    lambda_call(Ps, L, [A1,A2,A3,A4,A5]).
'>>'(Ps, L, A1, A2, A3, A4, A5, A6) :-
    lambda_call(Ps, L, [A1,A2,A3,A4,A5,A6]).
'>>'(Ps, L, A1, A2, A3, A4, A5, A6, A7) :-
    lambda_call(Ps, L, [A1,A2,A3,A4,A5,A6,A7]).

'/'(Free, L) :-
    lambda_free(Free),
    copy_term(Free+L, Free+C),
    call(C).
'/'(Free, L, A1) :-
    lambda_free(Free),
    copy_term(Free+L, Free+C),
    call(C, A1).
'/'(Free, L, A1, A2) :-
    lambda_free(Free),
    copy_term(Free+L, Free+C),
    call(C, A1, A2).
'/'(Free, L, A1, A2, A3) :-
    lambda_free(Free),
    copy_term(Free+L, Free+C),
    call(C, A1, A2, A3).
'/'(Free, L, A1, A2, A3, A4) :-
    lambda_free(Free),
    copy_term(Free+L, Free+C),
    call(C, A1, A2, A3, A4).
'/'(Free, L, A1, A2, A3, A4, A5) :-
    lambda_free(Free),
    copy_term(Free+L, Free+C),
    call(C, A1, A2, A3, A4, A5).
'/'(Free, L, A1, A2, A3, A4, A5, A6) :-
    lambda_free(Free),
    copy_term(Free+L, Free+C),
    call(C, A1, A2, A3, A4, A5, A6).
'/'(Free, L, A1, A2, A3, A4, A5, A6, A7) :-
    lambda_free(Free),
    copy_term(Free+L, Free+C),
    call(C, A1, A2, A3, A4, A5, A6, A7).

% Kopie, Parameter binden, den Rumpf mit den übrigen Argumenten aufrufen
lambda_call(Ps, L, Args) :-
    lambda_copy(Ps, L, PsC, C),
    bind_params(PsC, Args, Extra, Ps),
    G =.. [call, C|Extra],
    call(G).

lambda_copy(Ps, _, _, _) :-
    var(Ps),
    !,
    throw(error(instantiation_error, _)).
lambda_copy(Free/Ps, L, PsC, C) :-
    !,
    lambda_free(Free),
    must_be_list(Ps),
    copy_term(Free/Ps>>L, Free/PsC>>C).
lambda_copy(Ps, L, PsC, C) :-
    must_be_list(Ps),
    copy_term(Ps>>L, PsC>>C).

bind_params([], Extra, Extra, _) :- !.
bind_params([P|Ps], [A|As], Extra, Culprit) :-
    !,
    P = A,
    bind_params(Ps, As, Extra, Culprit).
bind_params(_, _, _, Culprit) :-
    throw(error(domain_error(lambda_parameters, Culprit), _)).

lambda_free(Free) :-
    var(Free),
    !,
    throw(error(instantiation_error, _)).
lambda_free({_}) :- !.
lambda_free({}) :- !.
lambda_free(Free) :-
    throw(error(type_error(lambda_free, Free), _)).

must_be_list(L) :-
    '$skip_list'(_, L, T),
    (   T == []
    ->  true
    ;   var(T)
    ->  throw(error(instantiation_error, _))
    ;   throw(error(type_error(list, L), _))
    ).

% is_lambda(@T): T ist ein Lambda-Ausdruck (Params>>Rumpf mit einer Liste
% oder Free/Liste, oder Free/Rumpf)
is_lambda(T) :-
    compound(T),
    T =.. [N, A, B|_],
    is_lambda(N, A, B).

is_lambda(>>, Ps, _) :-
    is_lambda_params(Ps).
is_lambda(/, Free, _) :-
    is_lambda_free(Free).

is_lambda_params(Ps) :-
    var(Ps),
    !,
    fail.
is_lambda_params(Free/Ps) :-
    !,
    is_lambda_free(Free),
    is_list(Ps).
is_lambda_params(Ps) :-
    is_list(Ps).

is_lambda_free(Free) :-
    nonvar(Free),
    ( Free = {_} -> true ; Free == {} ).
