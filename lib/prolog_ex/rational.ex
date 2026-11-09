defmodule PrologEx.Rational do
  @moduledoc """
  Rationale Zahlen (wie SWI): `{:rat, Zähler, Nenner}`, immer gekürzt,
  Nenner > 1 – ein Bruch mit Nenner 1 ist die Ganzzahl selbst. So ist die
  Darstellung eindeutig, und Gleichheit (Unifikation, `==`, Hashing) braucht
  keine Sonderbehandlung.

  Geschrieben und gelesen als `1r3` bzw. `-1r3` (SWI); gelesen wird auch
  `1 rdiv 3` (Scryer schreibt so) – das ist aber ein Term, der erst beim
  Auswerten zur Zahl wird.

  Rechnen: Ganzzahlen und Brüche bleiben exakt (`+ - * /` mit einem Bruch,
  `rdiv`, `^`/`**` mit ganzzahligem Exponenten); ein Float macht alles zum
  Float. Vergleiche in Ausdrücken über Float, wenn ein Float beteiligt ist,
  sonst exakt. Standardordnung: Float < (Ganzzahl und Bruch nach Wert).
  """

  import Bitwise
  import Kernel, except: [floor: 1, abs: 1]
  alias PrologEx.Error

  defguard is_rat(t) when is_tuple(t) and tuple_size(t) == 3 and elem(t, 0) == :rat

  @doc "n/d gekürzt: Ganzzahl oder `{:rat, n, d}` (d == 0: zero_divisor)"
  def make(_n, 0), do: Error.evaluation!("zero_divisor")
  def make(n, d) when d < 0, do: make(-n, -d)

  def make(n, d) do
    g = Integer.gcd(n, d)
    {n, d} = if g == 1, do: {n, d}, else: {div(n, g), div(d, g)}
    if d == 1, do: n, else: {:rat, n, d}
  end

  @doc "Zähler und Nenner einer Ganzzahl oder eines Bruchs"
  def parts(n) when is_integer(n), do: {n, 1}
  def parts({:rat, n, d}), do: {n, d}

  # --- Rechnen (Ganzzahl oder Bruch) ---------------------------------------

  def add(x, y), do: op2(x, y, fn a, b, c, d -> make(a * d + c * b, b * d) end)
  def sub(x, y), do: op2(x, y, fn a, b, c, d -> make(a * d - c * b, b * d) end)
  def mul(x, y), do: op2(x, y, fn a, b, c, d -> make(a * c, b * d) end)
  def divide(x, y), do: op2(x, y, fn a, b, c, d -> make(a * d, b * c) end)

  defp op2(x, y, f) do
    {a, b} = parts(x)
    {c, d} = parts(y)
    f.(a, b, c, d)
  end

  def neg({:rat, n, d}), do: {:rat, -n, d}
  def neg(n), do: -n

  def abs({:rat, n, d}), do: {:rat, Kernel.abs(n), d}
  def abs(n), do: Kernel.abs(n)

  def sign({:rat, n, _}), do: sign(n)
  def sign(n) when n > 0, do: 1
  def sign(n) when n < 0, do: -1
  def sign(_), do: 0

  @doc "x hoch e (e ganz; x == 0 und e < 0: undefined wie bei Ganzzahlen)"
  def pow(x, e) when e >= 0 do
    {n, d} = parts(x)
    make(Integer.pow(n, e), Integer.pow(d, e))
  end

  def pow(x, e) do
    if x == 0, do: Error.evaluation!("undefined")
    {n, d} = parts(x)
    make(Integer.pow(d, -e), Integer.pow(n, -e))
  end

  @doc "exakter Vergleich zweier Ganzzahlen/Brüche: :lt | :eq | :gt"
  def cmp(x, y) do
    {a, b} = parts(x)
    {c, d} = parts(y)
    l = a * d
    r = c * b

    cond do
      l < r -> :lt
      l > r -> :gt
      true -> :eq
    end
  end

  def floor({:rat, n, d}), do: Integer.floor_div(n, d)
  def floor(n), do: n
  def ceiling({:rat, n, d}), do: -Integer.floor_div(-n, d)
  def ceiling(n), do: n
  def truncate({:rat, n, d}), do: div(n, d)
  def truncate(n), do: n
  # floor(x + 1/2) wie round/1 für Floats hier (ISO)
  def round_iso({:rat, n, d}), do: Integer.floor_div(2 * n + d, 2 * d)
  def round_iso(n), do: n
  # Hälften weg von 0 (integer/1, wie für Floats)
  def round_away({:rat, n, d}) when n < 0, do: -round_away({:rat, -n, d})
  def round_away({:rat, n, d}), do: div(2 * n + d, 2 * d)
  def round_away(n), do: n

  # --- Float --------------------------------------------------------------

  @doc """
  Nächster Float (korrekt für alle Größen: nicht n/d, das große Zähler und
  Nenner einzeln umwandelte). Zu groß: float_overflow.
  """
  def to_float({:rat, n, d}) when n < 0, do: -to_float({:rat, -n, d})

  def to_float({:rat, n, d}) do
    # beide exakt als Float darstellbar: die Division rundet korrekt
    if n < 1 <<< 53 and d < 1 <<< 53 do
      n / d
    else
      # Quotient mit mindestens 55 Bits und Haftbit (Rest != 0), dann selbst
      # auf 53 Bits runden (auf das Runden beim Umwandeln großer Ganzzahlen
      # ist kein Verlass) – die Mantisse ist danach exakt ein Float
      k = bitlen(n) - bitlen(d) - 56
      {q, r} = if k >= 0, do: divrem(n, d <<< k), else: divrem(n <<< -k, d)
      sh = bitlen(q) - 53
      mant = q >>> sh
      low = q &&& (1 <<< sh) - 1
      half = 1 <<< (sh - 1)

      mant =
        cond do
          low > half -> mant + 1
          low == half and (r != 0 or (mant &&& 1) == 1) -> mant + 1
          true -> mant
        end

      scale(mant, k + sh)
    end
  end

  def to_float(n), do: n * 1.0

  defp divrem(a, b), do: {div(a, b), rem(a, b)}

  # m * 2^k als Float (m hat höchstens 54 Bits: exakt)
  defp scale(m, k) when k >= 0 do
    m * :math.pow(2, k)
  rescue
    ArithmeticError -> Error.evaluation!("float_overflow")
  end

  defp scale(m, k) when k >= -1000, do: m / :math.pow(2, -k)
  defp scale(m, k), do: scale(m, k + 1000) / :math.pow(2, 1000)

  # Anzahl der Bits (x > 0)
  defp bitlen(x) do
    <<first, _::binary>> = bin = :binary.encode_unsigned(x)
    (byte_size(bin) - 1) * 8 + byte_len(first, 0)
  end

  defp byte_len(0, n), do: n
  defp byte_len(b, n), do: byte_len(b >>> 1, n + 1)

  @doc "rational/1: der exakte Wert eines Floats"
  def from_float(f) when is_float(f) do
    <<s::1, e::11, m::52>> = <<f::float>>

    {mant, exp} =
      cond do
        e == 0 -> {m, -1074}
        true -> {m ||| 1 <<< 52, e - 1075}
      end

    mant = if s == 1, do: -mant, else: mant
    if exp >= 0, do: mant <<< exp, else: make(mant, 1 <<< -exp)
  end

  @doc """
  rationalize/1: der einfachste Bruch, der als Float wieder f ergibt
  (Kettenbruch des exakten Werts, bis ein Näherungsbruch passt)
  """
  def rationalize(f) when is_float(f) do
    case from_float(f) do
      n when is_integer(n) -> n
      {:rat, n, d} -> convergent(n, d, f, {1, 0}, {0, 1})
    end
  end

  # Näherungsbrüche h/k von n/d (Euklid); der erste, der f trifft
  defp convergent(n, d, f, {h1, k1}, {h2, k2}) do
    a = Integer.floor_div(n, d)
    h = a * h1 + h2
    k = a * k1 + k2
    r = make(h, k)

    if r_float(r) == f or n - a * d == 0,
      do: r,
      else: convergent(d, n - a * d, f, {h, k}, {h1, k1})
  end

  defp r_float(n) when is_integer(n), do: n * 1.0
  defp r_float(r), do: to_float(r)

  @doc """
  Der einfachste Bruch im geschlossenen Intervall [lo, hi] (Ganzzahlen oder
  Brüche, lo =< hi): kleinster Nenner, bei gleichem Nenner der kleinste
  Betrag – derselbe, den der Stern-Brocot-Baum zuerst träfe, nur über
  Kettenbrüche gerechnet (Schritte: Länge des Kettenbruchs, nicht Summe
  seiner Glieder).
  """
  def simplest(lo, hi) do
    cond do
      cmp(lo, 0) != :gt and cmp(hi, 0) != :lt -> 0
      cmp(hi, 0) == :lt -> neg(simplest(neg(hi), neg(lo)))
      true -> simplest_pos(lo, hi)
    end
  end

  # 0 < lo =< hi
  defp simplest_pos(lo, hi) do
    f = floor(lo)

    cond do
      # lo ganz: die kleinste Ganzzahl darin
      cmp(lo, f) == :eq -> f
      # eine Ganzzahl dazwischen: die kleinste
      floor(hi) > f -> f + 1
      # gleicher ganzzahliger Teil: f + 1/x mit x einfachst in [1/(hi-f), 1/(lo-f)]
      true -> add(f, divide(1, simplest_pos(divide(1, sub(hi, f)), divide(1, sub(lo, f)))))
    end
  end

  # --- Standardordnung --------------------------------------------------------

  @doc """
  Sortierschlüssel einer Ganzzahl oder eines Bruchs, nach Wert wie die
  Erlang-Ordnung: Ganzzahl x → {1, 1, x, 0}; Bruch → {1, 1, floor, K}
  mit K aus dem Kettenbruch des Nachkommateils [0; a1, a2, …] als Liste
  [-a1, a2, -a3, …] (ungerade Stellen negiert: dort heißt größer kleiner),
  und – wenn die nächste Stelle gerade wäre – dem Atom :inf am Ende (ein
  abgebrochener Kettenbruch hat dort ∞). Eine Liste ist größer als jede
  Zahl, also liegt der Bruch hinter der Ganzzahl gleichen Bodens.
  """
  def sort_key({:rat, n, d}) do
    f = Integer.floor_div(n, d)
    {1, 1, f, cf_key(d, n - f * d, 1, [])}
  end

  # Nachkommateil r/d (0 < r < d): 1/(r/d) = d/r = a + (d rem r)/r
  defp cf_key(d, r, pos, acc) do
    a = div(d, r)
    e = if rem(pos, 2) == 1, do: -a, else: a
    acc = [e | acc]

    case rem(d, r) do
      0 -> Enum.reverse(if rem(pos + 1, 2) == 0, do: [:inf | acc], else: acc)
      m -> cf_key(r, m, pos + 1, acc)
    end
  end

  # --- Text ---------------------------------------------------------------

  @doc "Text eines Bruchs: 1r3, -1r3"
  def to_string({:rat, n, d}), do: Integer.to_string(n) <> "r" <> Integer.to_string(d)
end
