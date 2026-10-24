defmodule PrologEx.Builtins.Random do
  @moduledoc """
  `library(random)` wie SICStus, dazu `random_between/3` und
  `set_random/1` aus SWI:

    * `random(-X)`                 Float in [0.0, 1.0)
    * `random(+L, +U, -X)`         Ganzzahlen: L =< X < U; sonst Float in [L, U)
    * `random_between(+L, +H, -X)` Ganzzahl L =< X =< H (SWI)
    * `random_member(-X, +Liste)`  zufälliges Element (leere Liste: scheitert)
    * `random_select(?X, ?Liste, ?Rest)` zufälliges Element entfernen; ist
      nur Rest eine Liste, wird X an zufälliger Stelle eingefügt
    * `random_subseq(+Liste, -Teil, -Rest)` jedes Element mit Wahrscheinlichkeit 1/2
    * `random_permutation(?Liste, ?Perm)` eine der beiden ist eine Liste
    * `randseq(+K, +N, -Liste)`    K verschiedene Zahlen aus 1..N, zufällige Reihenfolge
    * `randset(+K, +N, -Menge)`    dasselbe, aufsteigend sortiert
    * `getrand(-Zustand)`, `setrand(+Zustand)` Zustand des Generators
      (`rand(A, B)`), für reproduzierbare Läufe
    * `set_random(seed(N))`        Generator mit N initialisieren (SWI)

  Der Generator ist Erlangs `exsss` mit eigenem Zustand je Sitzung (im
  Prozess); er wird beim ersten Gebrauch zufällig initialisiert. Wie bei
  SICStus setzt Backtracking ihn nicht zurück. Alle Prädikate sind
  deterministisch.
  """
  use PrologEx.Builtin, module: "random"
  alias PrologEx.Builtins.Lists
  alias PrologEx.Error

  @key :prolog_ex_random

  defbuiltin "random", [x] do
    {:unify, [{x, draw(&:rand.uniform_real_s/1)}]}
  end

  defbuiltin "random", [l, u, x] do
    case {deref(l), deref(u)} do
      {lo, hi} when is_integer(lo) and is_integer(hi) ->
        if hi > lo, do: {:unify, [{x, lo + int_below(hi - lo)}]}, else: :fail

      {lo, hi} when is_number(lo) and is_number(hi) ->
        if hi > lo,
          do: {:unify, [{x, lo + draw(&:rand.uniform_real_s/1) * (hi - lo)}]},
          else: :fail

      {lo, hi} ->
        number_args!(lo, hi)
    end
  end

  defbuiltin "random_between", [l, h, x] do
    case {deref(l), deref(h)} do
      {lo, hi} when is_integer(lo) and is_integer(hi) ->
        if hi >= lo, do: {:unify, [{x, lo + int_below(hi - lo + 1)}]}, else: :fail

      {lo, hi} ->
        integer_args!(lo, hi)
    end
  end

  defbuiltin "random_member", [x, l] do
    case items!(l, subst()) do
      [] -> :fail
      items -> {:unify, [{x, Enum.at(items, int_below(length(items)))}]}
    end
  end

  defbuiltin "random_select", [x, l, r] do
    s = subst()

    case proper(l, s) do
      {:ok, []} ->
        :fail

      {:ok, items} ->
        {before, [picked | rest]} = Enum.split(items, int_below(length(items)))
        {:unify, [{x, picked}, {r, list(before ++ rest)}]}

      :partial ->
        # umgekehrt: X an zufälliger Stelle in Rest einfügen
        rest = items!(r, s)
        {before, after_} = Enum.split(rest, int_below(length(rest) + 1))
        {:unify, [{l, list(before ++ [x | after_])}]}
    end
  end

  defbuiltin "random_subseq", [l, sub, compl] do
    {ins, outs} = Enum.split_with(items!(l, subst()), fn _ -> int_below(2) == 0 end)
    {:unify, [{sub, list(ins)}, {compl, list(outs)}]}
  end

  defbuiltin "random_permutation", [l, p] do
    s = subst()

    case proper(l, s) do
      {:ok, items} ->
        {:unify, [{p, list(shuffle(items))}]}

      :partial ->
        {:unify, [{l, list(shuffle(items!(p, s)))}]}
    end
  end

  defbuiltin "randseq", [k, n, l] do
    {kk, nn} = sizes!(deref(k), deref(n))
    {:unify, [{l, {:glist, sample(kk, nn)}}]}
  end

  defbuiltin "randset", [k, n, l] do
    {kk, nn} = sizes!(deref(k), deref(n))
    {:unify, [{l, {:glist, Enum.sort(sample(kk, nn))}}]}
  end

  defbuiltin "getrand", [st] do
    {_alg, [a1 | b1]} = :rand.export_seed_s(state())
    {:unify, [{st, mk("rand", [a1, b1])}]}
  end

  defbuiltin "setrand", [st] do
    case PrologEx.unmark_top(deref(st)) do
      {:struct, "rand", [a1, b1]} ->
        case {deref(a1), deref(b1)} do
          {x, y} when is_integer(x) and is_integer(y) and x > 0 and y > 0 ->
            Process.put(@key, :rand.seed_s({:exsss, [x | y]}))
            :ok

          _ ->
            Error.domain!("random_state", resolve(st))
        end

      {:var, _} ->
        Error.instantiation!()

      _ ->
        Error.domain!("random_state", resolve(st))
    end
  end

  defbuiltin "set_random", [opt] do
    case PrologEx.unmark_top(deref(opt)) do
      {:struct, "seed", [seed]} ->
        case deref(seed) do
          n when is_integer(n) ->
            Process.put(@key, :rand.seed_s(:exsss, n))
            :ok

          {:var, _} ->
            Error.instantiation!()

          other ->
            Error.type!("integer", other)
        end

      {:var, _} ->
        Error.instantiation!()

      _ ->
        Error.domain!("set_random_option", resolve(opt))
    end
  end

  # ---------------------------------------------------------------------

  defp state do
    case Process.get(@key) do
      nil ->
        s = :rand.seed_s(:exsss)
        Process.put(@key, s)
        s

      s ->
        s
    end
  end

  @doc false
  # eine Zufallszahl aus dem Generator der Sitzung (auch für is/2: random/1,
  # random_float)
  def draw(fun) do
    {x, s} = fun.(state())
    Process.put(@key, s)
    x
  end

  # gleichverteilt in 0..n-1
  defp int_below(n), do: draw(&:rand.uniform_s(n, &1)) - 1

  # Mischen: jedem Element einen zufälligen 56-Bit-Schlüssel geben und
  # danach sortieren (O(n log n), auf der BEAM schneller als Fisher-Yates
  # mit einem Array; gleiche Schlüssel sind bei 2^56 praktisch
  # ausgeschlossen). Der Generatorzustand wird durchgereicht.
  @key_range 72_057_594_037_927_936

  defp shuffle(items) do
    {keyed, st} =
      Enum.map_reduce(items, state(), fn x, st ->
        {k, st} = :rand.uniform_s(@key_range, st)
        {{k, x}, st}
      end)

    Process.put(@key, st)
    keyed |> List.keysort(0) |> Enum.map(&elem(&1, 1))
  end

  # K verschiedene Zahlen aus 1..N in zufälliger Reihenfolge: bei kleinem K
  # durch Ziehen mit Ablehnung, sonst Mischen von 1..N
  defp sample(k, n) when k * 3 < n, do: draw_distinct(k, n, MapSet.new(), [])
  defp sample(k, n), do: Enum.to_list(1..n//1) |> shuffle() |> Enum.take(k)

  defp draw_distinct(0, _n, _seen, acc), do: acc

  defp draw_distinct(k, n, seen, acc) do
    x = int_below(n) + 1

    if MapSet.member?(seen, x),
      do: draw_distinct(k, n, seen, acc),
      else: draw_distinct(k - 1, n, MapSet.put(seen, x), [x | acc])
  end

  defp sizes!(k, n) do
    case {k, n} do
      {{:var, _}, _} -> Error.instantiation!()
      {_, {:var, _}} -> Error.instantiation!()
      {k, _} when not is_integer(k) -> Error.type!("integer", k)
      {_, n} when not is_integer(n) -> Error.type!("integer", n)
      {k, _} when k < 0 -> Error.domain!("not_less_than_zero", k)
      {k, n} when k > n -> Error.domain!("not_greater_than_n", k)
      {k, n} -> {k, n}
    end
  end

  defp number_args!(lo, hi) do
    cond do
      match?({:var, _}, lo) or match?({:var, _}, hi) -> Error.instantiation!()
      not is_number(lo) -> Error.type!("number", lo)
      true -> Error.type!("number", hi)
    end
  end

  defp integer_args!(lo, hi) do
    cond do
      match?({:var, _}, lo) or match?({:var, _}, hi) -> Error.instantiation!()
      not is_integer(lo) -> Error.type!("integer", lo)
      true -> Error.type!("integer", hi)
    end
  end

  defp proper(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> {:ok, Lists.items(l, s)}
      _ -> :partial
    end
  end

  defp items!(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> Lists.items(l, s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end
end
