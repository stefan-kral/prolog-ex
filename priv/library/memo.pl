/* library(memo): Memoisierung (PrologEx)

   :- use_module(library(memo)).
   :- memo fib/2.
   :- memo edit/3 as lru(10000).
   :- memo parse//1 as [first, fifo(500)].

   Ein memoisiertes Prädikat rechnet jede Variante eines Aufrufs nur
   einmal ganz durch und liefert sie danach aus der Tabelle. Die Bedeutung
   bleibt die des normalen Prolog: dieselben Antworten in derselben
   Reihenfolge, Duplikate bleiben, Seiteneffekte laufen beim ersten Rechnen.
   Das Prädikat muss dafür auch ohne Memo terminieren – Memo spart nur
   Arbeit (für Links- und Zyklenrekursion: library(tabling)).

   Optionen (nach `as`, einzeln oder als Liste):
     * lru(N)     höchstens N Einträge, der am längsten nicht benutzte fällt
     * fifo(N)    höchstens N Einträge, der älteste fällt
     * first      nur die erste Lösung (wie once/1) rechnen und merken
     * reentrant  ruft sich eine Variante, während sie noch läuft, selbst
                  auf, rechnet der innere Aufruf wie normales Prolog (sonst:
                  permission_error(reenter, memo, N/A) – in reinem Code wäre
                  das eine Endlosschleife)

   Varianten: p(X, a) und p(Y, a) teilen sich einen Eintrag, p(a, a)
   nicht. Attributierte Variablen im Aufruf: representation_error.

   Gemerkt wird erst, wenn ein Aufruf ganz durchgerechnet ist (eifrig: beim
   ersten Aufruf werden alle Antworten gesammelt, wie mit findall/3). Eine
   Ausnahme dabei (auch Zeit- oder Speichergrenze) hinterlässt nichts.

   Die Direktive steht vor den Klauseln des Prädikats; dessen Klauseln
   werden zu 'Name memo'/N, Name/N ruft die Tabelle. Lädt man die Datei
   neu, beginnt die Tabelle leer. Hängt das Prädikat von dynamischen
   Prädikaten ab, veraltet die Tabelle still, wenn sich diese ändern:
   abolish_memo/0,1.

   abolish_memo/0         alle Tabellen leeren
   abolish_memo(:PI)      die Tabelle von PI (N/A oder N//A) leeren
   memo_statistics(:PI, -Stats)
                          [entries(E), hits(H), misses(M), evictions(V)]
*/

:- module(memo, [(memo)/1,
                 abolish_memo/0,
                 abolish_memo/1,
                 memo_statistics/2,
                 op(1150, fx, memo),
                 op(1100, xfx, as)]).

:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(library(iso_ext), [forall/2]).
:- use_module(library(apply), [foldl/4]).
:- use_module(library(tabling/wrapper), [wrap_declare/6, directive_module/2, pis/3]).

:- meta_predicate(abolish_memo(:)).
:- meta_predicate(memo_statistics(:, -)).

%% memo(+Spec): nur als Direktive
memo(Spec) :-
    directive_module(memo(Spec), M),
    memo_spec(Spec, PIs, Opts),
    forall(member(N/A, PIs),
           (   wrap_declare(M, N, A, ' memo', (memo):'$memo_call', '$memo'(M, N, A, Opts)),
               '$memo_abolish'(M:N/A)
           )).

memo_spec(Spec, _, _) :-
    var(Spec), !,
    instantiation_error(Spec).
memo_spec((PIs0 as Os), PIs, Opts) :- !,
    pis(PIs0, PIs, []),
    options(Os, Opts).
memo_spec(PIs0, PIs, opts(none, false, false)) :-
    pis(PIs0, PIs, []).

options(Os, _) :-
    var(Os), !,
    instantiation_error(Os).
options(Os0, opts(P, F, R)) :-
    (   Os0 = [_|_] -> Os = Os0 ; Os0 == [] -> Os = [] ; Os = [Os0] ),
    must_be(list, Os),
    foldl(option, Os, opts(none, false, false), opts(P, F, R)).

option(O, _, _) :-
    var(O), !,
    instantiation_error(O).
option(lru(N), opts(none, F, R), opts(lru(N), F, R)) :-
    positive(N), !.
option(fifo(N), opts(none, F, R), opts(fifo(N), F, R)) :-
    positive(N), !.
option(first, opts(P, _, R), opts(P, true, R)) :- !.
option(reentrant, opts(P, F, _), opts(P, F, true)) :- !.
option(O, _, _) :-
    domain_error(memo_option, O).

positive(N) :-
    must_be(integer, N),
    (   N > 0 -> true ; domain_error(positive_integer, N) ).

% --- Aufruf --------------------------------------------------------------

'$memo_call'(Spec, G, I) :-
    '$memo_lookup'(Spec, G, R),
    memo_(R, Spec, G, I).

memo_(answers(As), _, G, _) :-
    table_wrapper:answer(As, G).
memo_(miss(T), Spec, G, I) :-
    Spec = '$memo'(_, _, _, opts(_, First, _)),
    catch(collect(First, G, I, As), E, ('$memo_drop'(T), throw(E))),
    '$memo_store'(T, As),
    table_wrapper:answer(As, G).
memo_(running, Spec, G, I) :-
    Spec = '$memo'(_, N, A, opts(_, _, Re)),
    (   Re == true
    ->  call(I)
    ;   throw(error(permission_error(reenter, memo, N/A),
                    context(G, 'dieselbe Variante ruft sich selbst auf, bevor sie fertig ist (Endlosschleife in reinem Code; table/1?)')))
    ).

collect(false, G, I, As) :-
    findall(G, I, As).
collect(true, G, I, As) :-
    findall(G, once(I), As).

% --- Verwaltung ----------------------------------------------------------

abolish_memo :-
    '$memo_abolish'(all).

abolish_memo(M:PI) :-
    pis(PI, [N/A], []),
    '$memo_abolish'(M:N/A).

memo_statistics(M:PI, Stats) :-
    pis(PI, [N/A], []),
    '$memo_stats'(M:N/A, Stats).
