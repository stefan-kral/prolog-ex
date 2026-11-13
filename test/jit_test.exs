defmodule PrologEx.JitTest do
  # Übersetzte Prädikate (PrologEx.Jit) geben dieselben Antworten, Fehler,
  # Inferenzen und Grenzen wie der Interpreter: jede Anfrage läuft gegen
  # beide (Flag jit beim Laden an bzw. aus) und muss gleich ausgehen.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(lists)).
  :- use_module(library(iso_ext)).
  :- use_module(library(swi)).
  :- use_module(library(arithmetic)).
  fib(0, 0).
  fib(1, 1).
  fib(N, F) :- N > 1, A is N-1, B is N-2, fib(A, FA), fib(B, FB), F is FA+FB.
  lp(0) :- !.
  lp(N) :- N1 is N - 1, lp(N1).
  gcd(X, 0, X) :- !.
  gcd(X, Y, G) :- Y > 0, Z is X mod Y, gcd(Y, Z, G).
  ack(0, N, R) :- !, R is N + 1.
  ack(M, 0, R) :- !, M1 is M - 1, ack(M1, 1, R).
  ack(M, N, R) :- M1 is M - 1, N1 is N - 1, ack(M, N1, R1), ack(M1, R1, R).
  col(1, 0) :- !.
  col(N, S) :- N mod 2 =:= 0, !, M is N // 2, col(M, S0), S is S0 + 1.
  col(N, S) :- M is 3 * N + 1, col(M, S0), S is S0 + 1.
  ab(X, Y) :- X >= 0, Y is X.
  ab(X, Y) :- X < 0, Y is -X.
  d(X, Y) :- Y is 10 // X.
  p2(0, 1) :- !.
  p2(N, R) :- N1 is N - 1, p2(N1, R1), R is R1 * 2.
  sum(N, S) :- N =< 0, S = 0.
  sum(N, S) :- N > 0, M is N - 1, sum(M, S0), S is S0 + N.
  fibi(N, F) :- ( N < 2 -> F = N ; A is N-1, B is N-2, fibi(A, FA), fibi(B, FB), F is FA+FB ).
  mx(X, Y, Z) :- ( X >= Y -> Z = X ; Z = Y ).
  sg(X, S) :- ( X > 0 -> S = 1 ; X < 0 -> S = -1 ; S = 0 ).
  fl(N, X) :- N =< 0, !, X = 1.0.
  fl(N, X) :- M is N - 1, fl(M, Y), X is Y * 1.5.
  hyp(A, B, C) :- C is sqrt(A*A + B*B).
  dv(X, Y) :- Y is X / 2.
  nt(X, Y) :- \+ X > 10, Y is X * 2.
  w(X, Y) :- X = 0, Y = 10.
  w(X, Y) :- X > 0, Y is X + 1.
  z(X, Y) :- X = 0, !, Y = 10.
  z(X, Y) :- Y is X + 1.
  it(X) :- ( X > 0 -> true ).
  nf(X) :- ( X > 5 -> fail ; true ).
  cb(X, Y) :- ( X > 0 -> !, Y = 1 ; Y = 2 ), Y > 1.
  cr(X, Y) :- ( X > 0, Z is X * 2, Z < 10 -> Y is Z + 1 ; Y = 0 ).
  pz(X, Y) :- ( X > 0 -> Z = 1 ; true ), Y = Z.
  wd(X, Y) :- X = 0, Y = 1.
  wd(X, Y) :- Y is 1 // X, X > 0.
  ev(N) :- N =:= 0, !.
  ev(N) :- N > 0, M is N - 1, od(M).
  od(N) :- N > 0, M is N - 1, ev(M).
  sq(X, Y) :- Y is X * X.
  twice(X, Y) :- sq(X, A), Y is A * 2.
  sumsq(N, S) :- N =< 0, S = 0.
  sumsq(N, S) :- N > 0, sq(N, Q), M is N - 1, sumsq(M, S0), S is S0 + Q.
  half(X, Y) :- Y is X / 2.
  hsum(N, S) :- N =< 0, S = 0.
  hsum(N, S) :- N > 0, half(N, H), M is N - 1, hsum(M, S0), S is S0 + H.
  nj(X, Y) :- atom_length(X, Y).
  cnj(X, Y) :- X > 0, nj(X, Y).
  :- dynamic(dsq/2).
  dsq(X, Y) :- Y is X * X.
  udsq(X, Y) :- dsq(X, Y).
  app([], L, L).
  app([H|T], L, [H|R]) :- app(T, L, R).
  nrev([], []).
  nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R).
  len([], 0).
  len([_|T], N) :- len(T, N0), N is N0 + 1.
  suml([], 0).
  suml([X|Xs], S) :- suml(Xs, S0), S is S0 + X.
  rev([], A, A).
  rev([H|T], A, R) :- rev(T, [H|A], R).
  reverse2(L, R) :- rev(L, [], R).
  maxl([X], X) :- !.
  maxl([X|Xs], M) :- maxl(Xs, M0), ( X > M0 -> M = X ; M = M0 ).
  dbl([], []).
  dbl([X|Xs], [Y|Ys]) :- Y is 2 * X, dbl(Xs, Ys).
  rng(N, N, [N]) :- !.
  rng(I, N, [I|T]) :- I < N, I1 is I + 1, rng(I1, N, T).
  last2([X], X) :- !.
  last2([_|T], X) :- last2(T, X).
  avg(L, A) :- suml(L, S), len(L, N), N > 0, A is S / N.
  al(X, [X], X).
  first2([X|_], X).
  fact(N, F) :- integer(N), N >= 0, fact_(N, 1, F).
  fact_(0, A, A) :- !.
  fact_(N, A, F) :- A1 is A * N, N1 is N - 1, fact_(N1, A1, F).
  kl(X, Y) :- integer(X), !, Y is X * 2.
  kl(X, Y) :- float(X), !, Y is X / 2.
  kl(_, 0).
  tw(X, Y) :- integer(X), Y is X + 1.
  tw(X, Y) :- float(X), Y is X * 2.0.
  vv(X, Y) :- var(X), !, Y = 0.
  vv(X, Y) :- ( integer(X) -> Y = 1 ; Y = 2 ).
  eqn(X, Y, Z) :- ( X == Y -> Z = 1 ; Z = 0 ).
  eqt(X, Y, Z) :- ( X \\== Y -> Z = 1 ; Z = 0 ).
  il(L, N) :- is_list(L), !, len(L, N).
  il(_, -1).
  avar(X, Y) :- Y = 1, var(X).
  aeq(X, Y) :- Y = 1, X == 1.
  cnt([], 0).
  cnt([X|Xs], N) :- cnt(Xs, N0), ( integer(X) -> N is N0 + 1 ; N = N0 ).
  nz(X, Y) :- number(X), X =\\= 0, Y is 1 / X.
  nz(X, Y) :- atom(X), Y = 0.
  nth(0, [X|_], X) :- !.
  nth(N, [_|T], X) :- N > 0, N1 is N - 1, nth(N1, T, X).
  inf(G, I) :- statistics(inferences, I0), call(G), statistics(inferences, I1), I is I1 - I0.
  padd(0, Y, Y).
  padd(s(X), Y, s(Z)) :- padd(X, Y, Z).
  pmul(0, _, 0).
  pmul(s(X), Y, Z) :- pmul(X, Y, Z0), padd(Y, Z0, Z).
  pnat(0, 0).
  pnat(N, s(P)) :- N > 0, N1 is N - 1, pnat(N1, P).
  pval(0, 0).
  pval(s(X), N) :- pval(X, N0), N is N0 + 1.
  pkeys([], []).
  pkeys([K-_|T], [K|Ks]) :- pkeys(T, Ks).
  psum([], S, S).
  psum([_-V|T], S0, S) :- S1 is S0 + V, psum(T, S1, S).
  pmk([], []).
  pmk([X|Xs], [X-Y|Ps]) :- Y is X * X, pmk(Xs, Ps).
  colr(red, 1).
  colr(green, 2).
  colr(blue, 3).
  csum([], S, S).
  csum([C|Cs], S0, S) :- colr(C, V), S1 is S0 + V, csum(Cs, S1, S).
  dd(U+V, X, DU+DV) :- !, dd(U, X, DU), dd(V, X, DV).
  dd(U*V, X, DU*V+U*DV) :- !, dd(U, X, DU), dd(V, X, DV).
  dd(X, X, 1) :- !.
  dd(_, _, 0).
  same(X, X, yes) :- !.
  same(_, _, no).
  targ(T, N, A) :- arg(N, T, A).
  tfun(T, F, N) :- functor(T, F, N).
  tsz(T, S) :- functor(T, _, N), tsz_(N, T, 0, S).
  tsz_(0, _, S, S) :- !.
  tsz_(I, T, S0, S) :-
      arg(I, T, A), ( compound(A) -> tsz(A, SA) ; SA = 1 ),
      S1 is S0 + SA, I1 is I - 1, tsz_(I1, T, S1, S).
  tuniv(T, L) :- T =.. L.
  tname(T, F) :- T =.. [F|_].
  tcmp(X, Y, O) :- compare(O, X, Y).
  tcmpo(X, O) :- compare(O, X, a).
  tmax(X, Y, M) :- ( X @> Y -> M = X ; M = Y ).
  tle(X, Y, R) :- ( X @=< Y -> R = 1 ; R = 0 ).
  tge(X, Y, R) :- ( X @>= Y -> R = 1 ; R = 0 ).
  tlt(X, Y, R) :- ( X @< Y -> R = 1 ; R = 0 ).
  tco(X, s(O)) :- compare(O, X, b).
  tgo(X, s(R)) :- ( X @> b -> R = 1 ; R = 0 ).
  od1(X, Y) :- ( X > 10, Y = big ; X > 5, Y = mid ; Y = small ), !.
  od2(X, Y) :- ( X < 0 ; X > 100 ), !, Y = out.
  od2(_, in).
  od3(X, Y) :- ( X > 0, Z = 1 ; Z = 2 ), !, Y is Z * 10.
  od4(X, Y) :- ( X > 0, !, X > 5 ; true ), !, Y = 1.
  od4(_, 2).
  od6(X, Y) :- ( X = a ; X = b ), !, Y = ab.
  od6(_, other).
  od7(X, Y) :- ( ( X > 5 -> Y = 1 ; Y = 2 ) ; Y = 3 ), !.
  tins(X, [], [X]).
  tins(X, [Y|Ys], L) :- compare(O, X, Y), tins_(O, X, Y, Ys, L).
  tins_(<, X, Y, Ys, [X,Y|Ys]).
  tins_(=, _, Y, Ys, [Y|Ys]).
  tins_(>, X, Y, Ys, [Y|L]) :- tins(X, Ys, L).
  nrv([], []).
  nrv([H|T], R) :- nrv(T, RT), append(RT, [H], R).
  tap(X, Y, Z) :- append(X, Y, Z).
  tapc(X, Z) :- append(X, [c], Z).
  % nichtdeterministisch ("Blatt")
  mem(X, [X|_]).
  mem(X, [_|T]) :- mem(X, T).
  btw(L, H, L) :- L =< H.
  btw(L, H, X) :- L < H, L1 is L + 1, btw(L1, H, X).
  sel(X, [X|T], T).
  sel(X, [H|T], [H|R]) :- sel(X, T, R).
  pk(X, Y) :- X > 2, !, Y = big.
  pk(_, small).
  nde(X, Y) :- Y is X.
  nde(X, Y) :- Y is 1 // X.
  ndl(_, first).
  ndl(L, Y) :- L = [_, Y|_].
  wrap(L, s(X)) :- mem(X, L).
  ones(L, k) :- mem(1, L).
  sq3(N, Y) :- N > 0, M is N * N, btw(1, M, Y).
  ndf(X, Y) :- X > 0, Y = pos.
  ndf(X, Y) :- X >= 0, Y = nonneg.
  ndf(_, any).
  % nur die erste Lösung zählt: Schnitt danach, Bedingung, \\+
  memc(X, L) :- mem(X, L), !.
  incl(X, L, R) :- ( mem(X, L) -> R = yes ; R = no ).
  notin(X, L) :- \\+ mem(X, L).
  firstbig(L, X) :- mem(X, L), X > 10, !.
  cntin([], _, 0).
  cntin([X|Xs], L, N) :- cntin(Xs, L, N0), ( mem(X, L) -> N is N0 + 1 ; N = N0 ).
  sqin(N, L) :- btw(1, N, X), X * X =:= L, !.
  pairin(K, L, V) :- ( mem(K-V0, L) -> V = V0 ; V = none ).
  % Bits: bit_is_set/2 (arithmetic) und getbit/2
  bcount(_, -1, C, C) :- !.
  bcount(N, K, C0, C) :- ( bit_is_set(N, K) -> C1 is C0 + 1 ; C1 = C0 ), K1 is K - 1, bcount(N, K1, C1, C).
  gsum(_, -1, S, S) :- !.
  gsum(N, K, S0, S) :- S1 is S0 + getbit(N, K), K1 is K - 1, gsum(N, K1, S1, S).
  """

  # übersetzt: der Eintritt lohnt ({:jit, ...} im Prädikat) oder nur für
  # übersetzte Rufer ({:jit_info, ...})
  defp jitted?(db, {m, n, a} = k),
    do:
      match?({:pred, _, _, {t, _, _, _, _, _}, _} when t in [:jit, :jit_nd], db[k]) or
        Map.has_key?(db, {:jit_info, m, n, a})

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    terms = Reader.read_terms(r, @program)
    PrologEx.Flags.set("jit", {:atom, "true"})
    {jit, _} = PrologEx.Consult.load(%{}, terms)
    PrologEx.Flags.set("jit", {:atom, "false"})
    {int, _} = PrologEx.Consult.load(%{}, terms)
    PrologEx.Flags.set("jit", {:atom, "true"})
    {:ok, reader: r, jit: jit, int: int}
  end

  # übersetzt gleich beim ersten Aufruf (sonst rechnete bis zur Schwelle der
  # Interpreter, und die Tests sähen den übersetzten Code oft gar nicht)
  setup do
    PrologEx.Flags.set("jit_threshold", 1)
    :ok
  end

  test "übersetzt wird, was passt; sonst nicht", c do
    jitted = &jitted?(c.jit, &1)

    for k <- [{"user", "fib", 2}, {"user", "lp", 1}, {"user", "gcd", 3}, {"user", "ack", 3}],
        do: assert(jitted.(k), inspect(k))

    for k <- [{"user", "col", 2}, {"user", "ab", 2}, {"user", "d", 2}, {"user", "p2", 2}],
        do: assert(jitted.(k), inspect(k))

    for k <- ~w(sum fibi sg fl dv nt w z cr),
        do: assert(jitted.({"user", k, 2}), k)

    for k <- [
          {"user", "mx", 3},
          {"user", "hyp", 3},
          {"user", "it", 1},
          {"user", "nf", 1},
          {"user", "cb", 2}
        ],
        do: assert(jitted.(k), inspect(k))

    # Aufrufe anderer übersetzter Prädikate (auch wechselseitig)
    for k <-
          [{"user", "ev", 1}, {"user", "od", 1}] ++
            for(n <- ~w(sq twice sumsq half hsum dsq), do: {"user", n, 2}),
        do: assert(jitted.(k), inspect(k))

    # Listen
    for k <-
          [{"user", "app", 3}, {"user", "rev", 3}, {"user", "rng", 3}, {"user", "nth", 3}] ++
            for(n <- ~w(nrev len suml reverse2 maxl dbl last2 avg first2), do: {"user", n, 2}),
        do: assert(jitted.(k), inspect(k))

    # app/3: erste Liste aufgelöst, zweite durchgereicht; Summe: Zahlen
    # (Floats auch: avg/2 ruft suml/2 und rechnet mit /), dbl/2: Ganzzahlen
    assert {:pred, _, _, {:jit, _, [{0, :list}, {1, :any}], [2], _, _}, _} =
             c.jit[{"user", "app", 3}]

    assert {:pred, _, _, {:jit, _, [{0, :nlist}], [1], _, _}, _} = c.jit[{"user", "suml", 2}]
    assert {:pred, _, _, {:jit, _, [{0, :ilist}], [1], _, _}, _} = c.jit[{"user", "dbl", 2}]

    # Typtests
    for k <-
          [{"user", "fact_", 3}, {"user", "eqn", 3}, {"user", "eqt", 3}] ++
            for(n <- ~w(fact kl tw vv il avar aeq cnt nz), do: {"user", n, 2}),
        do: assert(jitted.(k), inspect(k))

    # ein Gerufener nicht übersetzbar (cnj) oder dynamisch (udsq): nein
    refute jitted.({"user", "cnj", 2})
    refute jitted.({"user", "udsq", 2})
    # half rechnet mit /: auch hsum nimmt Floats
    assert {:pred, _, _, {:jit, _, [{0, :num}], _, _, _}, _} = c.jit[{"user", "hsum", 2}]

    # Atome und Strukturen: Peano, Paare, Konstanten, deriv
    for k <-
          [{"user", "padd", 3}, {"user", "pmul", 3}, {"user", "psum", 3}, {"user", "csum", 3}] ++
            [{"user", "dd", 3}, {"user", "same", 3}] ++
            for(n <- ~w(pnat pval pkeys pmk colr), do: {"user", n, 2}),
        do: assert(jitted.(k), inspect(k))

    # inf/2 ruft call/1 und statistics/2: nein
    refute jitted.({"user", "inf", 2})
    # Z nur in einem Zweig bestimmt: nein
    refute jitted.({"user", "pz", 2})
    # vor X > 0 kann 1 // X werfen (der Interpreter würde die Klausel nach
    # wd(0, Y) beim Zurücksetzen versuchen): nichtdeterministisch
    assert jitted.({"user", "wd", 2})
    # mit Flag jit = false nichts
    refute jitted?(c.int, {"user", "fib", 2})
  end

  test "Terme zerlegen und vergleichen: übersetzt", c do
    for {n, a} <- [
          {"targ", 3},
          {"tfun", 3},
          {"tsz", 2},
          {"tsz_", 4},
          {"tuniv", 2},
          {"tname", 2},
          {"tcmp", 3},
          {"tcmpo", 2},
          {"tmax", 3},
          {"tle", 3},
          {"tge", 3},
          {"tlt", 3},
          {"tco", 2},
          {"tgo", 2},
          {"tins", 3},
          {"od1", 2},
          {"od2", 2},
          {"od3", 2},
          {"od6", 2},
          {"od7", 2},
          {"tins_", 5},
          {"nrv", 2},
          {"tap", 3},
          {"tapc", 2},
          {"mem", 2},
          {"btw", 3},
          {"pk", 2},
          {"nde", 2},
          {"ndl", 2},
          {"wrap", 2},
          {"ones", 2},
          {"sq3", 2},
          {"ndf", 2},
          {"memc", 2},
          {"incl", 3},
          {"notin", 2},
          {"cntin", 3},
          {"pairin", 3},
          {"bcount", 4},
          {"gsum", 4}
        ],
        do: assert(jitted?(c.jit, {"user", n, a}), "#{n}/#{a}")

    # select/3: der rekursive Aufruf baut [H|R] auf jeder Stufe – jede
    # Lösung aus Tiefe k liefe durch k Hüllen: nicht übersetzt (auch in
    # keinem schwächeren Modus)
    refute jitted?(c.jit, {"user", "sel", 3})

    # btw/3 vor einem Vergleich, erst danach der Schnitt: der Vergleich
    # setzt in btw/3 zurück – keine bloße erste Lösung, nicht übersetzt
    refute jitted?(c.jit, {"user", "sqin", 2})

    # Schnitt in einem Zweig: dort schneidet er die Klausel ab – bleibt
    # eine Disjunktion, nicht übersetzt
    refute jitted?(c.jit, {"user", "od4", 2})
  end

  for q <- [
        # arg/3, functor/3, =../2 zum Zerlegen; Fehler und alles andere
        # wie der Interpreter (dort: aufgeben)
        "targ(f(a,b,c), 2, A)",
        "targ(f(a), 0, A)",
        "targ(f(a), 3, A)",
        "targ([x|y], 1, A)",
        "targ(f(X, Y), 2, A), A == Y",
        "catch(targ(f(a), -1, A), error(E, _), true)",
        "catch(targ(a, 1, A), error(E, _), true)",
        "catch(targ(_, 1, A), error(E, _), true)",
        "catch(targ(f(a), x, A), error(E, _), true)",
        "catch(targ(f(a), _, A), error(E, _), true)",
        "targ(f(a, b), 1, b)",
        "targ(f(a, b), 1, a)",
        "tfun(f(a,b), F, N)",
        "tfun(abc, F, N)",
        "tfun(3.5, F, N)",
        "tfun([a], F, N)",
        "tfun(T, foo, 2)",
        "tfun(f(a), f, 1)",
        "tfun(f(a), g, N)",
        "catch(tfun(_, F, N), error(E, _), true)",
        "tsz(f(g(a,b),h(c),d), S)",
        "tsz(a, S)",
        "inf(tsz(f(g(a,b),h(c),d), _), I)",
        "tuniv(f(a,B), L)",
        "tuniv(a, L)",
        "tuniv([1,2], L)",
        "tuniv(T, [g, 1])",
        "tname(foo(1,2), F)",
        "catch(tuniv(_, L), error(E, _), true)",
        # compare/3, @<, @>, @=<, @>=
        "tcmp(1, 2, O)",
        "tcmp(b, a, O)",
        "tcmp(f(X), f(Y), O)",
        "tcmp(1, 1.0, O)",
        "tcmp(1.0, 1, O)",
        "tcmp(X, X, O)",
        "tcmp(1, 2, <)",
        "tcmp(1, 2, >)",
        "catch(tcmp(1, 2, foo), error(E, _), true)",
        "tcmpo(O, O)",
        "tmax(f(b), f(a), M)",
        "tmax(1, a, M)",
        "tle(1, 1.0, R)",
        "tle(g(1), f(1, 2), R)",
        "tge(b, a, R)",
        "tge(a, a, R)",
        "tge(a, b, R)",
        "tlt(a, b, R)",
        "tlt(b, a, R)",
        "tlt(1.0, 1, R)",
        # eine Ausgabevariable des Aufrufs im Vergleich: der Interpreter
        # hat sie im Kopf schon gebunden (Z = s(O)) – aufgeben
        "tco(Z, Z)",
        "tgo(Z, Z)",
        "tins(3, [1,2,4,5], L)",
        "tins(2, [1,2,3], L)",
        "tins(z, [a,b], L)",
        "inf(tins(9, [1,2,3,4,5,6,7,8], _), I)",
        # lists:append/3 mit bestimmter erster Liste; offenes Ende oder
        # keine Liste: aufgeben (der Interpreter zählt auf)
        "nrv([1,2,3,4,5], R)",
        "nrv([], R)",
        "nrv([a,X,f(Y)], R)",
        "inf(nrv([1,2,3,4,5,6,7,8], _), I)",
        "tap([1,2], [3], Z)",
        "tap([1,2], T, Z)",
        "tap([], T, Z)",
        "tap([1,2], [3], [1,2,3])",
        "tap([1,2], [3], [1,2])",
        "tap([1,2], [3], [A|B])",
        "tap(\"ab\", \"cd\", Z)",
        "once(tap([1|X], [2], Z))",
        "call_nth(tap([1|X], [2], Z), 3)",
        "findall(X-Y, tap(X, Y, [1,2]), L)",
        "tap(a, [1], Z)",
        "tapc([a,b], Z)",
        "tapc(X, [a,b,c])",
        "findall(X, tapc(X, [a,c,b,c]), L)",
        # (A ; B), ! wie (A -> true ; B -> true), !
        "od1(15, Y)",
        "od1(7, Y)",
        "od1(1, Y)",
        "od1(7, small)",
        "catch(od1(a, Y), error(E, _), true)",
        "inf(od1(1, _), I)",
        "od2(-5, Y)",
        "od2(50, Y)",
        "od2(200, Y)",
        "findall(Y, od2(50, Y), L)",
        "findall(Y, od2(-1, Y), L)",
        "inf(od2(50, _), I)",
        "od3(5, Y)",
        "od3(-1, Y)",
        "od4(3, Y)",
        "od4(9, Y)",
        "od4(-1, Y)",
        "od6(a, Y)",
        "od6(c, Y)",
        "findall(Y, od6(b, Y), L)",
        "od7(9, Y)",
        "od7(1, Y)",
        "inf(od7(1, _), I)",
        # Peano: Strukturen zerlegen und bauen, auch anders herum
        "pnat(5, A), pnat(7, B), padd(A, B, C), pval(C, N)",
        "pnat(6, A), pnat(4, B), pmul(A, B, C), pval(C, N)",
        "padd(X, Y, s(s(0)))",
        "once(padd(s(_), 0, R))",
        "padd(s(0), s(0), s(s(0)))",
        "padd(s(0), s(0), s(0))",
        "padd(s(0), a, R)",
        "padd(f(0), 0, R)",
        "padd(s(0, 1), 0, R)",
        "inf(padd(s(s(s(0))), 0, _), I)",
        "inf(pmul(s(s(s(0))), s(s(0)), _), I)",
        # Paare in Listen
        "pmk([1,2,3], P), pkeys(P, K), psum(P, 0, S)",
        "pkeys([a-1, b-2], K)",
        "pkeys([a-1, b], K)",
        "once(pkeys([a-1|_], K))",
        "catch(psum([a-1, b-x], 0, S), error(E, _), true)",
        "psum([a-1, b-2.5], 0, S)",
        # Atome als Konstanten
        "csum([red, green, blue], 0, S)",
        "csum([red, pink], 0, S)",
        "colr(C, 2)",
        "colr(green, V)",
        # Gleichheit im Kopf wie die Unifikation (identisch, verschieden,
        # nur durch Binden gleich)
        "dd(x*x+3*x, x, D)",
        "dd(y*x, x, D)",
        "inf(dd(x*x+3*x, x, _), I)",
        "same(f(X), f(X), R)",
        "same(f(1), f(2), R)",
        "same(A, B, R)",
        "same(f(A), f(b), R)",
        "same(a, a, R)",
        "fib(21, F)",
        "fib(0, F)",
        "fib(-3, F)",
        "fib(10, 55)",
        "fib(10, 54)",
        "fib(X, 55)",
        "fib(a, F)",
        "fib(10, F), F > 50",
        "lp(10000)",
        "call_with_inference_limit(lp(-1), 1000, R)",
        "gcd(1071, 462, G)",
        "gcd(5, 0, G)",
        "ack(2, 3, R)",
        "col(27, S)",
        "ab(-5, Y), ab(7, Z)",
        "catch(d(0, Y), error(E, _), true)",
        "d(3, Y)",
        "p2(200, R)",
        "inf(fib(15, _), I)",
        "inf(lp(1000), I)",
        "inf(col(27, _), I)",
        "\\+ fib(10, 54)",
        "call_with_inference_limit(fib(15, _), 3000, R)",
        "call_with_inference_limit(fib(15, _), 2963, R)",
        "call_with_inference_limit(fib(15, _), 2962, R)",
        "call_with_inference_limit(lp(5000), 10000, R)",
        "call_with_inference_limit(lp(5000), 10001, R)",
        "call_with_inference_limit((fib(12, _), fib(12, _)), 1500, R)",
        "catch(call_with_time_limit(0.05, lp(100000000)), E, true)",
        "call_with_depth_limit(fib(10, F), 100, R)",
        "freeze(F, true), fib(10, F)",
        "findall(F, (member(N, [5, 6, 7]), fib(N, F)), L)",
        "sum(100, S)",
        "sum(0, S)",
        "sum(3.0, S)",
        "inf(sum(50, _), I)",
        "fibi(20, F)",
        "inf(fibi(12, _), I)",
        "call_with_inference_limit(fibi(12, _), 500, R)",
        "call_with_inference_limit(fibi(12, _), 2000, R)",
        "mx(3, 5, Z)",
        "mx(5, 3, Z)",
        "mx(5.0, 5, Z)",
        "findall(S, (member(X, [-3, 0, 7]), sg(X, S)), L)",
        "inf(sg(0, _), I)",
        "fl(10, X)",
        "fl(3, 3.375)",
        "fl(3, 3.4)",
        "fl(2.5, X)",
        "inf(fl(20, _), I)",
        "hyp(3, 4, C)",
        "hyp(3.0, 4, C)",
        "catch(hyp(1.0e200, 1.0e200, C), error(E, _), true)",
        "dv(7, Y)",
        "dv(8, Y)",
        "dv(7.0, Y)",
        "nt(5, Y)",
        "nt(50, Y)",
        "inf(nt(5, _), I)",
        "w(0, Y)",
        "w(5, Y)",
        "w(-1, Y)",
        "w(0.0, Y)",
        "z(0, Y)",
        "z(3, Y)",
        "it(1)",
        "it(-1)",
        "inf(\\+ it(-1), I)",
        "nf(3)",
        "nf(9)",
        "inf(nf(3), I)",
        "inf(\\+ nf(9), I)",
        "cb(1, Y)",
        "cb(-1, Y)",
        "cr(3, Y)",
        "cr(7, Y)",
        "cr(-1, Y)",
        "pz(1, Y)",
        "ev(10)",
        "ev(7)",
        "od(7)",
        "inf(ev(100), I)",
        "call_with_inference_limit(ev(1000), 500, R)",
        "twice(7, Y)",
        "twice(1.5, Y)",
        "sumsq(100, S)",
        "inf(sumsq(30, _), I)",
        "hsum(10, S)",
        "hsum(9, S)",
        "hsum(9.0, S)",
        "cnj(3, Y)",
        "catch(cnj(a, Y), error(E, _), true)",
        "udsq(4, Y)",
        "sumsq(20000, S)",
        "app([1,2,3], [4,5], L)",
        "app([a,f(X),Y], [b], L)",
        "app([1,2], X, L), X = [3]",
        "app([], foo, L)",
        "app([1], foo, L)",
        "once(app([1|T], [2], L))",
        "findall(X-Y, app(X, Y, [1,2]), Ls)",
        "app([1,2], [3], [1,2,3])",
        "app(foo, [1], L)",
        "freeze(R, true), app([1], [2], R)",
        "nrev([1,2,3,4,5,6,7,8,9,10], R)",
        "nrev([a,B,c], R)",
        "nrev([], R)",
        "inf(nrev([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30], _), I)",
        "call_with_inference_limit(nrev([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30], _), 400, R)",
        "numlist(1, 300, L), nrev(L, R), len(R, N), suml(R, S)",
        "len([a,b,c], N)",
        "len([], N)",
        "once(len(L, 0))",
        "len(\"abc\", N)",
        "suml([1,2,3], S)",
        "suml([1,2,3.5], S)",
        "catch(suml([1,a], S), error(E, _), true)",
        "catch(suml([1,X], S), error(E, _), true)",
        "rev([1,2,3], [], R)",
        "rev([1,2,3], T, R)",
        "reverse2([a,b,c], R)",
        "maxl([3,1,4,1,5,9,2,6], M)",
        "maxl([], M)",
        "maxl([2,X], M)",
        "dbl([1,2,3], L)",
        "dbl([1,2.5], L)",
        "rng(1, 5, L)",
        "rng(5, 1, L)",
        "last2([1,2,3], X)",
        "last2([], X)",
        "avg([1,2,3,4], A)",
        "avg([], A)",
        "numlist(1, 50000, L), len(L, N)",
        # Listen werden erst beim Zerlegen gelesen: ein offener Rest hinter
        # der gelesenen Stelle stört nicht; davor gibt der Code auf und der
        # Interpreter fängt neu an (gleiche Inferenzen)
        "first2([1|_], X)",
        "nth(1, [a,b|_], X)",
        "nth(3, [a,b|_], X)",
        "once(app([1,2|T], [3], L))",
        "inf(once(app([1,2|T], [3], L)), I)",
        "X = 2, suml([1,X,3], S)",
        "inf(catch(suml([1,2,a], _), _, true), I)",
        "call_with_inference_limit(suml([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,a], _), 30, R)",
        # Typtests (auch als Wächter), ==, \\==
        "fact(20, F)",
        "fact(-1, F)",
        "fact(a, F)",
        "fact(2.0, F)",
        "fact(X, F)",
        "inf(fact(20, _), I)",
        "inf(fact(X, _), I)",
        "inf(findall(Y, kl(2.5, Y), _), I)",
        "inf(findall(Y, kl(a, Y), _), I)",
        "inf(findall(Y, kl(_, Y), _), I)",
        "inf(vv(_, _), I)",
        "inf(vv(3, _), I)",
        "inf(findall(Y, tw(1.5, Y), _), I)",
        "findall(Y, kl(3, Y), L)",
        "findall(Y, kl(2.5, Y), L)",
        "findall(Y, kl(a, Y), L)",
        "findall(Y, kl(_, Y), L)",
        "X = 5, kl(X, Y)",
        "findall(Y, tw(3, Y), L)",
        "findall(Y, tw(1.5, Y), L)",
        "findall(Y, tw(a, Y), L)",
        "vv(X, Y)",
        "vv(3, Y)",
        "vv(a, Y)",
        "vv(f(Z), Y)",
        "eqn(1, 1, Z)",
        "eqn(1, 1.0, Z)",
        "eqn(a, a, Z)",
        "eqn(f(X), f(X), Z)",
        "eqn(f(X), f(Y), Z)",
        "eqn(X, Y, Z)",
        "eqn(X, X, Z)",
        "eqn([1,2], [1,2], Z)",
        "eqt(1, 1, Z)",
        "eqt(f(X), f(Y), Z)",
        "il([a,b], N)",
        "il(foo, N)",
        "il([a|T], N)",
        "il(X, N)",
        "cnt([1, a, 2, f(x), 3.0, X], N)",
        "inf(cnt([1, a, 2], _), I)",
        "nz(4, Y)",
        "nz(0, Y)",
        "nz(a, Y)",
        "nz(2.0, Y)",
        "nz(f(x), Y)",
        # Bindungsreihenfolge: der Interpreter bindet Y (= X) vor dem Test,
        # der übersetzte Code erst am Ende – er gibt auf, der Interpreter
        # rechnet neu
        "avar(A, A)",
        "avar(A, B)",
        "aeq(A, A)",
        "aeq(A, B)",
        "aeq(1, B)",
        # Ausgabe zugleich (in) Eingabe: gebunden wird durch Unifikation
        "al(A, B, A)",
        "al(A, B, C)",
        "\\+ \\+ app([1], X, X)",
        "app([X], [], X), X = [Y|_], Y == X",
        "set_prolog_flag(occurs_check, true), \\+ app([1], X, X)",
        "set_prolog_flag(occurs_check, error), catch(app([1], X, X), error(E, _), true)",
        "findall(Y, wd(0, Y), L)",
        # nichtdeterministisch übersetzt: dieselben Lösungen, Inferenzen,
        # Fehler, Schnitte, Grenzen
        "findall(X, mem(X, [a,b,c]), L)",
        "mem(X, [a,b,c])",
        "mem(X, [])",
        "findall(X, (mem(X, [1,2,3,4]), X > 2), L)",
        "mem(X, [1,2,3]), X > 1, !",
        "once(mem(X, [f(Y), g(Z)]))",
        "call_nth(mem(X, [a,b,c,d]), 3)",
        "findall(X, mem(X, [A, B, A]), L)",
        "inf(findall(X, mem(X, [a,b,c,d,e]), _), I)",
        "findall(X, btw(1, 6, X), L)",
        "btw(3, 1, X)",
        "inf(findall(X, btw(1, 20, X), _), I)",
        "findall(X, (btw(1, 30, X), X mod 7 =:= 0), L)",
        "catch(btw(a, 3, X), error(E, _), true)",
        "findall(X-R, sel(X, [1,2,3], R), L)",
        "findall(X-R, sel(X, [], R), L)",
        "inf(findall(X-R, sel(X, [1,2,3,4], R), _), I)",
        "findall(Y, pk(5, Y), L)",
        "findall(Y, pk(1, Y), L)",
        "catch(findall(Y, nde(0, Y), L), error(E, _), true)",
        "findall(Y, nde(2, Y), L)",
        "findall(Y, ndl([a|T], Y), L)",
        "findall(Y, ndl([a,b,c], Y), L)",
        "findall(Y, wrap([1,2], Y), L)",
        "findall(K, ones([1,2,1], K), L)",
        "findall(Y, sq3(2, Y), L)",
        "findall(Y, ndf(1, Y), L)",
        "findall(Y, ndf(0, Y), L)",
        "findall(Y, ndf(-1, Y), L)",
        "call_with_inference_limit(findall(X, btw(1, 1000, X), _), 500, R)",
        "call_with_inference_limit(mem(X, [a,b]), 100, R)",
        "mem(X, [1,2]), X > 5",
        # erste Lösung eines nichtdeterministischen aus deterministischem Code
        "memc(X, [a,b,c])",
        "memc(X, [])",
        "memc(b, [a,b,c])",
        "memc(z, [a,b,c])",
        "incl(b, [a,b,c], R)",
        "incl(z, [a,b,c], R)",
        "incl(X, [a,b], R)",
        "notin(z, [a,b])",
        "notin(a, [a,b])",
        "firstbig([1,20,5,30], X)",
        "firstbig([1,2], X)",
        "cntin([1,2,3,4,5], [2,4,6], N)",
        "inf(cntin([1,2,3,4,5], [2,4,6], _), I)",
        "sqin(20, 49)",
        "sqin(20, 50)",
        "inf(sqin(20, 196), I)",
        "pairin(b, [a-1, b-2, b-3], V)",
        "pairin(c, [a-1, b-2], V)",
        "pairin(b, [a-1, B-2], V)",
        "catch(incl(1, [a|_], R), error(E, _), true)",
        "bcount(1000, 20, 0, C)",
        "N is 7^300, bcount(N, 900, 0, C), D is popcount(N), C == D",
        "N is -(7^300), bcount(N, 900, 0, C)",
        "inf(bcount(1000, 20, 0, _), I)",
        "gsum(1000, 20, 0, S)",
        "N is 2^200 + 5, gsum(N, 210, 0, S)",
        "catch(bcount(a, 3, 0, C), error(E, _), true)",
        "catch(gsum(1, 0, 0.5, S), error(E, _), true)"
      ] do
    test q, c do
      Reader.put_current(c.reader)
      a = TableCase.run(c.reader, c.jit, unquote(q))
      b = TableCase.run(c.reader, c.int, unquote(q))
      assert a == b
    end
  end

  # Ein Gerufener wird neu geladen: wer ihn direkt rief, verliert seinen
  # Code und ruft die neue Fassung (über den Interpreter)
  test "Gerufener neu geladen", c do
    Reader.put_current(c.reader)

    {db, _} =
      PrologEx.Consult.load(c.jit, Reader.read_terms(c.reader, "sq(X, Y) :- Y is X * X * X."))

    assert {_, {:answers, ["Y = 54"]}} = TableCase.run(c.reader, db, "twice(3, Y)")
    assert {_, {:answers, ["S = 100"]}} = TableCase.run(c.reader, db, "sumsq(4, S)")
    refute jitted?(db, {"user", "twice", 2})
    refute jitted?(db, {"user", "sumsq", 2})
    assert jitted?(db, {"user", "sq", 2})
    # unberührt
    assert jitted?(db, {"user", "ev", 1})
  end

  # Später eine eigene Definition von append/3: wer lists:append/3 im
  # übersetzten Code rief, verliert ihn und ruft die eigene
  test "append/3 später selbst definiert", c do
    Reader.put_current(c.reader)
    assert jitted?(c.jit, {"user", "nrv", 2})
    src = "append(_, _, mine)."
    {db, _} = PrologEx.Consult.load(c.jit, Reader.read_terms(c.reader, src))
    refute jitted?(db, {"user", "nrv", 2})
    assert {_, {:answers, ["R = mine"]}} = TableCase.run(c.reader, db, "nrv([1,2], R)")
  end

  # Ein späterer Ladeschritt ruft schon übersetzte Prädikate direkt
  test "Aufruf über Ladeschritte hinweg", c do
    Reader.put_current(c.reader)
    src = "quad(X, Y) :- sq(X, A), sq(A, Y).\nhq(X, Y) :- half(X, A), sq(A, Y)."
    {db, _} = PrologEx.Consult.load(c.jit, Reader.read_terms(c.reader, src))
    assert jitted?(db, {"user", "quad", 2})
    assert {_, {:answers, ["Y = 81"]}} = TableCase.run(c.reader, db, "quad(3, Y)")
    # hq ist nicht ganzzahlig, sq schon übersetzt und ganzzahlig: nein
    refute jitted?(db, {"user", "hq", 2})
    assert {_, {:answers, ["Y = 2.25"]}} = TableCase.run(c.reader, db, "hq(3, Y)")
  end

  # Einzige Abweichung: setzt der Interpreter in Aufrufe zurück, die
  # übersetzt deterministisch sind, versucht er dort noch Klauseln, die
  # nichts mehr finden (fib(1, F) und die dritte Klausel), und zählt diese
  # Versuche; das übersetzte Stück hinterlässt keine solchen Choice Points
  test "Inferenzen beim Zurücksetzen: weniger, gleiche Antwort", c do
    Reader.put_current(c.reader)
    q = "inf(\\+ fib(10, 54), I)"
    {_, {:answers, [a]}} = TableCase.run(c.reader, c.jit, q)
    {_, {:answers, [b]}} = TableCase.run(c.reader, c.int, q)
    [_, ia] = Regex.run(~r/I = (\d+)/, a)
    [_, ib] = Regex.run(~r/I = (\d+)/, b)
    assert String.to_integer(ia) < String.to_integer(ib)
  end

  # und das Prädikat ist nachweislich deterministisch: kein Choice Point
  # (der Interpreter lässt bei fib(1, F) die dritte Klausel offen)
  test "deterministisch: ! statt true", c do
    Reader.put_current(c.reader)
    q = "call_with_inference_limit(fib(15, _), 10000, R)"
    assert {_, {:answers, ["R = !"]}} = TableCase.run(c.reader, c.jit, q)
    assert {_, {:answers, ["R = true"]}} = TableCase.run(c.reader, c.int, q)
  end

  # Typtests als Wächter: integer/float schließen sich aus, ohne Schnitt
  # (im Interpreter dank des Index ebenso)
  test "deterministisch über Typtests", c do
    Reader.put_current(c.reader)
    q = "call_with_inference_limit(tw(3, _), 100, R)"
    assert {_, {:answers, ["R = !"]}} = TableCase.run(c.reader, c.jit, q)
  end

  test "jit_listing", c do
    Reader.put_current(c.reader)
    {out, _} = TableCase.run(c.reader, c.jit, "fib(5, _), jit_listing")
    assert out =~ ~r"% fib/2 +übersetzt +fib\(\+int, -int\)"
    assert out =~ ~r"% app/3 +\S+ +app\(\+list, \+any, -\)"
    assert out =~ ~r"% first2/2 +nur für Rufer +first2\(\+list, -any\)"
    assert out =~ ~r"% pz/2 +nein +Klausel 1: Z ist nur in einem Zweig"
    assert out =~ ~r"% cnj/2 +nein +ruft nj/2, das nicht übersetzt wird"
    assert out =~ ~r"% nj/2 +nein +Klausel 1: Ziel atom_length/2"
    assert out =~ ~r"% wd/2 +\S+ +wd\(\+int, -int\)  nichtdeterministisch"
    assert out =~ ~r"% mem/2 +\S+ +mem\(-any, \+list\)  nichtdeterministisch"
    assert out =~ ~r"% udsq/2 +nein +Klausel 1: ruft das dynamische dsq/2"
    {out, _} = TableCase.run(c.reader, c.int, "jit_listing(fib/2)")
    assert out =~ ~r"% fib/2 +wäre übersetzbar"
    refute out =~ "app/3"
  end

  # das Flag wirkt auch beim Aufruf: übersetzt geladen, aber abgeschaltet
  # rechnet der Interpreter (Choice Point offen: true statt !)
  test "Flag jit beim Aufruf", c do
    Reader.put_current(c.reader)
    q = "set_prolog_flag(jit, false), call_with_inference_limit(fib(15, _), 10000, R)"
    assert {_, {:answers, ["R = true"]}} = TableCase.run(c.reader, c.jit, q)
    q = "set_prolog_flag(jit, true), call_with_inference_limit(fib(15, _), 10000, R)"
    assert {_, {:answers, ["R = !"]}} = TableCase.run(c.reader, c.jit, q)
  end

  # erst ab dem n-ten Aufruf übersetzt; vorher der Interpreter (gleiche
  # Antworten). Eigenes Prädikat: Module gelten für alle Tests
  test "Schwelle jit_threshold", c do
    Reader.put_current(c.reader)
    PrologEx.Flags.set("jit", {:atom, "true"})
    prog = "schw_#{System.unique_integer([:positive])}"
    src = "#{prog}(N, M) :- M is N * 7 + #{System.unique_integer([:positive])}."
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    {:pred, _, _, {:jit, {mod, _, _, _, _}, _, _, _, _}, _} = db[{"user", prog, 2}]
    PrologEx.Flags.set("jit_threshold", 5)

    for i <- 1..4 do
      assert {_, {:answers, [_]}} = TableCase.run(c.reader, db, "#{prog}(#{i}, _)")
    end

    refute :erlang.module_loaded(mod)
    assert {_, {:answers, [_]}} = TableCase.run(c.reader, db, "#{prog}(5, _)")
    assert :erlang.module_loaded(mod)
    assert_raise PrologEx.Error, fn -> PrologEx.Flags.set("jit_threshold", 0) end
  end

  # Gibt der übersetzte Code immer wieder auf (hier: die Eingabe enthält
  # Variablen, die er binden müsste), nimmt der Interpreter die Aufrufe
  # bald direkt (jit_cold?/1) – mit denselben Antworten
  test "kalt: oft aufgegeben, dann der Interpreter", c do
    Reader.put_current(c.reader)
    PrologEx.Flags.set("jit", {:atom, "true"})
    u = System.unique_integer([:positive])

    src = """
    :- use_module(library(between)).
    nb#{u}(t(L, N1, R), N0, N) :- nb#{u}(L, N0, N1), N2 is N1 + 1, nb#{u}(R, N2, N).
    nb#{u}(v, N, N).
    mk#{u}(0, v) :- !.
    mk#{u}(D, t(L, _, R)) :- D1 is D - 1, mk#{u}(D1, L), mk#{u}(D1, R).
    """

    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    {:pred, _, _, {:jit, _, _, _, _, stats}, _} = db[{"user", "nb#{u}", 3}]
    q = "\\+ (between(1, 200, _), mk#{u}(5, T), \\+ (nb#{u}(T, 1, N), N == 32))"
    assert {_, {:answers, ["true"]}} = TableCase.run(c.reader, db, q)
    assert :atomics.get(stats, 2) >= 64
    assert :atomics.get(stats, 3) > 0
  end

  test "schneller (grob)", c do
    Reader.put_current(c.reader)
    # einmal vorweg: übersetzt wird beim ersten Aufruf, das soll nicht in
    # die Messung (allein gestartet lief der Test sonst gegen den Compiler)
    TableCase.run(c.reader, c.jit, "fib(20, _)")
    {tj, _} = :timer.tc(fn -> TableCase.run(c.reader, c.jit, "fib(20, _)") end)
    {ti, _} = :timer.tc(fn -> TableCase.run(c.reader, c.int, "fib(20, _)") end)
    assert tj * 10 < ti, "jit #{tj} µs, interpretiert #{ti} µs"
  end
end
