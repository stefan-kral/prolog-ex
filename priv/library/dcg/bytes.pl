/* library(dcg/bytes): DCGs über Byte-Folgen (library(bytes)).

   Die Byte-Folge wird zu einer faulen Liste wie bei phrase_from_file/2
   (library(pio)): der noch nicht ausgepackte Rest wartet mit freeze/2,
   und erst beim Lesen kommt der nächste Block (256 Bytes) dazu. So laufen
   gewöhnliche Grammatiken – Terminale [X] und "...", seq//1, ...//0,
   library(dcg/high_order) – unverändert, und vorausliegende Bytes werden
   nie ausgepackt. Nach dem Rücksetzen wird ein Block neu erzeugt (die
   Byte-Folge ist unveränderlich).

     * phrase_bytes(:G, +B): phrase(G, L), L die Bytes von B
     * phrase_bytes(:G, +B, -Rest): ... Rest die übrigen Bytes, wieder als
       Byte-Folge (ohne Kopie)
     * phrase_bytes(:G, +B, -Rest, +Optionen): Optionen as(Sicht)
     * bytes_to_lazy_list(+B, +Sicht, -L): die faule Liste selbst

   Sichten: as(codes) – Zahlen 0..255; as(latin1) – ein Zeichen je Byte
   (71 ist 'G', 200 ist 'È'); as(utf8) – dekodierte Zeichen (ungültig:
   representation_error(character)). Ohne as(...) wie library(pio) nach dem
   Flag double_quotes: codes bei codes, sonst latin1 – so passt "GIF89a" in
   der Grammatik zur Liste.

   Für Binärformate (Sichten codes und latin1; ein Zeichen zählt als sein
   Code, höchstens 255):
     * u8(X)//, s8(X)//
     * u16le(X)//, u16be(X)//, s16le(X)//, s16be(X)//
     * u32le(X)//, u32be(X)//, s32le(X)//, s32be(X)//
     * take(+N, ?B)//: die nächsten N Bytes als Byte-Folge
     * eos//: das Ende

   Wie bei library(pio) liegt der gelesene Teil der Liste vorübergehend als
   Liste vor (was kein Choice Point mehr braucht, räumt die Kompaktierung
   weg); die Byte-Folge selbst bleibt kompakt.
*/

:- module(dcg_bytes,
          [ phrase_bytes/2,
            phrase_bytes/3,
            phrase_bytes/4,
            bytes_to_lazy_list/3,
            u8//1, s8//1,
            u16le//1, u16be//1, s16le//1, s16be//1,
            u32le//1, u32be//1, s32le//1, s32be//1,
            take//2,
            eos//0
          ]).

:- use_module(library(bytes)).
:- use_module(library(lists)).
:- use_module(library(error)).

:- meta_predicate(phrase_bytes(//, ?)).
:- meta_predicate(phrase_bytes(//, ?, ?)).
:- meta_predicate(phrase_bytes(//, ?, ?, ?)).

phrase_bytes(G, B) :-
   '$bytes_view'([], View),
   bytes_to_lazy_list(B, View, L),
   phrase(G, L).

phrase_bytes(G, B, Rest) :-
   phrase_bytes(G, B, Rest, []).

phrase_bytes(G, B, Rest, Options) :-
   '$bytes_view'(Options, View),
   bytes_to_lazy_list(B, View, L),
   phrase(G, L, T),
   '$bytes_rest_of'(T, View, B, Rest).

bytes_to_lazy_list(B, View, L) :-
   '$bytes_view_ok'(View),
   (  var(B) -> throw(error(instantiation_error, bytes_to_lazy_list/3))
   ;  bytes(B) -> true
   ;  throw(error(type_error(bytes, B), bytes_to_lazy_list/3))
   ),
   '$bytes_lazy'(B, View, 0, L).

'$bytes_lazy'(B, View, Off, L) :-
   freeze(L, '$bytes_fill'(B, View, Off, L)).

'$bytes_fill'(B, View, Off, L) :-
   '$bytes_block'(B, View, Off, L0, T, Off1),
   (  L0 == [] -> true
   ;  '$bytes_lazy'(B, View, Off1, T)
   ),
   L = L0.

% Rest als Byte-Folge: Versatz des wartenden Rests (oder das Ende), davor
% die schon ausgepackten Elemente abziehen
'$bytes_rest_of'(T, View, B, Rest) :-
   '$skip_list'(_, T, Tail),
   (  Tail == [] -> bytes_length(B, Off)
   ;  var(Tail), frozen(Tail, G), '$bytes_goal'(G, Off) -> true
   ;  throw(error(type_error(lazy_list, T), phrase_bytes/3))
   ),
   '$bytes_rest'(T, View, Off, B, Rest).

'$bytes_goal'(freeze(_, dcg_bytes:'$bytes_fill'(_, _, Off, _)), Off) :- !.
'$bytes_goal'((A, B), Off) :-
   (  '$bytes_goal'(A, Off) -> true
   ;  '$bytes_goal'(B, Off)
   ).

'$bytes_view'(Options, View) :-
   must_be(list, Options),
   (  member(O, Options), nonvar(O), O = as(View0) -> View = View0
   ;  current_prolog_flag(double_quotes, codes) -> View = codes
   ;  View = latin1
   ).

'$bytes_view_ok'(V) :-
   (  var(V) -> throw(error(instantiation_error, bytes_to_lazy_list/3))
   ;  memberchk(V, [codes, latin1, utf8]) -> true
   ;  throw(error(domain_error(oneof([codes,latin1,utf8]), V), bytes_to_lazy_list/3))
   ).

% --- Binärformate -------------------------------------------------------

u8(X) --> [E], { '$byte'(E, X) }.

s8(X) --> u8(U), { X is U - (U >> 7) * 256 }.

u16le(X) --> u8(A), u8(B), { X is B << 8 \/ A }.
u16be(X) --> u8(A), u8(B), { X is A << 8 \/ B }.
s16le(X) --> u16le(U), { X is U - (U >> 15) * 65536 }.
s16be(X) --> u16be(U), { X is U - (U >> 15) * 65536 }.

u32le(X) --> u16le(A), u16le(B), { X is B << 16 \/ A }.
u32be(X) --> u16be(A), u16be(B), { X is A << 16 \/ B }.
s32le(X) --> u32le(U), { X is U - (U >> 31) * 4294967296 }.
s32be(X) --> u32be(U), { X is U - (U >> 31) * 4294967296 }.

take(N, B, S0, S) :-
   must_be(integer, N),
   (  N >= 0 -> true
   ;  throw(error(domain_error(not_less_than_zero, N), take//2))
   ),
   length(Es, N),
   append(Es, S, S0),
   maplist('$byte', Es, Xs),
   bytes_list(B0, Xs),
   B = B0.

eos([], []).

% ein Element als Byte: eine Zahl 0..255 oder ein Zeichen mit Code =< 255
'$byte'(E, X) :-
   (  integer(E) -> X = E
   ;  atom(E), atom_length(E, 1), char_code(E, C), C =< 255 -> X = C
   ;  throw(error(type_error(byte, E), u8//1))
   ).
