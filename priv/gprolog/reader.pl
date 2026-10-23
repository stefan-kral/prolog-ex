% Term-Reader für PrologEx – läuft als Kindprozess unter GNU Prolog.
%
% Übersetzen:  mix prolog.build_reader   (ruft gplc auf)
%
% Protokoll (eine Zeile pro Antwort, jeweils kanonisch mit Punkt):
%   stdin:   beliebiger Prolog-Text, danach '$batch_end'(N). als Markierung
%   stdout:  term(Term, VarNames).   je gelesenem Term
%            error(Fehlerterm).      bei Syntaxfehler, danach wird weitergelesen
%            batch_end(N).           wenn die Markierung erreicht ist
%            eof.                    bei echtem Dateiende, dann Ende
%
% Operator-Direktiven (:- op(...)) werden hier ausgeführt, damit folgende
% Terme richtig gelesen werden. Sie werden trotzdem auch weitergereicht.

:- initialization(main).

main :-
    set_prolog_flag(double_quotes, chars),
    loop.

loop :-
    catch(read_term(T, [variable_names(Vs)]), E, true),
    (   nonvar(E)
    ->  emit(error(E)), loop
    ;   T == end_of_file
    ->  emit(eof)
    ;   T = '$batch_end'(N)
    ->  emit(batch_end(N)), loop
    ;   run_op(T),
        emit(term(T, Vs)),
        loop
    ).

run_op((:- op(P, Ty, N))) :- !, catch(op(P, Ty, N), _, true).
run_op(_).

emit(X) :- write_canonical(X), write('.'), nl, flush_output.
