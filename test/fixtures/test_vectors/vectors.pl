% Prüfungen an Testdaten mit unabhängigem Orakel (siehe SOURCES.md);
% jedes v_…(Name, V) gibt V = ok oder das abweichende Ergebnis
:- use_module(library(bytes)).
:- use_module(library(charsio)).
:- use_module(library(csv)).
:- use_module(library(lists)).

codes([], []).
codes([C|Cs], [D|Ds]) :- char_code(C, D), codes(Cs, Ds).

% --- RFC 4648, Abschnitt 10 ------------------------------------------
rfc4648('', '', '').
rfc4648(f, 'Zg==', '66').
rfc4648(fo, 'Zm8=', '666F').
rfc4648(foo, 'Zm9v', '666F6F').
rfc4648(foob, 'Zm9vYg==', '666F6F62').
rfc4648(fooba, 'Zm9vYmE=', '666F6F6261').
rfc4648(foobar, 'Zm9vYmFy', '666F6F626172').

% kodieren und dekodieren, mit library(bytes) und chars_base64/3
v_rfc4648(T, V) :-
    rfc4648(T, B64, B16),
    bytes_latin1(B, T),
    bytes_base64(B, E64), atom_chars(A64, E64),
    bytes_hex(B, E16), atom_chars(A16, E16), downcase_chars(B16, L16),
    bytes_base64(D64, B64), bytes_hex(D16, B16),
    atom_chars(T, Cs), chars_base64(Cs, C64, []), atom_chars(B64, C64),
    chars_base64(Back, C64, []),
    (   A64 == B64, A16 == L16, D64 == B, D16 == B, Back == Cs
    ->  V = ok
    ;   V = falsch(A64, A16)
    ).
downcase_chars(A, L) :- atom_chars(A, Cs), maplist(lower, Cs, Ls), atom_chars(L, Ls).
lower(C, L) :- ( char_code(C, K), K >= 0'A, K =< 0'F -> K1 is K + 32, char_code(L, K1) ; L = C ).

% --- UTF-8: Markus Kuhns Stresstest ----------------------------------
% streng über library(bytes)
v_utf8_bytes(N, V) :-
    line(N, Bs, Strict, _),
    bytes_list(B, Bs),
    catch(( bytes_utf8(B, Cs), codes(Cs, Got) ), error(representation_error(_), _), Got = invalid),
    ( Got == Strict -> V = ok ; V = Got ).
% streng aus einer Datei mit encoding(utf8)
v_utf8_stream(N, V) :-
    line(N, Bs, Strict, _),
    tmp_path(F),
    open(F, write, W, [type(binary)]), put_bytes(Bs, W), close(W),
    open(F, read, R, [encoding(utf8)]),
    catch(read_codes(R, Got), error(representation_error(_), _), Got = invalid),
    close(R),
    ( Got == Strict -> V = ok ; V = Got ).
put_bytes([], _).
put_bytes([B|Bs], W) :- put_byte(W, B), put_bytes(Bs, W).
read_codes(R, Cs) :- get_code(R, C), ( C == -1 -> Cs = [] ; Cs = [C|Cs1], read_codes(R, Cs1) ).
% chars_utf8bytes/2 (aus Scryer): ungültig wird U+FFFD
v_utf8_chars(N, V) :-
    line(N, Bs, _, Repl),
    catch(( chars_utf8bytes(Cs, Bs), codes(Cs, Got) ), E, Got = E),
    ( Got == Repl -> V = ok ; V = Got ).

% --- csv-spectrum ----------------------------------------------------
row_list(R, L) :- R =.. [_|L].
v_csv(N, V) :-
    spectrum(N, Want), csv_dir(D),
    atom_concat(D, N, F0), atom_concat(F0, '.csv', F),
    catch(( csv_read_file(F, Rows, [convert(false)]), maplist(row_list, Rows, Got) ), E, Got = E),
    ( Got == Want -> V = ok ; V = Got ).

% --- Groß- und Kleinschreibung nach Unicode 17.0 ---------------------
v_case(C, V) :-
    case(C, Up, Lo),
    char_code(Ch, C),
    char_type(Ch, upper(U)), char_type(Ch, lower(L)),
    codes(U, GU), codes(L, GL),
    ( GU == Up, GL == Lo -> V = ok ; V = GU/GL ).

% --- Zeichenklassen nach Unicode 17.0 --------------------------------
want_class(alphabetic, G, _) :- sub_atom(G, 0, 1, _, 'L') ; G == 'Nl'.
want_class(lower, 'Ll', _).
want_class(upper, 'Lu', _).
want_class(numeric, G, _) :- sub_atom(G, 0, 1, _, 'N').
want_class(control, 'Cc', _).
want_class(whitespace, _, 1).
v_class(C, V) :-
    uc(C, G, W),
    char_code(Ch, C),
    findall(K, ( member(K, [alphabetic, lower, upper, numeric, control, whitespace]),
                 ( want_class(K, G, W) -> \+ char_type(Ch, K) ; char_type(Ch, K) ) ), Ks),
    ( Ks == [] -> V = ok ; V = falsch(G, Ks) ).
