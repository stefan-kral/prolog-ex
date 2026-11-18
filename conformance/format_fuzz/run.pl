% je Fall c(X, N, C) eine Zeile: format("~NC~n", [X]) (Fehler als err(E))
go :- c(X, P, C), number_codes(P, Pc), atom_codes(Pa, Pc), atom_concat('~', Pa, F1),
      atom_concat(F1, C, F2), atom_concat(F2, '~n', F),
      catch(format(F, [X]), E, (print(err(E)), nl)), fail.
go.
