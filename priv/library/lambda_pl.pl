% library(lambda_pl): Lambda-Ausdrücke nach Ulrich Neumerkel, in reinem
% Prolog – Aufbau wie sein lambda.pl
% (https://www.complang.tuwien.ac.at/ulrich/Prolog-inedit/ISO-Hiord).
% Dieselbe Bibliothek in Elixir: library(lambda).
%
%   \X1^...^Xn^Rumpf   Lambda; beim Aufruf wird es kopiert (frische
%                      Variablen), Xi an die Argumente gebunden
%   Free+\Lambda       die Variablen von Free werden nicht kopiert
%
% copy_term/2 kopiert hier keine Attribute, entspricht also copy_term_nat/2.

:- module(lambda_pl, [
       (^)/3, (^)/4, (^)/5, (^)/6, (^)/7, (^)/8, (^)/9,
       (\)/1, (\)/2, (\)/3, (\)/4, (\)/5, (\)/6, (\)/7,
       (+\)/2, (+\)/3, (+\)/4, (+\)/5, (+\)/6, (+\)/7,
       op(201, xfx, +\)]).

:- meta_predicate
       ^(?, 0, ?),
       ^(?, 1, ?, ?),
       ^(?, 2, ?, ?, ?),
       ^(?, 3, ?, ?, ?, ?),
       ^(?, 4, ?, ?, ?, ?, ?),
       ^(?, 5, ?, ?, ?, ?, ?, ?),
       ^(?, 6, ?, ?, ?, ?, ?, ?, ?),
       \(0),
       \(1, ?),
       \(2, ?, ?),
       \(3, ?, ?, ?),
       \(4, ?, ?, ?, ?),
       \(5, ?, ?, ?, ?, ?),
       \(6, ?, ?, ?, ?, ?, ?),
       +\(?, 0),
       +\(?, 1, ?),
       +\(?, 2, ?, ?),
       +\(?, 3, ?, ?, ?),
       +\(?, 4, ?, ?, ?, ?),
       +\(?, 5, ?, ?, ?, ?, ?),
       no_hat_call(0).

^(V1, Goal, V1) :- no_hat_call(Goal).
^(V1, Goal, V1, V2) :- call(Goal, V2).
^(V1, Goal, V1, V2, V3) :- call(Goal, V2, V3).
^(V1, Goal, V1, V2, V3, V4) :- call(Goal, V2, V3, V4).
^(V1, Goal, V1, V2, V3, V4, V5) :- call(Goal, V2, V3, V4, V5).
^(V1, Goal, V1, V2, V3, V4, V5, V6) :- call(Goal, V2, V3, V4, V5, V6).
^(V1, Goal, V1, V2, V3, V4, V5, V6, V7) :- call(Goal, V2, V3, V4, V5, V6, V7).

\(FC) :- copy_term(FC, C), no_hat_call(C).
\(FC, V1) :- copy_term(FC, C), call(C, V1).
\(FC, V1, V2) :- copy_term(FC, C), call(C, V1, V2).
\(FC, V1, V2, V3) :- copy_term(FC, C), call(C, V1, V2, V3).
\(FC, V1, V2, V3, V4) :- copy_term(FC, C), call(C, V1, V2, V3, V4).
\(FC, V1, V2, V3, V4, V5) :- copy_term(FC, C), call(C, V1, V2, V3, V4, V5).
\(FC, V1, V2, V3, V4, V5, V6) :- copy_term(FC, C), call(C, V1, V2, V3, V4, V5, V6).

+\(GV, FC) :- copy_term(GV+FC, GV+C), no_hat_call(C).
+\(GV, FC, V1) :- copy_term(GV+FC, GV+C), call(C, V1).
+\(GV, FC, V1, V2) :- copy_term(GV+FC, GV+C), call(C, V1, V2).
+\(GV, FC, V1, V2, V3) :- copy_term(GV+FC, GV+C), call(C, V1, V2, V3).
+\(GV, FC, V1, V2, V3, V4) :- copy_term(GV+FC, GV+C), call(C, V1, V2, V3, V4).
+\(GV, FC, V1, V2, V3, V4, V5) :- copy_term(GV+FC, GV+C), call(C, V1, V2, V3, V4, V5).

% Wie call/1, aber ein übrig gebliebenes X^G (zu wenige Argumente) ist ein
% Fehler.
no_hat_call(MGoal) :-
    strip_module(MGoal, _, Goal),
    (   nonvar(Goal),
        Goal = (_^_)
    ->  throw(error(existence_error(lambda_parameter, MGoal), _))
    ;   call(MGoal)
    ).
