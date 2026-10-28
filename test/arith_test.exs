defmodule PrologEx.ArithTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r}
  end

  # Wert von X is Ausdruck, oder {:error, Fehlerterm}
  defp ev(c, expr) do
    [{:term, g, _}] = Reader.read_terms(c.reader, "X is #{expr}.")

    try do
      [ans] = PrologEx.query(%{}, g) |> Enum.take(1)
      ans["X"]
    rescue
      e in PrologEx.Error -> {:error, Exception.message(e)}
    end
  end

  defp check(c, cases) do
    for {expr, exp} <- cases do
      got = ev(c, expr)

      ok =
        case exp do
          {:approx, v} -> is_float(got) and abs(got - v) < 1.0e-12
          v -> got === v
        end

      assert ok, "#{expr}: #{inspect(got)}, erwartet #{inspect(exp)}"
    end
  end

  test "Grundrechenarten", c do
    check(c, [
      {"1 + 2", 3},
      {"1 + 2.0", 3.0},
      {"7 - 10", -3},
      {"6 * 7", 42},
      {"7 / 2", 3.5},
      {"8 / 2", 4},
      {"7.0 / 2", 3.5},
      {"7 // 2", 3},
      {"-7 // 2", -3},
      {"7 rem -2", 1},
      {"-7 rem 2", -1},
      {"-7 mod 2", 1},
      {"7 mod -2", -1},
      {"-7 div 2", -4},
      {"7 div 2", 3},
      {"- 3", -3},
      {"+ 3", 3},
      {"abs(-3)", 3},
      {"abs(-3.5)", 3.5},
      {"min(1, 2.0)", 1},
      {"max(1, 2.0)", 2.0},
      {"min(2, 2.0)", 2},
      {"sign(-5)", -1},
      {"sign(0)", 0},
      {"sign(2.5)", 1.0},
      {"sign(-2.5)", -1.0},
      {"succ(4)", 5},
      {"plus(1, 2)", 3}
    ])
  end

  test "Potenzen", c do
    check(c, [
      {"2 ** 10", 1024},
      {"2 ** -1", 0.5},
      {"2.0 ** 3", 8.0},
      {"2 ^ 100", 1_267_650_600_228_229_401_496_703_205_376},
      {"1 ^ -5", 1},
      {"-1 ^ -3", -1},
      {"-1 ^ -4", 1},
      {"2.0 ^ -1", 0.5},
      {"4 ** 0.5", 2.0},
      {"2 ^ -1", {:error, "type_error(float,2)"}},
      {"0 ^ -1", {:error, "evaluation_error(zero_divisor)"}},
      {"0 ** -1", {:error, "evaluation_error(zero_divisor)"}},
      {"-8 ** 0.5", {:error, "evaluation_error(undefined)"}},
      {"10.0 ** 400", {:error, "evaluation_error(float_overflow)"}}
    ])
  end

  test "Bitoperationen", c do
    check(c, [
      {"5 /\\ 3", 1},
      {"5 \\/ 3", 7},
      {"5 xor 3", 6},
      {"\\ 5", -6},
      {"1 << 70", 1_180_591_620_717_411_303_424},
      {"-16 >> 2", -4},
      {"msb(1000)", 9},
      {"msb(1)", 0},
      {"lsb(1000)", 3},
      {"popcount(255)", 8},
      {"gcd(12,18)", 6},
      {"gcd(-12,18)", 6},
      {"gcd(0,0)", 0},
      {"msb(0)", {:error, "type_error(positive_integer,0)"}},
      {"5.0 /\\ 3", {:error, "type_error(integer,5.0)"}},
      {"\\ 2.0", {:error, "type_error(integer,2.0)"}},
      {"7.0 // 2", {:error, "type_error(integer,7.0)"}},
      {"7 mod 2.0", {:error, "type_error(integer,2.0)"}}
    ])
  end

  test "Division durch 0", c do
    for e <- ["1 / 0", "1.0 / 0", "1 / 0.0", "1 // 0", "1 mod 0", "1 rem 0", "1 div 0"] do
      assert ev(c, e) == {:error, "evaluation_error(zero_divisor)"}, e
    end
  end

  test "Rundung und Umwandlung", c do
    check(c, [
      {"float(3)", 3.0},
      {"integer(2.5)", 3},
      {"integer(-2.5)", -3},
      {"integer(7)", 7},
      {"round(2.4)", 2},
      {"round(-2.5)", -3},
      {"truncate(-2.7)", -2},
      {"floor(-2.5)", -3},
      {"ceiling(2.1)", 3},
      {"floor(4)", 4},
      {"float_integer_part(-2.5)", -2.0},
      {"float_fractional_part(2.75)", 0.75},
      {"float_fractional_part(3)", 0.0},
      {"float(10 ^ 400)", {:error, "evaluation_error(float_overflow)"}}
    ])
  end

  test "Transzendente Funktionen", c do
    check(c, [
      {"sqrt(16)", 4.0},
      {"sin(0)", 0.0},
      {"cos(0)", 1.0},
      {"tan(pi / 4)", {:approx, 1.0}},
      {"asin(1)", {:approx, :math.pi() / 2}},
      {"acos(1)", 0.0},
      {"atan(1)", {:approx, :math.pi() / 4}},
      {"atan(1, 1)", {:approx, :math.pi() / 4}},
      {"atan2(1, -1)", {:approx, 3 * :math.pi() / 4}},
      {"cot(pi / 4)", {:approx, 1.0}},
      {"acot(1)", {:approx, :math.pi() / 4}},
      {"acot(0)", {:approx, :math.pi() / 2}},
      {"sinh(0)", 0.0},
      {"cosh(0)", 1.0},
      {"tanh(0)", 0.0},
      {"asinh(0)", 0.0},
      {"acosh(1)", 0.0},
      {"atanh(0)", 0.0},
      {"exp(0)", 1.0},
      {"log(e)", 1.0},
      {"log(2, 1024)", {:approx, 10.0}},
      {"log2(1024)", {:approx, 10.0}},
      {"log(10 ^ 400)", {:approx, 400 * :math.log(10)}},
      {"copysign(2, -0.0)", -2.0},
      {"copysign(-2, 1)", 2.0},
      {"pi", :math.pi()},
      {"e", :math.exp(1)},
      {"epsilon", 2.220446049250313e-16},
      {"max_tagged_integer", 576_460_752_303_423_487},
      {"min_tagged_integer", -576_460_752_303_423_488}
    ])
  end

  test "außerhalb des Definitionsbereichs", c do
    for e <- [
          "sqrt(-1)",
          "log(0)",
          "log(-1.0)",
          "log2(0)",
          "log(0, 5)",
          "asin(2)",
          "acos(-1.5)",
          "acosh(0.5)",
          "atanh(1)",
          "atan2(0, 0)",
          "atan(0.0, 0)"
        ] do
      assert ev(c, e) == {:error, "evaluation_error(undefined)"}, e
    end

    assert ev(c, "exp(1000)") == {:error, "evaluation_error(float_overflow)"}
    assert ev(c, "cosh(1000)") == {:error, "evaluation_error(float_overflow)"}
    assert ev(c, "1.0e308 * 10") == {:error, "evaluation_error(float_overflow)"}
    assert ev(c, "log(1, 5)") == {:error, "evaluation_error(zero_divisor)"}
    assert ev(c, "1 << (10 ^ 12)") == {:error, "resource_error(memory)"}
  end

  test "Fehler: ungebunden, nicht auswertbar", c do
    assert ev(c, "_ + 1") == {:error, "instantiation_error"}
    assert ev(c, "foo + 1") == {:error, "type_error(evaluable,foo/0)"}
    assert ev(c, "foo(1)") == {:error, "type_error(evaluable,foo/1)"}
    assert ev(c, "foo(1, 2, 3)") == {:error, "type_error(evaluable,foo/3)"}
    assert ev(c, "[]") == {:error, "type_error(evaluable,[]/0)"}
    assert ev(c, "[1, 2]") == {:error, "type_error(evaluable,'.'/2)"}
  end

  test "einelementige Liste", c do
    check(c, [{"[5]", 5}, {"[1 + 2]", 3}, {"\"a\" + 0", 97}, {"[a]", 97}, {"['ä']", 228}])
  end

  test "Zufall und Zeit", c do
    for _ <- 1..50 do
      x = ev(c, "random(10)")
      assert is_integer(x) and x >= 0 and x < 10
      f = ev(c, "random_float")
      assert is_float(f) and f >= 0 and f < 1
    end

    assert is_float(ev(c, "random"))
    assert ev(c, "random(0)") |> elem(1) =~ "domain_error"
    assert is_float(ev(c, "cputime"))
    assert ev(c, "realtime") > 1_700_000_000
  end
end
