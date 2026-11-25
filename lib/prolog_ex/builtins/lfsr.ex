defmodule PrologEx.Builtins.Lfsr do
  @moduledoc """
  `library(lfsr)`: Pseudozufallszahlen aus einem linear rückgekoppelten
  Schieberegister (LFSR) mit maximaler Periode. Mit N Bits durchläuft der
  Zustand jede Zahl in 1..2^N−1 genau einmal, dann kehrt er zum Seed
  zurück.

    * `lfsr_make(+Seed, +N, -St)`, `lfsr_make(+Seed, +N, +K, -St)` –
      `St = st(Seed, N, 0, K)`: Zustand, Bits, bisher gezogen, Schritte
      je Zahl. 1 ≤ N ≤ 168, 1 ≤ Seed ≤ 2^N−1, K ≥ 1 teilerfremd zu 2^N−1
      (sonst wäre die Periode kürzer); ohne K das kleinste solche K ≥ N:
      dann ist jedes Bit der nächsten Zahl neu, aufeinanderfolgende Zahlen
      hängen nicht sichtbar zusammen (bei K = 1 ist die nächste in der
      Hälfte der Fälle die halbe vorige).
    * `lfsr_next(+St0, -X, -St)` – K Schritte weiter, X der neue Zustand;
      scheitert, wenn alle 2^N−1 Zahlen gezogen sind. Die letzte ist der
      Seed.
    * `lfsr_done(+St)` – gelingt, wenn alle 2^N−1 Zahlen gezogen sind.

  Galois-Form, rechts schiebend: `S1 = S >> 1`, bei herausfallender 1
  dazu XOR mit der Maske der Taps. Die Taps (primitive Polynome vom Grad
  N) wie in Xilinx XAPP052 (Tabelle 3, für N = 1, 2 ergänzt), jedes
  nachgeprüft: x hat modulo des Polynoms die Ordnung 2^N−1 (über die
  Primfaktoren von 2^N−1). Bis auf N = 102: XAPP052s 102, 101, 36, 35 ist
  nicht einmal irreduzibel (ein Faktor vom Grad 3); stattdessen
  102, 101, 26, 25.

  Ab K = 3 springt `lfsr_next/3` mit der Matrix der K Schritte (linear
  über GF(2)), als Tabelle je 8 Bits des Zustands: ⌈N/8⌉ Nachschläge und
  XOR statt K einzelner Schritte; vorberechnet je (N, K) einmal, in
  :persistent_term. Der JIT ruft `lfsr_next/3` und `lfsr_done/1` direkt
  (PrologEx.Jit.b_lfsr_next/1, b_lfsr_done/1 über fields/2, next/1,
  done?/1).

  Fehler: `instantiation_error`, `type_error(integer, …)`,
  `domain_error(lfsr_bits, N)`, `domain_error(lfsr_seed, Seed)`,
  `domain_error(lfsr_step, K)`; ein `St0`, das kein `st/4` mit Ganzzahlen
  und 1 ≤ N ≤ 168 ist: `type_error(lfsr, St0)`.
  """
  use PrologEx.Builtin, module: "lfsr"
  import Bitwise
  alias PrologEx.Error

  @max 168

  @taps {
    {1},
    {2, 1},
    {3, 2},
    {4, 3},
    {5, 3},
    {6, 5},
    {7, 6},
    {8, 6, 5, 4},
    {9, 5},
    {10, 7},
    {11, 9},
    {12, 6, 4, 1},
    {13, 4, 3, 1},
    {14, 5, 3, 1},
    {15, 14},
    {16, 15, 13, 4},
    {17, 14},
    {18, 11},
    {19, 6, 2, 1},
    {20, 17},
    {21, 19},
    {22, 21},
    {23, 18},
    {24, 23, 22, 17},
    {25, 22},
    {26, 6, 2, 1},
    {27, 5, 2, 1},
    {28, 25},
    {29, 27},
    {30, 6, 4, 1},
    {31, 28},
    {32, 22, 2, 1},
    {33, 20},
    {34, 27, 2, 1},
    {35, 33},
    {36, 25},
    {37, 5, 4, 3, 2, 1},
    {38, 6, 5, 1},
    {39, 35},
    {40, 38, 21, 19},
    {41, 38},
    {42, 41, 20, 19},
    {43, 42, 38, 37},
    {44, 43, 18, 17},
    {45, 44, 42, 41},
    {46, 45, 26, 25},
    {47, 42},
    {48, 47, 21, 20},
    {49, 40},
    {50, 49, 24, 23},
    {51, 50, 36, 35},
    {52, 49},
    {53, 52, 38, 37},
    {54, 53, 18, 17},
    {55, 31},
    {56, 55, 35, 34},
    {57, 50},
    {58, 39},
    {59, 58, 38, 37},
    {60, 59},
    {61, 60, 46, 45},
    {62, 61, 6, 5},
    {63, 62},
    {64, 63, 61, 60},
    {65, 47},
    {66, 65, 57, 56},
    {67, 66, 58, 57},
    {68, 59},
    {69, 67, 42, 40},
    {70, 69, 55, 54},
    {71, 65},
    {72, 66, 25, 19},
    {73, 48},
    {74, 73, 59, 58},
    {75, 74, 65, 64},
    {76, 75, 41, 40},
    {77, 76, 47, 46},
    {78, 77, 59, 58},
    {79, 70},
    {80, 79, 43, 42},
    {81, 77},
    {82, 79, 47, 44},
    {83, 82, 38, 37},
    {84, 71},
    {85, 84, 58, 57},
    {86, 85, 74, 73},
    {87, 74},
    {88, 87, 17, 16},
    {89, 51},
    {90, 89, 72, 71},
    {91, 90, 8, 7},
    {92, 91, 80, 79},
    {93, 91},
    {94, 73},
    {95, 84},
    {96, 94, 49, 47},
    {97, 91},
    {98, 87},
    {99, 97, 54, 52},
    {100, 63},
    {101, 100, 95, 94},
    {102, 101, 26, 25},
    {103, 94},
    {104, 103, 94, 93},
    {105, 89},
    {106, 91},
    {107, 105, 44, 42},
    {108, 77},
    {109, 108, 103, 102},
    {110, 109, 98, 97},
    {111, 101},
    {112, 110, 69, 67},
    {113, 104},
    {114, 113, 33, 32},
    {115, 114, 101, 100},
    {116, 115, 46, 45},
    {117, 115, 99, 97},
    {118, 85},
    {119, 111},
    {120, 113, 9, 2},
    {121, 103},
    {122, 121, 63, 62},
    {123, 121},
    {124, 87},
    {125, 124, 18, 17},
    {126, 125, 90, 89},
    {127, 126},
    {128, 126, 101, 99},
    {129, 124},
    {130, 127},
    {131, 130, 84, 83},
    {132, 103},
    {133, 132, 82, 81},
    {134, 77},
    {135, 124},
    {136, 135, 11, 10},
    {137, 116},
    {138, 137, 131, 130},
    {139, 136, 134, 131},
    {140, 111},
    {141, 140, 110, 109},
    {142, 121},
    {143, 142, 123, 122},
    {144, 143, 75, 74},
    {145, 93},
    {146, 145, 87, 86},
    {147, 146, 110, 109},
    {148, 121},
    {149, 148, 40, 39},
    {150, 97},
    {151, 148},
    {152, 151, 87, 86},
    {153, 152},
    {154, 152, 27, 25},
    {155, 154, 124, 123},
    {156, 155, 41, 40},
    {157, 156, 131, 130},
    {158, 157, 132, 131},
    {159, 128},
    {160, 159, 142, 141},
    {161, 143},
    {162, 161, 75, 74},
    {163, 162, 104, 103},
    {164, 163, 151, 150},
    {165, 164, 135, 134},
    {166, 165, 128, 127},
    {167, 161},
    {168, 166, 153, 151}
  }

  @doc "Die Taps für N Bits (1 ≤ N ≤ 168), höchster zuerst."
  def taps(n) when n in 1..@max, do: Tuple.to_list(elem(@taps, n - 1))

  @masks @taps
         |> Tuple.to_list()
         |> Enum.map(fn ts ->
           ts |> Tuple.to_list() |> Enum.reduce(0, &(&2 ||| 1 <<< (&1 - 1)))
         end)
         |> List.to_tuple()

  @doc "Die Galois-Maske für N Bits."
  def mask(n), do: elem(@masks, n - 1)

  @doc "Das voreingestellte K: das kleinste K ≥ N, teilerfremd zu 2^N−1."
  def default_step(n),
    do: Enum.find(Stream.iterate(n, &(&1 + 1)), &(Integer.gcd(&1, (1 <<< n) - 1) == 1))

  defbuiltin "lfsr_make", [seed, n, st] do
    nb = bits!(deref(n))
    make(seed!(deref(seed), nb), nb, default_step(nb), st)
  end

  defbuiltin "lfsr_make", [seed, n, k, st] do
    nb = bits!(deref(n))
    sd = seed!(deref(seed), nb)
    kk = int!(deref(k))
    if kk < 1 or Integer.gcd(kk, (1 <<< nb) - 1) != 1, do: Error.domain!("lfsr_step", kk)
    make(sd, nb, kk, st)
  end

  defbuiltin "lfsr_next", [st0, x, st] do
    case next(state!(deref(st0), ctx)) do
      :no -> :fail
      {x1, st1} -> {:unify, [{x, x1}, {st, st1}]}
    end
  end

  defbuiltin "lfsr_done", [st] do
    if done?(state!(deref(st), ctx)), do: :ok, else: :fail
  end

  defp make(sd, n, k, st), do: {:unify, [{st, PrologEx.mk("st", [sd, n, 0, k])}]}

  # --- Schritte -------------------------------------------------------------------

  @doc "K Schritte von S aus (N Bits)."
  def steps(s, n, k) when k <= 2, do: loop(s, mask(n), k)
  def steps(s, n, k), do: apply_table(table(n, k), s, 0, 0)

  @doc false
  def loop_steps(s, n, k), do: loop(s, mask(n), k)

  defp loop(s, _m, 0), do: s
  defp loop(s, m, k) when (s &&& 1) == 1, do: loop(bxor(s >>> 1, m), m, k - 1)
  defp loop(s, m, k), do: loop(s >>> 1, m, k - 1)

  # K Schritte sind linear über GF(2): eine N×N-Matrix, hier als Tabelle
  # je 8 Bits des Zustands (256 XOR-Kombinationen der Spalten); ein Sprung
  # sind dann ⌈N/8⌉ Nachschläge und XOR
  defp apply_table(_t, 0, _i, acc), do: acc

  defp apply_table(t, s, i, acc),
    do: apply_table(t, s >>> 8, i + 1, bxor(acc, elem(elem(t, i), s &&& 255)))

  defp table(n, k) do
    key = {__MODULE__, n, k}

    case :persistent_term.get(key, nil) do
      nil ->
        one = List.to_tuple(for i <- 0..(n - 1), do: loop(1 <<< i, mask(n), 1))
        cols = mpow(one, k)

        t =
          cols
          |> Tuple.to_list()
          |> Enum.chunk_every(8)
          |> Enum.map(&byte_table/1)
          |> List.to_tuple()

        :persistent_term.put(key, t)
        t

      t ->
        t
    end
  end

  # t[b] = t[b ohne niedrigstes Bit] XOR Spalte des niedrigsten Bits
  defp byte_table(cols) do
    cs = List.to_tuple(cols ++ List.duplicate(0, 8 - length(cols)))

    Enum.reduce(1..255, %{0 => 0}, fn b, acc ->
      low = b &&& -b
      Map.put(acc, b, bxor(acc[b - low], elem(cs, low_bit(low, 0))))
    end)
    |> then(fn m -> List.to_tuple(for b <- 0..255, do: m[b]) end)
  end

  defp low_bit(1, i), do: i
  defp low_bit(b, i), do: low_bit(b >>> 1, i + 1)

  # Spalten (Bild von Bit i) von A^K
  defp mpow(a, 1), do: a

  defp mpow(a, k) do
    h = mpow(a, div(k, 2))
    hh = compose(h, h)
    if rem(k, 2) == 1, do: compose(a, hh), else: hh
  end

  # (A∘B) e_i = A(B e_i)
  defp compose(a, b),
    do: b |> Tuple.to_list() |> Enum.map(&apply_cols(a, &1, 0, 0)) |> List.to_tuple()

  defp apply_cols(_m, 0, _i, acc), do: acc

  defp apply_cols(m, s, i, acc) when (s &&& 1) == 1,
    do: apply_cols(m, s >>> 1, i + 1, bxor(acc, elem(m, i)))

  defp apply_cols(m, s, i, acc), do: apply_cols(m, s >>> 1, i + 1, acc)

  # --- Prüfungen ------------------------------------------------------------------

  defp int!(t) do
    case t do
      i when is_integer(i) -> i
      {:var, _} -> Error.instantiation!()
      other -> Error.type!("integer", PrologEx.unmark(other))
    end
  end

  defp bits!(n) do
    nb = int!(n)
    if nb < 1 or nb > @max, do: Error.domain!("lfsr_bits", nb)
    nb
  end

  defp seed!(seed, n) do
    sd = int!(seed)
    if sd < 1 or sd > (1 <<< n) - 1, do: Error.domain!("lfsr_seed", sd)
    sd
  end

  defp state!(st, ctx) do
    case fields(st, ctx.subst) do
      :var -> Error.instantiation!()
      :bad -> Error.type!("lfsr", PrologEx.resolve(st, ctx.subst))
      f -> f
    end
  end

  @doc """
  Die Felder eines Zustands (schon dereferenziert): `{S, N, Gezogen, K}`,
  `:var` (ungebunden) oder `:bad` (kein st/4 aus Ganzzahlen mit
  1 ≤ N ≤ 168). Auch für den übersetzten Code (PrologEx.Jit.b_lfsr_next/1).
  """
  def fields({:var, _}, _subst), do: :var

  def fields(st, subst) do
    with {:struct, "st", [s, n, d, k]} <- PrologEx.unmark_top(st),
         s when is_integer(s) <- PrologEx.Store.walk(s, subst),
         n when is_integer(n) and n in 1..@max <- PrologEx.Store.walk(n, subst),
         d when is_integer(d) <- PrologEx.Store.walk(d, subst),
         k when is_integer(k) <- PrologEx.Store.walk(k, subst) do
      {s, n, d, k}
    else
      _ -> :bad
    end
  end

  @doc "Ein Schritt von lfsr_next/3 auf den Feldern: `{X, St}` oder `:no`."
  def next({s, n, d, k}) do
    if d >= (1 <<< n) - 1 do
      :no
    else
      x = steps(s, n, k)
      {x, PrologEx.mk("st", [x, n, d + 1, k])}
    end
  end

  @doc "lfsr_done/1 auf den Feldern."
  def done?({_, n, d, _}), do: d >= (1 <<< n) - 1
end
