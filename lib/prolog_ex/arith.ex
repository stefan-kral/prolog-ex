defmodule PrologEx.Arith do
  @float_only [
    "round",
    "floor",
    "ceiling",
    "truncate",
    "float_integer_part",
    "float_fractional_part"
  ]
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
    * Ganzzahl zu groß für die BEAM (`1 << 10^12`): `resource_error(memory)`

  `/` auf Ganzzahlen gibt eine Ganzzahl, wenn die Division aufgeht, sonst
  einen Float (wie SWI). `round`, `truncate`, `floor`, `ceiling` und
  `integer` nehmen auch Ganzzahlen (wie SWI; ISO verlangt einen Float).
  """

  import PrologEx, only: [unmark_top: 1]
  import PrologEx.Store, only: [walk: 2]
  alias PrologEx.Error

  @max_tagged 576_460_752_303_423_487
  @min_tagged -576_460_752_303_423_488

  @ops0 ~w(pi e epsilon max_tagged_integer min_tagged_integer random random_float
           cputime realtime)
  @ops1 ~w(+ - \\ abs acos acosh acot asin asinh atan atanh ceiling cos cosh cot exp
           float float_fractional_part float_integer_part floor integer log log2 lsb
           log10 msb popcount random random_float round sign sin sinh sqrt succ tan
           tanh truncate)
  @ops2 ~w(* ** + - / // /\\ << >> \\/ ^ atan atan2 copysign div gcd log max min
           mod plus rem xor)

  # Signaturen der auswertbaren Funktoren für evaluable_property/2:
  # {Name, Stelligkeit} => [{Argumenttypen, Ergebnistyp}] mit den Typen
  # integer, float, number. Wie hier gerechnet wird: / gibt eine Ganzzahl,
  # wenn die Division aufgeht (number), round & Co. nehmen nur Floats.
  @float1 ~w(acos acosh acot asin asinh atan atanh cos cosh cot exp log log2 log10 sin
             sinh sqrt tan tanh)
  @int1 ~w(\\ lsb msb popcount random succ)
  @int2 ~w(// /\\ << >> \\/ div gcd mod rem xor)
  @templates Map.merge(
               %{
                 {"pi", 0} => [{[], :float}],
                 {"e", 0} => [{[], :float}],
                 {"epsilon", 0} => [{[], :float}],
                 {"max_tagged_integer", 0} => [{[], :integer}],
                 {"min_tagged_integer", 0} => [{[], :integer}],
                 {"random", 0} => [{[], :float}],
                 {"random_float", 0} => [{[], :float}],
                 {"cputime", 0} => [{[], :float}],
                 {"realtime", 0} => [{[], :integer}],
                 {"+", 1} => [{[:number], :number}],
                 {"-", 1} => [{[:number], :number}],
                 {"abs", 1} => [{[:number], :number}],
                 {"sign", 1} => [{[:number], :number}],
                 {"float", 1} => [{[:number], :float}],
                 {"integer", 1} => [{[:number], :integer}],
                 {"float_integer_part", 1} => [{[:float], :float}],
                 {"float_fractional_part", 1} => [{[:float], :float}],
                 {"ceiling", 1} => [{[:float], :integer}],
                 {"floor", 1} => [{[:float], :integer}],
                 {"round", 1} => [{[:float], :integer}],
                 {"truncate", 1} => [{[:float], :integer}],
                 {"random_float", 1} => [{[:number], :float}],
                 {"atan", 2} => [{[:number, :number], :float}],
                 {"atan2", 2} => [{[:number, :number], :float}],
                 {"copysign", 2} => [{[:number, :number], :float}],
                 {"log", 2} => [{[:number, :number], :float}]
               },
               Map.new(
                 Enum.map(@float1, &{{&1, 1}, [{[:number], :float}]}) ++
                   Enum.map(@int1, &{{&1, 1}, [{[:integer], :integer}]}) ++
                   Enum.map(@int2, &{{&1, 2}, [{[:integer, :integer], :integer}]}) ++
                   Enum.map(
                     ~w(+ - * / ** ^ max min plus),
                     &{{&1, 2}, [{[:number, :number], :number}]}
                   )
               )
             )

  # jede auswertbare Funktion hat eine Signatur (beim Übersetzen geprüft)
  for {ops, n} <- [{@ops0, 0}, {@ops1, 1}, {@ops2, 2}], op <- ops do
    unless Map.has_key?(@templates, {op, n}), do: raise("Signatur fehlt: #{op}/#{n}")
  end

  @doc "Signaturen eines auswertbaren Funktors (siehe @templates) oder nil"
  def templates(name, arity), do: Map.get(@templates, {name, arity})

  @doc "Wert des arithmetischen Ausdrucks t unter der Substitution s"
  def eval(t, s) do
    ev(t, s, 0)
  rescue
    # was die Prüfungen unten nicht abfangen (sollte nicht vorkommen)
    ArithmeticError -> undefined()
    # Ganzzahl zu groß für die BEAM (z. B. 1 << 10^12)
    SystemLimitError -> Error.resource!("memory")
  end

  # d: Tiefe. Alle @deep Stufen prüfen, ob der Ausdruck zyklisch ist (X = X
  # + 1): sonst liefe die Auswertung, bis der Speicher ausgeht
  @deep 1_000_000
  defp ev(t, s, d) when d >= @deep do
    if PrologEx.Builtins.Terms.acyclic?(t, s),
      do: ev(t, s, d - @deep),
      else: Error.type!("acyclic_term", t)
  end

  defp ev(t, s, d) do
    case unmark_top(walk(t, s)) do
      n when is_number(n) -> n
      # erst der Funktor, dann die Argumente: X is foo(bar) gibt
      # type_error(evaluable, foo/1), nicht bar/0 (ISO 9.1.1)
      {:struct, op, [x, y]} when op in @ops2 -> eval2(op, ev(x, s, d + 1), ev(y, s, d + 1))
      {:struct, op, [x]} when op in @ops1 -> eval1(op, ev(x, s, d + 1))
      {:atom, name} -> eval0(name)
      [x] -> ev_char(x, s, d)
      {:var, _} -> Error.instantiation!()
      {:struct, f, args} -> Error.type!("evaluable", Error.indicator(f, length(args)))
      [] -> Error.type!("evaluable", Error.indicator("[]", 0))
      [_ | _] -> Error.type!("evaluable", Error.indicator(".", 2))
      other -> Error.type!("evaluable", other)
    end
  end

  # --- cached_is/2 (library(iso_ext)) ------------------------------------
  #
  # Wie eval/2, aber ein geteilter Teilausdruck wird nur einmal ausgewertet:
  # gemerkt je gebundener Variable und je Struktur (PrologEx.Share, also
  # physisch gleiche Teilterme). So kostet X+X über 40 Stufen 40 Schritte
  # statt 2^40. Reihenfolge und Fehler wie bei eval/2 (ein wiederholter
  # Teilausdruck hätte beim ersten Mal denselben Fehler geworfen). Teilterme
  # mit unreinen Funktionen (random, random_float, cputime, realtime) werden
  # nicht gemerkt: sie liefern wie bei is/2 je Vorkommen einen neuen Wert.

  # unrein: der Wert ändert sich von Aufruf zu Aufruf (auch: nicht falten,
  # siehe unten)
  @impure ~w(random random_float cputime realtime)

  @doc "Wert von t wie eval/2, geteilte Teilausdrücke nur einmal"
  def eval_cached(t, s) do
    {v, _pure, _memo} = evc(t, s, %{})
    v
  rescue
    ArithmeticError -> undefined()
    SystemLimitError -> Error.resource!("memory")
  end

  # {Wert, rein?, Gedächtnis}
  # (:path: x liegt auf dem aktuellen Pfad – ein zyklischer Ausdruck)
  defp evc({:var, _} = x, s, memo) do
    case memo do
      %{^x => :path} ->
        Error.type!("acyclic_term", x)

      %{^x => v} ->
        {v, true, memo}

      _ ->
        case walk(x, s) do
          {:var, _} ->
            Error.instantiation!()

          t ->
            {v, pure, memo} = evc(t, s, Map.put(memo, x, :path))
            {v, pure, if(pure, do: Map.put(memo, x, v), else: Map.delete(memo, x))}
        end
    end
  end

  defp evc(n, _s, memo) when is_number(n), do: {n, true, memo}

  defp evc(t, s, memo) do
    # Schlüssel fürs Gedächtnis ist t selbst (ein gstruct ist geteilt,
    # seine entmarkierte Kopie wäre jedes Mal ein neues Tupel)
    case unmark_top(t) do
      {:struct, op, args}
      when (op in @ops2 and length(args) == 2) or (op in @ops1 and length(args) == 1) ->
        case PrologEx.Share.get(memo, t) do
          {:ok, v} ->
            {v, true, memo}

          :error ->
            {v, pure, memo} =
              case args do
                [x, y] ->
                  {vx, px, memo} = evc(x, s, memo)
                  {vy, py, memo} = evc(y, s, memo)
                  {eval2(op, vx, vy), px and py, memo}

                [x] ->
                  {vx, px, memo} = evc(x, s, memo)
                  {eval1(op, vx), px and op not in @impure, memo}
              end

            {v, pure, if(pure, do: PrologEx.Share.put(memo, t, v), else: memo)}
        end

      {:atom, name} ->
        {eval0(name), name not in @impure, memo}

      # alles andere (Liste [X], Fehler) wie eval/2
      other ->
        {ev(other, s, 0), true, memo}
    end
  end

  # [X]: X; ist X ein Ein-Zeichen-Atom (z. B. "a" bei double_quotes=chars),
  # sein Zeichencode (wie SWI)
  defp ev_char(x, s, d) do
    case walk(x, s) do
      {:atom, <<c::utf8>>} -> c
      _ -> ev(x, s, d + 1)
    end
  end

  # --- übersetzte Ausdrücke (siehe PrologEx.Compiler, is/2 im Rumpf) -------
  #
  # Der Compiler übersetzt den Ausdruck eines is/2- oder Vergleichsziels
  # im Klauselrumpf in einen Baum:
  #   {:num, n}             Zahl
  #   {:op0, name}          Konstante (pi, random, ...)
  #   {:op1, name, a}       einstellig
  #   {:op2, name, a, b}    zweistellig
  #   {:leaf, i}            i-tes Blatt (Variable, unbekannter Funktor, Liste):
  #                         zur Laufzeit wie bisher mit eval/2
  # Die Reihenfolge der Auswertung (links vor rechts, Tiefe zuerst) und
  # damit die Fehler sind dieselben wie bei eval/2.

  # @impure (nicht falten, Wert ändert sich): oben bei cached_is/2

  @doc false
  def op?(name, 0), do: name in @ops0
  def op?(name, 1), do: name in @ops1
  def op?(name, 2), do: name in @ops2
  def op?(_, _), do: false

  @doc false
  def impure?(name), do: name in @impure

  @doc false
  # Wert eines übersetzten Ausdrucks; leaves: Tupel der Blatt-Terme
  def run(code, leaves, s) do
    rn(code, leaves, s)
  rescue
    ArithmeticError -> undefined()
    SystemLimitError -> Error.resource!("memory")
  end

  defp rn({:num, n}, _l, _s), do: n

  defp rn({:leaf, i}, l, s) do
    case walk(elem(l, i), s) do
      n when is_number(n) -> n
      t -> ev(t, s, 0)
    end
  end

  defp rn({:op2, op, a, b}, l, s), do: eval2(op, rn(a, l, s), rn(b, l, s))
  defp rn({:op1, op, a}, l, s), do: eval1(op, rn(a, l, s))
  defp rn({:op0, name}, _l, _s), do: eval0(name)

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
  defp eval1("log10", x) when x <= 0, do: undefined()
  # kleine Ganzzahlen direkt (log10(1000) = 3.0), große über int_log
  defp eval1("log10", x) when is_integer(x) and x < 1.0e300, do: :math.log10(x)
  defp eval1("log10", x) when is_integer(x), do: int_log(x) / :math.log(10)
  defp eval1("log10", x), do: :math.log10(x)

  defp eval1("log2", x) when x <= 0, do: undefined()
  defp eval1("log2", x) when is_integer(x), do: int_log(x) / :math.log(2)
  defp eval1("log2", x), do: :math.log2(x)

  defp eval1("float", x), do: float!(x)
  defp eval1("integer", x) when is_integer(x), do: x
  defp eval1("integer", x), do: round(x)
  @float_only ~w(round floor ceiling truncate float_integer_part float_fractional_part)

  # ISO 9.1.1: Float → Float bzw. Float → Integer; ein Integer als
  # Argument ist type_error(float, X) (ISO 9.1.6, 9.3.x; SWI erlaubt ihn)
  defp eval1(f, x) when is_integer(x) and f in @float_only, do: Error.type!("float", x)
  defp eval1("float_integer_part", x), do: float!(trunc(x))
  defp eval1("float_fractional_part", x), do: x - trunc(x)
  defp eval1("truncate", x), do: trunc(x)
  defp eval1("round", x), do: iso_round(x)
  defp eval1("floor", x), do: floor(x)
  defp eval1("ceiling", x), do: ceil(x)

  defp eval1("\\", x), do: Bitwise.bnot(int!(x))
  defp eval1("msb", x), do: msb(positive!(int!(x)))
  defp eval1("lsb", x), do: lsb(positive!(int!(x)))

  defp eval1("popcount", x) do
    case int!(x) do
      n when n >= 0 -> popcount(n)
      n -> Error.domain!("not_less_than_zero", n)
    end
  end

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
  # Ganzzahlpotenz; groß (über 2^65536): vorab gegen eine Speichergrenze
  defp ipow(x, y) do
    if abs(x) > 1 do
      b = bits(x) * y
      if b > 65_536, do: PrologEx.reserve!(div(b, 64) + 2)
    end

    Integer.pow(x, y)
  end

  defp bits(0), do: 0
  defp bits(x), do: x |> abs() |> :binary.encode_unsigned() |> byte_size() |> Kernel.*(8)

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

  defp eval2("**", x, y) when is_integer(x) and is_integer(y) and y >= 0 and y <= 1024,
    do: Integer.pow(x, y)

  defp eval2("**", x, y) when is_integer(x) and is_integer(y) and y >= 0, do: ipow(x, y)
  # 0 hoch negativ: undefined (ISO 9.3.1.3, Cor.2 9.3.10.3 d)
  defp eval2("**", x, y) when x == 0 and y < 0, do: undefined()
  defp eval2("**", x, y), do: pow(x, y)

  defp eval2("^", x, y) when is_integer(x) and is_integer(y) and y >= 0 and y <= 1024,
    do: Integer.pow(x, y)

  defp eval2("^", x, y) when is_integer(x) and is_integer(y) and y >= 0, do: ipow(x, y)

  defp eval2("^", x, y) when is_integer(x) and is_integer(y) do
    cond do
      x == 1 -> 1
      x == -1 -> if(rem(y, 2) == 0, do: 1, else: -1)
      x == 0 -> undefined()
      true -> Error.type!("float", x)
    end
  end

  defp eval2("^", x, y) when x == 0 and y < 0, do: undefined()
  defp eval2("^", x, y), do: pow(x, y)

  defp eval2(">>", x, y), do: Bitwise.bsr(int!(x), int!(y))

  defp eval2("<<", x, y) when is_integer(x) and is_integer(y) and y <= 65_536,
    do: Bitwise.bsl(x, y)

  defp eval2("<<", x, y) do
    {x, y} = {int!(x), int!(y)}
    # groß: vorab gegen eine Speichergrenze (Bits / 64 Wörter)
    if y > 65_536, do: PrologEx.reserve!(div(bits(x) + y, 64) + 2)
    Bitwise.bsl(x, y)
  end

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

  # ISO 9.1.6.1: round(x) = floor(x + 1/2) – Halbwerte nach oben, auch
  # negative (round(-3.5) = -3; C, Rust, Elixir: weg von 0, -4). Nicht
  # wörtlich in Gleitkomma: x + 0.5 rundet selbst (0.49999999999999994 + 0.5
  # ergäbe 1.0); x - floor(x) ist für Floats exakt.
  defp iso_round(x) do
    f = floor(x)
    if x - f >= 0.5, do: f + 1, else: f
  end

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

  # höchstes gesetztes Bit (x > 0); über die Bytes, nicht die Binärziffern
  # (Integer.digits/2 braucht für 7^7^7 eine Minute)
  defp msb(x) do
    <<first, _::binary>> = bin = :binary.encode_unsigned(x)
    (byte_size(bin) - 1) * 8 + byte_msb(first, 0)
  end

  defp byte_msb(1, n), do: n
  defp byte_msb(b, n), do: byte_msb(Bitwise.bsr(b, 1), n + 1)

  defp lsb(x), do: lsb(x, 0)
  defp lsb(x, n) when Bitwise.band(x, 1) == 1, do: n
  defp lsb(x, n), do: lsb(Bitwise.bsr(x, 1), n + 1)

  defp popcount(x), do: x |> Integer.digits(2) |> Enum.sum()

  defp random_float, do: PrologEx.Builtins.Random.draw(&:rand.uniform_real_s/1)
end
