% PrologEx: alle Dateien mit json_chars//1 (scryer_json.pl), je 10 s
:- use_module(library(time)).
run :- ( file(F), dir(D), atom_concat(D, F, P),
         catch(call_with_time_limit(10, one(P, R)), time_limit_exceeded, R = timeout),
         write(F), write(' '), writeq(R), nl, fail ; true ).
