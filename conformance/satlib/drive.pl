% PrologEx und SWI: jede Formel (expected/3) mit verdict/2 (sat.pl), je
% tlimit/1 Sekunden
:- use_module(library(time)).
run :-
    expected(F, _, _),
    tlimit(T),
    catch(call_with_time_limit(T, verdict(F, V)), E, V = E),
    format("~w ~w~n", [F, V]),
    fail.
run.
