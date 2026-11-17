% aus Logtalk, examples/dcgs/bom.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
:- set_prolog_flag(double_quotes, codes).

parts(Object, Parts) :-
	phrase(Object, Parts).

bike --> frame, drivechain, wheel, wheel.

wheel --> spokes, rim, hub.

drivechain --> crank, pedal, pedal, chain.

spokes --> [spokes].
crank --> [crank].
pedal --> [pedal].
chain --> [chain].
rim --> [rim].
hub --> [hub].
frame --> [frame].
