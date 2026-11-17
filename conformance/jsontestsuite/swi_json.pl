% JSONTestSuite mit library(http/json): je Datei "Name accept|reject(F)|timeout".
% Angenommen: json_read/2 liest einen Wert, danach nur Leerraum (RFC 8259).
% Laeuft in SWI-Prolog und PrologEx; Dateien: file/1 und dir/1 (von run.sh).
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(time)).

run :- ( file(F), check(F, R), write(F), write(' '), writeq(R), nl, fail ; true ).

check(F, R) :-
    dir(D), atom_concat(D, F, P),
    catch(call_with_time_limit(10, parse(P, R)), E, err(E, R)).

err(time_limit_exceeded, timeout) :- !.
err(error(F, _), reject(N)) :- !, ( compound(F) -> functor(F, N, _) ; N = F ).
err(E, reject(E)).

parse(P, R) :-
    open(P, read, S, [encoding(utf8)]),
    catch(( json_read(S, _) -> ( rest_ws(S) -> R = accept ; R = reject(trailing) ) ; R = reject(fail) ),
          E, ( close(S), throw(E) )),
    close(S).

rest_ws(S) :- get_char(S, C), ( C == end_of_file -> true ; ws(C), rest_ws(S) ).

ws(' ').
ws('\t').
ws('\n').
ws('\r').
