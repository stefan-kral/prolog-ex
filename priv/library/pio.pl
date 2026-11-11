% library(pio): reine Eingabe (pure I/O) wie in SWI und Scryer –
% DCGs über den Inhalt einer Datei oder eines Streams, ohne ihn ganz
% einzulesen.
%
%   phrase_from_file(G, Datei)          phrase(G, Inhalt), Inhalt faul gelesen
%   phrase_from_file(G, Datei, Opts)    Opts: as(chars|codes), sonst für open/4
%   phrase_from_stream(G, S)            dasselbe für einen offenen Stream
%   phrase_from_stream(G, S, Opts)      Opts: as(chars|codes)
%   stream_to_lazy_list(S, L)           L: faule Liste der restlichen Zeichen
%   stream_to_lazy_chars(S, L), stream_to_lazy_codes(S, L)
%   lazy_list_character_count(N)//      Zeichennummer an dieser Stelle (ab 0)
%   lazy_list_location(Ort)//           file(Datei, Zeile, Spalte, Zeichen)
%                                       oder stream(S, Zeile, Spalte, Zeichen)
%   syntax_error(E)//                   throw(error(syntax_error(E), Ort))
%   phrase_to_file(G, Datei), phrase_to_file(G, Datei, Opts),
%   phrase_to_stream(G, S)              phrase(G, Ls), Ls schreiben (Scryer);
%                                       phrase_to_file/2,3: Backtracking
%                                       nimmt Geschriebenes zurück
%   phrase_to_stream(G, S, Opts)        ebenso auf einem offenen Stream;
%                                       Opts: undo(true|false)
%
% Ohne as(...) richtet sich die Liste nach dem Flag double_quotes: codes
% bei double_quotes = codes, sonst chars (Voreinstellung; wie Scryer). So
% passen "..." in der Grammatik und die gelesene Liste zusammen. (SWI
% nimmt immer codes.)
%
% Die faule Liste: ihr noch nicht gelesener Rest wartet mit freeze/2. Wird
% er gebunden, kommt der nächste Block des Streams (256 Zeichen) dazu.
% Gelesene Blöcke merkt sich der Stream, bis er geschlossen wird; nach dem
% Rücksetzen werden sie nicht neu gelesen. Am Ende ist der Rest [].
% Nach close/1 lässt sich nicht mehr in die Liste zurücksetzen (Blöcke
% wieder brauchen: existence_error(stream, S)) – phrase_from_file/2,3
% schließt erst, wenn die Grammatik erschöpft ist oder abgeschnitten wird.

:- module(pio, [phrase_from_file/2, phrase_from_file/3,
                phrase_from_stream/2, phrase_from_stream/3,
                stream_to_lazy_list/2, stream_to_lazy_chars/2,
                stream_to_lazy_codes/2,
                lazy_list_character_count//1, lazy_list_location//1,
                syntax_error//1,
                phrase_to_file/2, phrase_to_file/3, phrase_to_stream/2,
                phrase_to_stream/3]).

