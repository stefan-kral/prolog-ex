% weiter exportiert p/0, das es selbst nur aus quelle importiert (wie
% chat80.pl test_chat/0 aus chattop), dazu ein eigenes q/0
:- module(weiter, [p/1, q/1]).
:- use_module(quelle, [p/1]).
q(X) :- p(X).
