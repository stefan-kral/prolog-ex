:- module(kreis_b, [b_wert/1, b_ruft_a/1]).
:- use_module(kreis_a, [a_wert/1]).
b_wert(2).
b_ruft_a(X) :- a_wert(X).
