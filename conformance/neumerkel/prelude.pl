% Ersatz für Scryers library(charsio) & Co. über Dateien (nur ISO-Builtins)
'$tmpfile'(F) :- '$neumerkel_tmp'(F).

read_from_chars(Chars, T) :-
    '$tmpfile'(F),
    open(F, write, W), '$put_chars'(Chars, W), close(W),
    open(F, read, R),
    catch(read_term(R, T, []), E, (close(R), throw(E))),
    close(R).

'$put_chars'([], _).
'$put_chars'([C|Cs], S) :- put_char(S, C), '$put_chars'(Cs, S).

write_term_to_chars(Term, Options, Chars) :-
    '$tmpfile'(F),
    open(F, write, W), write_term(W, Term, Options), close(W),
    open(F, read, R), '$get_chars'(R, Chars), close(R).

'$get_chars'(S, Cs) :-
    get_char(S, C),
    (   C == end_of_file -> Cs = []
    ;   Cs = [C|Cs1], '$get_chars'(S, Cs1)
    ).

writeq_term_to_chars(Term, Chars) :-
    write_term_to_chars(Term, [ignore_ops(false), numbervars(true), quoted(true), variable_names([])], Chars).
write_term_to_chars(Term, Chars) :-
    write_term_to_chars(Term, [ignore_ops(false), numbervars(false), quoted(false), variable_names([])], Chars).
write_canonical_term_to_chars(Term, Chars) :-
    write_term_to_chars(Term, [ignore_ops(true), numbervars(false), quoted(true), variable_names([])], Chars).

% nur die Fehlerart zählt (die Bezeichnung in syntax_error/1 ist
% implementierungsabhängig)
test_syntax_error(ReadString, Expected) :-
    catch((once(read_from_chars(ReadString, _)), false), error(Error, _), true),
    nonvar(Error),
    functor(Expected, F, A), functor(Error, F, A).
