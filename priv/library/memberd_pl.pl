% library(memberd_pl): memberd/2 nach Ulrich Neumerkel in reinem Prolog,
% zum Vergleich mit lists:memberd/2 (in Elixir, mit denselben Antworten).
%
%   memberd(X, Es): X ist ein Element von Es; anders als member/2 kommt
%   jede Antwort nur einmal (dif/2 schließt die schon gegebenen aus).
%
%   ?- memberd(X, [a,b,a]).
%   X = a ; X = b ; false.

:- module(memberd_pl, [memberd/2]).

memberd(X, [E|Es]) :-
   (  X = E
   ;  dif(X, E),
      memberd(X, Es)
   ).
