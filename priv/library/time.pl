/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Written 2020-2024 by Markus Triska (triska@metalevel.at)
   Part of Scryer Prolog.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

/* library(time) aus Scryer Prolog (src/lib/time.pl; BSD-Lizenz, siehe
   SCRYER-LICENSE). Geändert:
     - statistics/2 steht nur in der Exportliste: es gilt das eingebaute
       (eine Obermenge; Scryers liefert nur runtime mit [T, unsupported]).
     - '$current_time' liefert den Zeitstempel als Term (ohne
       read_from_chars/2); '$cpu_now', '$inference_count', '$sleep' in
       Elixir (PrologEx.Builtins.ScryerPrims).
     - sleep/1 prüft die Zahl selbst (statt builtins:must_be_number/2).
     - time/1 misst direkt um das Ziel herum (siehe dort), statt einen
       festen Eigenverbrauch abzuziehen; Scryers Einrückung für sein
       Toplevel entfällt. Ausgabe wie Scryer.
*/

/** This library provides predicates for reasoning about time.
*/

:- module(time, [max_sleep_time/1,
                 sleep/1,
                 time/1,
                 current_time/1,
                 format_time//2,
                 statistics/2
                ]).

:- use_module(library(format)).
:- use_module(library(error)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(charsio), [read_from_chars/2]).


%% current_time(-T)
%
%  Yields the current system time _T_ in an opaque form, called a
%  _time stamp_. Use `format_time//2` to describe strings that contain
%  attributes of the time stamp.

current_time(T) :-
        '$current_time'(T).

%% format_time(FormatString, TimeStamp)//
%
% The nonterminal format_time//2 describes a list of characters that
% are formatted according to a format string. Usage:
%
% ```
%    phrase(format_time(FormatString, TimeStamp), Cs)
% ```
%
% TimeStamp represents a moment in time in an opaque form, as for
% example obtained by `current_time/1`.
%
% FormatString is a list of characters that are interpreted literally,
% except for the following specifiers (and possibly more in the future):
%
% |  `%Y` |  year of the time stamp. Example: 2020.                |
% |  `%m` |  month number (01-12), zero-padded to 2 digits         |
% |  `%d` |  day number (01-31), zero-padded to 2 digits           |
% |  `%H` |  hour number (00-24), zero-padded to 2 digits          |
% |  `%M` |  minute number (00-59), zero-padded to 2 digits        |
% |  `%S` |  second number (00-60), zero-padded to 2 digits        |
% |  `%b` |  abbreviated month name, always 3 letters              |
% |  `%a` |  abbreviated weekday name, always 3 letters            |
% |  `%A` |  full weekday name                                     |
% |  `%j` |  day of the year (001-366), zero-padded to 3 digits    |
% |  `%%` |  the literal `%`                                       |
%
% Example:
%
% ```
%    ?- current_time(T), phrase(format_time("%d.%m.%Y (%H:%M:%S)", T), Cs).
%       T = [...], Cs = "11.06.2020 (00:24:32)".
% ```

