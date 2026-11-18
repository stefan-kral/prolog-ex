% je Fall c(I, Ausdruck) eine Zeile "I Wert" (evaluation_error: err)
go :- c(I, E), catch((X is E, R = X), error(Err, _), (functor(Err, F, _), R = F)), write(I), write(' '), (R = evaluation_error -> write(err) ; write(R)), nl, fail.
go.
