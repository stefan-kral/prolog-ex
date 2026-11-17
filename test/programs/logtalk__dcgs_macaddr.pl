% aus Logtalk, examples/dcgs/macaddr.lgt (Paulo Moura,
% SPDX-License-Identifier: Apache-2.0). Angepasst: Objekt-Huelle und
% Direktiven entfernt; double_quotes = codes wie in Logtalk.
:- set_prolog_flag(double_quotes, codes).

valid(Address) :-
	phrase(mac, Address).

mac --> digits, ":", digits, ":", digits, ":", digits, ":", digits, ":", digits.

digits --> digit, digit.

digit --> [C], {0'0 =< C, C =< 0'9}.
digit --> [C], {0'a =< C, C =< 0'f}.
digit --> [C], {0'A =< C, C =< 0'F}.
