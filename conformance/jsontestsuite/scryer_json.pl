% JSONTestSuite mit library(serialization/json) (json_chars//1): je Datei
% "Name accept|reject(F)". Laeuft in Scryer (je Datei ein Aufruf, path/1)
% und PrologEx (alle Dateien, file/1 und dir/1, mit Zeitlimit).
:- use_module(library(serialization/json)).
:- use_module(library(pio)).

one(P, R) :-
    catch(( phrase_from_file(json_chars(_), P) -> R = accept ; R = reject(fail) ),
          E, err(E, R)).

err(error(F, _), reject(N)) :- compound(F), !, functor(F, N, _).
err(error(F, _), reject(F)) :- !.
err(E, reject(E)).

% Scryer: eine Datei
run1 :- path(P), one(P, R), writeq(R), nl.
