/* library(dcg/pcre): reguläre Ausdrücke als Nichtterminale (PrologEx)

   Die Brücke zwischen library(pcre) und DCGs: ein Muster wird an der
   aktuellen Stelle einer Zeichen- oder Codeliste verankert gesucht, der
   Treffer verbraucht.

     * re(+Regex)//: Regex passt hier; der Treffer wird verbraucht.
     * re(+Regex, -Sub)//: dazu Sub wie bei re_matchsub/3, die Paarliste
       [0-Text, 1-Gruppe1, Name-Wert, ...]; Texte in der Art der Liste
       (Zeichen oder Codes).
     * re(+Regex, -Sub, +Options)//: Optionen wie bei re_matchsub/4
       (caseless(true), capture_type(atom), ...; auch "Muster"/Flags).

   Deterministisch wie PCRE selbst: es gibt genau den einen Treffer, den
   PCRE an dieser Stelle findet (gierig, erste Alternative), kein
   Zurücksetzen auf kürzere Treffer. Ein leerer Treffer verbraucht nichts.

   Das Subjekt ist der ganze Rest der Liste: ^ und \A passen an der
   aktuellen Stelle, $ und \z am Ende der Eingabe, ein Lookbehind sieht
   nichts vor der Stelle; Positionen (capture_type(range)) zählen ab hier.
   Der Rest muss deshalb bekannt sein: eine faule Liste (phrase_from_file/2,
   allgemein: ein mit freeze/2 wartendes Ende) wird beim ersten Aufruf zu
   Ende gelesen; ein offenes Ende ohne freeze ist instantiation_error.

   Kosten: Der Rest wird einmal in Text umgewandelt und gemerkt; weitere
   Aufrufe über derselben Liste finden ihre Stelle von der letzten aus
   (vorwärts im Abstand, sonst vom Anfang) – ein Tokenizer, der re//N
   immer wieder aufruft, bleibt so linear.
*/

:- module(dcg_pcre, [re//1, re//2, re//3]).

:- use_module(library(pcre)).

re(Re) --> re(Re, _, []).

re(Re, Sub) --> re(Re, Sub, []).

re(Re, Sub, Options, S0, S) :-
    '$re_dcg'(Re, Options, S0, R),
    re_(R, Re, Sub, Options, S0, S).

re_(match(Sub0, S1), _, Sub, _, _, S) :-
    Sub = Sub0,
    S = S1.
re_(lazy(T), Re, Sub, Options, S0, S) :-
    re_force(T),
    '$re_dcg'(Re, Options, S0, R),
    re_(R, Re, Sub, Options, S0, S).

% das wartende Ende einer faulen Liste bis [] lesen
re_force(T) :-
    (   frozen(T, G), G \== true
    ->  (   T = [_|R]
        ->  '$skip_list'(_, R, T1),
            (   var(T1) -> re_force(T1) ; true )
        ;   T = []
        )
    ;   throw(error(instantiation_error, re//3))
    ).
