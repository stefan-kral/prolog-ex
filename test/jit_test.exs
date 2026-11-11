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
  nth(0, [X|_], X) :- !.
  nth(N, [_|T], X) :- N > 0, N1 is N - 1, nth(N1, T, X).
  inf(G, I) :- statistics(inferences, I0), call(G), statistics(inferences, I1), I is I1 - I0.
  """

  # übersetzt: der Eintritt lohnt ({:jit, ...} im Prädikat) oder nur für
  # übersetzte Rufer ({:jit_info, ...})
  defp jitted?(db, {m, n, a} = k),
    do:
      match?({:pred, _, _, {:jit, _, _, _, _}, _}, db[k]) or
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
    assert {:pred, _, _, {:jit, _, [{0, :list}, {1, :any}], [2], _}, _} =
             c.jit[{"user", "app", 3}]

    assert {:pred, _, _, {:jit, _, [{0, :nlist}], [1], _}, _} = c.jit[{"user", "suml", 2}]
    assert {:pred, _, _, {:jit, _, [{0, :ilist}], [1], _}, _} = c.jit[{"user", "dbl", 2}]

    # ein Gerufener nicht übersetzbar (cnj) oder dynamisch (udsq): nein
    refute jitted.({"user", "cnj", 2})
    refute jitted.({"user", "udsq", 2})
    # half rechnet mit /: auch hsum nimmt Floats
    assert {:pred, _, _, {:jit, _, [{0, :num}], _, _}, _} = c.jit[{"user", "hsum", 2}]

    # inf/2 ruft call/1 und statistics/2: nein
    refute jitted.({"user", "inf", 2})
    # Z nur in einem Zweig bestimmt: nein
    refute jitted.({"user", "pz", 2})
    # vor X > 0 kann 1 // X werfen (der Interpreter würde die Klausel nach
    # wd(0, Y) beim Zurücksetzen versuchen): nein
    refute jitted.({"user", "wd", 2})
    # mit Flag jit = false nichts
    refute jitted?(c.int, {"user", "fib", 2})
  end

  for q <- [
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
        # Ausgabe zugleich (in) Eingabe: gebunden wird durch Unifikation
        "al(A, B, A)",
        "al(A, B, C)",
        "\\+ \\+ app([1], X, X)",
        "app([X], [], X), X = [Y|_], Y == X",
        "set_prolog_flag(occurs_check, true), \\+ app([1], X, X)",
        "set_prolog_flag(occurs_check, error), catch(app([1], X, X), error(E, _), true)",
        "findall(Y, wd(0, Y), L)"
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

  test "jit_listing", c do
    Reader.put_current(c.reader)
    {out, _} = TableCase.run(c.reader, c.jit, "fib(5, _), jit_listing")
    assert out =~ ~r"% fib/2 +übersetzt +fib\(\+int, -int\)"
    assert out =~ ~r"% app/3 +\S+ +app\(\+list, \+any, -\)"
    assert out =~ ~r"% first2/2 +nur für Rufer +first2\(\+list, -any\)"
    assert out =~ ~r"% pz/2 +nein +Klausel 1: Z ist nur in einem Zweig"
    assert out =~ ~r"% cnj/2 +nein +ruft nj/2, das nicht übersetzt wird"
    assert out =~ ~r"% nj/2 +nein +Klausel 1: Ziel atom_length/2"
    assert out =~ ~r"% wd/2 +nein +Klauseln 1 und 2 schließen sich nicht nachweislich aus"
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

  test "schneller (grob)", c do
    Reader.put_current(c.reader)
    {tj, _} = :timer.tc(fn -> TableCase.run(c.reader, c.jit, "fib(20, _)") end)
    {ti, _} = :timer.tc(fn -> TableCase.run(c.reader, c.int, "fib(20, _)") end)
    assert tj * 10 < ti, "jit #{tj} µs, interpretiert #{ti} µs"
  end
end
