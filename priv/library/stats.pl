/** Beschreibende Statistik über Zahlenlisten

Umfang wie SICStus' library(statistics), dazu Quantile und Rangkorrelation
wie Logtalks statistics-Bibliothek. Der Name ist ein anderer, weil
statistics/0,2 (Laufzeitdaten) schon belegt ist.

Eine Stichprobe (Sample) ist eine echte Liste von Zahlen: Ganzzahlen,
Brüche (1r3) und Floats gemischt.

  * Exakt, wo es geht: ohne Floats rechnet alles mit Brüchen –
    mean([1,2,2], M) gibt M = 5r3, ebenso Varianz, Median, Quantile,
    Momente, harmonisches Mittel, Kovarianz. Wurzeln, Logarithmen und
    Quotienten mit Wurzeln (Standardabweichung, Schiefe, Korrelation,
    geometrisches Mittel, z-Normierung) sind Floats. Ein Float in der
    Liste macht das Ergebnis zum Float (float/1 macht aus einem Bruch
    einen Float).
  * Floats: Summen mit Neumaiers Kahan-Variante, Varianz und Momente in
    zwei Durchgängen um den Mittelwert (nicht E[x²] - E[x]²) – numerisch
    stabil.
  * n oder n-1 steht im Namen: sample_variance/2 (n-1, erwartungstreu),
    population_variance/2 (n), ebenso Standardabweichung und Kovarianz.
  * Undefiniertes (leere Liste, sample_* mit weniger als zwei Werten,
    Varianz 0 bei Schiefe, Kurtosis und Korrelation, nicht-positive Werte
    beim geometrischen Mittel, 0 beim harmonischen) gibt
    evaluation_error(undefined). Keine Liste oder kein Wert:
    instantiation_error bzw. type_error(list, S) / type_error(number, X).

Lage: mean/2, weighted_mean/3, geometric_mean/2, harmonic_mean/2,
trimmed_mean/3, median/2, modes/2.
Quantile: fractile/3, percentile/3, quartiles/4, interquartile_range/2.
Streuung: min/2, max/2, min_max/3, range/2, sample_variance/2,
population_variance/2, weighted_variance/3, sample_standard_deviation/2,
population_standard_deviation/2, standard_error/2,
coefficient_of_variation/2, mean_deviation/2, median_deviation/2.
Form: central_moment/3, skewness/2, kurtosis/2.
Zusammenhang: sample_covariance/3, population_covariance/3,
correlation/3, rank_correlation/3.
Sonst: z_normalization/2, min_max_normalization/2,
frequency_distribution/2.
*/

:- module(stats, [mean/2, weighted_mean/3, geometric_mean/2, harmonic_mean/2,
                  trimmed_mean/3, median/2, modes/2,
                  fractile/3, percentile/3, quartiles/4, interquartile_range/2,
                  min/2, max/2, min_max/3, range/2,
                  sample_variance/2, population_variance/2, weighted_variance/3,
                  sample_standard_deviation/2, population_standard_deviation/2,
                  standard_error/2, coefficient_of_variation/2,
                  mean_deviation/2, median_deviation/2,
                  central_moment/3, skewness/2, kurtosis/2,
                  sample_covariance/3, population_covariance/3,
                  correlation/3, rank_correlation/3,
                  z_normalization/2, min_max_normalization/2,
                  frequency_distribution/2]).

:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(pairs)).

% --- Prüfen ---------------------------------------------------------------

sample_(S, Ctx) :-
    must_be(list, S),
    numbers_(S, Ctx).

numbers_([], _).
numbers_([X|Xs], Ctx) :-
    (   var(X) -> instantiation_error(Ctx)
    ;   number(X) -> numbers_(Xs, Ctx)
    ;   type_error(number, X, Ctx)
    ).

% nicht leer
nonempty_(S, Ctx) :-
    sample_(S, Ctx),
    (   S == [] -> undefined_(Ctx) ; true ).

% mindestens zwei Werte (sample_*)
two_(S, Ctx) :-
    sample_(S, Ctx),
    (   S = [_,_|_] -> true ; undefined_(Ctx) ).

undefined_(Ctx) :-
    throw(error(evaluation_error(undefined), Ctx)).

