% Anwendungsfälle für library(linda): mehrere PrologEx-Sitzungen (eigene
% Betriebssystemprozesse, auch auf verschiedenen Rechnern) koordinieren
% sich über einen Tupelraum.
%
%   examples/linda_demo.sh          startet alles und prüft die Ergebnisse
%
% Jede Rolle ist ein Prädikat; das Skript startet je Rolle eine Sitzung:
%
%   start_ex -q examples/linda.pl -g "Rolle" -g halt
%
% Die Adresse des Servers steht in einer Datei (server/1 schreibt sie,
% verbinden/1 liest sie) – so muss niemand den Knotennamen kennen.

% fib/2 ist Rechenarbeit zum Verteilen; der JIT machte sie sonst so schnell,
% dass sich nichts zu verteilen lohnt
:- set_prolog_flag(jit, false).

:- use_module(library(linda)).
:- use_module(library(lists)).
:- use_module(library(between)).
:- use_module(library(format)).
:- use_module(library(time)).
:- use_module(library(random)).
:- use_module(library(iso_ext)).

% --- Server -------------------------------------------------------------------

% server(+Datei): Server starten, Adresse in Datei; läuft, bis jemand
% out(quit) ablegt
server(Datei) :-
    linda(A-true),
    setup_call_cleanup(open(Datei, write, S), (writeq(S, A), write(S, '.'), nl(S)), close(S)),
    linda_client(A),
    in(quit),
    close_client.

verbinden(Datei) :-
    setup_call_cleanup(open(Datei, read, S), read(S, A), close(S)),
    linda_client(A).

% --- 1. Arbeitsliste (Master/Worker) --------------------------------------------
%
% Der Master legt Aufgaben ab und sammelt die Ergebnisse; Worker nehmen sich
% Aufgaben, bis "stop" da ist. stop legt jeder Worker wieder zurück, damit
% ihn auch die anderen sehen (in/2 nimmt das erste verfügbare Muster).

fib(N, F) :- N < 2, !, F = N.
fib(N, F) :- N1 is N - 1, N2 is N - 2, fib(N1, F1), fib(N2, F2), F is F1 + F2.

master(Datei, Aufgaben, Groesse) :-
    verbinden(Datei),
    statistics(walltime, [T0|_]),
    forall(between(1, Aufgaben, I), out(task(I, Groesse))),
    findall(I-F, (between(1, Aufgaben, _), in(result(I, F))), Rs0),
    statistics(walltime, [T1|_]),
    out(stop),
    msort(Rs0, Rs),
    length(Rs, N),
    fib(Groesse, Soll),
    (   forall(member(_-F, Rs), F =:= Soll), numlist(1, Aufgaben, Is), pairs_keys(Rs, Is)
    ->  Ok = ok
    ;   Ok = falsch
    ),
    D is T1 - T0,
    format("farm: ~d Ergebnisse, ~w, ~d ms~n", [N, Ok, D]),
    close_client.

pairs_keys([], []).
pairs_keys([K-_|Ps], [K|Ks]) :- pairs_keys(Ps, Ks).

worker(Datei) :-
    verbinden(Datei),
    worker_loop(0, N),
    out(erledigt(N)),
    close_client.

% wie viele Aufgaben jeder Worker hatte (nach allen Workern)
farm_bericht(Datei) :-
    verbinden(Datei),
    bagof_in_noblock(N, erledigt(N), Ns),
    in(stop),
    format("worker: ~w Aufgaben~n", [Ns]),
    close_client.

worker_loop(N0, N) :-
    in([task(I, G), stop], T),
    (   T = stop
    ->  out(stop), N = N0
    ;   T = task(I, G), fib(G, F), out(result(I, F)),
        N1 is N0 + 1, worker_loop(N1, N)
    ).

% --- 2. Kritischer Bereich: ein gemeinsamer Zähler --------------------------------
%
% Das Tupel count(N) gibt es genau einmal; wer es herausnimmt, hat den
% Bereich für sich (in/1 ist atomar). Am Ende muss count = Summe aller
% Schritte sein.

zaehler_start(Datei) :- verbinden(Datei), out(count(0)), close_client.

zaehler(Datei, Schritte) :-
    verbinden(Datei),
    forall(between(1, Schritte, _), (in(count(C)), C1 is C + 1, out(count(C1)))),
    close_client.