format_time([], _) --> [].
format_time(['%','%'|Fs], T) --> !, "%", format_time(Fs, T).
format_time(['%',Spec|Fs], T) --> !,
        (   { member(Spec=Value, T) } ->
            seq(Value)
        ;   { domain_error(time_specifier, Spec, format_time//2) }
        ),
        format_time(Fs, T).
format_time([F|Fs], T) --> [F], format_time(Fs, T).

%% max_sleep_time(T)
%
%  The maximum admissible time span for `sleep/1`.

max_sleep_time(0xfffffffffffffbff).


%% sleep(S)
%
%  Sleeps for S seconds (a floating point number or integer).

sleep(T) :-
    (   var(T) -> instantiation_error(sleep/1)
    ;   number(T) -> true
    ;   type_error(number, T, sleep/1)
    ),
    (   T < 0 ->
        domain_error(not_less_than_zero, T, sleep/1)
    ;   max_sleep_time(N), T > N ->
        throw(error(representation_error(max_sleep_time), sleep/1))
    ;   '$sleep'(T)
    ).


%% statistics(?Keyword, ?List)
%
%  Preliminary support for statistics/2, yielding timing information.
%  The only supported `Keyword` is `runtime`. The first element of
%  `List` is the CPU time in milliseconds, the second element is
%  currently not supported.

% statistics/2: das eingebaute (siehe oben)

:- meta_predicate(time(0)).

:- dynamic(time_id/1).
:- dynamic(time_state/3).
:- dynamic(time_end/3).

time_next_id(N) :-
        (   retract(time_id(N0)) ->
            N is N0 + 1
        ;   N = 0
        ),
        asserta(time_id(N)).


%% time(Goal)
%
%  Reports the execution time of Goal.

% PrologEx: gemessen wird direkt um Goal herum – Anfang beim Eintritt
% (und beim Zurücksetzen hinein), Ende beim Austritt –, damit der
% Eigenverbrauch von time/1 nicht davon abhängt, ob Goal deterministisch
% war oder die wievielte Lösung kommt. Die Ausgabe ist die von Scryer.
time(Goal) :-
        time_next_id(ID),
        setup_call_cleanup(true,
                           (   call_cleanup(catch((time_start(ID, 0), Goal), E,
                                                  (report_time(ID, exception),throw(E))),
                                            Det = true),
                               time_exit(ID),
                               (   Det == true ->
                                   report_time(ID, exit_det),
                                   !
                               ;   report_time(ID, exit)
                               )
                           ;   report_time(ID, fail),
                               false
                           ),
                           (   retractall(time_state(ID, _, _)),
                               retractall(time_end(ID, _, _))
                           )).

% Adj: Inferenzen zwischen dieser Messung und Goal, die der andere Weg
% nicht hat (false beim Zurücksetzen)
time_start(ID, Adj) :-
        cputime_inferences(T0, I),
        I0 is I + Adj,
        retractall(time_state(ID, _, _)),
        asserta(time_state(ID, T0, I0)).

% Ende einer Lösung; beim Zurücksetzen in Goal: neuer Anfang
time_exit(ID) :-
        cputime_inferences(T, I),
        retractall(time_end(ID, _, _)),
        asserta(time_end(ID, T, I)).
time_exit(ID) :-
        time_start(ID, 1),
        false.

cputime_inferences(T, I) :-
        '$cpu_now'(T),
        '$inference_count'(I).

% Eigenverbrauch (Inferenzen) zwischen den Messpunkten und Goal, je nach
% Weg hinaus: Austritt (deterministisch oder nicht), Scheitern, Ausnahme;
% geeicht so, dass time(true) eine Inferenz meldet
overhead(exit_det, 9).
overhead(exit, 7).
overhead(fail, 12).
overhead(exception, 10).

report_time(ID, How) :-
        time_state(ID, T0, I0),
        (   ( How == exit ; How == exit_det ) -> time_end(ID, T, I)
        ;   cputime_inferences(T, I)
        ),
        overhead(How, Own),
        Time is T - T0,
        Inferences is I - I0 - Own,
        phrase(("% CPU time: ", format_("~3f", [Time]), "s, ",
                format_("~U", [Inferences])," inference",s_if_necessary(Inferences),"\n"), Cs),
        format("~s", [Cs]).

s_if_necessary(Inferences) -->
        { compare(C, 1, Inferences) },
        s_(C).

s_(=) --> "".
s_(<) --> "s".
s_(>) --> " (exception?)".

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
?- time((true;false)).
   % CPU time: 0.000s, 1 inference
   true
;  % CPU time: 0.000s, 0 inference (exception?)
   false.

:- time(use_module(library(clpz))).
   % CPU time: 0.343s, 409_874 inferences
   true.

:- time(use_module(library(lists))).
   % CPU time: 0.000s, 19 inferences
   true.

?- time(member(X, "abc")).
   % CPU time: 0.000s, 1 inference
   X = a
;  % CPU time: 0.000s, 3 inferences
   X = b
;  % CPU time: 0.000s, 3 inferences
   X = c.

?- time((repeat,false)).
   % CPU time: 2.726s, 53_330_502 inferences
   error('$interrupt_thrown',repl/0).
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */
