% clausex/2 (PrologEx)
s_cx(true) :- !.
s_cx((A,B)) :- !, s_cx(A), s_cx(B).
s_cx(G) :- ( clausex(G, B) *-> s_cx(B) ; call(G) ).
