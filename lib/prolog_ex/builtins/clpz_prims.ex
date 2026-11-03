defmodule PrologEx.Builtins.ClpzPrims do
  @moduledoc """
  Teile von `library(clpz)` (`priv/library/clpz.pl`) in Elixir.

  Domänen und Schranken. Eine Schranke ist `n(N)` (ganze Zahl N), `inf`
  oder `sup`; eine Domäne ist `empty`, `from_to(Von, Bis)` (ein Intervall
  zwischen zwei Schranken) oder `split(Loch, Links, Rechts)` (alle Elemente
  von Links sind kleiner als das Loch, alle von Rechts größer).

    * Schranken-Arithmetik: `'$clpz_cis_plus'/3`, `_minus/3`, `_times/3`,
      `_min/3`, `_max/3`, `_div/3`, `_slash/3`, `_exp/3`, `_uminus/2`,
      `_abs/2`, `_sign/2` und die Vergleiche `'$clpz_cis_gt'/2`,
      `_geq/2`, `_lt_numeric/2`, `_gt_numeric/2`, `_leq_numeric/2`,
      `_geq_numeric/2` (die `_numeric`-Formen vergleichen eine Schranke mit
      einer ganzen Zahl).
    * Domänen: `'$clpz_domain_infimum'/2`, `_supremum/2`,
      `_num_elements/2`, `_contains/2`, `_subdomain/2`, `_remove/3`,
      `_remove_greater_than/3`, `_remove_smaller_than/3`, `_subtract/3`,
      `_complement/2`, `_intervals/2`, `_shift/3`, `_expand/3`,
      `_expand_more/3`, `_contract/3`, `_contract_less/3`, `_negate/2`,
      `_spread/2`, `_smallest_finite/2`, `_largest_finite/2`, `_to_list/2`,
      `'$clpz_domains_intersection'/3`, `'$clpz_domains_union'/3`,
      `'$clpz_list_to_domain'/2`, `'$clpz_intervals_to_domain'/2`,
      `'$clpz_merge_intervals'/2`.

  Jedes rechnet wie das gleichnamige Prädikat in Triskas Code (dort mit
  der Endung `_ref` erhalten): dieselben Terme, dieselben Fehlschläge.
  clpz.pl ruft sie über `goal_expansion/2` direkt auf. Passen die
  Argumente nicht in dieses Schema (eine ungebundene Eingabe, keine ganze
  Zahl, keine Domäne) oder würde das Original einen Fehler werfen, rechnet
  das Original (`{:call, clpz:Name_ref(...)}`) – mit genau dessen
  Verhalten.
  """
  use PrologEx.Builtin

  # --- Rahmen ---------------------------------------------------------------

  # Rumpf eines Builtins: f rechnen; :fallback (aus dem Dekodieren) ruft das
  # Original clpz:Name_ref(Args)
  defp run(name, args, s, f) do
    Process.put(:clpz_prims_subst, s)

    try do
      f.()
    catch
      :fallback -> {:call, mk(":", [a("clpz"), mk(name <> "_ref", args)])}
    end
  end

  defp w(t), do: PrologEx.unmark_top(PrologEx.walk(t, subst_now()))

  # die Substitution des laufenden Builtins (im Prozess abgelegt, siehe defb)
  defp subst_now, do: Process.get(:clpz_prims_subst)

  # Schranke dekodieren: :inf | :sup | ganze Zahl
  defp bound(t) do
    case w(t) do
      {:atom, "inf"} -> :inf
      {:atom, "sup"} -> :sup
      {tag, "n", [x]} when tag in [:struct, :gstruct] -> int(x)
      _ -> throw(:fallback)
    end
  end

  defp int(t) do
    case w(t) do
      i when is_integer(i) -> i
      _ -> throw(:fallback)
    end
  end

  # Domäne dekodieren: :empty | {:ft, von, bis} | {:sp, loch, links, rechts}
  defp dom(t) do
    case w(t) do
      {:atom, "empty"} -> :empty
      {tag, "from_to", [f, to]} when tag in [:struct, :gstruct] -> {:ft, bound(f), bound(to)}
      {tag, "split", [s, l, r]} when tag in [:struct, :gstruct] -> {:sp, int(s), dom(l), dom(r)}
      _ -> throw(:fallback)
    end
  end

  defp eb(:inf), do: a("inf")
  defp eb(:sup), do: a("sup")
  defp eb(i) when is_integer(i), do: mk("n", [i])

  defp ed(:empty), do: a("empty")
  defp ed({:ft, f, t}), do: mk("from_to", [eb(f), eb(t)])
  defp ed({:sp, s, l, r}), do: mk("split", [s, ed(l), ed(r)])

  # Ergebnis: Ausgabe out mit dem Term t unifizieren (nil: Fehlschlag)
  defp out(_o, nil), do: :fail
  defp out(o, t), do: {:unify, [{o, t}]}

  # --- Schranken ------------------------------------------------------------

  # Vergleiche: inf < ganze Zahlen < sup
  defp lt(a, b), do: rank(a) < rank(b) or (is_integer(a) and is_integer(b) and a < b)
  defp rank(:inf), do: 0
  defp rank(:sup), do: 2
  defp rank(_), do: 1

  defp gt(a, b), do: lt(b, a)
  defp geq(a, b), do: not lt(a, b)
  defp leq(a, b), do: not lt(b, a)

  defp bmin(:inf, _), do: :inf
  defp bmin(:sup, b), do: b
  defp bmin(a, :inf) when is_integer(a), do: :inf
  defp bmin(a, :sup) when is_integer(a), do: a
  defp bmin(a, b), do: min(a, b)

  defp bmax(:sup, _), do: :sup
  defp bmax(:inf, b), do: b
  defp bmax(a, :inf) when is_integer(a), do: a
  defp bmax(a, :sup) when is_integer(a), do: :sup
  defp bmax(a, b), do: max(a, b)

  defp plus(:inf, _), do: :inf
  defp plus(:sup, _), do: :sup
  defp plus(_a, :sup), do: :sup
  defp plus(_a, :inf), do: :inf
  defp plus(a, b), do: a + b

  defp minus(:inf, _), do: :inf
  defp minus(:sup, _), do: :sup
  defp minus(_a, :inf), do: :sup
  defp minus(_a, :sup), do: :inf
  defp minus(a, b), do: a - b

  defp uminus(:inf), do: :sup
  defp uminus(:sup), do: :inf
  defp uminus(a), do: -a

  defp babs(:inf), do: :sup
  defp babs(:sup), do: :sup
  defp babs(a), do: abs(a)

  defp times(:inf, b), do: if(lt(b, 0), do: :sup, else: if(gt(b, 0), do: :inf, else: 0))
  defp times(:sup, b), do: if(gt(b, 0), do: :sup, else: if(lt(b, 0), do: :inf, else: 0))
  defp times(a, :inf), do: times(:inf, a)
  defp times(a, :sup), do: times(:sup, a)
  defp times(a, b), do: a * b

  # cis_exp: nil = keine Klausel passt (Fehlschlag)
  defp exp(:inf, b) when is_integer(b), do: if(rem(b, 2) == 0, do: :sup, else: :inf)
  defp exp(:inf, _), do: nil
  defp exp(:sup, _), do: :sup
  defp exp(_a, :sup), do: :sup
  defp exp(_a, :inf), do: :inf
  # negative Exponenten: das Original (Fehler oder ±1)
  defp exp(_a, b) when b < 0, do: throw(:fallback)
  defp exp(a, b), do: Integer.pow(a, b)

  defp sign(:sup), do: 1
  defp sign(:inf), do: -1
  defp sign(a) when a > 0, do: 1
  defp sign(a) when a < 0, do: -1
  defp sign(_), do: 0

  # cis_div: Abrundung zur Null (//), Division durch 0 ergibt ±unendlich
  defp bdiv(:sup, b), do: if(geq(b, 0), do: :sup, else: :inf)
  defp bdiv(:inf, b), do: if(geq(b, 0), do: :inf, else: :sup)
  defp bdiv(_a, b) when b in [:sup, :inf], do: 0
  defp bdiv(a, 0), do: if(a >= 0, do: :sup, else: :inf)
  defp bdiv(a, b), do: div(a, b)

  # cis_slash: //, Division durch 0 wie im Original (Fehler)
  defp slash(:sup, _), do: :sup
  defp slash(:inf, _), do: :inf
  defp slash(_a, b) when b in [:sup, :inf], do: 0
  defp slash(_a, 0), do: throw(:fallback)
  defp slash(a, b), do: div(a, b)

  defbuiltin "$clpz_cis_gt", [x, y] do
    run("cis_gt", [x, y], subst(), fn ->
      if gt(bound(x), bound(y)), do: :ok, else: :fail
    end)
  end

  defbuiltin "$clpz_cis_geq", [x, y] do
    run("cis_geq", [x, y], subst(), fn ->
      if geq(bound(x), bound(y)), do: :ok, else: :fail
    end)
  end

  defbuiltin "$clpz_cis_lt_numeric", [x, y] do
    run("cis_lt_numeric", [x, y], subst(), fn ->
      if lt(bound(x), int(y)), do: :ok, else: :fail
    end)
  end

  defbuiltin "$clpz_cis_gt_numeric", [x, y] do
    run("cis_gt_numeric", [x, y], subst(), fn ->
      if gt(bound(x), int(y)), do: :ok, else: :fail
    end)
  end

  defbuiltin "$clpz_cis_leq_numeric", [x, y] do
    run("cis_leq_numeric", [x, y], subst(), fn ->
      if leq(bound(x), int(y)), do: :ok, else: :fail
    end)
  end

  defbuiltin "$clpz_cis_geq_numeric", [x, y] do
    run("cis_geq_numeric", [x, y], subst(), fn ->
      if geq(bound(x), int(y)), do: :ok, else: :fail
    end)
  end

  defbuiltin "$clpz_cis_min", [x, y, z] do
    run("cis_min", [x, y, z], subst(), fn ->
      out(z, eb(bmin(bound(x), bound(y))))
    end)
  end

  defbuiltin "$clpz_cis_max", [x, y, z] do
    run("cis_max", [x, y, z], subst(), fn ->
      out(z, eb(bmax(bound(x), bound(y))))
    end)
  end

  defbuiltin "$clpz_cis_plus", [x, y, z] do
    run("cis_plus", [x, y, z], subst(), fn ->
      out(z, eb(plus(bound(x), bound(y))))
    end)
  end

  defbuiltin "$clpz_cis_minus", [x, y, z] do
    run("cis_minus", [x, y, z], subst(), fn ->
      out(z, eb(minus(bound(x), bound(y))))
    end)
  end

  defbuiltin "$clpz_cis_times", [x, y, z] do
    run("cis_times", [x, y, z], subst(), fn ->
      out(z, eb(times(bound(x), bound(y))))
    end)
  end

  defbuiltin "$clpz_cis_exp", [x, y, z] do
    run("cis_exp", [x, y, z], subst(), fn ->
      case exp(bound(x), bound(y)) do
        nil -> :fail
        r -> out(z, eb(r))
      end
    end)
  end

  defbuiltin "$clpz_cis_div", [x, y, z] do
    run("cis_div", [x, y, z], subst(), fn ->
      out(z, eb(bdiv(bound(x), bound(y))))
    end)
  end

  defbuiltin "$clpz_cis_slash", [x, y, z] do
    run("cis_slash", [x, y, z], subst(), fn ->
      out(z, eb(slash(bound(x), bound(y))))
    end)
  end

  defbuiltin "$clpz_cis_uminus", [x, y] do
    run("cis_uminus", [x, y], subst(), fn ->
      out(y, eb(uminus(bound(x))))
    end)
  end

  defbuiltin "$clpz_cis_abs", [x, y] do
    run("cis_abs", [x, y], subst(), fn ->
      out(y, eb(babs(bound(x))))
    end)
  end

  defbuiltin "$clpz_cis_sign", [x, y] do
    run("cis_sign", [x, y], subst(), fn ->
      out(y, eb(sign(bound(x))))
    end)
  end

  # --- Domänen: Abfragen ------------------------------------------------------

  # Infimum/Supremum entlang des linken/rechten Rands, ohne die Domäne
  # ganz zu dekodieren
  defp edge(t, side) do
    case w(t) do
      {tag, "from_to", [f, to]} when tag in [:struct, :gstruct] ->
        bound(if side == :left, do: f, else: to)

      {tag, "split", [_s, l, r]} when tag in [:struct, :gstruct] ->
        edge(if(side == :left, do: l, else: r), side)

      # empty oder keine Domäne: das Original (empty scheitert dort)
      _ ->
        throw(:fallback)
    end
  end

  defbuiltin "$clpz_domain_infimum", [d, i] do
    run("domain_infimum", [d, i], subst(), fn ->
      out(i, eb(edge(d, :left)))
    end)
  end

  defbuiltin "$clpz_domain_supremum", [d, s] do
    run("domain_supremum", [d, s], subst(), fn ->
      out(s, eb(edge(d, :right)))
    end)
  end

  defp num(:empty), do: 0
  defp num({:ft, f, t}), do: plus(minus(t, f), 1)
  defp num({:sp, _, l, r}), do: plus(num(l), num(r))

  defbuiltin "$clpz_domain_num_elements", [d, n] do
    run("domain_num_elements", [d, n], subst(), fn ->
      out(n, eb(num(dom(d))))
    end)
  end

  # auf dem Term, entlang des Pfads (ohne die Domäne ganz zu dekodieren)
  defp contains_t(t, i) do
    case w(t) do
      {tag, "from_to", [f, to]} when tag in [:struct, :gstruct] ->
        leq(bound(f), i) and leq(i, bound(to))

      {tag, "split", [s, l, r]} when tag in [:struct, :gstruct] ->
        s = int(s)
        (i < s and contains_t(l, i)) or (i > s and contains_t(r, i))

      {:atom, "empty"} ->
        false

      _ ->
        throw(:fallback)
    end
  end

  defbuiltin "$clpz_domain_contains", [d, i] do
    run("domain_contains", [d, i], subst(), fn ->
      x = int(i)
      if contains_t(d, x), do: :ok, else: :fail
    end)
  end

  # domain_subdomain(Dom, Sub): Sub ⊆ Dom (Fehlschlag für Dom = empty,
  # wie das Original)
  defp subdomain({:ft, _, _} = d, sub), do: sub_fromto(sub, d)
  defp subdomain({:sp, _, _, _} = d, sub), do: sub_split(sub, d, sub)
  defp subdomain(:empty, _), do: false

  defp sub_split(:empty, _, _), do: true

  defp sub_split({:ft, f, t}, {:sp, s, l0, r0}, sub) do
    cond do
      lt(t, s) -> subdomain(l0, sub)
      gt(f, s) -> subdomain(r0, sub)
      true -> false
    end
  end

  defp sub_split({:sp, _, l, r}, d, _), do: subdomain(d, l) and subdomain(d, r)

  defp sub_fromto(:empty, _), do: true
  defp sub_fromto({:ft, f, t}, {:ft, f0, t0}), do: leq(f0, f) and geq(t0, t)
  defp sub_fromto({:sp, _, l, r}, d), do: sub_fromto(l, d) and sub_fromto(r, d)

  defbuiltin "$clpz_domain_subdomain", [d, sub] do
    run("domain_subdomain", [d, sub], subst(), fn ->
      if subdomain(dom(d), dom(sub)), do: :ok, else: :fail
    end)
  end

  # --- Domänen: Entfernen -----------------------------------------------------

  defp remove(:empty, _x), do: :empty
  defp remove({:ft, l0, u0}, x), do: remove_(l0, u0, x)

  defp remove({:sp, s, l0, r0} = d, x) do
    cond do
      x == s ->
        d

      x < s ->
        case remove(l0, x) do
          :empty -> r0
          l1 -> {:sp, s, l1, r0}
        end

      true ->
        case remove(r0, x) do
          :empty -> l0
          r1 -> {:sp, s, l0, r1}
        end
    end
  end

  defp remove_(:inf, u0, x) do
    cond do
      u0 == x -> {:ft, :inf, x - 1}
      lt(u0, x) -> {:ft, :inf, u0}
      true -> {:sp, x, {:ft, :inf, x - 1}, {:ft, x + 1, u0}}
    end
  end

  defp remove_(l0, u0, x) when is_integer(l0), do: remove_upper(u0, l0, x)
  # from_to(sup, _): keine Klausel im Original
  defp remove_(:sup, _u0, _x), do: throw(:fallback)

  defp remove_upper(:sup, l0, x) do
    cond do
      l0 == x -> {:ft, x + 1, :sup}
      l0 > x -> {:ft, l0, :sup}
      true -> {:sp, x, {:ft, l0, x - 1}, {:ft, x + 1, :sup}}
    end
  end

  defp remove_upper(u0, l0, x) when is_integer(u0) do
    cond do
      l0 == u0 and x == l0 -> :empty
      l0 == x -> {:ft, x + 1, u0}
      u0 == x -> {:ft, l0, x - 1}
      l0 <= x and x <= u0 -> {:sp, x, {:ft, l0, x - 1}, {:ft, x + 1, u0}}
      true -> {:ft, l0, u0}
    end
  end

  # from_to(n(_), inf): keine Klausel im Original
  defp remove_upper(:inf, _l0, _x), do: throw(:fallback)

  # auf dem Term entlang des Pfads; unberührte Teilbäume bleiben, wie sie
  # sind (wie im Original)
  defp remove_t(t, x) do
    case w(t) do
      {:atom, "empty"} = e ->
        e

      {tag, "from_to", [f, to]} when tag in [:struct, :gstruct] ->
        ed(remove_(bound(f), bound(to), x))

      {tag, "split", [s0, l0, r0]} = sp when tag in [:struct, :gstruct] ->
        s = int(s0)

        cond do
          x == s ->
            sp

          x < s ->
            case remove_t(l0, x) do
              {:atom, "empty"} -> r0
              l1 -> mk("split", [s, l1, r0])
            end

          true ->
            case remove_t(r0, x) do
              {:atom, "empty"} -> l0
              r1 -> mk("split", [s, l0, r1])
            end
        end

      _ ->
        throw(:fallback)
    end
  end

  defbuiltin "$clpz_domain_remove", [d, x, r] do
    run("domain_remove", [d, x, r], subst(), fn ->
      i = int(x)
      out(r, remove_t(d, i))
    end)
  end

  defp remove_gt(:empty, _), do: :empty

  defp remove_gt({:ft, f0, t0}, g) do
    if gt(f0, g), do: :empty, else: {:ft, f0, bmin(t0, g)}
  end

  defp remove_gt({:sp, s, l0, r0}, g) do
    if s <= g do
      case remove_gt(r0, g) do
        :empty -> l0
        r -> {:sp, s, l0, r}
      end
    else
      remove_gt(l0, g)
    end
  end

  defbuiltin "$clpz_domain_remove_greater_than", [d, g, r] do
    run("domain_remove_greater_than", [d, g, r], subst(), fn ->
      out(r, ed(remove_gt(dom(d), int(g))))
    end)
  end

  defp remove_lt(:empty, _), do: :empty

  defp remove_lt({:ft, f0, t0}, v) do
    if lt(t0, v), do: :empty, else: {:ft, bmax(f0, v), t0}
  end

  defp remove_lt({:sp, s, l0, r0}, v) do
    if s >= v do
      case remove_lt(l0, v) do
        :empty -> r0
        l -> {:sp, s, l, r0}
      end
    else
      remove_lt(r0, v)
    end
  end

  defbuiltin "$clpz_domain_remove_smaller_than", [d, v, r] do
    run("domain_remove_smaller_than", [d, v, r], subst(), fn ->
      out(r, ed(remove_lt(dom(d), int(v))))
    end)
  end

  # domain_subtract/4 des Originals; :none = Fehlschlag
  defp subtract(:empty, _, _), do: :empty

  defp subtract({:ft, from0, to0}, d, sub) do
    case sub do
      :empty ->
        d

      {:ft, from, to} ->
        cond do
          from == to ->
            if is_integer(from), do: remove(d, from), else: :none

          gt(from, to0) ->
            d

          lt(to, from0) ->
            d

          leq(from, from0) ->
            if geq(to, to0), do: :empty, else: {:ft, plus(to, 1), to0}

          true ->
            to1 = minus(from, 1)

            if lt(to, to0) do
              if is_integer(from),
                do: {:sp, from, {:ft, from0, to1}, {:ft, plus(to, 1), to0}},
                else: :none
            else
              {:ft, from0, to1}
            end
        end

      {:sp, s, l, r} ->
        cond do
          gt(s, to0) ->
            subtract(d, d, l)

          lt(s, from0) ->
            subtract(d, d, r)

          true ->
            case subtract(d, d, l) do
              :none -> :none
              d1 -> subtract(d1, d1, r)
            end
        end
    end
  end

  defp subtract({:sp, s, l0, r0}, _, sub) do
    with l when l != :none <- subtract(l0, l0, sub),
         r when r != :none <- subtract(r0, r0, sub) do
      cond do
        l == :empty -> r
        r == :empty -> l
        true -> {:sp, s, l, r}
      end
    end
  end

  defp subtract(:none, _, _), do: :none

  defp nonone(:none), do: nil
  defp nonone(d), do: ed(d)

  defbuiltin "$clpz_domain_subtract", [d0, sub, d] do
    run("domain_subtract", [d0, sub, d], subst(), fn ->
      dd = dom(d0)
      out(d, nonone(subtract(dd, dd, dom(sub))))
    end)
  end

  defbuiltin "$clpz_domain_complement", [d, c] do
    run("domain_complement", [d, c], subst(), fn ->
      default = {:ft, :inf, :sup}
      out(c, nonone(subtract(default, default, dom(d))))
    end)
  end

  # --- Domänen: Intervalle, Schnitt, Vereinigung ------------------------------

  defp intervals(:empty, acc), do: acc
  defp intervals({:ft, f, t}, acc), do: [{f, t} | acc]
  defp intervals({:sp, _, l, r}, acc), do: intervals(l, intervals(r, acc))

  defp e_intervals(is), do: list(Enum.map(is, fn {f, t} -> mk("-", [eb(f), eb(t)]) end))

  defbuiltin "$clpz_domain_intervals", [d, is] do
    run("domain_intervals", [d, is], subst(), fn ->
      out(is, e_intervals(intervals(dom(d), [])))
    end)
  end

  defp intersection_(:empty, _), do: :empty
  defp intersection_({:ft, l0, u0}, d2), do: narrow(d2, l0, u0)

  defp intersection_({:sp, s, l0, r0}, d2) do
    l1 = intersection_(l0, d2)
    r1 = intersection_(r0, d2)

    cond do
      l1 == :empty -> r1
      r1 == :empty -> l1
      true -> {:sp, s, l1, r1}
    end
  end

  defp narrow(:empty, _, _), do: :empty

  defp narrow({:ft, l0, u0}, from0, to0) do
    from1 = bmax(from0, l0)
    to1 = bmin(to0, u0)
    if gt(from1, to1), do: :empty, else: {:ft, from1, to1}
  end

  defp narrow({:sp, s, l0, r0}, from0, to0) do
    cond do
      lt(to0, s) ->
        narrow(l0, from0, to0)

      gt(from0, s) ->
        narrow(r0, from0, to0)

      true ->
        l1 = narrow(l0, from0, to0)
        r1 = narrow(r0, from0, to0)

        cond do
          l1 == :empty -> r1
          r1 == :empty -> l1
          true -> {:sp, s, l1, r1}
        end
    end
  end

  defbuiltin "$clpz_domains_intersection", [d1, d2, i] do
    run("domains_intersection", [d1, d2, i], subst(), fn ->
      case intersection_(dom(d1), dom(d2)) do
        :empty -> :fail
        r -> out(i, ed(r))
      end
    end)
  end

  # merge_intervals/2: keysort (Standardordnung der Schlüssel: inf, sup,
  # dann n(N) nach N; stabil), dann Überlappendes zusammenfassen
  defp key_rank(:inf), do: {0, 0}
  defp key_rank(:sup), do: {1, 0}
  defp key_rank(i), do: {2, i}

  defp merge_intervals(is) do
    is |> Enum.sort_by(fn {a, _} -> key_rank(a) end) |> merge_overlapping()
  end

  defp merge_overlapping([]), do: []

  defp merge_overlapping([{a, b0} | rest]) do
    {b, rest} = merge_remaining(rest, b0)
    [{a, b} | merge_overlapping(rest)]
  end

  defp merge_remaining([], b), do: {b, []}

  defp merge_remaining([{n, m} | nms] = all, b0) do
    if gt(n, plus(b0, 1)), do: {b0, all}, else: merge_remaining(nms, bmax(b0, m))
  end

  # intervals_to_domain/2; nil = Fehlschlag (das hintere Teilstück beginnt
  # nicht mit n(_))
  defp to_domain([]), do: :empty
  defp to_domain([{m, n}]), do: {:ft, m, n}

  defp to_domain(is) do
    {front, tail} = Enum.split(is, div(length(is), 2))

    case tail do
      [{start, _} | _] when is_integer(start) ->
        with l when l != nil <- to_domain(front),
             r when r != nil <- to_domain(tail),
             do: {:sp, start - 1, l, r}

      _ ->
        nil
    end
  end

  defp maybe_ed(nil), do: nil
  defp maybe_ed(d), do: ed(d)

  defp union(d1, d2) do
    to_domain(merge_intervals(intervals(d1, []) ++ intervals(d2, [])))
  end

  defbuiltin "$clpz_domains_union", [d1, d2, u] do
    run("domains_union", [d1, d2, u], subst(), fn ->
      out(u, maybe_ed(union(dom(d1), dom(d2))))
    end)
  end

  # Liste von Intervallen A-B (Schranken)
  defp interval_list(t) do
    case w(t) do
      [] ->
        []

      [h | tl] ->
        case w(h) do
          {tag, "-", [a, b]} when tag in [:struct, :gstruct] ->
            [{bound(a), bound(b)} | interval_list(tl)]

          _ ->
            throw(:fallback)
        end

      {:glist, l} ->
        interval_list(l)

      _ ->
        throw(:fallback)
    end
  end

  defbuiltin "$clpz_merge_intervals", [is0, is] do
    run("merge_intervals", [is0, is], subst(), fn ->
      out(is, e_intervals(merge_intervals(interval_list(is0))))
    end)
  end

  defbuiltin "$clpz_intervals_to_domain", [is, d] do
    run("intervals_to_domain", [is, d], subst(), fn ->
      out(d, maybe_ed(to_domain(interval_list(is))))
    end)
  end

  defp int_list(t) do
    case w(t) do
      [] -> []
      [h | tl] -> [int(h) | int_list(tl)]
      {:glist, l} -> int_list(l)
      _ -> throw(:fallback)
    end
  end

  defp disjoint([]), do: []
  defp disjoint([n | ns]), do: disjoint(ns, n, n)
  defp disjoint([], m, n), do: [{m, n}]

  defp disjoint([b | bs], m, n) do
    if b == n + 1, do: disjoint(bs, m, b), else: [{m, n} | disjoint(bs, b, b)]
  end

  defbuiltin "$clpz_list_to_domain", [l, d] do
    run("list_to_domain", [l, d], subst(), fn ->
      case int_list(l) do
        [] -> out(d, a("empty"))
        ns -> out(d, maybe_ed(to_domain(disjoint(Enum.uniq(Enum.sort(ns))))))
      end
    end)
  end

  # --- Domänen: Verschieben, Strecken, Stauchen, Spiegeln ---------------------

  defp shift(:empty, _), do: :empty
  defp shift({:ft, f, t}, o), do: {:ft, plus(f, o), plus(t, o)}
  defp shift({:sp, s, l, r}, o), do: {:sp, s + o, shift(l, o), shift(r, o)}

  defbuiltin "$clpz_domain_shift", [d, o, r] do
    run("domain_shift", [d, o, r], subst(), fn ->
      out(r, ed(shift(dom(d), int(o))))
    end)
  end

  defp negate(:empty), do: :empty
  defp negate({:ft, f, t}), do: {:ft, uminus(t), uminus(f)}
  defp negate({:sp, s, l, r}), do: {:sp, -s, negate(r), negate(l)}

  defbuiltin "$clpz_domain_negate", [d, r] do
    run("domain_negate", [d, r], subst(), fn ->
      out(r, ed(negate(dom(d))))
    end)
  end

  defp expand_(:empty, _), do: :empty
  defp expand_({:ft, f, t}, m), do: {:ft, times(f, m), times(t, m)}
  defp expand_({:sp, s, l, r}, m), do: {:sp, m * s, expand_(l, m), expand_(r, m)}

  defbuiltin "$clpz_domain_expand", [d0, m, d] do
    run("domain_expand", [d0, m, d], subst(), fn ->
      dd = dom(d0)
      mm = int(m)

      r =
        cond do
          mm < 0 -> expand_(negate(dd), abs(mm))
          mm == 1 -> dd
          true -> expand_(dd, mm)
        end

      out(d, ed(r))
    end)
  end

  defp expand_more_(:empty, _), do: :empty

  defp expand_more_({:ft, f0, t0}, m) do
    f = if leq(f0, 0), do: plus(times(minus(f0, 1), m), 1), else: times(f0, m)
    t = if lt(t0, 0), do: times(t0, m), else: minus(times(plus(t0, 1), m), 1)
    {:ft, f, t}
  end

  defp expand_more_({:sp, s, l, r}, m), do: {:sp, m * s, expand_more_(l, m), expand_more_(r, m)}

  defbuiltin "$clpz_domain_expand_more", [d0, m, d] do
    run("domain_expand_more", [d0, m, d], subst(), fn ->
      {dd, mm} = neg_abs(dom(d0), int(m))
      out(d, ed(expand_more_(dd, mm)))
    end)
  end

  defp neg_abs(d, m) when m < 0, do: {negate(d), abs(m)}
  defp neg_abs(d, m), do: {d, m}

  # Stauchen: die Teile mit domains_union/3 zusammengefügt (nil: Fehlschlag)
  defp contract_(:empty, _), do: :empty

  defp contract_({:ft, f0, t0}, m) do
    f = if geq(f0, 0), do: slash(minus(plus(f0, m), 1), m), else: slash(f0, m)
    t = if geq(t0, 0), do: slash(t0, m), else: slash(plus(minus(t0, m), 1), m)
    {:ft, f, t}
  end

  defp contract_({:sp, _, l0, r0}, m) do
    with l when l != nil <- contract_(l0, m),
         r when r != nil <- contract_(r0, m),
         do: union(l, r)
  end

  defbuiltin "$clpz_domain_contract", [d0, m, d] do
    run("domain_contract", [d0, m, d], subst(), fn ->
      {dd, mm} = neg_abs(dom(d0), int(m))
      out(d, maybe_ed(contract_(dd, mm)))
    end)
  end

  defp contract_less_(:empty, _), do: :empty
  defp contract_less_({:ft, f0, t0}, m), do: {:ft, slash(f0, m), slash(t0, m)}

  defp contract_less_({:sp, _, l0, r0}, m) do
    with l when l != nil <- contract_less_(l0, m),
         r when r != nil <- contract_less_(r0, m),
         do: union(l, r)
  end

  defbuiltin "$clpz_domain_contract_less", [d0, m, d] do
    run("domain_contract_less", [d0, m, d], subst(), fn ->
      {dd, mm} = neg_abs(dom(d0), int(m))
      out(d, maybe_ed(contract_less_(dd, mm)))
    end)
  end

  # --- Domänen: Spannweite, Liste ---------------------------------------------

  defp smallest_finite({:ft, :inf, t}), do: t
  defp smallest_finite({:ft, f, _}) when is_integer(f), do: f
  defp smallest_finite({:sp, _, l, _}), do: smallest_finite(l)
  defp smallest_finite(_), do: nil

  defp largest_finite({:ft, f, :sup}), do: f
  defp largest_finite({:ft, _, t}) when is_integer(t), do: t
  defp largest_finite({:sp, _, _, r}), do: largest_finite(r)
  defp largest_finite(_), do: nil

  defp maybe_eb(nil), do: nil
  defp maybe_eb(b), do: eb(b)

  defbuiltin "$clpz_domain_smallest_finite", [d, s] do
    run("domain_smallest_finite", [d, s], subst(), fn ->
      out(s, maybe_eb(smallest_finite(dom(d))))
    end)
  end

  defbuiltin "$clpz_domain_largest_finite", [d, l] do
    run("domain_largest_finite", [d, l], subst(), fn ->
      out(l, maybe_eb(largest_finite(dom(d))))
    end)
  end

  defbuiltin "$clpz_domain_spread", [d, sp] do
    run("domain_spread", [d, sp], subst(), fn ->
      dd = dom(d)

      with s when s != nil <- smallest_finite(dd),
           l when l != nil <- largest_finite(dd) do
        out(sp, eb(minus(l, s)))
      else
        nil -> :fail
      end
    end)
  end

  # domain_to_list/2: nur endliche Intervalle (sonst scheitert das Original)
  defp to_list(:empty, acc), do: {:ok, acc}

  defp to_list({:ft, f, t}, acc) when is_integer(f) and is_integer(t) and f <= t,
    do: {:ok, Enum.to_list(f..t//1) ++ acc}

  defp to_list({:ft, _, _}, _acc), do: :fail

  defp to_list({:sp, _, l, r}, acc) do
    with {:ok, acc} <- to_list(r, acc), do: to_list(l, acc)
  end

  defbuiltin "$clpz_domain_to_list", [d, l] do
    run("domain_to_list", [d, l], subst(), fn ->
      case to_list(dom(d), []) do
        {:ok, ns} -> out(l, list(ns))
        :fail -> :fail
      end
    end)
  end
end
