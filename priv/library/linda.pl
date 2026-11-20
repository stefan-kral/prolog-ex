/* library(linda): Tupelraum nach Linda, wie SICStus (library(linda/server),
   library(linda/client)), dazu bagof_in_noblock/3 und linda_timeout/1 aus
   SWI (library(tipc/tipc_linda)) (PrologEx)

   Ein Server hält den Tupelraum, Clients legen Tupel ab (out/1), lesen
   (rd/1) oder nehmen sie heraus (in/1); in/1 und rd/1 warten, bis ein
   passendes Tupel da ist. Server und Clients sind Knoten der
   Erlang-Distribution, auf einem oder mehreren Rechnern; die Adresse ist
   ein Knotenname wie 'linda_4711@rechner' (statt Host:Port bei SICStus).
   PrologEx wird dafür selbst zum Knoten und startet nötigenfalls epmd
   (wie erl -sname). Knoten brauchen dasselbe Cookie (~/.erlang.cookie;
   auf einem Rechner mit demselben Benutzer von selbst).

   Server

     linda
         startet den Server in dieser Sitzung und schreibt seine Adresse
         (writeq) auf die aktuelle Ausgabe. Anders als bei SICStus kehrt
         linda/0 gleich zurück, der Server läuft im Hintergrund weiter (wie
         bei SWI); die Sitzung kann selbst Client sein
     linda(:Options)
         Options: Address-Goal (Address wird mit der Adresse unifiziert,
         dann Goal gerufen; Address gebunden: so soll der Knoten heißen),
         auch als Liste [Address-Goal]; oder ein Ziel (wie SWI). Nichts
         ausgegeben

   Client (höchstens eine Verbindung je Sitzung)

     linda_client(+Address)        verbinden
     close_client                  trennen
     shutdown_server               der Server nimmt keine neuen Clients
                                   mehr an und endet, wenn alle getrennt
                                   haben
     linda_timeout(?Old, ?New)     Zeitgrenze für Antworten des Servers:
                                   off (Vorgabe) oder Sekunden:Millisekunden;
                                   New offen: nur abfragen
     linda_timeout(+New)           wie SWI: vorübergehend; das Alte gilt
                                   wieder beim Cut, beim Backtracking und
                                   bei einer Ausnahme
     out(+Tuple)                   ablegen
     in(?Tuple)                    passendes Tupel herausnehmen; wartet
     in_noblock(?Tuple)            ebenso; scheitert, wenn keins da ist
     in(+TupleList, ?Tuple)        das erste verfügbare zu einem der
                                   Muster herausnehmen; wartet. Passt es
                                   dann nicht zu Tuple: Scheitern, das
                                   Tupel bleibt draußen (wie SICStus)
     rd(?Tuple), rd_noblock(?Tuple), rd(+TupleList, ?Tuple)
                                   ebenso, ohne herauszunehmen
     bagof_rd_noblock(?Template, +Tuple, ?Bag)
                                   wie bagof(Template, Tuple, Bag) über
                                   alle passenden Tupel (auf einmal
                                   gelesen; ^ wie bei bagof/3)
     bagof_in_noblock(?Template, +Tuple, ?Bag)
                                   ebenso, nimmt alle passenden heraus

   "Passen" heißt unifizierbar; Tupel dürfen Variablen enthalten.
   Gefunden wird jeweils das älteste passende Tupel. Ein neues Tupel
   bekommen erst alle wartenden rd, zu denen es passt, dann nimmt es das
   erste wartende in. Gewartet wird ohne
   Zeitgrenze (linda_timeout/2 gilt für die Antwort des Servers, nicht
   für das Warten auf ein Tupel); Ctrl-C bricht das Warten ab, ein dabei
   schon herausgenommenes Tupel kommt zurück. Ist der Server weg:
   existence_error(linda_server, Address); ohne Verbindung:
   existence_error(linda_client, none).
*/

:- module(linda, [linda/0, linda/1, linda_client/1, close_client/0, shutdown_server/0,
                  linda_timeout/1, linda_timeout/2, out/1, in/1, in/2, in_noblock/1,
                  rd/1, rd/2, rd_noblock/1, bagof_rd_noblock/3, bagof_in_noblock/3]).

