defmodule PrologEx.RationalTest do
  # Rationale Zahlen (PrologEx.Rational): Lesen und Schreiben, Arithmetik,
  # Typen, Standardordnung und das Durchreichen durch das übrige System
  use ExUnit.Case, async: true
  alias PrologEx.{Rational, Reader, TableCase}

  @rows [
    # --- Lesen und Schreiben ---
    {"X = 1r3", ["X = 1r3"]},
    {"X = -1r3", ["X = -1r3"]},
    {"X = - 1r3", ["X = -1r3"]},
    {"X = 4r2", ["X = 2"]},
    {"X = 2r6", ["X = 1r3"]},
    {"X = 3r1", ["X = 3"]},
    {"X = 0r5", ["X = 0"]},
    {"X = 1_000r3", ["X = 1000r3"]},
    {"X = - (1r3), X =.. L", ["L = [-,1r3], X = - (1r3)"]},
    {"read_term_from_atom('1r0', T, [])", {:error, "syntax_error("}},
    {"read_term_from_atom('1r', T, [])", {:error, "syntax_error("}},
    {"read_term_from_atom('1.5r3', T, [])", {:error, "syntax_error("}},
    {"writeq([1r3, -1r3, 1-1r3, 1- -1r3, -(1r3), 1r3^2])",
     {:out, "[1r3,-1r3,1-1r3,1- -1r3,- (1r3),1r3^2]", true}},
    {"write_canonical(f(1r3, -7r2))", {:out, "f(1r3,-7r2)", true}},
    {"writeq(1 rdiv 3)", {:out, "1 rdiv 3", true}},
    {"term_to_atom(1r3, A)", ["A = '1r3'"]},
    {"atom_number('3r4', N)", ["N = 3r4"]},
    {"atom_number(A, -3r4)", ["A = '-3r4'"]},
    {"number_codes(N, \"-3r4\")", ["N = -3r4"]},
    {"number_codes(N, \"1r0\")", {:error, "syntax_error(illegal_number)"}},
    {"atom_number('1r0', N)", :fails},
    {"current_op(P, T, rdiv)", ["P = 400, T = yfx"]},
    # --- Arithmetik ---
    {"X is 1 rdiv 3", ["X = 1r3"]},
    {"X is 1r3 + 1r6", ["X = 1r2"]},
    {"X is 1r3 * 3", ["X = 1"]},
    {"X is 1r3 - 1r3", ["X = 0"]},
    {"X is 1r3 / 2", ["X = 1r6"]},
    {"X is 2 / 1r3", ["X = 6"]},
    {"X is -8 rdiv 6", ["X = -4r3"]},
    {"X is 1 rdiv 3 rdiv 2", ["X = 1r6"]},
    {"X is 1r3 + 0.5", ["X = 0.8333333333333333"]},
    {"X is 1r3 * 1.0", ["X = 0.3333333333333333"]},
    {"X is -(1r3), Y is abs(-1r3), Z is sign(-1r3)", ["X = -1r3, Y = 1r3, Z = -1"]},
    {"X is 1r3 ^ 3, Y is 2r3 ** -2, Z is (-1r2) ^ 3", ["X = 1r27, Y = 9r4, Z = -1r8"]},
    {"X is 1r3 ** 0.5", ["X = 0.5773502691896257"]},
    {"X is max(1r3, 1r4), Y is min(1r3, 0.3), Z is max(1r3, 0.3)", ["X = 1r3, Y = 0.3, Z = 1r3"]},
    {"X is floor(-7r2), Y is ceiling(-7r2), Z is truncate(-7r2)", ["X = -4, Y = -3, Z = -3"]},
    {"X is round(-7r2), Y is round(7r2), Z is integer(-7r2), W is integer(7r2)",
     ["W = 4, X = -3, Y = 4, Z = -4"]},
    {"X is float(1r3), Y is float(10^30 rdiv 3)",
     ["X = 0.3333333333333333, Y = 3.333333333333333e29"]},
    {"X is sqrt(9r4)", ["X = 1.5"]},
    {"X is numerator(3r4), Y is denominator(3r4), Z is denominator(5), W is numerator(-6)",
     ["W = -6, X = 3, Y = 4, Z = 1"]},
    {"X is numerator(0.5)", {:error, "type_error(rational,0.5)"}},
    {"X is rational(0.1), Y is rationalize(0.1)",
     ["X = 3602879701896397r36028797018963968, Y = 1r10"]},
    {"X is rational(0.5), Y is rational(-2.0), Z is rationalize(3)", ["X = 1r2, Y = -2, Z = 3"]},
    {"X is rationalize(0.3333333333333333)", ["X = 1r3"]},
    {"X is 1r3 // 2", {:error, "type_error(integer,1r3)"}},
    {"X is 7r2 mod 2", {:error, "type_error(integer,7r2)"}},
    {"X is msb(1r3)", {:error, "type_error(integer,1r3)"}},
    {"X is 1 rdiv 0.5", {:error, "type_error(rational,0.5)"}},
    {"X is 1r2 rdiv 0", {:error, "evaluation_error(zero_divisor)"}},
    {"X is 1r2 / 0", {:error, "evaluation_error(zero_divisor)"}},
    {"X is 0 ** -1r2", {:error, "evaluation_error(undefined)"}},
    # prefer_rationals (Vorgabe false): / ** ^ auf Ganzzahlen
    {"current_prolog_flag(prefer_rationals, F)", ["F = false"]},
    {"X is 1/3, Y is 2 ** -1", ["X = 0.3333333333333333, Y = 0.5"]},
    {"set_prolog_flag(prefer_rationals, true), X is 1/3, Y is 2 ** -2, Z is 2 ^ -1, " <>
       "W is 4/2, set_prolog_flag(prefer_rationals, false)",
     ["W = 2, X = 1r3, Y = 1r4, Z = 1r2"]},
    # --- Vergleiche ---
    {"1r3 < 1r2, 1r2 > 1r3, 1r3 =< 1r3, 1r3 =:= 2r6, 1r3 =\\= 1r2", true},
    {"1r3 < 1, 1 > 1r3, 1r3 < 0.34, 0.3 < 1r3, 1r2 =:= 0.5", true},
    {"X = 1r3, X < 1", ["X = 1r3"]},
    # --- Typen ---
    {"number(1r3), atomic(1r3), rational(1r3), rational(2), nonvar(1r3), ground(f(1r3))", true},
    {"integer(1r3)", :fails},
    {"float(1r3)", :fails},
    {"compound(1r3)", :fails},
    {"callable(1r3)", :fails},
    {"rational(0.5)", :fails},
    {"rational(3r4, N, D), rational(5, N5, D5)", ["D = 4, D5 = 1, N = 3, N5 = 5"]},
    {"rational(0.5, N, D)", :fails},
    {"call(1r3)", {:error, "type_error(callable,1r3)"}},
    {"functor(T, 1r3, 0), functor(1r3, N, A)", ["A = 0, N = 1r3, T = 1r3"]},
    {"X =.. [1r3]", ["X = 1r3"]},
    {"length(L, 1r3)", {:error, "type_error(integer,1r3)"}},
    # --- Standardordnung: Float < (Ganzzahl und Bruch nach Wert) ---
    {"msort([b, 1r3, 0.9, f(x), Z, 2, -1r2, 1, 1r2, 0.1], L)",
     ["L = [Z,0.1,0.9,-1r2,1r3,1r2,1,2,b,f(x)]"]},
    {"sort([1r2, 1r2, 2r4, 1r3], L)", ["L = [1r3,1r2]"]},
    {"msort([3r2, 1, 2, 5r4, 7r5, 4r3, 10r7, 13r9], L)", ["L = [1,5r4,4r3,7r5,10r7,13r9,3r2,2]"]},
    {"sort(0, @>=, [1r2, 1r3, 1, 2r3], L)", ["L = [1,2r3,1r2,1r3]"]},
    {"keysort([1r2-a, 1r3-b, 1-c, 1r3-d], L)", ["L = [1r3-b,1r3-d,1r2-a,1-c]"]},
    {"compare(O, 1r3, 0.9)", ["O = (>)"]},
    {"compare(O, 1r3, 1)", ["O = (<)"]},
    {"compare(O, 1r3, 2r6)", ["O = (=)"]},
    {"1r3 @< a, 1r3 == 2r6, 1r3 \\== 1r2, f(1r3) @< f(1r2)", true},
    {"setof(X, member(X, [1r2, 1r3, 1r2, 0.5]), L)", ["L = [0.5,1r3,1r2]"]},
    # --- Unifikation und Durchreichen ---
    {"1r3 = 2r6", true},
    {"1r3 = 1r2", :fails},
    {"1r3 = 0.3333333333333333", :fails},
    {"X = f(1r3, Y), X = f(Z, 2)", ["X = f(1r3,2), Y = 2, Z = 1r3"]},
    {"X = f(X, 1r3), Y = f(Y, 1r3), X == Y", ["X = f(X,1r3), Y = f(Y,1r3)"]},
    {"copy_term(g(Y, 1r3), Z)", ["Z = g(_A,1r3)"]},
    {"assertz(rq(f(1r3))), assertz(rq(2r3)), findall(X, rq(X), L), retract(rq(2r3))",
     ["L = [f(1r3),2r3]"]},
    {"assertz((rh(1r3) :- true)), rh(X), rh(2r6)", ["X = 1r3"]},
    {"catch(throw(f(1r3)), B, true)", ["B = f(1r3)"]},
    {"dif(X, 1r3), X = 1r2", ["X = 1r2"]},
    {"dif(X, 1r3), X = 2r6", :fails},
    {"subsumes_term(1r3, 1r3), unify_with_occurs_check(X, 1r3)", ["X = 1r3"]},
    {"term_hash(1r3, H1), term_hash(2r6, H2), term_hash(1r2, H3), H1 == H2, H1 \\== H3",
     :succeeds},
    {"fast_term_serialized(f(1r3, -7r2), S), fast_term_serialized(T, S), T == f(1r3, -7r2)",
     :succeeds},
    {"atom_length('1r3', L)", ["L = 3"]},
    {"format(\"~w ~q ~4f ~0f ~2f ~2e~n\", [1r3, -2r5, 1r3, 1r2, -5r8, 1r3])",
     {:out, "1r3 -2r5 0.3333 1 -0.63 3.33e-01\n", true}},
    {"format(\"~2f\", [10^30 rdiv 3])", {:out, "333333333333333333333333333333.33", true}},
    {"format(\"~d\", [1r3])", {:error, "type_error(integer,1r3)"}},
    {"sum_list([1r2, 1r3, 1r6], S), max_list([1r2, 1r3], M)", ["M = 1r2, S = 1"]}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(lists iso_ext swi))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  # --- die Bausteine direkt -----------------------------------------------

  test "Sortierschlüssel ordnen wie die Werte" do
    :rand.seed(:exsss, {1, 2, 3})

    nums =
      for _ <- 1..400 do
        d = :rand.uniform(60)
        Rational.make(:rand.uniform(400) - 200, d)
      end

    key = fn
      n when is_integer(n) -> {1, 1, n, 0}
      r -> Rational.sort_key(r)
    end

    by_key = Enum.sort_by(nums, key)
    by_value = Enum.sort(nums, fn a, b -> Rational.cmp(a, b) != :gt end)
    assert by_key == by_value
  end

  test "to_float rundet korrekt, auch bei großen Zählern und Nennern" do
    :rand.seed(:exsss, {4, 5, 6})

    for _ <- 1..300 do
      n = :rand.uniform(Integer.pow(10, :rand.uniform(80)))
      d = :rand.uniform(Integer.pow(10, :rand.uniform(80))) + 1

      case Rational.make(n, d) do
        i when is_integer(i) ->
          :ok

        r ->
          f = Rational.to_float(r)
          # f ist der nächste Float: beide Nachbarn liegen nicht näher
          exact = r
          err = fn g -> Rational.abs(Rational.sub(Rational.from_float(g), exact)) end
          up = next_float(f, 1)
          down = next_float(f, -1)
          assert Rational.cmp(err.(f), err.(up)) != :gt, inspect({n, d})
          assert Rational.cmp(err.(f), err.(down)) != :gt, inspect({n, d})
      end
    end
  end

  test "rationalize/1 gibt den Float wieder" do
    :rand.seed(:exsss, {7, 8, 9})

    for _ <- 1..500 do
      f = (:rand.uniform() - 0.5) * :math.pow(10, :rand.uniform(20) - 10)
      assert Rational.to_float(Rational.rationalize(f) |> wrap()) == f
    end
  end

  test "simplest/2: kleinster Nenner im Intervall, wie eine Suche über alle Nenner" do
    :rand.seed(:exsss, {3, 3, 3})

    for _ <- 1..300 do
      a = Rational.make(:rand.uniform(400) - 200, :rand.uniform(40))
      b = Rational.add(a, Rational.make(:rand.uniform(30) - 1, :rand.uniform(60)))
      s = Rational.simplest(a, b)
      {_, d} = Rational.parts(s)
      assert Rational.cmp(a, s) != :gt and Rational.cmp(s, b) != :gt
      # kein kleinerer Nenner hat einen Bruch im Intervall
      for k <- 1..(d - 1)//1 do
        lo = Rational.ceiling(Rational.mul(a, k))
        assert Rational.cmp(Rational.make(lo, k), b) == :gt, inspect({a, b, s, k})
      end
    end
  end

  # Nachbar eines positiven Floats (über die Bits)
  defp next_float(f, step) do
    <<b::64>> = <<f::float>>
    <<g::float>> = <<b + step::64>>
    g
  end

  defp wrap(n) when is_integer(n), do: {:rat, n, 1}
  defp wrap(r), do: r
end
