defmodule PrologEx.Jit.Excl do
  @moduledoc false
  # Ausschließlichkeit der Klauseln (PrologEx.Jit): deterministisch
  # übersetzt wird nur, was sich nachweislich ausschließt.

  alias PrologEx.Jit.Util

  # auf Ganzzahlen fehlerfrei
  @total2 ~w(+ - * min max /\\ \\/ xor gcd)
  @total1 ~w(- + abs sign \\)

  # --- Ausschließlichkeit -------------------------------------------------

  # Je Paar geprüft – quadratisch. Große Tabellen von Fakten haben meist
  # eine Stelle mit lauter verschiedenen Konstanten (Schlüssel): das reicht
  # (dann unterscheiden sich je zwei dort); sonst ab @max_pairwise
  # Klauseln nicht übersetzen (49 151 Sudoku-Fakten brauchten 20 Minuten)
  @max_pairwise 300
  def exclusive!(irs, num) do
    cond do
      key_column?(irs) -> :ok
      length(irs) > @max_pairwise -> Util.no!("mehr als #{@max_pairwise} Klauseln ohne Schlüssel")
      true -> exclusive_pairs!(irs, num)
    end
  end

  defp key_column?([_, _ | _] = irs) do
    hins = Enum.map(irs, &eff_hin/1)
    n = length(irs)

    hins
    |> Enum.zip()
    |> Enum.any?(fn col ->
      ps = Tuple.to_list(col)

      Enum.all?(ps, &match?({_, {:const, _}}, &1)) and
        map_size(Map.new(ps, fn {_, {:const, c}} -> {c, true} end)) == n
    end)
  end

  defp key_column?(_), do: false

  defp exclusive_pairs!(irs, num) do
    pairs =
      for {a, i} <- Enum.with_index(irs, 1),
          {b, j} <- Enum.with_index(irs, 1),
          i < j,
          do: {a, b, i, j}

    for {a, b, i, j} <- pairs,
        not exclusive?(a, b, num),
        do: Util.no!("Klauseln #{i} und #{j} schließen sich nicht nachweislich aus")

    :ok
  end

  # a vor b: hat a eine Lösung, scheitert b sicher (ohne Fehler davor)
  defp exclusive?(a, b, num) do
    :cut in a.goals or pats_differ?(a, b) or const_vs_guard?(a, b, num) or
      complementary?(a, b, num) or classes_differ?(a, b, num)
  end

  # Vergleiche, `=` und Typtests am Anfang des Rumpfs
  defp guards(c) do
    c.goals
    |> Enum.map(fn
      {:idx, g, _} -> g
      g -> g
    end)
    |> Enum.take_while(fn
      {:cmp, _, _, _} -> true
      {:u, _, _} -> true
      {:tt, _, _, _} -> true
      _ -> false
    end)
  end

  # Typklassen: was ein Argument nach Muster und Typtests am Anfang noch
  # sein kann; haben a und b an einer Stelle nichts gemeinsam, schließen
  # sie sich aus
  @all ~w(var int float rat nil atom cons struct bytes other)a
  defp classes_differ?(a, b, num) do
    ca = classes(a, guards(a))
    cb = classes(b, reachable(b, num))
    Enum.any?(Enum.zip(ca, cb), fn {x, y} -> MapSet.disjoint?(x, y) end)
  end

  defp classes(c, gs) do
    falsum = Enum.any?(gs, &match?({:tt, _, _, false}, &1))

    for {{_, mp0}, {_, mp}} <- Enum.zip(c.hin, eff_hin(c)) do
      base =
        case mp do
          {:const, n} when is_integer(n) -> [:int]
          {:const, n} when is_float(n) -> [:float]
          {:const, {:atom, _}} -> [:atom]
          :nl -> [nil]
          {:cons, _, _} -> [:cons]
          {:st, _, _} -> [:struct]
          _ -> @all
        end

      v = with {:bind, v} <- mp0, do: v

      gs
      |> Enum.reduce(MapSet.new(base), fn
        {:tt, t, ^v, how}, acc when how != true -> MapSet.intersection(acc, MapSet.new(tclass(t)))
        _, acc -> acc
      end)
      |> then(&if(falsum, do: MapSet.new(), else: &1))
    end
  end

  defp tclass("var"), do: [:var]
  defp tclass("nonvar"), do: @all -- [:var]
  defp tclass("integer"), do: [:int]
  defp tclass("float"), do: [:float]
  defp tclass("number"), do: [:int, :float, :rat]
  defp tclass("atom"), do: [nil, :atom]
  defp tclass("atomic"), do: [:int, :float, :rat, nil, :atom, :bytes]
  defp tclass("compound"), do: [:cons, :struct]
  defp tclass("callable"), do: [nil, :atom, :cons, :struct]
  defp tclass("is_list"), do: [nil, :cons]

  # die Wächter von b, die b erreicht, ohne dass einer davor werfen kann
  defp reachable(c, num) do
    Enum.reduce_while(guards(c), [], fn g, acc ->
      if safe?(g, num), do: {:cont, [g | acc]}, else: {:halt, [g | acc]}
    end)
    |> Enum.reverse()
  end

  defp safe?({:u, _, _}, _), do: true
  defp safe?({:tt, _, _, _}, _), do: true
  defp safe?({:cmp, _, x, y}, num), do: safe_ex?(x, num) and safe_ex?(y, num)

  defp safe_ex?(n, _) when is_number(n), do: true
  defp safe_ex?({:var, _}, _), do: true

  defp safe_ex?({:op2, op, a, b}, false) when op in @total2,
    do: safe_ex?(a, false) and safe_ex?(b, false)

  defp safe_ex?({:op1, op, a}, false) when op in @total1, do: safe_ex?(a, false)
  defp safe_ex?(_, _), do: false

  # Kopfeingaben, mit `V = Muster` am Anfang als Muster an V's Stelle (für
  # die Prüfung: Konstanten einheitlich {:const, c}, ohne {:num, _})
  defp eff_hin(c) do
    eqs = for {:u, {:var, _} = v, mp} <- guards(c), into: %{}, do: {v, unrt(mp)}

    Enum.map(c.hin, fn
      {k, {:bind, v}} = e -> if Map.has_key?(eqs, v), do: {k, eqs[v]}, else: e
      {k, mp} -> {k, unrt(mp)}
    end)
  end

  defp unrt({:constrt, c}), do: {:const, c}
  defp unrt({:num, m}), do: unrt(m)
  defp unrt({:cons, h, t}), do: {:cons, unrt(h), unrt(t)}
  defp unrt({:st, f, ms}), do: {:st, f, Enum.map(ms, &unrt/1)}
  defp unrt(m), do: m

  defp pats_differ?(a, b) do
    Enum.any?(Enum.zip(eff_hin(a), eff_hin(b)), fn {{k, x}, {k, y}} -> pat_differ?(x, y) end)
  end

  defp pat_differ?({:const, x}, {:const, y}), do: x !== y
  defp pat_differ?(:nl, {:cons, _, _}), do: true
  defp pat_differ?({:cons, _, _}, :nl), do: true

  defp pat_differ?({:cons, h1, t1}, {:cons, h2, t2}),
    do: pat_differ?(h1, h2) or pat_differ?(t1, t2)

  defp pat_differ?({:st, f, a}, {:st, g, b}),
    do:
      f != g or length(a) != length(b) or
        Enum.any?(Enum.zip(a, b), fn {x, y} -> pat_differ?(x, y) end)

  # eine Struktur gegen eine Konstante, [] oder eine Listenzelle ('.'/2
  # vorsichtshalber nicht)
  defp pat_differ?({:st, f, a}, x) when x == :nl or elem(x, 0) in [:const, :cons],
    do: not (f == "." and length(a) == 2 and x != :nl and elem(x, 0) == :cons)

  defp pat_differ?(x, {:st, _, _} = y) when x == :nl or elem(x, 0) in [:const, :cons],
    do: pat_differ?(y, x)

  defp pat_differ?({:const, _}, x) when x == :nl or elem(x, 0) == :cons, do: true
  defp pat_differ?(x, {:const, _}) when x == :nl or elem(x, 0) == :cons, do: true
  defp pat_differ?(_, _), do: false

  # a hat an k die Konstante c, b dort die Variable V und am Anfang einen
  # Wächter nur über V, der für V = c falsch ist
  defp const_vs_guard?(a, b, num) do
    Enum.any?(Enum.zip(eff_hin(a), b.hin), fn
      {{k, {:const, c}}, {k, {:bind, v}}} ->
        Enum.any?(reachable(b, num), fn g ->
          gv = guard_vars(g)
          gv != :unknown and Enum.all?(gv, &(&1 == v)) and guard_val(g, %{v => c}) == false
        end)

      _ ->
        false
    end)
  end

  defp guard_vars({:cmp, _, x, y}), do: Util.vars(x) ++ Util.vars(y)
  defp guard_vars({:u, {:var, _} = v, {k, _}}) when k in [:const, :constrt], do: [v]
  defp guard_vars(_), do: :unknown

  defp guard_val({:cmp, op, x, y}, env) do
    PrologEx.compare(op, ceval(x, env), ceval(y, env))
  rescue
    _ -> :unknown
  catch
    _ -> :unknown
  end

  defp guard_val({:u, v, {k, c}}, env) when k in [:const, :constrt],
    do: Map.fetch!(env, v) === c

  defp ceval(n, _) when is_number(n), do: n
  defp ceval({:var, _} = v, env), do: Map.fetch!(env, v)
  defp ceval({:op2, op, a, b}, env), do: PrologEx.Arith.op2(op, ceval(a, env), ceval(b, env))
  defp ceval({:op1, op, a}, env), do: PrologEx.Arith.op1(op, ceval(a, env))

  # einander ausschließende Vergleiche am Anfang (über Eingaben des Kopfs)
  defp complementary?(a, b, num) do
    ga = for g <- guards(a), n = norm(g, a), n != nil, do: n
    gb = for g <- reachable(b, num), n = norm(g, b), n != nil, do: n
    Enum.any?(ga, fn x -> Enum.any?(gb, &complement?(x, &1)) end)
  end

  # Vergleich mit Positionen statt Variablen; < und =< (> und >= gedreht)
  defp norm({:cmp, op, x, y}, c) do
    pos = for {k, {:bind, v}} <- c.hin, into: %{}, do: {v, {:pos, k}}

    with {:ok, x} <- subst_pos(x, pos), {:ok, y} <- subst_pos(y, pos) do
      case op do
        ">" -> {y, "<", x}
        ">=" -> {y, "=<", x}
        _ -> {x, op, y}
      end
    else
      _ -> nil
    end
  end

  defp norm(_, _), do: nil

  defp subst_pos({:var, _} = v, pos), do: if(Map.has_key?(pos, v), do: {:ok, pos[v]}, else: :no)

  defp subst_pos({:op2, op, a, b}, pos) do
    with {:ok, a} <- subst_pos(a, pos), {:ok, b} <- subst_pos(b, pos), do: {:ok, {:op2, op, a, b}}
  end

  defp subst_pos({:op1, op, a}, pos) do
    with {:ok, a} <- subst_pos(a, pos), do: {:ok, {:op1, op, a}}
  end

  defp subst_pos(n, _), do: {:ok, n}

  defp complement?({a, "<", b}, {b, "=<", a}), do: true
  defp complement?({a, "=<", b}, {b, "<", a}), do: true
  defp complement?({a, "=:=", b}, {a, "=\\=", b}), do: true
  defp complement?({a, "=:=", b}, {b, "=\\=", a}), do: true
  defp complement?({a, "=\\=", b}, {a, "=:=", b}), do: true
  defp complement?({a, "=\\=", b}, {b, "=:=", a}), do: true
  defp complement?(_, _), do: false
end