same_length_(Xs, Ys, Ctx) :-
    length(Xs, N),
    length(Ys, M),
    (   N =:= M -> true ; domain_error(same_length, Xs-Ys, Ctx) ).

% --- Rechnen: exakt ohne Floats, sonst stabil -------------------------------

% X / Y (Ausdrücke), exakt, wenn beide Ganzzahlen oder Brüche sind
div_(X0, Y0, Z) :-
    X is X0,
    Y is Y0,
    (   rational(X), rational(Y) -> Z is X rdiv Y
    ;   Z is X / Y
    ).

number_(P, Ctx) :-
    (   var(P) -> instantiation_error(Ctx)
    ;   number(P) -> true
    ;   type_error(number, P, Ctx)
    ).

% Summe: exakt, oder mit einem Float nach Neumaier (Kahan-Babuška)
sum_(Xs, S) :-
    (   member(X, Xs), float(X) -> neumaier_(Xs, 0.0, 0.0, S)
    ;   sum_list(Xs, S)
    ).

neumaier_([], S, C, R) :- R is S + C.
neumaier_([X0|Xs], S, C0, R) :-
    X is float(X0),
    T is S + X,
    (   abs(S) >= abs(X) -> C is C0 + ((S - T) + X)
    ;   C is C0 + ((X - T) + S)
    ),
    neumaier_(Xs, T, C, R).

mean_(Xs, M) :-
    length(Xs, N),
    sum_(Xs, S),
    div_(S, N, M).

% Summe der K-ten Potenzen der Abweichungen vom Mittelwert
dev_sum_(Xs, M, K, S) :-
    devs_(Xs, M, K, Ds),
    sum_(Ds, S).

devs_([], _, _, []).
devs_([X|Xs], M, K, [D|Ds]) :-
    D is (X - M) ^ K,
    devs_(Xs, M, K, Ds).

sqrt_(X, R) :- R is sqrt(X).

% floor/ceiling auch für Ganzzahlen (ISO verlangt dort Floats)
floor_(X0, F) :-
    X is X0,
    (   integer(X) -> F = X ; F is floor(X) ).

ceiling_(X0, C) :-
    X is X0,
    (   integer(X) -> C = X ; C is ceiling(X) ).

times_(A, B, C) :- C is A * B.
log_(X, L) :- L is log(X).
wsq_(M, A, X, D) :- D is A * (X - M)^2.
absdev_(M, X, A) :- A is abs(X - M).
coprod_(Mx, My, X, Y, P) :- P is (X - Mx) * (Y - My).
z_(M, SD, X, Z) :- Z is (X - M) / SD.
scale_(Min, Span, X, N) :- div_(X - Min, Span, N).

% --- Lage -------------------------------------------------------------------

%% mean(+Sample, -Mean)
mean(S, M) :-
    nonempty_(S, mean/2),
    mean_(S, M).

%% weighted_mean(+Weights, +Sample, -Mean): Summe w·x durch Summe w
weighted_mean(W, S, M) :-
    nonempty_(S, weighted_mean/3),
    sample_(W, weighted_mean/3),
    same_length_(W, S, weighted_mean/3),
    weighted_mean_(W, S, M).

weighted_mean_(W, S, M) :-
    maplist(times_, W, S, WS),
    sum_(WS, Num),
    sum_(W, Den),
    (   Den =:= 0 -> undefined_(weighted_mean/3) ; div_(Num, Den, M) ).

%% geometric_mean(+Sample, -Mean): exp(Mittel der Logarithmen), alle > 0
geometric_mean(S, M) :-
    nonempty_(S, geometric_mean/2),
    (   member(X, S), X =< 0 -> undefined_(geometric_mean/2) ; true ),
    maplist(log_, S, Ls),
    mean_(Ls, ML),
    M is exp(ML).

%% harmonic_mean(+Sample, -Mean): n durch Summe der Kehrwerte (exakt)
harmonic_mean(S, M) :-
    nonempty_(S, harmonic_mean/2),
    (   member(X, S), X =:= 0 -> undefined_(harmonic_mean/2) ; true ),
    maplist(div_(1), S, Rs),
    sum_(Rs, Sum),
    length(S, N),
    div_(N, Sum, M).

