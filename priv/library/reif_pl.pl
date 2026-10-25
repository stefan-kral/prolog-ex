% library(reif_pl): reifizierte Gleichheit und Kontrolle nach Ulrich
% Neumerkel und Stefan Kral, "Indexing dif/2" (2016), in reinem Prolog –
% Aufbau wie reif.pl (Scryer, SICStus, SWI), ohne die goal_expansion für
% if_/3. Dieselbe Bibliothek mit Schnellwegen in Elixir: library(reif).
%
%   if_(If_1, Then_0, Else_0)   call(If_1, T): T = true -> Then, T = false -> Else
%   =(X, Y, T)                  T = true, wenn X = Y; T = false, wenn dif(X, Y)
%   dif(X, Y, T)                umgekehrt
%   ','(A_1, B_1, T), ;(A_1, B_1, T), cond_t(If_1, Then_0, T)
%   memberd_t(E, Xs, T), tfilter(C_2, Es, Fs), tpartition(P_2, Xs, Ts, Fs),
%   tmember(P_2, Xs), tmember_t(P_2, Xs, T)

:- module(reif_pl, [if_/3, (=)/3, dif/3, (',')/3, (;)/3, cond_t/3,
                    memberd_t/3, tfilter/3, tpartition/4, tmember/2, tmember_t/3]).

:- meta_predicate
       if_(1, 0, 0),
       cond_t(1, 0, ?),
       tfilter(2, ?, ?),
       tpartition(2, ?, ?, ?),
       ','(1, 1, ?),
       ;(1, 1, ?),
       tmember(2, ?),
       tmember_t(2, ?, ?).

if_(If_1, Then_0, Else_0) :-
   call(If_1, T),
   (  T == true -> call(Then_0)
   ;  T == false -> call(Else_0)
   ;  nonvar(T) -> throw(error(type_error(boolean, T), _))
   ;  throw(error(instantiation_error, _))
   ).

=(X, Y, T) :-
   (  X == Y -> T = true
   ;  X \= Y -> T = false
   ;  T = true, X = Y
   ;  T = false,
      dif(X, Y)
   ).

dif(X, Y, T) :-
   =(X, Y, NT),
   non(NT, T).

non(true, false).
non(false, true).

','(A_1, B_1, T) :-
   if_(A_1, call(B_1, T), T = false).

;(A_1, B_1, T) :-
   if_(A_1, T = true, call(B_1, T)).

cond_t(If_1, Then_0, T) :-
   if_(If_1, ( Then_0, T = true ), T = false).

memberd_t(E, Xs, T) :-
   i_memberd_t(Xs, E, T).

i_memberd_t([], _E, false).
i_memberd_t([X|Xs], E, T) :-
   if_(X = E, T = true, i_memberd_t(Xs, E, T)).

tfilter(_CT_2, [], []).
tfilter(CT_2, [E|Es], Fs0) :-
   if_(call(CT_2, E), Fs0 = [E|Fs], Fs0 = Fs),
   tfilter(CT_2, Es, Fs).

tpartition(P_2, Xs, Ts, Fs) :-
   i_tpartition(Xs, P_2, Ts, Fs).

i_tpartition([], _P_2, [], []).
i_tpartition([X|Xs], P_2, Ts0, Fs0) :-
   if_(call(P_2, X),
       ( Ts0 = [X|Ts], Fs0 = Fs ),
       ( Fs0 = [X|Fs], Ts0 = Ts )),
   i_tpartition(Xs, P_2, Ts, Fs).

tmember(P_2, [X|Xs]) :-
   if_(call(P_2, X), true, tmember(P_2, Xs)).

tmember_t(_P_2, [], false).
tmember_t(P_2, [X|Xs], T) :-
   if_(call(P_2, X), T = true, tmember_t(P_2, Xs, T)).
