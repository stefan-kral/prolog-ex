% Nachbau des Teils von Logtalks lgtunit, den die ISO-Konformitätstests in
% logtalk3/tests/prolog brauchen – damit sie ohne Logtalk direkt in
% PrologEx laufen (siehe conformance/run.exs).
%
% Die Testobjekte werden zu Klauseln dieses Moduls: Ziele in {...} laufen
% in user (das getestete Prolog), ^^Helfer und lokale Prädikate des
% Testobjekts hier. Ausgang und Optionen wie in lgtunit
% (convert_test_outcome/10, check_error/10 in tools/lgtunit/lgtunit.lgt).

:- module(lgt, []).

:- dynamic(lgt_dir/1).

:- op(700, xfx, =~=).

% ungefähre Gleichheit von Gleitkommazahlen (wie lgtunit)
'=~='(X, _) :- var(X), !, throw(error(instantiation_error, _)).
'=~='(_, Y) :- var(Y), !, throw(error(instantiation_error, _)).
'=~='([], []) :- !.
'=~='([X|Xs], [Y|Ys]) :- !, '=~='(X, Y), '=~='(Xs, Ys).
'=~='(X, Y) :-
    number(X), number(Y),
    (   abs(X - Y) < 100 * epsilon -> true
    ;   abs(X - Y) < 0.00001 * max(abs(X), abs(Y))
    ).

epsilon(E) :- E is epsilon.

% '$lgt_run'(+Outcome, +Goal, +Options, -Result)
% Result: passed, skipped oder failed(Grund)
'$lgt_run'(Outcome, Goal, Options, Result) :-
    (   memberchk_(condition(C), Options),
        \+ catch(C, _, fail)
    ->  Result = skipped
    ;   (   memberchk_(setup(S), Options)
        ->  (   catch(S, E, (Result = failed(setup_error(E)), true))
            ->  true
            ;   Result = failed(setup_failed)
            )
        ;   true
        ),
        (   var(Result)
        ->  catch(outcome(Outcome, Goal, Result0), E2, Result0 = failed(error(E2))),
            Result = Result0
        ;   true
        ),
        (   memberchk_(cleanup(Cl), Options)
        ->  catch(Cl, _, true) -> true ; true
        ;   true
        )
    ),
    !.
'$lgt_run'(_, _, _, failed(harness)).

memberchk_(X, [Y|Ys]) :- ( X = Y -> true ; memberchk_(X, Ys) ).

% Ziel einmal: success, failure oder error(E); Bindungen bleiben
once_status(G, S) :-
    catch(( call(G) -> S = success ; S = failure ), E, S = error(E)).

check(A, R) :-
    catch(( \+ \+ call(A) -> R = passed ; R = failed(assertion(A)) ),
          E, R = failed(assertion_error(E))).

after(success, A, R) :- !, check(A, R).
after(failure, _, failed(failure)).
after(error(E), _, failed(error(E))).

outcome(true, G, R) :- !, once_status(G, S), after(S, true, R).
% wie lgtunit: die Zusicherung wird geprüft, solange die Choice Points von G
% noch stehen (erst danach wird abgeschnitten)
outcome(true(A), G, R) :- !,
    catch(( call(G), check(A, R0) -> R = R0 ; R = failed(failure) ),
          E, R = failed(error(E))).
outcome(deterministic, G, R) :- !, outcome(deterministic(true), G, R).
outcome(deterministic(A), G, R) :- !,
    once_status(call_with_inference_limit(G, 100000000, D), S),
    (   S == success, D \== !
    ->  R = failed(nondeterministic)
    ;   after(S, A, R)
    ).
outcome(subsumes(Exp, Res), G, R) :- !, outcome(true(subsumes_term(Exp, Res)), G, R).
outcome(variant(T1, T2), G, R) :- !, outcome(true(T1 =@= T2), G, R).
outcome(exists(A), G, R) :- !,
    once_status((G, A), S), after(S, true, R).
outcome(all(A), G, R) :- !,
    catch(( \+ (G, \+ A) -> R = passed ; R = failed(all) ), E, R = failed(error(E))).
