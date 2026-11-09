/** Arithmetic predicates

Wie Scryers library(arithmetic) (siehe SCRYER-LICENSE). Die Prädikate für
Brüche (number_to_rational/2,3, rational_numerator_denominator/3) sind neu
geschrieben, über die eingebauten Brüche (1r3, rational/3):

  * number_to_rational(+Eps, +Real, -F): F ist der einfachste Bruch (kleinster
    Nenner) im geschlossenen Intervall [Real - Eps, Real + Eps], exakt
    gerechnet (ein Float zählt mit seinem exakten Wert). Scryer sucht nur im
    Nachkommateil und trifft dessen Ränder 0 und 1 nie: 2.0000001 mit Eps
    1.0e-6 gibt dort 2 + 1/909091, hier 2; eine negative Ganzzahl -2 gibt
    dort -3. Über Kettenbrüche statt Schritt für Schritt durch den
    Stern-Brocot-Baum: auch number_to_rational(0, 1.0e-300, F) ist sofort
    fertig.
  * number_to_rational(+Real, -F): Ganzzahl unverändert, sonst mit Eps
    1.0e-6 (wie Scryer): number_to_rational(3.14159265, F) gibt 355r113.
  * rational_numerator_denominator(+R, -N, -D): wie rational/3 (auch für
    Ganzzahlen: D = 1; Scryer scheitert dort, sein Bruch 2 rdiv 1 ist keine
    Ganzzahl). Kein Bruch: scheitert. msb/2, lsb/2 und popcount/2 rechnen über
die gleichnamigen Funktionen von is/2.
*/

:- module(arithmetic, [expmod/4, lcm/3, lsb/2, msb/2, number_to_rational/2,
                       number_to_rational/3, popcount/2,
                       rational_numerator_denominator/3]).

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

%% number_to_rational(+Real, -Fraction).
%
% Fraction ist Real als Bruch: eine Ganzzahl unverändert, sonst der
% einfachste Bruch im Abstand höchstens 1.0e-6.
number_to_rational(Real, Fraction) :-
    (   var(Real) -> instantiation_error(number_to_rational/2)
    ;   integer(Real) -> Fraction = Real
    ;   number(Real) -> number_to_rational(1.0e-6, Real, Fraction)
    ;   type_error(number, Real, number_to_rational/2)
    ).

%% number_to_rational(+Eps, +Real, -Fraction).
%
% Fraction ist der einfachste Bruch (kleinster Nenner, dann kleinster
% Betrag) mit |Fraction - Real| =< Eps, exakt gerechnet.
number_to_rational(Eps0, Real0, Fraction) :-
    (   var(Eps0) -> instantiation_error(number_to_rational/3)
    ;   \+ number(Eps0) -> type_error(number, Eps0, number_to_rational/3)
    ;   Eps0 < 0 -> domain_error(not_less_than_zero, Eps0, number_to_rational/3)
    ;   var(Real0) -> instantiation_error(number_to_rational/3)
    ;   \+ number(Real0) -> type_error(number, Real0, number_to_rational/3)
    ;   Eps is rational(Eps0),
        Real is rational(Real0),
        Lo is Real - Eps,
        Hi is Real + Eps,
        '$simplest_rational'(Lo, Hi, Fraction)
    ).

%% rational_numerator_denominator(+Fraction, -Numerator, -Denominator).
%
% Zähler und Nenner eines Bruchs (einer Ganzzahl: Nenner 1).
rational_numerator_denominator(R, N, D) :-
    rational(R, N, D).
