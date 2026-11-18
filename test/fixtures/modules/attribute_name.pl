% attribute als gewöhnlicher Name: ohne library(atts) kein Operator (wie
% SWI und Scryer), etwa in einer Exportliste wie in Chat-80
:- module(attribute_name, [attribute/6, nach/1]).
attribute(a, b, c, d, e, f).
nach(X) :- X = [attribute/6, b].
