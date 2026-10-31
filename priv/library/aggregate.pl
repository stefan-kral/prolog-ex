/* library(aggregate) für PrologEx – zwischen SWI-Prolog und SICStus

   aggregate/3,4, aggregate_all/3,4 und foreach/2 mit den Templates beider
   Systeme: count, sum(E), min(E), max(E), min(E, W), max(E, W), set(X),
   bag(X) und zusammengesetzte Templates, deren Argumente selbst Templates
   sind (r(count, min(X), max(X))).

   Semantik wie SWI (SICStus lässt die Punkte offen oder stimmt überein):
     - aggregate/3,4 wie bagof/setof: freie Variablen des Generators
       gruppieren (eine Lösung je Gruppe), ^ quantifiziert existenziell;
       ohne Lösung scheitern sie.
     - aggregate_all/3,4: genau ein Ergebnis über alle Lösungen; ohne
       Lösung count und sum 0, bag und set [], min und max scheitern.
     - Mit Diskriminator zählen Lösungen, die in Diskriminator UND
       Template gleich sind, einmal.
     - Arithmetik wie is/2: sum addiert, min/max vergleichen numerisch;
       beim Zeugen gewinnt bei Gleichstand der erste. Ergebnis von
       max(E, W): max(Wert, Zeuge), entsprechend min.
     - Fehler: freies Template instantiation_error, unbekanntes
       domain_error(aggregate_template, T), nicht aufrufbares
       type_error(aggregate_template, T) – vor dem Generator.

   aggregate_all/3 faltet in der Maschine ('$aggregate_all'/3,
   PrologEx.Aggregate), ohne die Lösungen zu sammeln: count, sum, min und
   max brauchen konstanten Speicher.
*/

:- module(aggregate, [aggregate/3,
                      aggregate/4,
                      aggregate_all/3,
                      aggregate_all/4,
                      foreach/2]).

:- use_module(library(ordsets), [ord_subtract/3, ord_intersection/3]).

:- meta_predicate(aggregate(?, ^, -)).
:- meta_predicate(aggregate(?, ?, ^, -)).
:- meta_predicate(aggregate_all(?, 0, -)).
:- meta_predicate(aggregate_all(?, ?, 0, -)).
:- meta_predicate(foreach(0, 0)).

%% aggregate(+Template, :Generator, -Result)
%
% Aggregiert die Lösungen von Generator; gruppiert nach den freien
% Variablen wie bagof/3 (^ für existenzielle). Scheitert ohne Lösung.
aggregate(Template, Goal, Result) :-
    '$aggregate_check'(Template),
    bagof(Template, Goal, List),
    '$aggregate_list'(Template, List, Result).

%% aggregate(+Template, +Discriminator, :Generator, -Result)
%
% Wie aggregate/3; Lösungen, die in Discriminator und Template gleich
% sind, zählen einmal (wie setof/3).
aggregate(Template, Discriminator, Goal, Result) :-
    '$aggregate_check'(Template),
    setof(Discriminator-Template, Goal, Pairs),
    pairs_values_(Pairs, List),
    '$aggregate_list'(Template, List, Result).

%% aggregate_all(+Template, :Generator, -Result)
%
% Aggregiert alle Lösungen zu genau einem Ergebnis; freie Variablen des
% Generators gruppieren nicht (und bleiben ungebunden).
aggregate_all(Template, Goal, Result) :-
    '$aggregate_all'(Template, Goal, Result).

%% aggregate_all(+Template, +Discriminator, :Generator, -Result)
%
% Wie aggregate_all/3; Lösungen, die in Discriminator und Template gleich
% sind, zählen einmal.
aggregate_all(Template, Discriminator, Goal, Result) :-
    '$aggregate_check'(Template),
    findall(Discriminator-Template, Goal, Pairs0),
    sort(Pairs0, Pairs),
    pairs_values_(Pairs, List),
    '$aggregate_list'(Template, List, Result).

pairs_values_([], []).
pairs_values_([_-V|Ps], [V|Vs]) :-
    pairs_values_(Ps, Vs).

%% foreach(:Generator, :Goal)
%
% Wahr, wenn die Konjunktion der Instanzen von Goal für alle Lösungen von
% Generator wahr ist (wie SWI und SICStus). Anders als forall/2 werden
% die Variablen von Goal, die nicht in Generator vorkommen, über alle
% Instanzen hinweg geteilt und dabei gebunden:
%
%   ?- foreach(member(X, [1,2,3]), dif(Y, X)), Y = 4.   % gelingt
%   ?- foreach(between(1, 4, X), dif(X, Y)), Y = 3.     % scheitert
foreach(Generator, Goal) :-
    term_variables(Generator, GenVars0), sort(GenVars0, GenVars),
    term_variables(Goal, GoalVars0), sort(GoalVars0, GoalVars),
    ord_subtract(GoalVars, GenVars, SharedGoalVars),
    (   SharedGoalVars == [] ->
        \+ (Generator, \+ Goal)
    ;   ord_intersection(GenVars, GoalVars, SharedVars),
        Templ =.. [v|SharedVars],
        SharedTempl =.. [v|SharedGoalVars],
        findall(Templ, Generator, List),
        prove_list_(List, Templ, SharedTempl, Goal)
    ).

prove_list_([], _, _, _).
prove_list_([H|T], Templ, SharedTempl, Goal) :-
    copy_term(Templ/SharedTempl/Goal, H/SharedTempl/Copy),
    call(Copy),
    prove_list_(T, Templ, SharedTempl, Goal).
