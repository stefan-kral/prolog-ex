defmodule PrologEx.Builtins.ListUtils do
  @moduledoc """
  Weitere Prädikate aus SWIs `library(lists)` und `library(apply)`, mit
  derselben Bedeutung und Lösungsreihenfolge wie dort.

  Elixir-Schnellwege, wenn die Liste eine echte Liste ist (sonst läuft die
  Prolog-Definition `$...` wie in SWI):

    * `memberchk/2`, `last/2`, `reverse/2`, `proper_length/2`
    * `sum_list/2` (`sumlist/2`), `max_list/2`, `min_list/2` – wenn alle
      Elemente Zahlen sind (bei max/min: nur Integer oder nur Floats; sonst
      rechnet `is` wie in SWI)
    * `max_member/2`, `min_member/2` – Standardordnung, bei Gleichstand
      gewinnt das erste Element
    * `delete/3` – entfernt alle Elemente, die mit dem Muster
      unifizierbar sind (ohne zu binden)
    * `list_to_set/2` – erstes Vorkommen bleibt, Gleichheit `==`

  Nur in Prolog: `nextto/3`, `subtract/3`, `intersection/3`, `union/3`,
  `include/3`, `exclude/3`, `partition/4`, `foldl/4,5,6`.
  """
  use PrologEx.Builtin, module: "lists"
  alias PrologEx.Builtins.Lists
  alias PrologEx.Order

  # --- Schnellwege -----------------------------------------------------

  # memberchk(X, L): wie member(X, L), !. Ein offener Rest wird wie bei
  # member/2 zu [X|_] verlängert.
  defbuiltin "memberchk", [x, l], protected: false do
    chk(x, PrologEx.walk(l, subst()), subst())
  end

  defbuiltin "last", [l, x], protected: false, helpers: [{"$last", 2}] do
    case proper(l, subst()) do
      {:ok, []} -> false
      {:ok, items} -> {:unify, [{x, List.last(items)}]}
      :partial -> {:call, mk("$last", [l, x])}
    end
  end

  defbuiltin "reverse", [l, r], protected: false, helpers: [{"$reverse", 4}] do
    case proper(l, subst()) do
      {:ok, items} -> {:unify, [{r, PrologEx.list(Enum.reverse(items), [])}]}
      :partial -> {:call, mk("$reverse", [l, r, [], r])}
    end
  end

  defbuiltin "proper_length", [l, n], protected: false do
    case Lists.skip_list(l, subst()) do
      {len, []} -> {:unify, [{n, len}]}
      _ -> false
    end
  end

  defbuiltin "sum_list", [l, sum], protected: false, helpers: [{"$sum_list", 3}] do
    sum_list(l, sum, subst())
  end

  defbuiltin "sumlist", [l, sum], protected: false, helpers: [{"$sum_list", 3}] do
    sum_list(l, sum, subst())
  end

  defbuiltin "max_list", [l, m], protected: false, helpers: [{"$max_list", 3}] do
    extremum(l, m, subst(), &max/2, "$max_list")
  end

  defbuiltin "min_list", [l, m], protected: false, helpers: [{"$min_list", 3}] do
    extremum(l, m, subst(), &min/2, "$min_list")
  end

  defbuiltin "max_member", [m, l], protected: false, helpers: [{"$max_member", 3}] do
    member_by(m, l, subst(), :gt, "$max_member")
  end

  defbuiltin "min_member", [m, l], protected: false, helpers: [{"$min_member", 3}] do
    member_by(m, l, subst(), :lt, "$min_member")
  end

  defbuiltin "delete", [l, del, r], protected: false, helpers: [{"$delete", 3}] do
    s = subst()

    case proper(l, s) do
      {:ok, items} ->
        keep = Enum.reject(items, &unifiable?(&1, del, s))
        {:unify, [{r, PrologEx.list(keep, [])}]}

      :partial ->
        {:call, mk("$delete", [l, del, r])}
    end
  end

  defbuiltin "list_to_set", [l, set], protected: false do
    s = subst()

    case proper(l, s) do
      {:ok, items} ->
        {keep, _} =
          Enum.reduce(items, {[], MapSet.new()}, fn x, {acc, seen} ->
            k = Order.key(x, s)
            if MapSet.member?(seen, k), do: {acc, seen}, else: {[x | acc], MapSet.put(seen, k)}
          end)

        {:unify, [{set, PrologEx.list(Enum.reverse(keep), [])}]}

      :partial ->
        case Lists.skip_list(l, s) do
          {_, {:var, _}} -> PrologEx.Error.instantiation!()
          _ -> PrologEx.Error.type!("list", resolve(l))
        end
    end
  end

  # --- Hilfsfunktionen ---------------------------------------------------

  # Elemente einer echten Liste (Ende []) oder :partial
  defp proper(l, s) do
    case Lists.skip_list(l, s) do
      {_, []} -> {:ok, Lists.items(l, s)}
      _ -> :partial
    end
  end

  defp chk(x, t, s) do
    case PrologEx.uncons(t) do
      {:cons, h, tl} ->
        if unifiable?(x, h, s),
          do: {:unify, [{x, h}]},
          else: chk(x, PrologEx.walk(tl, s), s)

      :empty ->
        false

      :other ->
        case t do
          {:var, _} -> {:unify, [{t, [x | fresh_var()]}]}
          _ -> false
        end
    end
  end

  defp unifiable?(a, b, s), do: match?({:ok, _}, PrologEx.unify(a, b, s))

  defp sum_list(l, sum, s) do
    with {:ok, items} <- proper(l, s),
         nums = Enum.map(items, &PrologEx.walk(&1, s)),
         true <- Enum.all?(nums, &is_number/1) do
      {:unify, [{sum, Enum.reduce(nums, 0, &(&2 + &1))}]}
    else
      _ -> {:call, mk("$sum_list", [l, 0, sum])}
    end
  end

  # nur Integer oder nur Floats: dann ist max/min der BEAM eindeutig
  defp extremum(l, m, s, fun, helper) do
    with {:ok, [_ | _] = items} <- proper(l, s),
         nums = Enum.map(items, &PrologEx.walk(&1, s)),
         true <- Enum.all?(nums, &is_integer/1) or Enum.all?(nums, &is_float/1) do
      {:unify, [{m, Enum.reduce(nums, fun)}]}
    else
      {:ok, []} -> false
      _ -> prolog_extremum(l, m, helper)
    end
  end

  defp prolog_extremum(l, m, helper) do
    h = fresh_var()
    t = fresh_var()
    {:call, mk(",", [mk("=", [l, [h | t]]), mk(helper, [t, h, m])])}
  end

  # erstes Element, das bezüglich `want` (:gt oder :lt) extrem ist
  defp member_by(m, l, s, want, helper) do
    case proper(l, s) do
      {:ok, []} ->
        false

      {:ok, [first | rest]} ->
        best =
          Enum.reduce(rest, first, fn x, b ->
            if Order.compare(x, b, s) == want, do: x, else: b
          end)

        {:unify, [{m, best}]}

      :partial ->
        prolog_extremum(l, m, helper)
    end
  end

  # --- Prolog ------------------------------------------------------------

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, fact: 1, rule: 2]

    [
      x,
      xs,
      l,
      y,
      ys,
      h,
      t,
      r,
      r1,
      m,
      m0,
      m1,
      e,
      d,
      _p,
      i,
      _i1,
      _ex,
      _ex1,
      _g,
      _v0,
      _v,
      _v1,
      _z,
      zs,
      b,
      rs,
      s0,
      s1,
      sum
    ] =
      Enum.map(
        ~w(X Xs L Y Ys H T R R1 M M0 M1 E D P I I1 Ex Ex1 G V0 V V1 Z Zs B Rs S0 S1 S),
        &v/1
      )

    w = v("_")
    ite = fn c, a, b -> s(";", [s("->", [c, a]), b]) end
    conj = fn gs -> PrologEx.conj(gs) end

    [
      # last/2
      rule(s("$last", [[x | xs], l]), [s("$last_", [xs, x, l])]),
      fact(s("$last_", [[], l, l])),
      rule(s("$last_", [[x | xs], w, l]), [s("$last_", [xs, x, l])]),
      # reverse/2: zweites Argument begrenzt die Länge (terminiert auch,
      # wenn nur Ys eine echte Liste ist)
      fact(s("$reverse", [[], [], ys, ys])),
      rule(s("$reverse", [[x | xs], [w | b], rs, ys]), [s("$reverse", [xs, b, [x | rs], ys])]),
      # sum_list/2 mit is (rechnet Ausdrücke aus wie SWI)
      fact(s("$sum_list", [[], sum, sum])),
      rule(s("$sum_list", [[x | xs], s0, sum]), [
        s("is", [s1, s("+", [s0, x])]),
        s("$sum_list", [xs, s1, sum])
      ]),
      # max_list/2, min_list/2: erstes Element unausgewertet als Start (SWI)
      fact(s("$max_list", [[], m, m])),
      rule(s("$max_list", [[h | t], m0, m]), [
        s("is", [m1, s("max", [m0, h])]),
        s("$max_list", [t, m1, m])
      ]),
      fact(s("$min_list", [[], m, m])),
      rule(s("$min_list", [[h | t], m0, m]), [
        s("is", [m1, s("min", [m0, h])]),
        s("$min_list", [t, m1, m])
      ]),
      # max_member/2, min_member/2
      fact(s("$max_member", [[], m, m])),
      rule(s("$max_member", [[h | t], m0, m]), [
        ite.(s("@=<", [h, m0]), s("=", [m1, m0]), s("=", [m1, h])),
        s("$max_member", [t, m1, m])
      ]),
      fact(s("$min_member", [[], m, m])),
      rule(s("$min_member", [[h | t], m0, m]), [
        ite.(s("@>=", [h, m0]), s("=", [m1, m0]), s("=", [m1, h])),
        s("$min_member", [t, m1, m])
      ]),
      # delete/3
      fact(s("$delete", [[], w, []])),
      rule(s("$delete", [[e | t], d, r]), [
        ite.(
          s("\\+", [s("\\=", [e, d])]),
          s("$delete", [t, d, r]),
          conj.([s("=", [r, [e | r1]]), s("$delete", [t, d, r1])])
        )
      ]),
      # nextto/3
      fact(s("nextto", [x, y, [x, y | w]])),
      rule(s("nextto", [x, y, [w | zs]]), [s("nextto", [x, y, zs])]),
      # subtract/3, intersection/3, union/3 (memberchk/2, wie SWI)
      fact(s("subtract", [[], w, []])),
      rule(s("subtract", [[e | t], d, r]), [
        s("memberchk", [e, d]),
        a("!"),
        s("subtract", [t, d, r])
      ]),
      rule(s("subtract", [[h | t], d, [h | r]]), [s("subtract", [t, d, r])]),
      rule(s("intersection", [[], w, []]), [a("!")]),
      rule(s("intersection", [[x | t], l, i]), [
        s("memberchk", [x, l]),
        a("!"),
        s("=", [i, [x | r]]),
        s("intersection", [t, l, r])
      ]),
      rule(s("intersection", [[w | t], l, r]), [s("intersection", [t, l, r])]),
      rule(s("union", [[], l, l]), [a("!")]),
      rule(s("union", [[h | t], l, r]), [s("memberchk", [h, l]), a("!"), s("union", [t, l, r])]),
      rule(s("union", [[h | t], l, [h | r]]), [s("union", [t, l, r])])
    ]
    |> then(&%{"lists" => &1, "apply" => apply_library()})
  end

  @doc false
  def meta do
    [
      {"apply", "include", [1, "+", "-"]},
      {"apply", "exclude", [1, "+", "-"]},
      {"apply", "partition", [1, "+", "-", "-"]},
      {"apply", "foldl", [3, "+", "+", "-"]},
      {"apply", "foldl", [4, "+", "+", "+", "-"]},
      {"apply", "foldl", [5, "+", "+", "+", "+", "-"]}
    ]
  end

  defp apply_library do
    import PrologEx, only: [s: 2, v: 1, fact: 1, rule: 2]

    [x, xs, l, i, i1, ex, ex1, g, v0, vv, v1, y, ys, z, zs, h, t, p] =
      Enum.map(~w(X Xs L I I1 Ex Ex1 G V0 V V1 Y Ys Z Zs H T P), &PrologEx.v/1)

    w = v("_")
    ite = fn c, a, b -> s(";", [s("->", [c, a]), b]) end
    conj = fn gs -> PrologEx.conj(gs) end
    v = vv

    [
      # include/3, exclude/3, partition/4 (Liste vorn: Indexierung)
      rule(s("include", [p, l, i]), [s("$include", [l, p, i])]),
      fact(s("$include", [[], w, []])),
      rule(s("$include", [[x | xs], p, i]), [
        ite.(s("call", [p, x]), s("=", [i, [x | i1]]), s("=", [i, i1])),
        s("$include", [xs, p, i1])
      ]),
      rule(s("exclude", [p, l, i]), [s("$exclude", [l, p, i])]),
      fact(s("$exclude", [[], w, []])),
      rule(s("$exclude", [[x | xs], p, i]), [
        ite.(s("call", [p, x]), s("=", [i, i1]), s("=", [i, [x | i1]])),
        s("$exclude", [xs, p, i1])
      ]),
      rule(s("partition", [p, l, i, ex]), [s("$partition", [l, p, i, ex])]),
      fact(s("$partition", [[], w, [], []])),
      rule(s("$partition", [[h | t], p, i, ex]), [
        ite.(
          s("call", [p, h]),
          conj.([s("=", [i, [h | i1]]), s("=", [ex, ex1])]),
          conj.([s("=", [i, i1]), s("=", [ex, [h | ex1]])])
        ),
        s("$partition", [t, p, i1, ex1])
      ]),
      # foldl/4,5,6
      rule(s("foldl", [g, l, v0, v]), [s("$foldl", [l, g, v0, v])]),
      fact(s("$foldl", [[], w, v, v])),
      rule(s("$foldl", [[x | xs], g, v0, v]), [
        s("call", [g, x, v0, v1]),
        s("$foldl", [xs, g, v1, v])
      ]),
      rule(s("foldl", [g, l, ys, v0, v]), [s("$foldl", [l, ys, g, v0, v])]),
      fact(s("$foldl", [[], [], w, v, v])),
      rule(s("$foldl", [[x | xs], [y | ys], g, v0, v]), [
        s("call", [g, x, y, v0, v1]),
        s("$foldl", [xs, ys, g, v1, v])
      ]),
      rule(s("foldl", [g, l, ys, zs, v0, v]), [s("$foldl", [l, ys, zs, g, v0, v])]),
      fact(s("$foldl", [[], [], [], w, v, v])),
      rule(s("$foldl", [[x | xs], [y | ys], [z | zs], g, v0, v]), [
        s("call", [g, x, y, z, v0, v1]),
        s("$foldl", [xs, ys, zs, g, v1, v])
      ])
    ]
  end
end
