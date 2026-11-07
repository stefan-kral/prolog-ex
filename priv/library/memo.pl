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

:- meta_predicate(abolish_memo(:)).
:- meta_predicate(memo_statistics(:, -)).

% Hooks werden erst gebraucht, wenn eine Datei memo/1 benutzt: term_expansion/2
% gibt es nur, solange eine solche Datei geladen wird (sonst kostet das Laden
% anderer Dateien nichts)
:- '$expansion_hooks'.

% '$memo_decl'(Modul, Name, Stelligkeit, Innenname, Spec, Quelle)
:- dynamic('$memo_decl'/6).
% die Hülle Name/N ist in dieser Ladung schon erzeugt
:- dynamic('$memo_emitted'/3).
:- dynamic('$memo_hook_on'/0).

%% memo(+Spec): nur als Direktive
memo(Spec) :-
    (   prolog_load_context(module, M)
    ->  true
    ;   throw(error(context_error(nodirective, memo(Spec)), (memo)/1))
    ),
    load_source(Src),
    memo_spec(Spec, PIs, Opts),
    forall(member(N/A, PIs), declare(M, N, A, Opts, Src)),
    hook_on.

load_source(S) :-
    (   prolog_load_context(source, S0) -> S = S0 ; S = user ).

memo_spec(Spec, _, _) :-
    var(Spec), !,
    instantiation_error(Spec).
memo_spec((PIs0 as Os), PIs, Opts) :- !,
    pis(PIs0, PIs, []),
    options(Os, Opts).
memo_spec(PIs0, PIs, opts(none, false, false)) :-
    pis(PIs0, PIs, []).

pis(V, _, _) :-
    var(V), !,
    instantiation_error(V).
pis((A, B), PIs0, PIs) :- !,
    pis(A, PIs0, PIs1),
    pis(B, PIs1, PIs).
pis([], PIs, PIs) :- !.
pis([P|Ps], PIs0, PIs) :- !,
    pis(P, PIs0, PIs1),
    pis(Ps, PIs1, PIs).
pis(N//A0, [N/A|PIs], PIs) :- !,
    must_be(atom, N),
    must_be(not_less_than_zero, A0),
    A is A0 + 2.
pis(N/A, [N/A|PIs], PIs) :- !,
    must_be(atom, N),
    must_be(not_less_than_zero, A).
pis(P, _, _) :-
    type_error(predicate_indicator, P).

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

declare(M, N, A, Opts, Src) :-
    atom_concat(N, ' memo', Impl),
    retractall('$memo_decl'(M, N, A, _, _, _)),
    assertz('$memo_decl'(M, N, A, Impl, '$memo'(M, N, A, Opts), Src)),
    retractall('$memo_emitted'(M, N, A)),
    '$memo_abolish'(M:N/A).

hook_on :-
    (   '$memo_hook_on'
    ->  true
    ;   assertz('$memo_hook_on'),
        assertz((term_expansion(end_of_file, _) :- end_file, fail)),
        assertz((term_expansion(T, Ts) :- rename(T, Ts)))
    ).

% am Ende einer Datei: ihre Deklarationen sind erledigt; ohne weitere den
% Hook entfernen
end_file :-
    load_source(S),
    retractall('$memo_decl'(_, _, _, _, _, S)),
    (   '$memo_decl'(_, _, _, _, _, _)
    ->  true
    ;   retractall('$memo_hook_on'),
        retractall('$memo_emitted'(_, _, _)),
        abolish(term_expansion/2)
    ).

% Klauseln eines memoisierten Prädikats bekommen den Innennamen; vor der
% ersten steht die Hülle
rename(T, Ts) :-
    nonvar(T),
    clause_head(T, H, Extra),
    callable(H),
    prolog_load_context(module, M),
    functor(H, N, A0),
    A is A0 + Extra,
    '$memo_decl'(M, N, A, Impl, Spec, _), !,
    rename_head(T, Impl, T1),
    (   '$memo_emitted'(M, N, A)
    ->  Ts = T1
    ;   assertz('$memo_emitted'(M, N, A)),
        functor(Head, N, A),
        Head =.. [_|Args],
        Inner =.. [Impl|Args],
        Ts = [(Head :- (memo):'$memo_call'(Spec, Head, M:Inner)), T1]
    ).

clause_head((:- _), _, _) :- !, fail.
clause_head((?- _), _, _) :- !, fail.
clause_head((H :- _), H, 0) :- !.
clause_head((H --> _), H, 2) :- !.
clause_head(H, H, 0).

rename_head((H :- B), Impl, (H1 :- B)) :- !,
    rename_term(H, Impl, H1).
rename_head((H --> B), Impl, (H1 --> B)) :- !,
    rename_term(H, Impl, H1).
rename_head(H, Impl, H1) :-
    rename_term(H, Impl, H1).

rename_term(H, Impl, H1) :-
    H =.. [_|Args],
    H1 =.. [Impl|Args].

% --- Aufruf --------------------------------------------------------------

'$memo_call'(Spec, G, I) :-
    '$memo_lookup'(Spec, G, R),
    memo_(R, Spec, G, I).

memo_(answers(As), _, G, _) :-
    answer(As, G).
memo_(miss(T), Spec, G, I) :-
    Spec = '$memo'(_, _, _, opts(_, First, _)),
    catch(collect(First, G, I, As), E, ('$memo_drop'(T), throw(E))),
    '$memo_store'(T, As),
    answer(As, G).
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

% wie member/2, beim letzten Element ohne Wahlpunkt
answer([A|As], G) :-
    (   As == []
    ->  G = A
    ;   (   G = A
        ;   answer(As, G)
        )
    ).

% --- Verwaltung ----------------------------------------------------------

abolish_memo :-
    '$memo_abolish'(all).

abolish_memo(M:PI) :-
    pis(PI, [N/A], []),
    '$memo_abolish'(M:N/A).

memo_statistics(M:PI, Stats) :-
    pis(PI, [N/A], []),
    '$memo_stats'(M:N/A, Stats).
