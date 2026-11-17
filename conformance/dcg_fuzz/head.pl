% Kopf der DCG-Fälle für Scryer und PrologEx (head_swi.pl: SWI). Je Fall
% case(Id) mit c(Id, A, I, R) (phrase/3) und g(Id, A, I) (phrase/2). Für
% jede Eingabe aus inputs/1 die Lösungen A-R in Reihenfolge, dazu für
% Längen 0..2 die erzeugten I-A (phrase/2 mit offener Liste fester
% Länge); Variablen als v(0), v(1), …; Fehler als ex(Name/Stelligkeit).
:- set_prolog_flag(double_quotes, chars).
:- use_module(library(lists)).
:- use_module(library(dcgs)).
:- use_module(library(iso_ext)).
:- discontiguous(case/1).
:- discontiguous(c/4).
:- discontiguous(g/3).