outcome(fail, G, R) :- !, outcome(false, G, R).
outcome(false, G, R) :- !,
    once_status(G, S),
    (   S == failure -> R = passed
    ;   S == success -> R = failed(success)
    ;   S = error(E), R = failed(error(E))
    ).
outcome(error(B), G, R) :- !, balls([error(B, _)], G, R).
outcome(errors(Bs), G, R) :- !, errors_balls(Bs, Es), balls(Es, G, R).
outcome(ball(B), G, R) :- !, balls([B], G, R).
outcome(balls(Bs), G, R) :- !, balls(Bs, G, R).
outcome(O, _, failed(unknown_outcome(O))).

errors_balls([], []).
errors_balls([B|Bs], [error(B, _)|Es]) :- errors_balls(Bs, Es).

balls(Expected, G, R) :-
    once_status(G, S),
    (   S = error(E)
    ->  (   member_(X, Expected), subsumes_term(X, E)
        ->  R = passed
        ;   R = failed(wrong_error(E))
        )
    ;   R = failed(S)
    ).

member_(X, [X|_]).
member_(X, [_|Xs]) :- member_(X, Xs).

% --- Helfer von lgtunit (Ein-/Ausgabe) ---------------------------------

file_path(File, Path) :-
    (   sub_atom(File, 0, 1, _, '/')
    ->  Path = File
    ;   lgt_dir(D), atom_concat(D, File, Path)
    ).

assertion(G) :- \+ \+ call(G).
assertion(_, G) :- \+ \+ call(G).

variant(T1, T2) :- T1 =@= T2.

suppress_text_output :-
    open('/dev/null', write, S, [type(text)]), set_output(S).
suppress_binary_output :-
    open('/dev/null', write, S, [type(binary)]), set_output(S).

set_text_input(Alias, Contents, Options) :-
    clean_file(Alias, 'test_input.text', Path),
    open(Path, write, W, [type(text)|Options]),
    write_text_contents(W, Contents),
    close(W),
    open(Path, read, _, [type(text), alias(Alias)|Options]).
set_text_input(Alias, Contents) :- set_text_input(Alias, Contents, []).
set_text_input(Contents) :-
    clean_file('test_input.text', Path),
    open(Path, write, W, [type(text)]),
    write_text_contents(W, Contents),
    close(W),
    open(Path, read, R, [type(text)]),
    set_input(R).

check_text_input(Alias, Expected) :-
    get_text_contents(Alias, Expected, Contents),
    clean_text_input,
    Expected == Contents.
check_text_input(Expected) :-
    current_input(S),
    get_text_contents(S, Expected, Contents),
    clean_text_input,
    Expected == Contents.

text_input_assertion(Alias, Expected, Expected == Contents) :-
    get_text_contents(Alias, Expected, Contents),
    clean_text_input.
text_input_assertion(Expected, Expected == Contents) :-
    current_input(S),
    get_text_contents(S, Expected, Contents),
    clean_text_input.

clean_text_input :- clean_file('test_input.text', _).

set_binary_input(Alias, Bytes, Options) :-
    clean_file(Alias, 'test_input.binary', Path),
    open(Path, write, W, [type(binary)|Options]),
    write_binary_contents(Bytes, W),
    close(W),
    open(Path, read, _, [type(binary), alias(Alias)|Options]).
set_binary_input(Alias, Bytes) :- set_binary_input(Alias, Bytes, []).
set_binary_input(Bytes) :-
    clean_file('test_input.binary', Path),
    open(Path, write, W, [type(binary)]),
    write_binary_contents(Bytes, W),
    close(W),
    open(Path, read, R, [type(binary)]),
    set_input(R).

check_binary_input(Alias, Expected) :-
    get_binary_contents(Alias, Expected, Contents),
    clean_binary_input,
    Expected == Contents.
check_binary_input(Expected) :-
    current_input(S),
    get_binary_contents(S, Expected, Contents),
    clean_binary_input,
    Expected == Contents.

binary_input_assertion(Alias, Expected, Expected == Contents) :-
    get_binary_contents(Alias, Expected, Contents),
    clean_binary_input.
