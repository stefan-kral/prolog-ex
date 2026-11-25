/* driver.pl - ein Programm der SICStus-Suite (bench.zip, nicht im Repo)
   in einem System laden, pruefen und messen; gleich in PrologEx, SWI und
   Scryer (der Prelude des Systems davor). Aufgerufen von run.sh, im
   Ordner der Suite.

     sb_check(+Datei)              einmal data(D), benchmark(D, R) (die
                                   erste Loesung, wie harness.pl);
                                   Ausgabe RESULT ok(D-R) | failed | error(F)
     sb_time(+Datei, +Anzahl, +N)  N-mal bench(Anzahl) aus harness.pl

   Die Suite ist fuer SICStus geschrieben: "..." sind Codelisten
   (double_quotes = codes, flatten.pl braucht das). harness.pl laedt der
   Driver selbst; das :- ensure_loaded(harness) der Programme laedt es
   dann nicht noch einmal (Scryer: Prelude verwirft die Direktive).
   Ausgabe des Ergebnisses mit eigenem Schreiber: write_canonical/1
   schreibt Listen nicht ueberall gleich.
*/

sb_load(File) :-
    set_prolog_flag(double_quotes, codes),
    consult('harness.pl'),
    consult(File).

sb_check(File) :-
    sb_load(File),
    (   catch(sb_first(T), error(F, _), (sb_out(error(F)), fail))
    ->  sb_out(ok(T))
    ;   sb_out(failed)
    ).
sb_check(_).

sb_first(D-R) :-
    data(D),
    benchmark(D, R), !.

sb_out(T) :-
    term_variables(T, Vs),
    write('RESULT '), sb_w(T, Vs), nl.

% Variablen als _G<Nummer> in der Reihenfolge des ersten Auftretens,
% Listen als [...], sonst f(...) ohne Operatoren
sb_w(X, Vs) :- var(X), !, sb_var(Vs, X, 0).
sb_w(X, _) :- X == [], !, write('[]').
sb_w(X, _) :- number(X), !, write(X).
sb_w(X, _) :- atom(X), !, writeq(X).
sb_w([H|T], Vs) :- !, write('['), sb_w(H, Vs), sb_wt(T, Vs).
sb_w(X, Vs) :-
    X =.. [F|As],
    writeq(F), write('('), sb_args(As, Vs), write(')').

sb_wt(T, Vs) :- var(T), !, write('|'), sb_w(T, Vs), write(']').
sb_wt([], _) :- !, write(']').
sb_wt([H|T], Vs) :- !, write(','), sb_w(H, Vs), sb_wt(T, Vs).
sb_wt(T, Vs) :- write('|'), sb_w(T, Vs), write(']').

sb_args([A], Vs) :- !, sb_w(A, Vs).
sb_args([A|As], Vs) :- sb_w(A, Vs), write(','), sb_args(As, Vs).

sb_var([V|_], X, N) :- V == X, !, write('_G'), write(N).
sb_var([_|Vs], X, N) :- N1 is N + 1, sb_var(Vs, X, N1).

sb_time(File, Count, Runs) :-
    sb_load(File),
    sb_runs(Runs, Count).

sb_runs(0, _) :- !.
sb_runs(N, Count) :-
    bench(Count),
    N1 is N - 1,
    sb_runs(N1, Count).
