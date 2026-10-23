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
% Dateien (für consult/use_module; Direktiven darin können die Syntax für
% den Rest der Datei ändern, z. B. Operatoren aus use_module):
%   stdin:   '$open'(Pfad).    Datei öffnen (oben auf einen Stapel)
%   stdout:  opened.  oder  error(Fehlerterm).
%   stdin:   '$next'.          Terme bis einschließlich der nächsten
%                              Direktive lesen
%   stdout:  term(...)/error(...) je Term, dann pause. (nach einer
%            Direktive) oder file_end. (Datei zu Ende, geschlossen)
% Während eine Datei pausiert, darf eine weitere geöffnet werden (use_module
% in einer Direktive); gelesen wird immer aus der obersten.
%
% Operator-Direktiven (:- op(...)) und :- set_prolog_flag(double_quotes, _)
% werden hier ausgeführt, damit folgende Terme richtig gelesen werden. Sie
% werden trotzdem auch weitergereicht.

:- initialization(main).

main :-
    set_prolog_flag(double_quotes, chars),
    % Präfix-Operatoren für Deklarationen wie in SWI/ISO-Praxis
    op(1150, fx, [dynamic, discontiguous, initialization, multifile, meta_predicate,
                  module_transparent, table, attribute]),
    loop.

loop :-
    catch(read_term(T, [variable_names(Vs)]), E, true),
    (   nonvar(E)
    ->  emit(error(E)), loop
    ;   T == end_of_file
    ->  emit(eof)
    ;   T = '$batch_end'(N)
    ->  emit(batch_end(N)), loop
    ;   T = '$open'(Path)
    ->  open_file(Path), loop
    ;   T == '$next'
    ->  next_chunk, loop
    ;   run_op(T),
        emit(term(T, Vs)),
        loop
    ).

run_op((:- op(P, Ty, N))) :- !, catch(op(P, Ty, N), _, true).
% Operatoren in der Exportliste von module/2 gelten (global) ab sofort
run_op((:- module(_, Exports))) :- !,
    (   is_list(Exports)
    ->  forall(member(op(P, Ty, N), Exports), catch(op(P, Ty, N), _, true))
    ;   true
    ).
run_op((:- set_prolog_flag(double_quotes, V))) :- !,
    catch(set_prolog_flag(double_quotes, V), _, true).
run_op(_).

emit(X) :- write_canonical(X), write('.'), nl, flush_output.

% --- Dateien ------------------------------------------------------------

open_file(Path) :-
    catch(( open(Path, read, S),
            g_read(files, Fs0), ( Fs0 == 0 -> Fs = [] ; Fs = Fs0 ),
            g_assign(files, [S|Fs]),
            emit(opened) ),
          E, emit(error(E))).

next_chunk :-
    g_read(files, Fs),
    (   Fs = [S|Rest]
    ->  chunk(S, Rest)
    ;   emit(file_end)
    ).

chunk(S, Rest) :-
    catch(read_term(S, T, [variable_names(Vs)]), E, true),
    (   nonvar(E)
    ->  emit(error(E)), chunk(S, Rest)
    ;   T == end_of_file
    ->  close(S), g_assign(files, Rest), emit(file_end)
    ;   run_op(T),
        emit(term(T, Vs)),
        (   T = (:- _)
        ->  emit(pause)
        ;   chunk(S, Rest)
        )
    ).