%% trimmed_mean(+Sample, +P, -Mean): Mittel ohne die floor(P·n) kleinsten
%% und größten Werte, 0 =< P < 1/2
trimmed_mean(S, P, M) :-
    nonempty_(S, trimmed_mean/3),
    number_(P, trimmed_mean/3),
    (   P >= 0, P < 1r2 -> true ; domain_error(trim_fraction, P, trimmed_mean/3) ),
    msort(S, Ss),
    length(Ss, N),
    floor_(P * N, K),
    length(Front, K),
    append(Front, Rest, Ss),
    L is N - 2*K,
    length(Mid, L),
    append(Mid, _, Rest),
    mean_(Mid, M).

%% median(+Sample, -Median): bei gerader Anzahl das Mittel der beiden
%% mittleren Werte (SICStus: der kleinere)
median(S, M) :-
    nonempty_(S, median/2),
    percentile_(S, 50, M).

%% modes(+Sample, -Modes): die häufigsten Werte, in Standardordnung
modes(S, Ms) :-
    nonempty_(S, modes/2),
    frequency_distribution(S, Fs),
    pairs_values(Fs, Cs),
    max_list(Cs, Max),
    findall(V, member(V-Max, Fs), Ms).

% --- Quantile -----------------------------------------------------------

%% fractile(+P, +Sample, -X): das kleinste X der Stichprobe, unter dem
%% mindestens der Anteil P liegt (nächster Rang: ceiling(P·n)-tes), 0 < P =< 1
fractile(P, S, X) :-
    nonempty_(S, fractile/3),
    number_(P, fractile/3),
    (   P > 0, P =< 1 -> true ; domain_error(fractile, P, fractile/3) ),
    msort(S, Ss),
    length(Ss, N),
    ceiling_(P * N, K0),
    K is max(1, K0),
    nth1(K, Ss, X).

%% percentile(+P, +Sample, -X): P in 0..100, linear zwischen den Rängen
%% interpoliert (Hyndman-Fan Typ 7, wie R, NumPy und Tabellenkalkulationen)
percentile(P, S, X) :-
    nonempty_(S, percentile/3),
    number_(P, percentile/3),
    (   P >= 0, P =< 100 -> true ; domain_error(percentile, P, percentile/3) ),
    percentile_(S, P, X).

percentile_(S, P, X) :-
    msort(S, Ss),
    length(Ss, N),
    div_(P * (N - 1), 100, H),
    floor_(H, F),
    nth0(F, Ss, Lo),
    (   H =:= F -> X = Lo
    ;   F1 is F + 1,
        nth0(F1, Ss, Hi),
        X is Lo + (H - F) * (Hi - Lo)
    ).

%% quartiles(+Sample, -Q1, -Q2, -Q3): 25., 50. (Median) und 75. Perzentil
quartiles(S, Q1, Q2, Q3) :-
    nonempty_(S, quartiles/4),
    percentile_(S, 25, Q1),
    percentile_(S, 50, Q2),
    percentile_(S, 75, Q3).

%% interquartile_range(+Sample, -IQR): Q3 - Q1
interquartile_range(S, R) :-
    quartiles(S, Q1, _, Q3),
    R is Q3 - Q1.

% --- Streuung -----------------------------------------------------------

%% min(+Sample, -Min), max(+Sample, -Max), min_max(+Sample, -Min, -Max)
min(S, X) :-
    nonempty_(S, min/2),
    min_list(S, X).

max(S, X) :-
    nonempty_(S, max/2),
    max_list(S, X).

min_max(S, Min, Max) :-
    nonempty_(S, min_max/3),
    min_list(S, Min),
    max_list(S, Max).

%% range(+Sample, -Range): Max - Min
range(S, R) :-
    min_max(S, Min, Max),
    R is Max - Min.

%% sample_variance(+Sample, -V): Summe (x-m)² durch n-1
sample_variance(S, V) :-
    two_(S, sample_variance/2),
    variance_(S, 1, V).

%% population_variance(+Sample, -V): Summe (x-m)² durch n
population_variance(S, V) :-
    nonempty_(S, population_variance/2),
    variance_(S, 0, V).

