:- use_module(geo).
:- use_module(meta).
:- use_module(library(lists)).
:- use_module(library(apply)).

hilfe(user).
positiv(X) :- X > 0.
pfeil_test(X) :- X = (links ===> rechts).
meta:von_haupt(X) :- hilfe(X).          % Rumpf läuft in user