binary_input_assertion(Expected, Expected == Contents) :-
    current_input(S),
    get_binary_contents(S, Expected, Contents),
    clean_binary_input.

clean_binary_input :- clean_file('test_input.binary', _).

set_text_output(Alias, Contents, Options) :-
    clean_file(Alias, 'test_output.text', Path),
    open(Path, write, S, [type(text), alias(Alias)|Options]),
    write_text_contents(S, Contents).
set_text_output(Alias, Contents) :- set_text_output(Alias, Contents, []).
set_text_output(Contents) :-
    clean_file('test_output.text', Path),
    open(Path, write, S, [type(text)]),
    write_text_contents(S, Contents),
    set_output(S).

check_text_output(Alias, Expected, Options) :-
    close(Alias),
    file_path('test_output.text', Path),
    open(Path, read, In, Options),
    get_text_contents(In, Expected, Contents),
    clean_text_output,
    Expected == Contents.
check_text_output(Alias, Expected) :- check_text_output(Alias, Expected, []).
check_text_output(Expected) :-
    current_output(Out),
    close(Out),
    file_path('test_output.text', Path),
    open(Path, read, In),
    get_text_contents(In, Expected, Contents),
    clean_text_output,
    Expected == Contents.

text_output_assertion(Alias, Expected, Options, Expected == Contents) :-
    close(Alias),
    file_path('test_output.text', Path),
    open(Path, read, In, Options),
    get_text_contents(In, Expected, Contents),
    clean_text_output.
text_output_assertion(Alias, Expected, Expected == Contents) :-
    text_output_assertion(Alias, Expected, [], Expected == Contents).
text_output_assertion(Expected, Expected == Contents) :-
    current_output(Out),
    close(Out),
    file_path('test_output.text', Path),
    open(Path, read, In),
    get_text_contents(In, Expected, Contents),
    clean_text_output.

text_output_contents(Alias, Contents, Options) :-
    close(Alias),
    file_path('test_output.text', Path),
    open(Path, read, In, Options),
    get_text_contents(In, Contents),
    clean_text_output.
text_output_contents(Alias, Contents) :-
    close(Alias),
    file_path('test_output.text', Path),
    open(Path, read, In),
    get_text_contents(In, Contents),
    clean_text_output.
text_output_contents(Contents) :-
    current_output(Out),
    close(Out),
    file_path('test_output.text', Path),
    open(Path, read, In),
    get_text_contents(In, Contents),
    clean_text_output.

clean_text_output :- clean_file('test_output.text', _).

set_binary_output(Alias, Bytes, Options) :-
    clean_file(Alias, 'test_output.binary', Path),
    open(Path, write, S, [type(binary), alias(Alias)|Options]),
    write_binary_contents(Bytes, S).
set_binary_output(Alias, Bytes) :- set_binary_output(Alias, Bytes, []).
set_binary_output(Bytes) :-
    clean_file('test_output.binary', Path),
    open(Path, write, S, [type(binary)]),
    write_binary_contents(Bytes, S),
    set_output(S).

check_binary_output(Alias, Expected) :-
    close(Alias),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Expected, Contents),
    clean_binary_output,
    Expected == Contents.
check_binary_output(Expected) :-
    current_output(Out),
    close(Out),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Expected, Contents),
    clean_binary_output,
    Expected == Contents.

binary_output_assertion(Alias, Expected, Expected == Contents) :-
    close(Alias),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Expected, Contents),
    clean_binary_output.
binary_output_assertion(Expected, Expected == Contents) :-
    current_output(Out),
    close(Out),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Expected, Contents),
    clean_binary_output.

binary_output_contents(Alias, Contents) :-
    close(Alias),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Contents),
    clean_binary_output.
binary_output_contents(Contents) :-
    current_output(Out),
    close(Out),
    file_path('test_output.binary', Path),
    open(Path, read, In, [type(binary)]),
    get_binary_contents(In, Contents),
    clean_binary_output.

clean_binary_output :- clean_file('test_output.binary', _).

