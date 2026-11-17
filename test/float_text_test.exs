defmodule PrologEx.FloatTextTest do
  # Gleitkommazahlen lesen, schreiben und umwandeln gegen ein unabhängiges
  # Orakel: Nigel Taos parse-number-fxx-test-data (Apache-2.0, Stand
  # 55d79b1; 5,3 Mio. Zeilen „Text → IEEE-Bits“ aus double-conversion,
  # Ryu, RapidJSON, fast_float, IBM fpgen u. a.). Hier eine Stichprobe
  # (test/fixtures/float_text/sample.txt): je Quelle rund 400 Zeilen, dazu
  # alle subnormalen Werte. Spalten: f64-Bits, Text, kürzeste Ziffernfolge
  # und Exponent nach Python (repr; Wert = 0.Ziffern * 10^Exponent).
  # Alle Zeilen prüft conformance/float_text/run.sh.
  use ExUnit.Case, async: true
  import Bitwise
  alias PrologEx.Builtins.Atoms
  alias PrologEx.{Parser, Rational, Reader, TableCase}

  @lines "test/fixtures/float_text/sample.txt"
         |> File.read!()
         |> String.split("\n", trim: true)
         |> Enum.map(fn l ->
           [h, s, d, e] = String.split(l, " ")
           {h, s, d, String.to_integer(e)}
         end)

  @inf "7FF0000000000000"

  # Text der Daten (1, .5, 1., 1E5) in Prolog-Schreibweise: Ziffern
  # unverändert, 0 vor und nach dem Punkt ergänzt
  defp prolog_text(s) do
    [_ | parts] = Regex.run(~r/^(\d*)(?:\.(\d*))?(?:[eE]([-+]?\d+))?$/, s)
    [i, f, e] = parts ++ List.duplicate("", 3 - length(parts))
    nz = fn x -> if x == "", do: "0", else: x end
    nz.(i) <> "." <> nz.(f) <> if(e == "", do: "", else: "e" <> e)
  end

  defp want(@inf), do: :inf

  defp want(h) do
    <<x::float>> = Base.decode16!(h)
    x
  end

  defp same?(x, w) when is_float(x) and is_float(w), do: <<x::float>> == <<w::float>>
  defp same?(x, w), do: x == w

  # Wert = 0.Ziffern * 10^Exponent, wie in sample.txt
  defp digits(text) do
    {m, e} =
      case String.split(text, "e") do
        [m] -> {m, 0}
        [m, e] -> {m, String.to_integer(e)}
      end

    [i, f] = String.split(String.trim_leading(m, "-"), ".")
    all = i <> f
    ds = String.trim_leading(all, "0")
    lead = byte_size(all) - byte_size(ds)
    ds = String.trim_trailing(ds, "0")
    if ds == "", do: {"0", 0}, else: {ds, byte_size(i) + e - lead}
  end

  test "Lesen: number_codes/2 (Atoms.parse_number) und der Leser treffen jedes Bit" do
    ctx = Parser.context("")

    bad =
      for {h, s, _, _} <- @lines,
          t = prolog_text(s),
          a =
            (case Atoms.parse_number(t) do
               {:ok, x} -> x
               :max_float -> :inf
               o -> o
             end),
          b =
            (case Parser.read_term(t <> " .", 0, ctx) do
               {:term, x, _, _, _, _} ->
                 x

               {:error, "Syntaxfehler" <> m, _, _} ->
                 if(m =~ "nicht darstellbar", do: :inf, else: m)
             end),
          not (same?(a, want(h)) and same?(b, want(h))),
          do: {s, h, a, b}

    assert bad == []
  end

  test "Schreiben: kürzeste Ziffern (wie Python), die sich wieder lesen" do
    bad =
      for {h, _s, d, e} <- @lines,
          h != @inf,
          f = want(h),
          w = PrologEx.format_float(f),
          back = Atoms.parse_number(w),
          not (back == {:ok, f} and same?(elem(back, 1), f) and digits(w) == {d, e}),
          do: {h, w, {d, e}}

    assert bad == []
  end

  test "Umwandeln: Ganzzahl und Bruch (Text als exakte Zahl) ergeben den nächsten Float" do
    bad =
      for {h, s, _, _} <- @lines,
          [_ | parts] = Regex.run(~r/^(\d*)(?:\.(\d*))?(?:[eE]([-+]?\d+))?$/, s),
          [i, f, e] = parts ++ List.duplicate("", 3 - length(parts)),
          n = String.to_integer(if(i <> f == "", do: "0", else: i <> f)),
          e = if(e == "", do: 0, else: String.to_integer(e)) - byte_size(f),
          n > 0 and abs(e) < 1200,
          got =
            (try do
               if e >= 0,
                 do: Rational.int_to_float(n * Integer.pow(10, e)),
                 else: Rational.to_float({:rat, n, Integer.pow(10, -e)})
             rescue
               PrologEx.Error -> :inf
             end),
          not same?(got, want(h)),
          do: {s, h, got}

    assert bad == []
  end

  # --- unabhängig von den Daten: ist das Ergebnis der nächste Float? ------

  # exakter Wert eines Floats als {Zähler, Nenner}
  defp exact(f) do
    case Rational.from_float(f) do
      {:rat, n, d} -> {n, d}
      n -> {n, 1}
    end
  end

  defp next_up(f) do
    <<b::64>> = <<f::float>>
    <<g::float>> = <<b + 1::64>>
    g
  end

  # |x - y| verglichen mit |x - z| (exakt, alles > 0 bzw. >= 0)
  defp dist({n, d}, {a, b}), do: {abs(n * b - a * d), d * b}
  defp cmp({p, q}, {r, s}), do: (p * s) |> Kernel.-(r * q) |> Integer.to_string() |> sign()
  defp sign("-" <> _), do: :lt
  defp sign("0"), do: :eq
  defp sign(_), do: :gt

  # f ist der nächste Float zu n/d (Gleichstand: gerade Mantisse)
  defp nearest?(f, n, d) do
    x = {n, d}
    here = dist(x, exact(f))
    <<bits::64>> = <<f::float>>

    up_ok =
      f == 1.7976931348623157e308 or
        case cmp(here, dist(x, exact(next_up(f)))) do
          :lt -> true
          :eq -> (bits &&& 1) == 0
          :gt -> false
        end

    down_ok =
      f == 0.0 or
        (
          <<g::float>> = <<bits - 1::64>>

          case cmp(here, dist(x, exact(g))) do
            :lt -> true
            :eq -> (bits &&& 1) == 0
            :gt -> false
          end
        )

    up_ok and down_ok
  end

  # Zufallszahl mit genau k Bits
  defp rand_bits(k), do: (1 <<< (k - 1)) + :rand.uniform(1 <<< (k - 1)) - 1

  test "Bruch → Float: der nächste, auch subnormal und an Gleichständen (Zufall)" do
    :rand.seed(:exsss, {7, 11, 13})

    bad =
      for _ <- 1..4000,
          {n, d} =
            (case :rand.uniform(4) do
               # beliebig groß
               1 ->
                 kd = :rand.uniform(1100)
                 {rand_bits(:rand.uniform(min(1100, kd + 1000))), rand_bits(kd)}

               # Ergebnis subnormal oder knapp darüber
               2 ->
                 {rand_bits(:rand.uniform(60)), rand_bits(1020 + :rand.uniform(110))}

               # Gleichstand zwischen zwei Floats: (2m+1) / 2^k
               3 ->
                 {2 * rand_bits(53) + 1, 1 <<< (1 + :rand.uniform(1100))}

               # knapp neben einem Gleichstand
               4 ->
                 {((2 * rand_bits(53) + 1) <<< 70) + :rand.uniform(3) - 2,
                  1 <<< (71 + :rand.uniform(1000))}
             end),
          f = Rational.to_float({:rat, n, d}),
          # 0.0 nur bis 2^-1075 (Gleichstand mit 5.0e-324: gerade, also 0)
          if(f == 0.0, do: n <<< 1075 > d, else: not nearest?(f, n, d)),
          do: {n, d, f}

    assert bad == []
  end

  test "Ganzzahl → Float: der nächste (Erlangs float/1 rundet ab 2^53 nicht immer so)" do
    :rand.seed(:exsss, {3, 5, 7})

    bad =
      for _ <- 1..4000,
          k = 53 + :rand.uniform(970),
          n =
            (case :rand.uniform(2) do
               1 -> rand_bits(k)
               # Gleichstand oder knapp daneben
               2 -> ((2 * rand_bits(53) + 1) <<< (k - 54)) + :rand.uniform(3) - 2
             end),
          f = Rational.int_to_float(n),
          not nearest?(f, n, 1) or Rational.int_to_float(-n) != -f,
          do: {n, f}

    assert bad == []
  end

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  describe "in Prolog" do
    setup c do
      Reader.put_current(c.reader)
      :ok
    end

    for {q, a} <- [
          {"X is float(10^39)", "X = 1.0e39"},
          {"X is 10^39 * 1.0", "X = 1.0e39"},
          {"X is 0.0 - 10^39", "X = -1.0e39"},
          {"X is float(19758051025259239319)", "X = 1.9758051025259237e19"},
          # ISO: float(X) / float(Y), wie SWI und Scryer
          {"X is 10^39 / 7", "X = 1.4285714285714284e38"},
          # genau teilbar: bleibt ganz
          {"X is 10^39 / 10^20", "X = 10000000000000000000"},
          {"X is 10^39 / 2.0", "X = 5.0e38"},
          {"X is float(1 rdiv 2^1075 + 1 rdiv 2^1200)", "X = 5.0e-324"},
          {"X is float(1 rdiv 2^1075)", "X = 0.0"},
          {"X is float(3 rdiv 2^1076)", "X = 5.0e-324"},
          {"X is float(2^1024 - 2^971)", "X = 1.7976931348623157e308"},
          {"catch(X is float(2^1024 - 2^970), error(E, _), true)",
           "E = evaluation_error(float_overflow)"},
          {"number_codes(X, \"72057594037927940.0\")", "X = 7.205759403792794e16"},
          # Vergleich mit Float: über den nächsten Float (ISO, SWI, Scryer),
          # zu groß wie unendlich
          {"( 2^53+1 =:= 2.0^53, \\+ 2^53+1 > 2.0^53, 10^39 =:= 1.0e39 -> A = ja ; A = nein )",
           "A = ja"},
          {"( 10^400 > 1.0e308, -(10^400) < -1.0e308, 10^400 rdiv 3 > 1.0 -> A = ja ; A = nein )",
           "A = ja"},
          {"X = 1.0e23, Y is 10^23, Z is float(Y), X == Z",
           "X = 1.0e23, Y = 100000000000000000000000, Z = 1.0e23"}
        ] do
      test q, c do
        assert TableCase.run(c.reader, %{}, unquote(q)) == {"", {:answers, [unquote(a)]}}
      end
    end
  end
end
