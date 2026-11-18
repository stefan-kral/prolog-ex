% Die Tests eines Moduls aus Scryers src/tests (test(Name, Ziel), Rahmen
% test_framework.pl) einzeln: je Test eine Zeile "Name ok", "Name fail"
% oder "Name error(E)", höchstens 20 s je Test.
:- use_module(library(time)).
:- use_module(library(format)).

run_module(M) :-
    (   M:test(Name, Goal),
        (   catch(limited(M:Goal), E, true)
        ->  ( var(E) -> V = ok ; V = error(E) )
        ;   V = fail
        ),
        format("~s ~q~n", [Name, V]),
        flush_output,
        fail
    ;   true
    ).

% Scryer hat kein call_with_time_limit/2
limited(G) :-
    (   catch(current_prolog_flag(version_data, prolog_ex(_, _, _, _)), _, fail)
    ->  call_with_time_limit(20, G)
    ;   call(G)
    ).