:- meta_predicate
       phrase_from_file(//, +),
       phrase_from_file(//, +, +),
       phrase_from_stream(//, +),
       phrase_from_stream(//, +, +),
       phrase_to_file(//, +),
       phrase_to_file(//, +, +),
       phrase_to_stream(//, +),
       phrase_to_stream(//, +, +).

phrase_from_file(G, File) :-
   phrase_from_file(G, File, []).

phrase_from_file(G, File, Options) :-
   '$pio_options'(Options, Type, OpenOptions),
   setup_call_cleanup(open(File, read, S, OpenOptions),
                      '$phrase_lazy'(G, S, Type),
                      close(S)).

phrase_from_stream(G, S) :-
   phrase_from_stream(G, S, []).

phrase_from_stream(G, S, Options) :-
   '$pio_options'(Options, Type, Rest),
   (  Rest == [] -> true
   ;  Rest = [O|_],
      throw(error(domain_error(phrase_from_stream_option, O), phrase_from_stream/3))
   ),
   '$phrase_lazy'(G, S, Type).

'$phrase_lazy'(G, S, Type) :-
   '$lazy_list'(S, Type, L),
   phrase(G, L).

stream_to_lazy_list(S, L) :-
   '$pio_default'(Type),
   '$lazy_list'(S, Type, L).

stream_to_lazy_chars(S, L) :-
   '$lazy_list'(S, chars, L).

stream_to_lazy_codes(S, L) :-
   '$lazy_list'(S, codes, L).

% as(Typ) herausnehmen (das erste gilt), der Rest geht an open/4. Keine
% Liste: unverändert weiter, open/4 meldet den Fehler.
'$pio_options'(Os, Type, Open) :-
   '$pio_default'(Type0),
   '$skip_list'(_, Os, Tail),
   (  Tail == []
   -> '$pio_opts'(Os, Type0, -, Type, Open)
   ;  Type = Type0, Open = Os
   ).

'$pio_opts'([], T0, T1, T, []) :-
   ( T1 == (-) -> T = T0 ; T = T1 ).
'$pio_opts'([O|Os], T0, T1, T, Open) :-
   (  nonvar(O), O = as(A)
   -> '$pio_type'(A),
      ( T1 == (-) -> T2 = A ; T2 = T1 ),
      '$pio_opts'(Os, T0, T2, T, Open)
   ;  Open = [O|Open1],
      '$pio_opts'(Os, T0, T1, T, Open1)
   ).

'$pio_type'(A) :-
   (  var(A) -> throw(error(instantiation_error, phrase_from_file/3))
   ;  A == chars -> true
   ;  A == codes -> true
   ;  throw(error(domain_error(oneof([codes,chars]), A), phrase_from_file/3))
   ).

'$pio_default'(Type) :-
   (  current_prolog_flag(double_quotes, codes) -> Type = codes
   ;  Type = chars
   ).

'$lazy_list'(S, Type, L) :-
   '$lazy_start'(S, K),
   '$lazy_tail'(S, K, Type, L).

'$lazy_tail'(S, K, Type, L) :-
   freeze(L, '$lazy_fill'(S, K, Type, L)).

'$lazy_fill'(S, K, Type, L) :-
   '$lazy_block'(S, K, Type, L0, T),
   (  L0 == [] -> true
   ;  K1 is K + 1,
      '$lazy_tail'(S, K1, Type, T)
   ),
   L = L0.

% Rest einer faulen Liste: Stream und Blocknummer
'$lazy_rest'(T, S, K) :-
   var(T),
   frozen(T, G),
   '$lazy_goal'(G, S, K).

'$lazy_goal'(freeze(_, pio:'$lazy_fill'(S, K, _, _)), S, K) :- !.
'$lazy_goal'((A, B), S, K) :-
   (  '$lazy_goal'(A, S, K) -> true
   ;  '$lazy_goal'(B, S, K)
   ).

lazy_list_character_count(N, Here, Here) :-
   '$skip_list'(Skipped, Here, Tail),
   (  '$lazy_rest'(Tail, S, K)
   -> '$lazy_position'(S, K, Skipped, pos(N, _, _))
   ;  Tail == []
   -> N = end_of_file-Skipped
   ;  throw(error(type_error(lazy_list, Here), lazy_list_character_count//1))
   ).

lazy_list_location(Loc, Here, Here) :-
   '$skip_list'(Skipped, Here, Tail),
   (  '$lazy_rest'(Tail, S, K)
   -> '$lazy_position'(S, K, Skipped, pos(N, Line, Col)),
      (  stream_property(S, file_name(F))
      -> Loc = file(F, Line, Col, N)
      ;  Loc = stream(S, Line, Col, N)
      )
   ;  Tail == []
   -> Loc = end_of_file-Skipped
   ;  throw(error(type_error(lazy_list, Here), lazy_list_location//1))
   ).

% wie in SWI: erst der Ort, dann werfen (ohne den Rest zu binden)
syntax_error(E, Here, _) :-
   lazy_list_location(Loc, Here, _),
   throw(error(syntax_error(E), Loc)).

phrase_to_file(G, File) :-
   phrase_to_file(G, File, []).

% Backtracking nimmt das Geschriebene zurück: jede Lösung schreibt ab der
% Stelle, an der die vorige Lösung begonnen hat (die Datei wird dort
% abgeschnitten), und am Ende gilt, was die zuletzt gültige Lösung
% geschrieben hat – nach dem Erschöpfen aller Lösungen also nichts.
% (Scryer und SWI lassen das Geschriebene stehen; so mit undo(false).)
% undo(B): true – zurücknehmen (Fehler, wenn der Stream es nicht kann);
% false – stehen lassen; ohne die Option: zurücknehmen, wo es geht.
phrase_to_file(G, File, Options) :-
   '$pio_undo_option'(Options, Undo, Open, phrase_to_file/3),
   (  Undo == false
   -> setup_call_cleanup(open(File, write, S, Open),
                         phrase_to_stream(G, S),
                         close(S))
   ;  '$pio_key'(K),
      setup_call_cleanup(( open(File, write, S, Open), '$pio_mark'(S, K) ),
                         ( '$pio_check_undo'(Undo, S, phrase_to_file/3),
                           '$pio_to_stream'(G, S, K, phrase_to_file/2) ),
                         ( '$pio_rewind'(S, K), close(S) ))
   ).

% dasselbe auf einem offenen Stream: zurückgenommen wird bis zur Stelle,
% an der der Aufruf begonnen hat (auch was danach sonst in den Stream kam –
% es gehört zu dem, was das Zurücksetzen ungeschehen macht). Schneidet
% ab: nur für Dateien, die sich positionieren lassen
phrase_to_stream(G, S, Options) :-
   '$pio_undo_option'(Options, Undo, Rest, phrase_to_stream/3),
   (  Rest == [] -> true
   ;  Rest = [O|_],
      throw(error(domain_error(phrase_to_stream_option, O), phrase_to_stream/3))
   ),
   (  Undo == false
   -> phrase_to_stream(G, S)
   ;  Undo == default, \+ '$pio_undoable'(S)
   -> phrase_to_stream(G, S)
   ;  '$pio_check_undo'(Undo, S, phrase_to_stream/3),
      '$pio_key'(K),
      setup_call_cleanup('$pio_mark'(S, K),
                         '$pio_to_stream'(G, S, K, phrase_to_stream/3),
                         '$pio_rewind'(S, K))
   ).

'$pio_to_stream'(G, S, K, PI) :-
   phrase(G, Ls),
   '$pio_list'(Ls, PI),
   '$pio_rewind'(S, K),
   '$pio_put'(Ls, S),
   '$pio_mark'(S, K).

'$pio_check_undo'(Undo, S, PI) :-
   (  Undo == true, \+ '$pio_undoable'(S)
   -> throw(error(permission_error(reposition, stream, S), PI))
   ;  true
   ).

% undo(B) herausnehmen (das erste gilt; default ohne), der Rest bleibt
'$pio_undo_option'(Os, Undo, Rest, PI) :-
   '$skip_list'(_, Os, Tail),
   (  Tail == [] -> '$pio_undo_opts'(Os, default, Undo, Rest, PI)
   ;  var(Tail) -> throw(error(instantiation_error, PI))
   ;  throw(error(type_error(list, Os), PI))
   ).

'$pio_undo_opts'([], U, U, [], _).
'$pio_undo_opts'([O|Os], U0, U, Rest, PI) :-
   (  var(O) -> throw(error(instantiation_error, PI))
   ;  O = undo(B)
   -> (  var(B) -> throw(error(instantiation_error, PI))
      ;  B == true -> true
      ;  B == false -> true
      ;  throw(error(domain_error(oneof([true,false]), B), PI))
      ),
      ( U0 == default -> U1 = B ; U1 = U0 ),
      '$pio_undo_opts'(Os, U1, U, Rest, PI)
   ;  Rest = [O|Rest1],
      '$pio_undo_opts'(Os, U0, U, Rest1, PI)
   ).

phrase_to_stream(G, S) :-
   phrase(G, Ls),
   '$pio_list'(Ls, phrase_to_stream/2),
   '$pio_put'(Ls, S).

'$pio_list'(Ls, PI) :-
   '$skip_list'(_, Ls, Tail),
   (  var(Tail) -> throw(error(instantiation_error, PI))
   ;  Tail == [] -> true
   ;  throw(error(type_error(list, Ls), PI))
   ).

'$pio_put'([], _).
'$pio_put'([C|Cs], S) :-
   (  integer(C) -> put_code(S, C)
   ;  put_char(S, C)
   ),
   '$pio_put'(Cs, S).
