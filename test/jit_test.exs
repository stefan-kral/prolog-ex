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
  inf(G, I) :- statistics(inferences, I0), call(G), statistics(inferences, I1), I is I1 - I0.
  """

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
    jitted = fn key -> match?({:pred, _, _, {:jit, _, _, _, _}, _}, c.jit[key]) end

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

    # inf/2 ruft call/1 und statistics/2: nein
    refute jitted.({"user", "inf", 2})
    # Z nur in einem Zweig bestimmt: nein
    refute jitted.({"user", "pz", 2})
    # vor X > 0 kann 1 // X werfen (der Interpreter würde die Klausel nach
    # wd(0, Y) beim Zurücksetzen versuchen): nein
    refute jitted.({"user", "wd", 2})
    # mit Flag jit = false nichts
    refute match?({:pred, _, _, {:jit, _, _, _, _}, _}, c.int[{"user", "fib", 2}])
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
        "findall(Y, wd(0, Y), L)"
      ] do
    test q, c do
      Reader.put_current(c.reader)
      a = TableCase.run(c.reader, c.jit, unquote(q))
      b = TableCase.run(c.reader, c.int, unquote(q))
      assert a == b
    end
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

  test "schneller (grob)", c do
    Reader.put_current(c.reader)
    {tj, _} = :timer.tc(fn -> TableCase.run(c.reader, c.jit, "fib(20, _)") end)
    {ti, _} = :timer.tc(fn -> TableCase.run(c.reader, c.int, "fib(20, _)") end)
    assert tj * 10 < ti, "jit #{tj} µs, interpretiert #{ti} µs"
  end
end
