% Pruefer der Programm-Batterie, portabel (ISO, dazu findall/3 und
% length/2): laeuft in PrologEx, SWI-Prolog und Scryer gleich.
% Ein Programm NAME.pl kommt mit NAME.checks.pl, darin Fakten
%   expect(Ziel, Schablone, Liste)   alle Loesungen, in Reihenfolge (==)
%   expect_count(Ziel, N)            Anzahl der Loesungen
%   expect_first(Ziel, Schablone, T) erste Loesung (none: keine)
% failures(Fs): die verletzten Erwartungen mit dem, was herauskam.
:- dynamic(expect/3).
:- dynamic(expect_count/2).
:- dynamic(expect_first/3).

failures(Fs) :- findall(F, failure(F), Fs).

failure(all(G)-got(L)) :-
    expect(G, T, E),
    catch(findall(T, G, L), Err, L = error(Err)),
    L \== E.
failure(count(G)-got(M)) :-
    expect_count(G, N),
    catch((findall(x, G, L), length(L, M)), Err, M = error(Err)),
    M \== N.
failure(first(G)-got(X)) :-
    expect_first(G, T, E),
    catch((G -> X = T ; X = none), Err, X = error(Err)),
    X \== E.

% fuer die Gegenproben in SWI und Scryer (cross.sh)
report :-
    failures(Fs),
    ( Fs == [] -> write(ok) ; write(Fs) ), nl.
