% Byte-Folgen: library(bytes) und library(dcg/bytes)
%
%   mix prolog examples/bytes.pl -g main -q
%
% Eine Byte-Folge ist kompakt (ein Byte je Byte), ein Teilstück ein
% Verweis ohne Kopie. Eine gewöhnliche Grammatik liest sie als faule Liste:
% Terminale, seq//1 und ...//0 laufen unverändert, und phrase_bytes/3
% gibt den Rest wieder als Byte-Folge.

% Für Binärformate: "..." als Codes, dann ist auch die faule Liste aus
% Codes (Zahlen 0..255), und Zahlen und Text in der Grammatik passen
% zusammen. (Mit double_quotes = chars wäre sie aus Zeichen, je Byte eins:
% "GIF" passte, [137] nicht – u8(137) passt in beiden Sichten.)
:- set_prolog_flag(double_quotes, codes).

:- use_module(library(bytes)).
:- use_module(library(dcg/bytes)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).

% --- GIF: Präfix, zwei Felder, der Rest ----------------------------------

gif(V, W, H) --> "GIF", version(V), u16le(W), u16le(H).

version(87) --> "87a".
version(89) --> "89a".

gif_demo :-
    bytes_utf8(Kopf, "GIF89a"),
    bytes_list(Daten, [64, 1, 200, 0, 0xF7, 0, 0]),
    bytes_concat(Kopf, Daten, B),
    phrase_bytes(gif(V, W, H), B, Rest),
    bytes_list(Rest, R),
    format('GIF~w, ~w x ~w Pixel, danach ~w~n', [V, W, H, R]).

% --- PNG: Chunks mit Längenfeld ------------------------------------------

png(Cs) --> [137, 80, 78, 71, 13, 10, 26, 10], chunks(Cs).

chunks([Typ-Len|Cs]) -->
    u32be(Len), take(4, T), take(Len, _Daten), u32be(_Crc), !,
    { bytes_latin1(T, Tc), atom_chars(Typ, Tc) },
    chunks(Cs).
chunks([]) --> eos.

% ein PNG von 1 x 1 Pixel
png_bytes(B) :-
    bytes_base64(B, 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==').

ihdr(W, H) --> [137, 80, 78, 71, 13, 10, 26, 10], u32be(13), "IHDR", u32be(W), u32be(H), ... .

png_demo :-
    png_bytes(B),
    bytes_length(B, N),
    phrase_bytes(png(Cs), B),
    phrase_bytes(ihdr(W, H), B),
    format('PNG, ~w Bytes, ~w x ~w Pixel, Chunks ~w~n', [N, W, H, Cs]).

% --- Bits: ein Sieb des Eratosthenes -------------------------------------

sieve(N, Ps) :-
    Bs is (N + 8) // 8,
    bytes_fill(Bs, 255, S0),
    bytes_set_bit(0, S0, 0, S1),
    bytes_set_bit(1, S1, 0, S2),
    M is floor(sqrt(N)),
    sieve(2, M, N, S2, S),
    findall(P, (bytes_bit(P, S, 1), P =< N), Ps).

sieve(P, M, _, S, S) :- P > M, !.
sieve(P, M, N, S0, S) :-
    (   bytes_bit(P, S0, 1) -> Q is P * P, strike(Q, P, N, S0, S1) ; S1 = S0 ),
    P1 is P + 1,
    sieve(P1, M, N, S1, S).

strike(Q, _, N, S, S) :- Q > N, !.
strike(Q, P, N, S0, S) :- bytes_set_bit(Q, S0, 0, S1), Q1 is Q + P, strike(Q1, P, N, S1, S).

sieve_demo :-
    sieve(60, Ps),
    format('Primzahlen bis 60 (eine Bitmenge): ~w~n', [Ps]).

main :-
    gif_demo,
    png_demo,
    sieve_demo.
