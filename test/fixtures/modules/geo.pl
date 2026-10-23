:- module(geo, [flaeche/2, quadrat/2, op(700, xfx, ===>), zaehle/1, tick/0]).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- dynamic zaehler/1.

zaehler(0).
flaeche(rechteck(B, H), A) :- mal(B, H, A).
flaeche(quadrat(S), A) :- quadrat(S, A).
quadrat(X, Y) :- mal(X, X, Y).
mal(X, Y, Z) :- Z is X * Y.                 % privat
pfeil(a ===> b).
tick :- retract(zaehler(N)), N1 is N + 1, assertz(zaehler(N1)).
zaehle(N) :- zaehler(N).
benutzt_user(X) :- hilfe(X).                % hilfe/1 steht in user: unsichtbar
benutzt_user_q(X) :- user:hilfe(X).         % so geht es
benutzt_lists(L, X) :- last(L, X).
