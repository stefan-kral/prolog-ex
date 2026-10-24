defmodule PrologEx.Arith do
  @moduledoc """
  Arithmetik: Auswertung für `is/2` und die Vergleiche (`=:=`, `<`, ...).

  Ganzzahlen sind beliebig groß, Floats IEEE double. Die BEAM kennt weder
  `inf` noch `nan`: wo ein solcher Wert entstünde, gibt es einen Fehler
  (`evaluation_error(float_overflow)` bzw. `evaluation_error(undefined)`).

  ## Auswertbare Funktoren

  Konstanten: `pi`, `e`, `epsilon`, `max_tagged_integer`,
  `min_tagged_integer`, `random` (Float in [0,1), wie `random_float`),
  `random_float`, `cputime` (Sekunden, Float), `realtime` (Sekunden seit
  1970, Ganzzahl).

  Einstellig: `-`, `+`, `abs`, `sign`, `min`/`max` (zweistellig), `sqrt`,
  `sin`, `cos`, `tan`, `cot`, `asin`, `acos`, `atan`, `acot`, `sinh`,
  `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `exp`, `log`, `log2`,
  `float`, `integer` (runden), `float_integer_part`,
  `float_fractional_part`, `truncate`, `round`, `ceiling`, `floor`, `\\`,
  `msb`, `lsb`, `popcount`, `succ`, `random(N)` (Ganzzahl in 0..N-1),
  `random_float`.

  Zweistellig: `+`, `-`, `*`, `/`, `//`, `mod`, `rem`, `div`, `min`, `max`,
  `**`, `^`, `>>`, `<<`, `/\\`, `\\/`, `xor`, `atan/2`, `atan2/2`,
  `copysign`, `gcd`, `log/2` (`log(B, X)`: Logarithmus von X zur Basis B),
  `plus/2`.

  Eine einelementige Liste `[X]` wertet zu X aus, bei einem
  Ein-Zeichen-Atom zu dessen Code (`X is "a"` gibt 97, mit
  `double_quotes=codes` wie `chars`).

  ## Fehler (ISO)

    * Variable: `instantiation_error`
    * kein auswertbarer Funktor: `type_error(evaluable, Name/Stelligkeit)`
    * Ganzzahl-Operation mit Float (`//`, `mod`, `rem`, `div`, Bitoperationen,
      `msb`, `gcd`, ...): `type_error(integer, X)`
    * Division durch 0 (auch `mod`, `rem`, `//`, `div`, `0 ** -1`, `0 ^ -1`):
      `evaluation_error(zero_divisor)`
    * außerhalb des Definitionsbereichs (`sqrt(-1)`, `log(0)`,
      `asin(2)`, `atan2(0, 0)`, ...): `evaluation_error(undefined)`
    * Float zu groß (`exp(1000)`, `float(10^400)`):
      `evaluation_error(float_overflow)`
    * `I ^ N` mit Ganzzahlen, N < 0 und I nicht 1 oder -1:
      `type_error(float, I)` (ISO Cor. 2)

  `/` auf Ganzzahlen gibt eine Ganzzahl, wenn die Division aufgeht, sonst
  einen Float (wie SWI). `round`, `truncate`, `floor`, `ceiling` und
  `integer` nehmen auch Ganzzahlen (wie SWI; ISO verlangt einen Float).
  """

  import PrologEx, only: [walk: 2, unmark_top: 1]
  alias PrologEx.Error

  @max_tagged 576_460_752_303_423_487
  @min_tagged -576_460_752_303_423_488

  @doc "Wert des arithmetischen Ausdrucks t unter der Substitution s"
  def eval(t, s) do
    ev(t, s)
  rescue
    # was die Prüfungen unten nicht abfangen (sollte nicht vorkommen)
    ArithmeticError -> undefined()
  end

  defp ev(t, s) do
    case unmark_top(walk(t, s)) do
      n when is_number(n) -> n
      {:struct, op, [x, y]} -> eval2(op, ev(x, s), ev(y, s))
      {:struct, op, [x]} -> eval1(op, ev(x, s))
      {:atom, name} -> eval0(name)
      [x] -> ev_char(x, s)
      {:var, _} -> Error.instantiation!()
      {:struct, f, args} -> Error.type!("evaluable", Error.indicator(f, length(args)))
      [] -> Error.type!("evaluable", Error.indicator("[]", 0))
      [_ | _] -> Error.type!("evaluable", Error.indicator(".", 2))
      other -> Error.type!("evaluable", other)
    end
  end

  # [X]: X; ist X ein Ein-Zeichen-Atom (z. B. "a" bei double_quotes=chars),
  # sein Zeichencode (wie SWI)
  defp ev_char(x, s) do
    case walk(x, s) do
      {:atom, <<c::utf8>>} -> c
      _ -> ev(x, s)
    end
  end

  # --- Konstanten ---------------------------------------------------------

  defp eval0("pi"), do: :math.pi()
  defp eval0("e"), do: :math.exp(1)
  defp eval0("epsilon"), do: 2.220446049250313e-16
  defp eval0("max_tagged_integer"), do: @max_tagged
  defp eval0("min_tagged_integer"), do: @min_tagged
  defp eval0("random"), do: random_float()
  defp eval0("random_float"), do: random_float()
  defp eval0("cputime"), do: :erlang.statistics(:runtime) |> elem(0) |> Kernel./(1000)
  defp eval0("realtime"), do: System.os_time(:second)
  defp eval0("[]"), do: Error.type!("evaluable", Error.indicator("[]", 0))
  defp eval0(name), do: Error.type!("evaluable", Error.indicator(name, 0))

  # --- einstellig -----------------------------------------------------------

  defp eval1("-", x), do: -x
  defp eval1("+", x), do: x
  defp eval1("abs", x), do: abs(x)
  defp eval1("sign", x) when is_integer(x), do: int_sign(x)
  defp eval1("sign", x), do: int_sign(x) * 1.0

  defp eval1("sqrt", x) when x < 0, do: undefined()
  defp eval1("sqrt", x), do: :math.sqrt(float!(x))
  defp eval1("sin", x), do: :math.sin(float!(x))
  defp eval1("cos", x), do: :math.cos(float!(x))
  defp eval1("tan", x), do: :math.tan(float!(x))

  defp eval1("cot", x) do
    t = :math.tan(float!(x))
    if t == 0, do: zero_divisor(), else: 1 / t
  end

  defp eval1("asin", x) when x < -1 or x > 1, do: undefined()
  defp eval1("asin", x), do: :math.asin(float!(x))
  defp eval1("acos", x) when x < -1 or x > 1, do: undefined()
  defp eval1("acos", x), do: :math.acos(float!(x))
  defp eval1("atan", x), do: :math.atan(float!(x))
  defp eval1("acot", x) when x == 0, do: :math.pi() / 2
  defp eval1("acot", x), do: :math.atan(1 / float!(x))
  defp eval1("sinh", x), do: overflow(fn -> :math.sinh(float!(x)) end)
  defp eval1("cosh", x), do: overflow(fn -> :math.cosh(float!(x)) end)
  defp eval1("tanh", x), do: :math.tanh(float!(x))
  defp eval1("asinh", x), do: :math.asinh(float!(x))
  defp eval1("acosh", x) when x < 1, do: undefined()
  defp eval1("acosh", x), do: :math.acosh(float!(x))
  defp eval1("atanh", x) when x <= -1 or x >= 1, do: undefined()
  defp eval1("atanh", x), do: :math.atanh(float!(x))
  defp eval1("exp", x), do: overflow(fn -> :math.exp(float!(x)) end)
  defp eval1("log", x) when x <= 0, do: undefined()
  defp eval1("log", x) when is_integer(x), do: int_log(x)
  defp eval1("log", x), do: :math.log(x)
  defp eval1("log2", x) when x <= 0, do: undefined()
  defp eval1("log2", x) when is_integer(x), do: int_log(x) / :math.log(2)
  defp eval1("log2", x), do: :math.log2(x)

  defp eval1("float", x), do: float!(x)
  defp eval1("integer", x) when is_integer(x), do: x
  defp eval1("integer", x), do: round(x)
  defp eval1("float_integer_part", x), do: float!(trunc(x))
  defp eval1("float_fractional_part", x) when is_integer(x), do: 0.0
  defp eval1("float_fractional_part", x), do: x - trunc(x)
  defp eval1("truncate", x), do: trunc(x)
  defp eval1("round", x), do: round(x)
  defp eval1("floor", x), do: floor(x)
  defp eval1("ceiling", x), do: ceil(x)

  defp eval1("\\", x), do: Bitwise.bnot(int!(x))
  defp eval1("msb", x), do: msb(positive!(int!(x)))
  defp eval1("lsb", x), do: lsb(positive!(int!(x)))
  defp eval1("popcount", x), do: popcount(nonneg!(int!(x)))
  defp eval1("succ", x), do: nonneg!(int!(x)) + 1

  defp eval1("random", x) do
    n = int!(x)
    if n <= 0, do: Error.domain!("positive_integer", n)
    PrologEx.Builtins.Random.draw(&:rand.uniform_s(n, &1)) - 1
  end

  defp eval1("random_float", _x), do: random_float()

  defp eval1(op, _), do: Error.type!("evaluable", Error.indicator(op, 1))

  # --- zweistellig ----------------------------------------------------------

  # Ganzzahlen laufen nicht über: ohne overflow/1 (schneller)
  defp eval2("+", x, y) when is_integer(x) and is_integer(y), do: x + y
  defp eval2("-", x, y) when is_integer(x) and is_integer(y), do: x - y
  defp eval2("*", x, y) when is_integer(x) and is_integer(y), do: x * y
  defp eval2("mod", x, y) when is_integer(x) and is_integer(y) and y != 0, do: Integer.mod(x, y)
  defp eval2("//", x, y) when is_integer(x) and is_integer(y) and y != 0, do: div(x, y)
  defp eval2("+", x, y), do: overflow(fn -> x + y end)
  defp eval2("-", x, y), do: overflow(fn -> x - y end)
  defp eval2("*", x, y), do: overflow(fn -> x * y end)

  defp eval2("/", _x, y) when y == 0, do: zero_divisor()

  defp eval2("/", x, y) when is_integer(x) and is_integer(y),
    do: if(rem(x, y) == 0, do: div(x, y), else: overflow(fn -> x / y end))

  defp eval2("/", x, y), do: overflow(fn -> x / y end)

  defp eval2("//", x, y), do: div(int!(x), divisor!(y))
  defp eval2("rem", x, y), do: rem(int!(x), divisor!(y))
  defp eval2("mod", x, y), do: Integer.mod(int!(x), divisor!(y))
  defp eval2("div", x, y), do: Integer.floor_div(int!(x), divisor!(y))

  defp eval2("min", x, y), do: if(y < x, do: y, else: x)
  defp eval2("max", x, y), do: if(y > x, do: y, else: x)

  defp eval2("**", x, y) when is_integer(x) and is_integer(y) and y >= 0, do: Integer.pow(x, y)
  defp eval2("**", x, y) when x == 0 and y < 0, do: zero_divisor()
  defp eval2("**", x, y), do: pow(x, y)

  defp eval2("^", x, y) when is_integer(x) and is_integer(y) and y >= 0, do: Integer.pow(x, y)

  defp eval2("^", x, y) when is_integer(x) and is_integer(y) do
    cond do
      x == 1 -> 1
      x == -1 -> if(rem(y, 2) == 0, do: 1, else: -1)
      x == 0 -> zero_divisor()
      true -> Error.type!("float", x)
    end
  end

  defp eval2("^", x, y) when x == 0 and y < 0, do: zero_divisor()
  defp eval2("^", x, y), do: pow(x, y)

  defp eval2(">>", x, y), do: Bitwise.bsr(int!(x), int!(y))
  defp eval2("<<", x, y), do: Bitwise.bsl(int!(x), int!(y))
  defp eval2("/\\", x, y), do: Bitwise.band(int!(x), int!(y))
  defp eval2("\\/", x, y), do: Bitwise.bor(int!(x), int!(y))
  defp eval2("xor", x, y), do: Bitwise.bxor(int!(x), int!(y))

  defp eval2("atan", x, y), do: atan2(x, y)
  defp eval2("atan2", x, y), do: atan2(x, y)

  defp eval2("copysign", x, y) do
    x = float!(x)
    if negative?(y), do: -abs(x), else: abs(x)
  end

  defp eval2("gcd", x, y), do: Integer.gcd(int!(x), int!(y))

  defp eval2("log", b, x) when b <= 0 or x <= 0, do: undefined()
  defp eval2("log", b, _x) when b == 1, do: zero_divisor()
  defp eval2("log", b, x), do: eval1("log", x) / eval1("log", b)

  defp eval2("plus", x, y), do: eval2("+", x, y)
  defp eval2(op, _, _), do: Error.type!("evaluable", Error.indicator(op, 2))

  # --- Hilfen -------------------------------------------------------------

  defp int!(x) when is_integer(x), do: x
  defp int!(x), do: Error.type!("integer", x)

  defp divisor!(y) do
    y = int!(y)
    if y == 0, do: zero_divisor(), else: y
  end

  defp positive!(x) when x > 0, do: x
  defp positive!(x), do: Error.type!("positive_integer", x)

  defp nonneg!(x) when x >= 0, do: x
  defp nonneg!(x), do: Error.type!("not_less_than_zero", x)

  # Float, mit float_overflow für zu große Ganzzahlen
  defp float!(x) when is_float(x), do: x
  defp float!(x), do: overflow(fn -> x * 1.0 end)

  defp overflow(f) do
    f.()
  rescue
    ArithmeticError -> Error.evaluation!("float_overflow")
  end

  defp undefined, do: Error.evaluation!("undefined")
  defp zero_divisor, do: Error.evaluation!("zero_divisor")

  defp int_sign(x) when x > 0, do: 1
  defp int_sign(x) when x < 0, do: -1
  defp int_sign(_), do: 0

  defp negative?(y) when is_float(y), do: y < 0 or (y == 0 and <<y::float>> == <<-0.0::float>>)
  defp negative?(y), do: y < 0

  # log einer (auch sehr großen) Ganzzahl > 0
  defp int_log(x) when x < 1.0e300, do: :math.log(x)

  defp int_log(x) do
    shift = msb(x) - 900
    :math.log(Bitwise.bsr(x, shift)) + shift * :math.log(2)
  end

  defp pow(x, y) do
    xf = float!(x)
    yf = float!(y)

    cond do
      xf < 0 and yf != Float.round(yf) -> undefined()
      true -> overflow(fn -> :math.pow(xf, yf) end)
    end
  end

  defp atan2(x, y) do
    if x == 0 and y == 0, do: undefined(), else: :math.atan2(float!(x), float!(y))
  end

  defp msb(x), do: length(Integer.digits(x, 2)) - 1

  defp lsb(x), do: lsb(x, 0)
  defp lsb(x, n) when Bitwise.band(x, 1) == 1, do: n
  defp lsb(x, n), do: lsb(Bitwise.bsr(x, 1), n + 1)

  defp popcount(x), do: x |> Integer.digits(2) |> Enum.sum()

  defp random_float, do: PrologEx.Builtins.Random.draw(&:rand.uniform_real_s/1)
end
