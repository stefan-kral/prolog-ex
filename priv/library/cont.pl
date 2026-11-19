/* library(cont): begrenzte Fortsetzungen (delimited continuations) wie
   Scryer Prolog (src/lib/cont.pl), dort an die WAM gebunden; hier führt die
   Maschine die Fortsetzung ohnehin als Liste von Zielen ('$reset'/3,
   '$shift'/1, '$call_continuation'/1 in PrologEx).

   reset(:Goal, ?Ball, -Cont)
       Ruft Goal. Ruft Goal shift(B), kehrt reset/3 dorthin zurück mit
       Ball = B und Cont = cont(G): call(G) setzt Goal hinter shift/1 fort.
       Endet Goal ohne shift/1, ist Cont = none (Ball bleibt frei).
       Choice Points von Goal vor shift/1 bleiben (Backtracking läuft
       wieder bis zum nächsten shift/1).
   shift(+Ball)
       Kehrt zum innersten reset/3 zurück; ohne eines
       existence_error(reset, Ball).

   In der Fortsetzung wirken ein Schnitt, once/1 und if-then-else nur bis
   zu ihrem Anfang; catch/3, setup_call_cleanup/3 und Grenzen
   (call_with_time_limit/2, …) um shift/1 herum sind mit shift/1 beendet
   und gelten in der Fortsetzung nicht mehr. Durch findall/3, \+/1 und
   ähnliche, die ihr Ziel für sich lösen, reicht shift/1 nicht hindurch.
*/

:- module(cont, [reset/3, shift/1, call_continuation/1]).

:- meta_predicate(reset(0, ?, ?)).

reset(Goal, Ball, Cont) :- '$reset'(Goal, Ball, Cont).

shift(Ball) :- '$shift'(Ball).

call_continuation(L) :- '$call_continuation'(L).
