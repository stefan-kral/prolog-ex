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
% Operatoren (op/3 und current_op/3 als Prädikate):
%   stdin:   '$op'(P, T, Ops).   op/3 ausführen
%   stdout:  op_ok.  oder  op_error(Fehlerterm).
%   stdin:   '$ops'.             die aktuelle Operatortabelle
%   stdout:  ops([op(P, T, Name), ...]).
%
% Für Tests des Writers: gprologs writeq-Text eines Terms
%   stdin:   '$writeq'(T).
%   stdout:  writeq('Text').
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
    % Variante (wie SWI)
    op(700, xfx, [=@=, \=@=]),
    % ISO Cor. 2 (wie SWI)
    op(400, yfx, xor),
    loop.

% Fehlschlag-getriebene Schleife: gprolog hat keine Speicherbereinigung für
% den globalen Stack, Speicher wird nur beim Backtracking frei. Eine
% rekursive Schleife behielte jeden gelesenen Term (nach ~70 000 Termen:
% global stack overflow). So wird nach jedem Schritt alles freigegeben;
% die offenen Dateien stehen in g_assign-Variablen (überstehen das).
loop :-
    repeat,
    catch(read_term(T, [variable_names(Vs)]), E, true),
    step(E, T, Vs, R),
    R == stop,
    !.

step(E, _, _, cont) :- nonvar(E), !, emit(error(E)).
step(_, T, Vs, cont) :- var(T), !, emit(term(T, Vs)).   % sonst passte T = '$batch_end'(N) & Co.
step(_, T, _, stop) :- T == end_of_file, !, emit(eof).
step(_, '$batch_end'(N), _, cont) :- !, emit(batch_end(N)).
step(_, '$open'(Path), _, cont) :- !, open_file(Path).
step(_, T, _, cont) :- T == '$next', !, next_chunk.
step(_, '$op'(P, Ty, N), _, cont) :- !,
    catch((op(P, Ty, N), R = op_ok), E, R = op_error(E)),
    emit(R).
step(_, '$writeq'(X), _, cont) :- !,
    format_to_atom(A, '~q', [X]),
    emit(writeq(A)).
step(_, T, _, cont) :- T == '$ops', !,
    findall(op(P, Ty, N), current_op(P, Ty, N), L),
    emit(ops(L)).
step(_, T, Vs, cont) :-
    run_op(T),
    emit(term(T, Vs)).

% Nur echte Direktiven: Variablen dürfen nicht an op(...) usw. gebunden
% werden (sonst änderte sich der gelesene Term, z. B. bei ":- X.")
run_op(T) :- var(T), !.
run_op((:- D)) :- nonvar(D), run_directive(D), !.
run_op(_).

run_directive(op(P, Ty, N)) :- catch(op(P, Ty, N), _, true).
% Operatoren in der Exportliste von module/2 gelten (global) ab sofort
run_directive(module(_, Exports)) :-
    (   is_list(Exports)
    ->  forall(( member(E, Exports), nonvar(E), E = op(P, Ty, N) ),
               catch(op(P, Ty, N), _, true))
    ;   true
    ).
run_directive(set_prolog_flag(F, V)) :-
    F == double_quotes,
    catch(set_prolog_flag(double_quotes, V), _, true).

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

% wie loop/0 fehlschlag-getrieben (eine große Datei ohne Direktiven ist ein
% einziger Abschnitt)
chunk(S, Rest) :-
    repeat,
    catch(read_term(S, T, [variable_names(Vs)]), E, true),
    chunk_step(E, T, Vs, S, Rest, R),
    R \== cont,
    !.

chunk_step(E, _, _, _, _, cont) :- nonvar(E), !, emit(error(E)).
chunk_step(_, T, _, S, Rest, done) :- T == end_of_file, !,
    close(S), g_assign(files, Rest), emit(file_end).
chunk_step(_, T, Vs, _, _, R) :-
    run_op(T),
    emit(term(T, Vs)),
    (   nonvar(T), T = (:- _)
    ->  emit(pause), R = paused
    ;   R = cont
    ).
