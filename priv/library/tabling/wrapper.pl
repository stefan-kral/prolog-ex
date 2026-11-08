/* library(tabling/wrapper): gemeinsamer Teil von library(memo) und
   library(tabling) (intern)

   Eine Direktive wie `:- memo p/2.` oder `:- table p/2.` meldet p/2 hier
   an (wrap_declare/6). Bis zum Ende der geladenen Datei bekommen dann die
   Klauseln von p/2 einen Innennamen ('p memo'/2, 'p tabled'/2), und vor der
   ersten steht eine Hülle

       p(X, Y) :- Mod:Pred(Spec, p(X, Y), M:'p memo'(X, Y)).

   Den Expansions-Hook (term_expansion/2 in diesem Modul) gibt es nur,
   solange eine Datei mit solchen Direktiven geladen wird: das Laden anderer
   Dateien kostet nichts.
*/

:- module(table_wrapper, [wrap_declare/6, directive_module/2, pis/3]).

:- use_module(library(error)).

:- '$expansion_hooks'.

% '$wrap_decl'(Modul, Name, Stelligkeit, Innenname, Aufruf, Quelle)
:- dynamic('$wrap_decl'/6).
% die Hülle Name/N ist in dieser Ladung schon erzeugt
:- dynamic('$wrap_emitted'/3).
:- dynamic('$wrap_hook_on'/0).

%% directive_module(+Directive, -Module): das Modul, in das gerade geladen
%  wird; außerhalb des Ladens context_error(nodirective, Directive)
directive_module(D, M) :-
    (   prolog_load_context(module, M0)
    ->  M = M0
    ;   functor(D, N, A),
        throw(error(context_error(nodirective, D), (N)/A))
    ).

%% pis(+Spec, -PIs, ?Tail): N/A, N//A (als N/A+2), Konjunktion oder Liste
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

%% wrap_declare(+M, +N, +A, +Suffix, +Call, +Spec): M:N/A umhüllen; Call
%  ist Mod:Pred, die Hülle ruft Mod:Pred(Spec, Kopf, M:Innen)
wrap_declare(M, N, A, Suffix, Mod:Pred, Spec) :-
    load_source(Src),
    atom_concat(N, Suffix, Impl),
    retractall('$wrap_decl'(M, N, A, _, _, _)),
    assertz('$wrap_decl'(M, N, A, Impl, call(Mod, Pred, Spec), Src)),
    retractall('$wrap_emitted'(M, N, A)),
    hook_on.

load_source(S) :-
    (   prolog_load_context(source, S0) -> S = S0 ; S = user ).

hook_on :-
    (   '$wrap_hook_on'
    ->  true
    ;   assertz('$wrap_hook_on'),
        assertz((term_expansion(end_of_file, _) :- end_file, fail)),
        assertz((term_expansion(T, Ts) :- rename(T, Ts)))
    ).

% am Ende einer Datei: ihre Deklarationen sind erledigt; ohne weitere den
% Hook entfernen
end_file :-
    load_source(S),
    retractall('$wrap_decl'(_, _, _, _, _, S)),
    (   '$wrap_decl'(_, _, _, _, _, _)
    ->  true
    ;   retractall('$wrap_hook_on'),
        retractall('$wrap_emitted'(_, _, _)),
        abolish(term_expansion/2)
    ).

% Klauseln eines umhüllten Prädikats bekommen den Innennamen; vor der
% ersten steht die Hülle
rename(T, Ts) :-
    nonvar(T),
    clause_head(T, H, Extra),
    callable(H),
    prolog_load_context(module, M),
    functor(H, N, A0),
    A is A0 + Extra,
    '$wrap_decl'(M, N, A, Impl, call(Mod, Pred, Spec), _), !,
    rename_head(T, Impl, T1),
    (   '$wrap_emitted'(M, N, A)
    ->  Ts = T1
    ;   assertz('$wrap_emitted'(M, N, A)),
        functor(Head, N, A),
        Head =.. [_|Args],
        Inner =.. [Impl|Args],
        Body =.. [Pred, Spec, Head, M:Inner],
        Ts = [(Head :- Mod:Body), T1]
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

%% answer(+Antworten, ?G): wie member/2, beim letzten Element ohne Wahlpunkt
answer([A|As], G) :-
    (   As == []
    ->  G = A
    ;   (   G = A
        ;   answer(As, G)
        )
    ).
