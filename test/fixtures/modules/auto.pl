:- module(auto, [letztes/2]).
letztes(L, X) :- last(L, X).            % ohne use_module: kein Zugriff