zaehler_stand(Datei) :- verbinden(Datei), rd(count(C)), format("zaehler: ~d~n", [C]), close_client.

% --- 3. Beschränkter Puffer (Erzeuger/Verbraucher) ---------------------------------
%
% K Plätze als Tupel slot; der Erzeuger braucht einen freien Platz, der
% Verbraucher gibt ihn zurück. Nie mehr als K Elemente gleichzeitig im Raum
% (der Verbraucher prüft das mit bagof_rd_noblock/3).

puffer_start(Datei, K) :- verbinden(Datei), forall(between(1, K, _), out(slot)), close_client.

erzeuger(Datei, N) :-
    verbinden(Datei),
    forall(between(1, N, I), (in(slot), out(item(I)))),
    out(item(ende)),
    close_client.

verbraucher(Datei, K) :-
    verbinden(Datei),
    verbrauchen(K, 0, 0, Summe, Max),
    format("puffer: Summe ~d, hoechstens ~d im Puffer (Grenze ~d)~n", [Summe, Max, K]),
    close_client.

verbrauchen(K, S0, M0, S, M) :-
    % im Puffer: die Elemente ohne die Endmarke
    findall(I, (bagof_rd_noblock(I, item(I), L), member(I, L), integer(I)), Is),
    length(Is, Da),
    M1 is max(M0, Da),
    in(item(I)),
    (   I == ende
    ->  S = S0, M = M1
    ;   out(slot), S1 is S0 + I, verbrauchen(K, S1, M1, S, M)
    ).

% --- 4. Barriere ---------------------------------------------------------------------
%
% N Teilnehmer, mehrere Runden: wer ankommt, zählt (cnt(Runde, K), wie der
% Zähler oben); der N-te gibt die Runde frei (go(Runde)), alle warten mit
% rd/1 darauf. Danach melden alle durch(Runde, Ich).

barriere_start(Datei, Runden) :-
    verbinden(Datei),
    forall(between(1, Runden, R), out(cnt(R, 0))),
    close_client.

teilnehmer(Datei, Ich, N, Runden) :-
    verbinden(Datei),
    forall(between(1, Runden, R),
           ( random_between(0, 30, Ms), S is Ms / 1000, sleep(S),
             in(cnt(R, K)), K1 is K + 1,
             ( K1 =:= N -> out(go(R)) ; out(cnt(R, K1)) ),
             rd(go(R)),
             out(durch(R, Ich))
           )),
    close_client.

barriere_pruefen(Datei, N, Runden) :-
    verbinden(Datei),
    findall(R, (between(1, Runden, R), bagof_rd_noblock(I, durch(R, I), Is), length(Is, N)), Rs),
    length(Rs, Voll),
    bagof_rd_noblock(R, go(R), Gos), length(Gos, G),
    format("barriere: ~d von ~d Runden vollstaendig, ~d mal go~n", [Voll, Runden, G]),
    close_client.

% --- 5. Speisende Philosophen ----------------------------------------------------------
%
% Gabeln sind Tupel fork(I); höchstens N-1 Philosophen am Tisch (room) –
% so kann es keine Verklemmung geben.

tisch(Datei, N) :-
    verbinden(Datei),
    forall(between(1, N, I), out(fork(I))),
    N1 is N - 1,
    forall(between(1, N1, _), out(room)),
    close_client.

philosoph(Datei, I, N, Runden) :-
    verbinden(Datei),
    J is I mod N + 1,
    forall(between(1, Runden, R),
           ( in(room), in(fork(I)), in(fork(J)),
             out(gegessen(I, R)),
             out(fork(I)), out(fork(J)), out(room) )),
    close_client.

tisch_pruefen(Datei, N, Runden) :-
    verbinden(Datei),
    bagof_rd_noblock(x, I^R^gegessen(I, R), Es), length(Es, E),
    bagof_rd_noblock(I, fork(I), Fs), msort(Fs, Fs1),
    bagof_rd_noblock(x, room, Rooms), length(Rooms, Ro),
    Soll is N * Runden,
    format("philosophen: ~d von ~d Mahlzeiten, Gabeln ~w, ~d Plaetze~n", [E, Soll, Fs1, Ro]),
    close_client.

% --- Ende --------------------------------------------------------------------------------

beenden(Datei) :- verbinden(Datei), out(quit), close_client.
