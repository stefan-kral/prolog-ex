/** Arithmetic predicates

Wie Scryers library(arithmetic) (siehe SCRYER-LICENSE), ohne
number_to_rational/2,3 und rational_numerator_denominator/3: PrologEx
kennt keine rationalen Zahlen. msb/2, lsb/2 und popcount/2 rechnen über
die gleichnamigen Funktionen von is/2.
*/

:- module(arithmetic, [expmod/4, lcm/3, lsb/2, msb/2, popcount/2]).

:- use_module(library(error)).
:- use_module(library(lists), [member/2]).

%% expmod(+Base, +Expo, +Mod, -R).
%
% Modular exponentiation. Base, Expo and Mod must be integers.
expmod(Base, Expo, Mod, R) :-
    (   member(N, [Base, Expo, Mod]), var(N) -> instantiation_error(expmod/4)
    ;   member(N, [Base, Expo, Mod]), \+ integer(N) ->
        type_error(integer, N, expmod/4)
    ;   Expo < 0 -> domain_error(not_less_than_zero, Expo, expmod/4)
    ;   expmod_(Base, Expo, Mod, 1, R)
    ).

expmod_(_, _, 1, _, 0) :- !.
expmod_(_, 0, _, R, R) :- !.
expmod_(Base0, Expo0, Mod, C0, R) :-
    Expo0 /\ 1 =:= 1,
    C is (C0 * Base0) mod Mod,
    !,
    Expo is Expo0 >> 1,
    Base is (Base0 * Base0) mod Mod,
    expmod_(Base, Expo, Mod, C, R).
expmod_(Base0, Expo0, Mod, C, R) :-
    Expo is Expo0 >> 1,
    Base is (Base0 * Base0) mod Mod,
    expmod_(Base, Expo, Mod, C, R).

%% lcm(+A, +B, -X).
%
% Least common multiple of A and B.
lcm(A, B, X) :-
    must_be_number(A, lcm/2),
    must_be_number(B, lcm/2),
    (   \+ integer(A) -> type_error(integer, A, lcm/2)
    ;   \+ integer(B) -> type_error(integer, B, lcm/2)
    ;   (A = 0, B = 0) -> X = 0
    ;   can_be_number(X, lcm/2),
        X is abs(B) // gcd(A,B) * abs(A)
    ).

%% lsb(+X, -N).
%
% N is the index of the least significant 1 bit of X (X >= 1).
lsb(X, N) :-
    must_be_number(X, lsb/2),
    (   \+ integer(X) -> type_error(integer, X, lsb/2)
    ;   X < 1 -> domain_error(not_less_than_one, X, lsb/2)
    ;   can_be_number(N, lsb/2),
        N is lsb(X)
    ).

%% msb(+X, -N).
%
% N is the index of the most significant 1 bit of X (X >= 1).
msb(X, N) :-
    must_be_number(X, msb/2),
    (   \+ integer(X) -> type_error(integer, X, msb/2)
    ;   X < 1 -> domain_error(not_less_than_one, X, msb/2)
    ;   can_be_number(N, msb/2),
        N is msb(X)
    ).

%% popcount(+X, -N).
%
% N is the number of 1 bits of the non-negative integer X.
popcount(X, N) :-
    must_be(integer, X),
    N is popcount(X).

% wie Scryers builtins:must_be_number/2 und builtins:can_be_number/2
must_be_number(X, PI) :-
    (   var(X) -> instantiation_error(PI)
    ;   number(X) -> true
    ;   type_error(number, X, PI)
    ).

can_be_number(X, PI) :-
    (   var(X) -> true
    ;   number(X) -> true
    ;   type_error(number, X, PI)
    ).