variance_(S, Ddof, V) :-
    mean_(S, M),
    dev_sum_(S, M, 2, Q),
    length(S, N),
    div_(Q, N - Ddof, V).

%% weighted_variance(+Weights, +Sample, -V): Summe w·(x-m)² durch Summe w,
%% m das gewichtete Mittel (verzerrt, wie SICStus)
weighted_variance(W, S, V) :-
    nonempty_(S, weighted_variance/3),
    sample_(W, weighted_variance/3),
    same_length_(W, S, weighted_variance/3),
    weighted_mean_(W, S, M),
    maplist(wsq_(M), W, S, Ds),
    sum_(Ds, Num),
    sum_(W, Den),
    div_(Num, Den, V).

%% sample_standard_deviation(+Sample, -SD), population_standard_deviation/2
sample_standard_deviation(S, SD) :-
    sample_variance(S, V),
    sqrt_(V, SD).

population_standard_deviation(S, SD) :-
    population_variance(S, V),
    sqrt_(V, SD).

%% standard_error(+Sample, -SE): Standardfehler des Mittels, s / sqrt(n)
standard_error(S, SE) :-
    sample_variance(S, V),
    length(S, N),
    SE is sqrt(V) / sqrt(N).

%% coefficient_of_variation(+Sample, -CV): s / Mittel
coefficient_of_variation(S, CV) :-
    sample_standard_deviation(S, SD),
    mean_(S, M),
    (   M =:= 0 -> undefined_(coefficient_of_variation/2) ; CV is SD / M ).

%% mean_deviation(+Sample, -D): mittlere absolute Abweichung vom Mittel
mean_deviation(S, D) :-
    nonempty_(S, mean_deviation/2),
    mean_(S, M),
    maplist(absdev_(M), S, As),
    mean_(As, D).

%% median_deviation(+Sample, -D): Median der absoluten Abweichungen vom
%% Median (MAD, ohne Skalierungsfaktor)
median_deviation(S, D) :-
    median(S, Med),
    maplist(absdev_(Med), S, As),
    percentile_(As, 50, D).

% --- Form -----------------------------------------------------------------

%% central_moment(+K, +Sample, -M): Mittel von (x-m)^K, K >= 1 ganz
central_moment(K, S, M) :-
    must_be(integer, K),
    (   K >= 1 -> true ; domain_error(not_less_than_one, K, central_moment/3) ),
    nonempty_(S, central_moment/3),
    mean_(S, Mean),
    dev_sum_(S, Mean, K, Q),
    length(S, N),
    div_(Q, N, M).

%% skewness(+Sample, -G1): m3 / m2^(3/2) (Momente um das Mittel, durch n)
skewness(S, G) :-
    nonempty_(S, skewness/2),
    central_moment(2, S, M2),
    central_moment(3, S, M3),
    (   M2 =:= 0 -> undefined_(skewness/2) ; G is M3 / M2 ** 1.5 ).

%% kurtosis(+Sample, -G2): Exzess, m4 / m2² - 3 (Normalverteilung: 0)
kurtosis(S, G) :-
    nonempty_(S, kurtosis/2),
    central_moment(2, S, M2),
    central_moment(4, S, M4),
    (   M2 =:= 0 -> undefined_(kurtosis/2)
    ;   div_(M4, M2 * M2, Q),
        G is Q - 3
    ).

% --- Zusammenhang -------------------------------------------------------

%% sample_covariance(+Xs, +Ys, -C): durch n-1; population_covariance/3: durch n
sample_covariance(Xs, Ys, C) :-
    two_(Xs, sample_covariance/3),
    sample_(Ys, sample_covariance/3),
    same_length_(Xs, Ys, sample_covariance/3),
    covariance_(Xs, Ys, 1, C).

population_covariance(Xs, Ys, C) :-
    nonempty_(Xs, population_covariance/3),
    sample_(Ys, population_covariance/3),
    same_length_(Xs, Ys, population_covariance/3),
    covariance_(Xs, Ys, 0, C).

covariance_(Xs, Ys, Ddof, C) :-
    co_sum_(Xs, Ys, Sxy),
    length(Xs, N),
    div_(Sxy, N - Ddof, C).

