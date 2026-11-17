% alle Sudokus (puzzle/2) und Golomb-Lineale bis zur Markenzahl gmax/1
run :- puzzle(N, _), verdict(N, V), format("~w ~w~n", [N, V]), fail.
run.
grun :-
    gmax(Max), upto(1, Max, N),
    catch(call_with_time_limit(600, g_verdict(N, V)), E, V = E),
    format("golomb~w ~w~n", [N, V]), flush_output, fail.
grun.
upto(I, Max, I) :- I =< Max.
upto(I, Max, N) :- I < Max, J is I + 1, upto(J, Max, N).
