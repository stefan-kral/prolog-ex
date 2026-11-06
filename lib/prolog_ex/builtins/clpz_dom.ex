defmodule PrologEx.Builtins.ClpzDom do
  @moduledoc """
  Domänen von clpz als kanonische Liste maximaler Intervalle.

  Eine Domäne ist eine Liste von Paaren `{Von, Bis}` mit `Von =< Bis`;
  `Von` ist eine ganze Zahl oder `:inf`, `Bis` eine ganze Zahl oder
  `:sup`. Die Liste ist aufsteigend sortiert, die Intervalle sind
  disjunkt und nicht benachbart (zwischen `Bis` und dem nächsten `Von`
  liegt mindestens eine Zahl). Damit hat jede Menge genau eine
  Darstellung: `[]` ist die leere Domäne, `[{:inf, :sup}]` sind alle
  ganzen Zahlen, ein Punkt ist `{x, x}`.

  Als Prolog-Term (siehe `to_term/1`, `from_term/1`) ist das
  `[inf..3, 5, 9..13, 16..sup]`: Intervalle als `Von..Bis`, Punkte als
  Zahl, also die Schreibweise der Domänen (`drep`) von clpz als Liste.

  Die Mengenoperationen (Schnitt, Vereinigung, Differenz, Komplement,
  Entfernen, Enthalten, Teilmenge) sind exakt. Die Operationen für
  `ptimes` (`expand/2`, `expand_more/2`, `contract/2`, `contract_less/2`)
  rechnen wie das Original intervallweise mit den Schranken – das sind
  bewusste Näherungen (Obermengen), die so bleiben müssen, damit die
  Propagation dieselben Ergebnisse liefert wie clpz in Scryer.

  Alles hier ist rein; die Builtins in `PrologEx.Builtins.ClpzPrims`
  übersetzen zwischen Prolog-Termen und diesen Listen.
  """

  @type bound :: integer | :inf | :sup
  @type t :: [{bound, bound}]

  # --- Schranken ---------------------------------------------------------

  defp rank(:inf), do: 0
  defp rank(:sup), do: 2
  defp rank(_), do: 1

  @doc false
  def lt(a, b) when is_integer(a) and is_integer(b), do: a < b
  def lt(a, b), do: rank(a) < rank(b)
  @doc false
  def leq(a, b) when is_integer(a) and is_integer(b), do: a <= b
  def leq(a, b), do: not lt(b, a)

  defp bmin(a, b), do: if(lt(b, a), do: b, else: a)
  defp bmax(a, b), do: if(lt(a, b), do: b, else: a)

  defp plus(:inf, _), do: :inf
  defp plus(:sup, _), do: :sup
  defp plus(_, :sup), do: :sup
  defp plus(_, :inf), do: :inf
  defp plus(a, b), do: a + b

  defp minus(:inf, _), do: :inf
  defp minus(:sup, _), do: :sup
  defp minus(_, :inf), do: :sup
  defp minus(_, :sup), do: :inf
  defp minus(a, b), do: a - b

  defp uminus(:inf), do: :sup
  defp uminus(:sup), do: :inf
  defp uminus(a), do: -a

  # cis_times: m ist hier immer eine positive Zahl
  defp times(:inf, _m), do: :inf
  defp times(:sup, _m), do: :sup
  defp times(a, m), do: a * m

  # cis_slash: m positiv; Prolog // (zur Null hin)
  defp slash(:inf, _m), do: :inf
  defp slash(:sup, _m), do: :sup
  defp slash(a, m), do: div(a, m)

  # --- Konstruktion ------------------------------------------------------

  @doc "Die leere Domäne"
  def empty, do: []

  @doc "Alle ganzen Zahlen"
  def all, do: [{:inf, :sup}]

  @doc "Das Intervall l..u (leer, wenn l > u oder eine Schranke falsch herum unendlich ist)"
  def interval(l, u) do
    if leq(l, u) and l != :sup and u != :inf, do: [{l, u}], else: []
  end

  @doc "Der Punkt x"
  def point(x) when is_integer(x), do: [{x, x}]

  @doc """
  Aus beliebigen Intervallen (ungeordnet, überlappend, auch leer oder falsch
  herum): die kanonische Liste
  """
  def from_intervals(ivs) do
    ivs
    |> Enum.flat_map(fn {l, u} -> interval(l, u) end)
    |> Enum.sort(&leq(elem(&1, 0), elem(&2, 0)))
    |> merge([])
  end

  # sortierte Intervalle zusammenfassen (überlappend oder benachbart)
  defp merge([], acc), do: Enum.reverse(acc)
  defp merge([iv | rest], []), do: merge(rest, [iv])

  defp merge([{l, u} | rest], [{l0, u0} | acc]) do
    if adjacent_or_overlapping?(u0, l),
      do: merge(rest, [{l0, bmax(u0, u)} | acc]),
      else: merge(rest, [{l, u}, {l0, u0} | acc])
  end

  # u0 = sup (dann gibt es kein weiteres Intervall), oder l =< u0 + 1
  defp adjacent_or_overlapping?(:sup, _l), do: true
  defp adjacent_or_overlapping?(u0, l), do: leq(l, u0 + 1)

  @doc "Aus einer Liste ganzer Zahlen (unsortiert, mit Dubletten)"
  def from_list(ns), do: from_intervals(Enum.map(ns, &{&1, &1}))

  @doc "Ist das eine kanonische Domäne?"
  def valid?([]), do: true

  def valid?([{l, u} | rest]) do
    is_bound?(l) and is_bound?(u) and l != :sup and u != :inf and leq(l, u) and
      valid_rest?(u, rest)
  end

  def valid?(_), do: false

  defp valid_rest?(_, []), do: true

  defp valid_rest?(u0, [{l, u} | rest]) do
    is_integer(u0) and is_bound?(l) and is_bound?(u) and l != :inf and u != :inf and
      is_integer(l) and l > u0 + 1 and leq(l, u) and valid_rest?(u, rest)
  end

  defp is_bound?(b), do: is_integer(b) or b in [:inf, :sup]

  # --- Abfragen ----------------------------------------------------------

  @doc "Untere Schranke (nil für die leere Domäne)"
  def infimum([]), do: nil
  def infimum([{l, _} | _]), do: l

  @doc "Obere Schranke (nil für die leere Domäne)"
  def supremum([]), do: nil
  def supremum(d), do: elem(List.last(d), 1)

  @doc "Anzahl der Elemente (:sup, wenn unendlich)"
  def num_elements(d) do
    Enum.reduce(d, 0, fn {l, u}, n -> plus(n, plus(minus(u, l), 1)) end)
  end

  @doc "Enthält die Domäne die Zahl x?"
  def contains?(d, x) when is_integer(x), do: contains_(d, x)

  # (aufsteigend: hinter einem Intervall, das über x beginnt, kommt nichts mehr)
  defp contains_([], _x), do: false

  defp contains_([{l, u} | rest], x) do
    cond do
      lt(x, l) -> false
      leq(x, u) -> true
      true -> contains_(rest, x)
    end
  end

  @doc "Genau ein Element? Dann {:ok, x}"
  def singleton([{x, x}]) when is_integer(x), do: {:ok, x}
  def singleton(_), do: :error

  @doc """
  Ist sub eine Teilmenge von d? Für d = [] falsch, auch bei sub = []
  (domain_subdomain/2 des Originals hat keine Klausel für empty)
  """
  def subdomain?([], _sub), do: false

  def subdomain?(d, sub) do
    Enum.all?(sub, fn {l, u} -> Enum.any?(d, fn {l0, u0} -> leq(l0, l) and leq(u, u0) end) end)
  end

  @doc "Die Intervalle als Liste von {Von, Bis}"
  def intervals(d), do: d

  @doc "Alle Elemente aufsteigend; :error, wenn unendlich"
  def to_list(d) do
    if Enum.all?(d, fn {l, u} -> is_integer(l) and is_integer(u) end),
      do: {:ok, Enum.flat_map(d, fn {l, u} -> Enum.to_list(l..u//1) end)},
      else: :error
  end

  @doc """
  domain_smallest_finite/2: die untere Schranke des ersten Intervalls, oder
  dessen obere, wenn die untere inf ist – wie das Original, also für
  inf..sup auch sup (nil nur für die leere Domäne)
  """
  def smallest_finite([]), do: nil
  def smallest_finite([{:inf, u} | _]), do: u
  def smallest_finite([{l, _} | _]), do: l

  @doc "domain_largest_finite/2 (siehe smallest_finite/1; für inf..sup inf)"
  def largest_finite([]), do: nil

  def largest_finite(d) do
    case List.last(d) do
      {l, :sup} -> l
      {_, u} -> u
    end
  end

  @doc "domain_spread/2: größte minus kleinste endliche Schranke (nil für die leere Domäne)"
  def spread([]), do: nil
  def spread(d), do: minus(largest_finite(d), smallest_finite(d))

  # --- Mengenoperationen -------------------------------------------------

  # Die Liste ist aufsteigend: Die drei Operationen hier laufen nur bis zu
  # der Stelle, die sich ändert, und übernehmen den Rest unverändert (statt
  # ihn Intervall für Intervall zu kopieren). Kommt x nicht vor, ist das
  # Ergebnis die Domäne selbst.

  @doc "Ohne die Zahl x"
  def remove(d, x) when is_integer(x) do
    case remove_(d, x) do
      :same -> d
      d1 -> d1
    end
  end

  defp remove_([], _x), do: :same

  defp remove_([{l, u} = iv | rest], x) do
    cond do
      lt(x, l) ->
        :same

      lt(u, x) ->
        case remove_(rest, x) do
          :same -> :same
          rest -> [iv | rest]
        end

      l == x and u == x ->
        rest

      l == x ->
        [{x + 1, u} | rest]

      u == x ->
        [{l, x - 1} | rest]

      true ->
        [{l, x - 1}, {x + 1, u} | rest]
    end
  end

  @doc "Nur die Elemente =< g"
  def remove_greater_than(d, g) when is_integer(g), do: rgt(d, g)

  defp rgt([], _g), do: []

  defp rgt([{l, u} = iv | rest], g) do
    cond do
      lt(g, l) -> []
      leq(u, g) -> [iv | rgt(rest, g)]
      true -> [{l, g}]
    end
  end

  @doc "Nur die Elemente >= v"
  def remove_smaller_than(d, v) when is_integer(v), do: rst(d, v)

  defp rst([], _v), do: []

  defp rst([{l, u} | rest] = d, v) do
    cond do
      lt(u, v) -> rst(rest, v)
      leq(v, l) -> d
      true -> [{v, u} | rest]
    end
  end

  @doc "Schnitt"
  def intersection(d1, d2), do: isect(d1, d2, [])

  defp isect([], _, acc), do: Enum.reverse(acc)
  defp isect(_, [], acc), do: Enum.reverse(acc)

  defp isect([{l1, u1} | r1] = d1, [{l2, u2} | r2] = d2, acc) do
    l = bmax(l1, l2)
    u = bmin(u1, u2)
    acc = if leq(l, u), do: [{l, u} | acc], else: acc
    # das Intervall mit der kleineren oberen Schranke ist erledigt
    if lt(u1, u2), do: isect(r1, d2, acc), else: isect(d1, r2, acc)
  end

  @doc "Vereinigung"
  def union(d1, d2), do: d1 |> Kernel.++(d2) |> from_intervals()

  @doc "Komplement (alle ganzen Zahlen außer d)"
  def complement([]), do: all()

  def complement(d) do
    {acc, from} =
      Enum.reduce(d, {[], :inf}, fn {l, u}, {acc, from} ->
        acc =
          case {from, l} do
            {:inf, :inf} -> acc
            {from, l} -> [{from, minus(l, 1)} | acc]
          end

        {acc, if(u == :sup, do: nil, else: u + 1)}
      end)

    case from do
      nil -> Enum.reverse(acc)
      from -> Enum.reverse([{from, :sup} | acc])
    end
  end

  @doc "Differenz d ohne sub"
  def subtract(d, sub), do: intersection(d, complement(sub))

  # --- Arithmetik (für ptimes, pplus) --------------------------------------

  @doc "Um o verschoben"
  def shift(d, o) when is_integer(o), do: Enum.map(d, fn {l, u} -> {plus(l, o), plus(u, o)} end)

  @doc "Gespiegelt (−x)"
  def negate(d), do: d |> Enum.reverse() |> Enum.map(fn {l, u} -> {uminus(u), uminus(l)} end)

  # negatives m: erst spiegeln, dann mit |m|
  defp neg_abs(d, m) when m < 0, do: {negate(d), -m}
  defp neg_abs(d, m), do: {d, m}

  @doc """
  domain_expand/3: jedes Intervall l..u wird l·m..u·m (eine Obermenge der
  Vielfachen, wie im Original)
  """
  def expand(d, 1), do: d

  def expand(d, m) when is_integer(m) do
    {d, m} = neg_abs(d, m)
    d |> Enum.map(fn {l, u} -> {times(l, m), times(u, m)} end) |> from_intervals()
  end

  @doc """
  domain_expand_more/3: l..u wird zur Menge aller x mit x // m in l..u
  (für die Rückrichtung von ptimes)
  """
  def expand_more(d, m) when is_integer(m) do
    {d, m} = neg_abs(d, m)

    d
    |> Enum.map(fn {l0, u0} ->
      l = if leq(l0, 0), do: plus(times(minus(l0, 1), m), 1), else: times(l0, m)
      u = if lt(u0, 0), do: times(u0, m), else: minus(times(plus(u0, 1), m), 1)
      {l, u}
    end)
    |> from_intervals()
  end

  @doc """
  domain_contract/3: l..u wird (zur Null hin gerundet) ⌈l/m⌉..⌊u/m⌋, also
  die Zahlen, deren m-faches in l..u liegt; m ≠ 0
  """
  def contract(d, m) when is_integer(m) and m != 0 do
    {d, m} = neg_abs(d, m)

    d
    |> Enum.map(fn {l0, u0} ->
      l = if leq(0, l0), do: slash(minus(plus(l0, m), 1), m), else: slash(l0, m)
      u = if leq(0, u0), do: slash(u0, m), else: slash(plus(minus(u0, m), 1), m)
      {l, u}
    end)
    |> from_intervals()
  end

  @doc "domain_contract_less/3: l..u wird l//m..u//m; m ≠ 0"
  def contract_less(d, m) when is_integer(m) and m != 0 do
    {d, m} = neg_abs(d, m)
    d |> Enum.map(fn {l, u} -> {slash(l, m), slash(u, m)} end) |> from_intervals()
  end

  # --- Prolog-Term ---------------------------------------------------------

  import PrologEx, only: [mk: 2, a: 1]

  @doc "Als Prolog-Term: [inf..3, 5, 9..13, 16..sup]"
  def to_term(d) do
    Enum.map(d, fn
      {x, x} -> x
      {l, u} -> mk("..", [bt(l), bt(u)])
    end)
  end

  defp bt(:inf), do: a("inf")
  defp bt(:sup), do: a("sup")
  defp bt(i), do: i

  @doc """
  Aus einem (aufgelösten) Prolog-Term; {:ok, d} oder :error, wenn es
  keine kanonische Domäne ist
  """
  def from_term(t) do
    with {:ok, ivs} <- items(t, []),
         true <- valid?(ivs) do
      {:ok, ivs}
    else
      _ -> :error
    end
  end

  defp items([], acc), do: {:ok, Enum.reverse(acc)}
  defp items([h | t], acc) when is_integer(h), do: items(t, [{h, h} | acc])

  defp items([{tag, "..", [l, u]} | t], acc) when tag in [:struct, :gstruct] do
    # (ein Punkt steht als Zahl, nie als X..X)
    with lb when lb != nil <- tb(l),
         ub when ub != nil and ub != lb <- tb(u),
         do: items(t, [{lb, ub} | acc]),
         else: (_ -> :error)
  end

  defp items(_, _), do: :error

  defp tb(i) when is_integer(i), do: i
  defp tb({:atom, "inf"}), do: :inf
  defp tb({:atom, "sup"}), do: :sup
  defp tb(_), do: nil
end
