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
   zusammenhängender Komponente (siehe PrologEx.Builtins.Tabling); eine
   unvollständige Tabelle wird live gelesen (auch Antworten, die während des
   Lesens dazukommen). Eifrig:
   eine Variante wird ganz durchgerechnet, bevor ihre erste Antwort kommt.
   Eine Ausnahme dabei verwirft die unvollständigen Tabellen.

   Die Direktive steht vor den Klauseln (Name/N oder Name//N); diese werden
   zu 'Name tabled'/N. Neu laden leert die Tabellen des Prädikats. Hängt es
   von dynamischen Prädikaten ab, veralten die Tabellen still:
   abolish_all_tables/0.

   Wie Scryer: table/1 (Direktive), abolish_all_tables/0,
   start_tabling/2, op(1150, fx, table).

   Dazu tnot/1 (stratifizierte Negation, geprüft) und Modi wie SWI: `:- table path(_, _, min).` – je Belegung der übrigen
   Argumente bleibt nur die beste Antwort (min, max, first, lattice(P/3));
   höchstens ein Argument mit Modus.
*/

:- module(tabling, [(table)/1,
                    tnot/1,
                    abolish_all_tables/0,
                    start_tabling/2,
                    op(1150, fx, table)]).

:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(library(iso_ext), [forall/2]).
:- use_module(library(tabling/wrapper), [wrap_declare/6, directive_module/2, pis/3]).

%% table(+Spec): nur als Direktive. Spec: Name/N, Name//N oder ein Kopf
%  mit Modi (path(_,_,min)); mehrere mit Komma oder als Liste
table(Spec) :-
    directive_module(table(Spec), M),
    specs(Spec, M, Ts, []),
    forall(member(t(N, A, Spec1), Ts),
           (   wrap_declare(M, N, A, ' tabled', (tabling):'$tbl_call', Spec1),
               '$tbl_abolish'(M:N/A),
               retractall('$tabled'(M, N, A)),
               assertz('$tabled'(M, N, A))
           )).

% getablte Prädikate (für tnot/1)
:- dynamic('$tabled'/3).

%% tnot(:G): Negation über ein getabltes Prädikat, stratifiziert. G wird
%  ganz ausgewertet; hat es eine Antwort, scheitert tnot, ist seine Tabelle
%  vollständig ohne Antwort, gelingt es. Bleibt sie unvollständig, hängt G
%  negativ von einer gerade laufenden Auswertung ab (das Programm ist nicht
%  stratifiziert): Fehler statt einer Antwort, die von der Reihenfolge der
%  Aufrufe abhinge.
:- meta_predicate(tnot(0)).
tnot(M:G) :-
    (   var(G) -> instantiation_error(G)
    ;   callable(G) -> true
    ;   type_error(callable, G)
    ),
    (   ground(G) -> true ; instantiation_error(G) ),
    functor(G, N, A),
    (   '$tabled'(M, N, A) -> true ; type_error(tabled_predicate, M:N/A) ),
    (   \+ \+ call(M:G)
    ->  fail
    ;   '$tbl_status'(M:G, complete)
    ->  true
    ;   throw(error(permission_error(tnot, incomplete_table, M:G),
                    context(tnot/1, 'nicht stratifiziert: das Ziel hängt negativ von einer laufenden Auswertung ab')))
    ).

specs(V, _, _, _) :-
    var(V), !,
    instantiation_error(V).
specs((A, B), M, Ts0, Ts) :- !,
    specs(A, M, Ts0, Ts1),
    specs(B, M, Ts1, Ts).
specs([], _, Ts, Ts) :- !.
specs([S|Ss], M, Ts0, Ts) :- !,
    specs(S, M, Ts0, Ts1),
    specs(Ss, M, Ts1, Ts).
specs(PI, M, Ts0, Ts) :-
    (   PI = _/_ ; PI = _//_ ), !,
    pis(PI, PIs, []),
    findall(t(N, A, '$tbl'(M, N, A)), member(N/A, PIs), Ts1),
    append(Ts1, Ts, Ts0).
specs(Head, M, [t(N, A, Spec)|Ts], Ts) :-
    compound(Head), !,
    functor(Head, N, A),
    Head =.. [_|Ms],
    modes(Ms, 1, M, none, Mode),
    (   Mode == none
    ->  Spec = '$tbl'(M, N, A)
    ;   Spec = '$tbl'(M, N, A, Mode)
    ).
specs(S, _, _, _) :-
    type_error(predicate_indicator, S).

% höchstens ein Argument mit Modus: mode(Position, Modus)
modes([], _, _, Mode, Mode).
modes([X|Xs], P, M, Mode0, Mode) :-
    (   index_mode(X)
    ->  Mode1 = Mode0
    ;   answer_mode(X, M, AM),
        (   Mode0 == none
        ->  Mode1 = mode(P, AM)
        ;   domain_error(table_mode, X)
        )
    ),
    P1 is P + 1,
    modes(Xs, P1, M, Mode1, Mode).

index_mode(X) :- var(X), !.
index_mode(index).

answer_mode(min, _, min) :- !.
answer_mode(max, _, max) :- !.
answer_mode(first, _, first) :- !.
answer_mode(lattice(P), M, lattice(Q)) :-
    nonvar(P), !,
    (   P = _:_/3 -> Q = P
    ;   P = N/3, atom(N) -> Q = M:N
    ;   atom(P) -> Q = M:P
    ;   domain_error(table_mode, lattice(P))
    ).
answer_mode(X, _, _) :-
    domain_error(table_mode, X).

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
    (   Spec = '$tbl'(_, _, _, mode(P, _)),
        arg(P, G, V),
        nonvar(V)
    ->  % gebundener Wert: mit freiem Argument rechnen (die beste Antwort),
        % dann unifizieren
        G =.. [F|Args],
        nth1(P, Args, _, Rest),
        nth1(P, Args1, V1, Rest),
        G1 =.. [F|Args1],
        I = Mod:IH,
        IH =.. [IF|_],
        IH1 =.. [IF|Args1],
        '$tbl_call'(Spec, G1, Mod:IH1),
        V = V1
    ;   '$tbl_lookup'(Spec, G, I, R),
        tbl_(R, Spec, G, I)
    ).

tbl_(complete(As), _, G, _) :-
    table_wrapper:answer(As, G).
tbl_(incomplete(Id), _, G, _) :-
    live(Id, 0, G).
tbl_(evaluate(Id), Spec, G, I) :-
    catch(eval(Id, Spec, G, I), E, ('$tbl_abandon'(Id), throw(E))),
    '$tbl_answers'(Id, R),
    answers(R, G).
tbl_(reevaluate(Id), Spec, G, I) :-
    catch(run(live, Id, Spec, G, I, _), E, ('$tbl_abandon'(Id), throw(E))),
    '$tbl_answers'(Id, R),
    answers(R, G).

answers(complete(As), G) :-
    table_wrapper:answer(As, G).
answers(incomplete(Id), G) :-
    live(Id, 0, G).

% eine unvollständige Tabelle live lesen: auch Antworten, die erst während
% des Lesens dazukommen (so schließt etwa Links-Rekursion in einer Runde)
live(Id, I, G) :-
    '$tbl_chunk'(Id, I, As, I1),
    (   member(G, As)
    ;   live(Id, I1, G)
    ).

% der erste Lauf einer neuen Tabelle sammelt (findall, wie ohne Rekursion
% am billigsten), weitere Läufe tragen jede Antwort sofort ein
eval(Id, Spec, G, I) :-
    run(bulk, Id, Spec, G, I, Leader),
    (   Leader == true -> lead(Id, Spec, G, I) ; true ).

% die Klauseln auswerten: bulk sammelt erst und trägt dann alles ein, live
% trägt jede Antwort sofort ein (wer die Tabelle gerade liest, sieht sie)
run(How, Id, Spec, G, I, Leader) :-
    '$tbl_frame'(Id),
    (   Spec = '$tbl'(_, _, _, mode(P, Mode))
    ->  (   How == bulk
        ->  findall(G, I, As),
            add_moded_all(As, Id, P, Mode)
        ;   (   call(I), add_moded(G, Id, P, Mode), fail ; true )
        )
    ;   How == bulk
    ->  findall(G, I, As),
        '$tbl_add_all'(Id, As)
    ;   (   call(I), '$tbl_add'(Id, G), fail ; true )
    ),
    '$tbl_unframe'(Id, Leader).

add_moded_all([], _, _, _).
add_moded_all([A|As], Id, P, Mode) :-
    add_moded(A, Id, P, Mode),
    add_moded_all(As, Id, P, Mode).

% Anführer: Mitglieder nachziehen, dann neue Runde oder fertig
lead(Id, Spec, G, I) :-
    stale(Id),
    '$tbl_round'(Id, S),
    (   S == again
    ->  run(live, Id, Spec, G, I, _),
        lead(Id, Spec, G, I)
    ;   true
    ).

stale(Id) :-
    (   '$tbl_next_stale'(Id, M, SM, GM, IM)
    ->  run(live, M, SM, GM, IM, _),
        stale(Id)
    ;   true
    ).

% --- Modi -------------------------------------------------------------------
% Je Belegung der übrigen Argumente (Schlüssel) bleibt eine Antwort: die
% beste nach dem Modus. Eine bessere ersetzt sie und zählt als Änderung.

add_moded(A, Id, P, Mode) :-
    A =.. [F|Args],
    nth1(P, Args, V, Key),
    '$tbl_mget'(Id, Key, Old),
    (   Old = some(OA)
    ->  OA =.. [_|OArgs],
        nth1(P, OArgs, OV),
        (   better(Mode, OV, V, NV)
        ->  nth1(P, NArgs, NV, Key),
            NA =.. [F|NArgs],
            '$tbl_mput'(Id, Key, NA)
        ;   true
        )
    ;   '$tbl_mput'(Id, Key, A)
    ).

% better(+Modus, +Alt, +Neu, -Wert): Neu verbessert Alt zu Wert
better(min, O, N, N) :- compare(<, N, O).
better(max, O, N, N) :- compare(>, N, O).
better(lattice(J), O, N, V) :-
    call(J, O, N, V),
    V \== O.
