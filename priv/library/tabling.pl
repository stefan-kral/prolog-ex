/* library(tabling): Tabling (SLG-artig) wie Scryer Prolog

   :- use_module(library(tabling)).
   :- table path/2.
   path(X, Y) :- path(X, Z), edge(Z, Y).
   path(X, Y) :- edge(X, Y).

   Ein getabltes Prädikat terminiert auch bei Links- und Zyklenrekursion,
   solange es für jede Variante endlich viele Antworten gibt. Die Antworten
   sind eine Menge: keine Varianten doppelt, die Reihenfolge ist nicht
   festgelegt (die des Findens). Seiteneffekte in getablten Prädikaten
   laufen unbestimmt oft.

   Umsetzung ohne Eingriff in die Maschine: Fixpunkt je stark
   zusammenhängender Komponente (siehe PrologEx.Builtins.Tabling). Eifrig:
   eine Variante wird ganz durchgerechnet, bevor ihre erste Antwort kommt.
   Eine Ausnahme dabei verwirft die unvollständigen Tabellen.

   Die Direktive steht vor den Klauseln (Name/N oder Name//N); diese werden
   zu 'Name tabled'/N. Neu laden leert die Tabellen des Prädikats. Hängt es
   von dynamischen Prädikaten ab, veralten die Tabellen still:
   abolish_all_tables/0.

   Wie Scryer: table/1 (Direktive), abolish_all_tables/0,
   start_tabling/2, op(1150, fx, table).
*/

:- module(tabling, [(table)/1,
                    abolish_all_tables/0,
                    start_tabling/2,
                    op(1150, fx, table)]).

:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(library(iso_ext), [forall/2]).
:- use_module(library(tabling/wrapper), [wrap_declare/6, directive_module/2, pis/3]).

%% table(+Spec): nur als Direktive
table(Spec) :-
    directive_module(table(Spec), M),
    pis(Spec, PIs, []),
    forall(member(N/A, PIs),
           (   wrap_declare(M, N, A, ' tabled', (tabling):'$tbl_call', '$tbl'(M, N, A)),
               '$tbl_abolish'(M:N/A)
           )).

%% abolish_all_tables: alle vollständigen Tabellen verwerfen
abolish_all_tables :-
    '$tbl_abolish'(all).

%% start_tabling(:Wrapper, :Worker) wie Scryer: Wrapper getablt über Worker
:- meta_predicate(start_tabling(:, 0)).
start_tabling(M:Wrapper, Worker) :-
    functor(Wrapper, N, A),
    '$tbl_call'('$tbl'(M, N, A), Wrapper, Worker).

% --- Auswertung ------------------------------------------------------------

'$tbl_call'(Spec, G, I) :-
    '$tbl_lookup'(Spec, G, I, R),
    tbl_(R, G, I).

tbl_(complete(As), G, _) :-
    table_wrapper:answer(As, G).
tbl_(incomplete(As), G, _) :-
    table_wrapper:answer(As, G).
tbl_(evaluate(Id), G, I) :-
    catch(eval(Id, G, I), E, ('$tbl_abandon'(Id), throw(E))),
    '$tbl_answers'(Id, As),
    table_wrapper:answer(As, G).

tbl_(reevaluate(Id), G, I) :-
    catch(run(Id, G, I, _), E, ('$tbl_abandon'(Id), throw(E))),
    '$tbl_answers'(Id, As),
    table_wrapper:answer(As, G).

eval(Id, G, I) :-
    run(Id, G, I, Leader),
    (   Leader == true -> lead(Id, G, I) ; true ).

run(Id, G, I, Leader) :-
    '$tbl_frame'(Id),
    findall(G, I, As),
    '$tbl_unframe'(Id, As, Leader).

% Anführer: Mitglieder nachziehen, dann neue Runde oder fertig
lead(Id, G, I) :-
    stale(Id),
    '$tbl_round'(Id, S),
    (   S == again
    ->  run(Id, G, I, _),
        lead(Id, G, I)
    ;   true
    ).

stale(Id) :-
    (   '$tbl_next_stale'(Id, M, GM, IM)
    ->  run(M, GM, IM, _),
        stale(Id)
    ;   true
    ).