create_text_file(File, Contents, Options) :-
    file_path(File, Path),
    open(Path, write, S, Options),
    write_text_contents(S, Contents),
    close(S).
create_text_file(File, Contents) :- create_text_file(File, Contents, []).

create_binary_file(File, Bytes) :-
    file_path(File, Path),
    open(Path, write, S, [type(binary)]),
    write_binary_contents(Bytes, S),
    close(S).

check_text_file(File, Expected, Options) :-
    file_path(File, Path),
    open(Path, read, S, Options),
    get_text_contents(S, Expected, Contents),
    Expected == Contents.
check_text_file(File, Expected) :- check_text_file(File, Expected, []).

text_file_assertion(File, Expected, Options, Expected == Contents) :-
    file_path(File, Path),
    open(Path, read, S, Options),
    get_text_contents(S, Expected, Contents).
text_file_assertion(File, Expected, Assertion) :-
    text_file_assertion(File, Expected, [], Assertion).

check_binary_file(File, Expected) :-
    file_path(File, Path),
    open(Path, read, S, [type(binary)]),
    get_binary_contents(S, Expected, Contents),
    Expected == Contents.

binary_file_assertion(File, Expected, Expected == Contents) :-
    file_path(File, Path),
    open(Path, read, S, [type(binary)]),
    get_binary_contents(S, Expected, Contents).

clean_file(File) :- clean_file(File, _).
clean_file(File, Path) :-
    file_path(File, Path),
    forall(stream_property(S, file_name(Path)), close(S)),
    (   exists_file(Path) -> delete_file(Path) ; true ).
clean_file(Alias, File, Path) :-
    (   stream_property(S, alias(Alias)) -> close(S) ; true ),
    clean_file(File, Path).

write_text_contents(S, Contents) :-
    (   atom(Contents) -> write(S, Contents)
    ;   write_text_contents_list(Contents, S)
    ).
write_text_contents_list([], _).
write_text_contents_list([A|As], S) :-
    write(S, A),
    write_text_contents_list(As, S).

get_text_contents(S, Expected, Contents) :-
    atom_length(Expected, Length),
    Limit is Length + 1,
    get_chars(S, Chars, Limit),
    atom_chars(Contents, Chars).

get_chars(S, Chars, Countdown) :-
    get_char(S, C),
    (   C == end_of_file -> Chars = [], close(S)
    ;   Countdown =< 0 -> Chars = []
    ;   Chars = [C|Rest], N is Countdown - 1, get_chars(S, Rest, N)
    ).

get_text_contents(S, Chars) :-
    get_char(S, C),
    (   C == end_of_file -> Chars = [], close(S)
    ;   Chars = [C|Rest], get_text_contents(S, Rest)
    ).

write_binary_contents([], _).
write_binary_contents([B|Bs], S) :-
    put_byte(S, B),
    write_binary_contents(Bs, S).

get_binary_contents(S, Expected, Bytes) :-
    length(Expected, Length),
    Limit is Length + 1,
    get_bytes(S, Bytes, Limit).

get_bytes(S, Bytes, Countdown) :-
    get_byte(S, B),
    (   B == -1 -> close(S), Bytes = []
    ;   Countdown =< 0 -> Bytes = []
    ;   Bytes = [B|Rest], N is Countdown - 1, get_bytes(S, Rest, N)
    ).

get_binary_contents(S, Bytes) :-
    get_byte(S, B),
    (   B == -1 -> close(S), Bytes = []
    ;   Bytes = [B|Rest], get_binary_contents(S, Rest)
    ).

closed_input_stream(R, Options) :-
    file_path(temporary_file, Path),
    open(Path, write, W),
    close(W),
    open(Path, read, R, Options),
    close(R),
    delete_file(Path).

closed_output_stream(W, Options) :-
    file_path(temporary_file, Path),
    open(Path, write, W, Options),
    close(W),
    delete_file(Path).

stream_position(Position) :-
    file_path(temporary_file, Path),
    open(Path, write, S),
    stream_property(S, position(Position)),
    close(S),
    delete_file(Path).