:- use_module(library(lists), [member/2]).
:- use_module(library(error)).

:- meta_predicate(linda(:)).
:- meta_predicate(bagof_rd_noblock(?, ^, -)).
:- meta_predicate(bagof_in_noblock(?, ^, -)).

linda :-
    '$linda_start'(Address),
    writeq(Address), nl.

linda(M:Options) :-
    linda_options(Options, M, Address, Goal),
    '$linda_start'(Address),
    call(Goal).

linda_options(Options, _, _, _) :-
    var(Options), !,
    instantiation_error(Options).
linda_options([], _, _, true) :- !.
linda_options([Option], M, Address, Goal) :- !,
    linda_options(Option, M, Address, Goal).
linda_options(Address-Goal, M, Address, M:Goal) :-
    ( var(Address) ; atom(Address) ), !.
linda_options(Options, _, _, _) :-
    Options = [_|_], !,
    domain_error(linda_options, Options).
linda_options(Goal, M, _, M:Goal).

linda_client(Address) :-
    linda_fx('$linda_connect'(Address), linda_client(Address)).

close_client :-
    linda_fx('$linda_close', close_client).

shutdown_server :-
    linda_fx('$linda_shutdown', shutdown_server).

linda_timeout(Old, New) :-
    linda_fx('$linda_timeout'(Old, New), linda_timeout(Old, New)).

linda_timeout(New) :-
    setup_call_cleanup(linda_timeout(Old, New),
                       ( true ; fail ),
                       '$linda_timeout'(_, Old)).

out(Tuple) :-
    linda_fx('$linda_out'(Tuple), out(Tuple)).

in(Tuple) :-
    linda_fx('$linda_in'([Tuple], true, Tuple), in(Tuple)).

in_noblock(Tuple) :-
    linda_fx('$linda_in'([Tuple], false, Tuple), in_noblock(Tuple)).

in(TupleList, Tuple) :-
    must_be(list, TupleList),
    linda_fx('$linda_in'(TupleList, true, Found), in(TupleList, Tuple)),
    Tuple = Found.

rd(Tuple) :-
    linda_fx('$linda_rd'([Tuple], true, Tuple), rd(Tuple)).

rd_noblock(Tuple) :-
    linda_fx('$linda_rd'([Tuple], false, Tuple), rd_noblock(Tuple)).

rd(TupleList, Tuple) :-
    must_be(list, TupleList),
    linda_fx('$linda_rd'(TupleList, true, Found), rd(TupleList, Tuple)),
    Tuple = Found.

% Die Grundlagen sind äußere Wirkungen: wo das verboten ist
% (library(concurrent), call_with_no_side_effects/1), nennt der Fehler
% das Prädikat der Bibliothek statt der Grundlage
linda_fx(G, User) :-
    catch(G, error(permission_error(perform, side_effect, _), context(_, Kind)),
          ( functor(User, N, A),
            throw(error(permission_error(perform, side_effect, User),
                        context(linda:N/A, Kind))) )).

bagof_rd_noblock(Template, _:Tuple, Bag) :-
    linda_bagof(Template, Tuple, false, Bag).

bagof_in_noblock(Template, _:Tuple, Bag) :-
    linda_bagof(Template, Tuple, true, Bag).

% Tuple, ohne V^ davor, ist das Muster; über die gefundenen Tupel dann
% bagof/3 mit demselben ^ (die Liste selbst ist nicht frei)
linda_bagof(Template, Tuple, Remove, Bag) :-
    linda_pattern(Tuple, Pattern, Tuples, Goal),
    (   Remove == true
    ->  User = bagof_in_noblock(Template, Tuple, Bag)
    ;   User = bagof_rd_noblock(Template, Tuple, Bag)
    ),
    linda_fx('$linda_all'(Pattern, Remove, Tuples), User),
    bagof(Template, Tuples^Goal, Bag).

linda_pattern(T, _, _, _) :-
    var(T), !,
    instantiation_error(T).
linda_pattern(V^T, Pattern, Tuples, V^Goal) :- !,
    linda_pattern(T, Pattern, Tuples, Goal).
linda_pattern(T, T, Tuples, member(T, Tuples)).
