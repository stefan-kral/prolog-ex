% Soft-Cut mit catch/3 um clause/2 (SWI, PrologEx)
s_soft(true) :- !.
s_soft((A,B)) :- !, s_soft(A), s_soft(B).
s_soft(G) :- ( catch(clause(G, B), error(permission_error(_, _, _), _), fail) *-> s_soft(B) ; call(G) ).