% Summe (x-mx)(y-my)
co_sum_(Xs, Ys, S) :-
    mean_(Xs, Mx),
    mean_(Ys, My),
    maplist(coprod_(Mx, My), Xs, Ys, Ps),
    sum_(Ps, S).

%% correlation(+Xs, +Ys, -R): Pearson
correlation(Xs, Ys, R) :-
    two_(Xs, correlation/3),
    sample_(Ys, correlation/3),
    same_length_(Xs, Ys, correlation/3),
    pearson_(Xs, Ys, R, correlation/3).

pearson_(Xs, Ys, R, Ctx) :-
    co_sum_(Xs, Ys, Sxy),
    co_sum_(Xs, Xs, Sxx),
    co_sum_(Ys, Ys, Syy),
    (   Sxx =:= 0 -> undefined_(Ctx)
    ;   Syy =:= 0 -> undefined_(Ctx)
    ;   R is Sxy / sqrt(Sxx * Syy)
    ).

%% rank_correlation(+Xs, +Ys, -Rho): Spearman (Pearson der Ränge, gleiche
%% Werte bekommen den mittleren Rang)
rank_correlation(Xs, Ys, R) :-
    two_(Xs, rank_correlation/3),
    sample_(Ys, rank_correlation/3),
    same_length_(Xs, Ys, rank_correlation/3),
    ranks_(Xs, Rx),
    ranks_(Ys, Ry),
    pearson_(Rx, Ry, R, rank_correlation/3).

% Ränge 1..n in der Reihenfolge der Liste, gleiche Werte (=:=) gemittelt
ranks_(Xs, Rs) :-
    numlist_(Xs, 1, Is),
    pairs_keys_values(Ps, Xs, Is),
    keysort(Ps, Sorted),
    tie_ranks_(Sorted, 1, Ranked),
    keysort(Ranked, ByIndex),
    pairs_values(ByIndex, Rs).

numlist_([], _, []).
numlist_([_|Xs], I, [I|Is]) :- I1 is I + 1, numlist_(Xs, I1, Is).

% Sorted: Wert-Index; Ergebnis: Index-Rang
tie_ranks_([], _, []).
tie_ranks_([X-I|Ps], Pos, Out) :-
    same_value_(Ps, X, Same, Rest),
    length(Same, K),
    Last is Pos + K,
    R is (Pos + Last) rdiv 2,
    findall(J-R, member(_-J, [X-I|Same]), Rs),
    append(Rs, Out1, Out),
    Next is Last + 1,
    tie_ranks_(Rest, Next, Out1).

same_value_([Y-J|Ps], X, [Y-J|Same], Rest) :-
    Y =:= X, !,
    same_value_(Ps, X, Same, Rest).
same_value_(Ps, _, [], Ps).

% --- Sonst ----------------------------------------------------------------

%% z_normalization(+Sample, -Zs): (x - Mittel) / Populations-
%% Standardabweichung (wie SICStus' normalize/2)
z_normalization(S, Zs) :-
    population_standard_deviation(S, SD),
    (   SD =:= 0 -> undefined_(z_normalization/2) ; true ),
    mean_(S, M),
    maplist(z_(M, SD), S, Zs).

%% min_max_normalization(+Sample, -Ns): (x - Min) / (Max - Min), exakt
min_max_normalization(S, Ns) :-
    min_max(S, Min, Max),
    (   Max =:= Min -> undefined_(min_max_normalization/2) ; true ),
    Span is Max - Min,
    maplist(scale_(Min, Span), S, Ns).

%% frequency_distribution(+Sample, -Pairs): Wert-Anzahl in Standardordnung
frequency_distribution(S, Fs) :-
    sample_(S, frequency_distribution/2),
    msort(S, Ss),
    runs_(Ss, Fs).

runs_([], []).
runs_([X|Xs], [X-N|Fs]) :-
    run_(Xs, X, 1, N, Rest),
    runs_(Rest, Fs).

run_([Y|Ys], X, N0, N, Rest) :-
    Y == X, !,
    N1 is N0 + 1,
    run_(Ys, X, N1, N, Rest).
run_(Rest, _, N, N, Rest).
