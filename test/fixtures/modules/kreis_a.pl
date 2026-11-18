% Kreis: kreis_a und kreis_b laden einander mit use_module (wie world0 und
% aggreg in Chat-80); das innere use_module importiert nur
:- module(kreis_a, [a_wert/1, a_ruft_b/1]).
:- use_module(kreis_b, [b_wert/1]).
a_wert(1).
a_ruft_b(X) :- b_wert(X).
