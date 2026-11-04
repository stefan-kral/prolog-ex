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
  alias PrologEx.Builtins.Blackboard

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

  # --- Ablage und Warteschlange ---------------------------------------------
  #
  # Der Zustand ist der des Originals: das Attribut clpz(clpz_attr(Links,
  # Rechts, Spanne, Domäne, fd_props(Gs, Bs, Os), Queue)) an jeder
  # Variablen; die Warteschlange queue(Ziele, Schnell, Langsam, Aux) ist ein
  # Term aus vier Variablen, deren Attribut queue(Kopf, Ende) eine offene
  # Liste hält (Aux: disabled/0); ein Propagator propagator(C, Zustand)
  # merkt sich über clpz_aux(queued) an seinem Zustand, dass er eingereiht
  # ist. Der DCG-Zustand ([Queue|_]) läuft unverändert durch.

  defp ws(t, s), do: PrologEx.unmark_top(PrologEx.walk(t, s))

  defp cell(t, s) do
    case ws(t, s) do
      [h | tl] -> {h, tl}
      {:glist, [h | tl]} -> {h, {:glist, tl}}
      _ -> nil
    end
  end

  # Argumente des Attributs name/ar von v im Modul clpz, oder nil
  defp att(v, s, name, ar) do
    v |> PrologEx.get_attrs(s) |> Map.get("clpz", []) |> att_find(s, name, ar)
  end

  defp att_find(l, s, name, ar) do
    case cell(l, s) do
      nil ->
        nil

      {h, tl} ->
        case ws(h, s) do
          {tag, ^name, args} when tag in [:struct, :gstruct] and length(args) == ar -> args
          {:atom, ^name} when ar == 0 -> []
          _ -> att_find(tl, s, name, ar)
        end
    end
  end

  defp put_att(s, v, t), do: PrologEx.Builtins.Atts.put_one(s, v, "clpz", t)

  # Attribut name/ar entfernen (wie put_atts(V, -A))
  defp del_att(s, v, name, ar) do
    items = all_items(v |> PrologEx.get_attrs(s) |> Map.get("clpz", []), s)

    kept =
      Enum.reject(items, fn h ->
        case ws(h, s) do
          {tag, ^name, args} when tag in [:struct, :gstruct] -> length(args) == ar
          {:atom, ^name} -> ar == 0
          _ -> false
        end
      end)

    PrologEx.put_attr(s, v, "clpz", list(kept))
  end

  defp all_items(l, s) do
    case cell(l, s) do
      nil -> []
      {h, tl} -> [h | all_items(tl, s)]
    end
  end

  defp list_items(l, s) do
    case cell(l, s) do
      nil -> if ws(l, s) == [], do: [], else: throw(:fallback)
      {h, tl} -> [h | list_items(tl, s)]
    end
  end

  # die Queue aus dem DCG-Zustand [Queue|_]
  defp state_q(s0, s) do
    case cell(s0, s) do
      {q, _} -> q
      nil -> throw(:fallback)
    end
  end

  # S = S0 (der Zustand bleibt) und Ergebnis
  defp finish(s1, s0, s) do
    case PrologEx.unify(s1, s0, s) do
      {:ok, s} -> {:subst, s}
      :error -> :fail
    end
  end

  defp new_queue, do: mk("queue", [fresh_var(), fresh_var(), fresh_var(), fresh_var()])

  # fd_get/3: {Domäne, Propagatoren} von x, :default oder :fail
  defp fd_get(x, s) do
    case PrologEx.walk(x, s) do
      {:var, _} = v ->
        case att(v, s, "clpz", 1) do
          [a] ->
            case ws(a, s) do
              {tag, "clpz_attr", [_, _, _, d, ps, _]} when tag in [:struct, :gstruct] -> {d, ps}
              _ -> throw(:fallback)
            end

          nil ->
            :default
        end

      _ ->
        :fail
    end
  end

  defp default_dom, do: mk("from_to", [a("inf"), a("sup")])
  defp no_props, do: mk("fd_props", [[], [], []])

  defbuiltin "$clpz_fd_get", [x, dom, ps] do
    run("fd_get", [x, dom, ps], subst(), fn ->
      case fd_get(x, subst_now()) do
        {d, p} -> {:unify, [{dom, d}, {ps, p}]}
        :default -> {:unify, [{dom, default_dom()}, {ps, no_props()}]}
        :fail -> :fail
      end
    end)
  end

  defbuiltin "$clpz_fd_get", [x, dom, inf, sup, ps] do
    run("fd_get", [x, dom, inf, sup, ps], subst(), fn ->
      case fd_get(x, subst_now()) do
        {d, p} ->
          {:unify, [{dom, d}, {inf, eb(edge(d, :left))}, {sup, eb(edge(d, :right))}, {ps, p}]}

        :default ->
          {:unify, [{dom, default_dom()}, {inf, a("inf")}, {sup, a("sup")}, {ps, no_props()}]}

        :fail ->
          :fail
      end
    end)
  end

  # --- Einreihen ---

  # insert_queue//2: Element ans Ende der Liste Nummer which der Queue q
  defp insert(elem, which, q, s) do
    arg =
      case ws(q, s) do
        {tag, "queue", [_, _, _, _] = args} when tag in [:struct, :gstruct] ->
          PrologEx.walk(Enum.at(args, which - 1), s)

        _ ->
          throw(:fallback)
      end

    unless match?({:var, _}, arg), do: throw(:fallback)
    tail = fresh_var()

    case att(arg, s, "queue", 2) do
      [h0, t0] ->
        case PrologEx.unify(t0, [elem | tail], s) do
          {:ok, s} -> put_att(s, arg, mk("queue", [h0, tail]))
          :error -> :fail
        end

      nil ->
        put_att(s, arg, mk("queue", [[elem | tail], tail]))
    end
  end

  defbuiltin "$clpz_insert_queue", [e, which, s0, s1] do
    run("insert_queue", [e, which, s0, s1], subst(), fn ->
      s = subst_now()

      case int(which) do
        k when k in 1..3 ->
          case insert(e, k, state_q(s0, s), s) do
            :fail -> :fail
            s -> finish(s1, s0, s)
          end

        _ ->
          throw(:fallback)
      end
    end)
  end

  # --- Auslösen ---

  @global ~w(pdistinct pnvalue pgcc pgcc_single pcircuit)

  @doc false
  def global_constraints, do: @global

  # trigger_prop//1
  defp trigger(p, q, s) do
    case ws(p, s) do
      {tag, "propagator", [c, state]} when tag in [:struct, :gstruct] ->
        st = PrologEx.walk(state, s)

        cond do
          st == {:atom, "dead"} ->
            s

          match?({:var, _}, st) and queued?(st, s) ->
            s

          current?(st, s) ->
            s

          match?({:var, _}, st) ->
            s = put_att(s, st, mk("clpz_aux", [a("queued")]))
            insert(p, if(global?(c, s), do: 3, else: 2), q, s)

          true ->
            throw(:fallback)
        end

      _ ->
        throw(:fallback)
    end
  end

  defp queued?(st, s) do
    case PrologEx.get_attrs(st, s) |> Map.get("clpz", []) |> att_find(s, "clpz_aux", 1) do
      [v] -> ws(v, s) == {:atom, "queued"}
      nil -> false
    end
  end

  defp current?(st, s) do
    case PrologEx.Builtins.Blackboard.b_value("clpz", "$clpz_current_propagator", s) do
      {:ok, c} -> PrologEx.Order.equal?(c, st, s)
      _ -> false
    end
  end

  defp global?(c, s) do
    case ws(c, s) do
      {tag, f, _} when tag in [:struct, :gstruct] -> f in @global
      {:atom, f} -> f in @global
      _ -> throw(:fallback)
    end
  end

  defp trigger_all(ps, q, s) do
    Enum.reduce_while(list_items(ps, s), s, fn p, s ->
      case trigger(p, q, s) do
        :fail -> {:halt, :fail}
        s -> {:cont, s}
      end
    end)
  end

  defp then_all(:fail, _ps, _q), do: :fail
  defp then_all(s, ps, q), do: trigger_all(ps, q, s)

  defp props(ps, s) do
    case ws(ps, s) do
      {tag, "fd_props", [gs, bs, os]} when tag in [:struct, :gstruct] -> {gs, bs, os}
      _ -> throw(:fallback)
    end
  end

  defp ground?(x, s), do: PrologEx.Builtins.Order.first_var(x, s) == nil

  # trigger_props//4: nach der Änderung der Domäne von x von d0 zu d
  defp trigger4(ps, x, d0, d, q, s) do
    {gs, bs, os} = props(ps, s)

    s =
      cond do
        ground?(x, s) ->
          s |> then_all(gs, q) |> then_all(bs, q)

        ws(bs, s) != [] ->
          if edge(d0, :left) == edge(d, :left) and edge(d0, :right) == edge(d, :right),
            do: s,
            else: then_all(s, bs, q)

        true ->
          s
      end

    then_all(s, os, q)
  end

  defp result(:fail, _s1, _s0), do: :fail
  defp result(s, s1, s0), do: finish(s1, s0, s)

  defbuiltin "$clpz_trigger_props", [ps, x, d0, d, s0, s1] do
    run("trigger_props", [ps, x, d0, d, s0, s1], subst(), fn ->
      s = subst_now()
      result(trigger4(ps, x, d0, d, state_q(s0, s), s), s1, s0)
    end)
  end

  # trigger_props//2: Os, Bs, und Gs, wenn x ground ist
  defbuiltin "$clpz_trigger_props", [ps, x, s0, s1] do
    run("trigger_props", [ps, x, s0, s1], subst(), fn ->
      s = subst_now()
      q = state_q(s0, s)
      {gs, bs, os} = props(ps, s)
      s = s |> then_all(os, q) |> then_all(bs, q)
      s = if s != :fail and ground?(x, s), do: then_all(s, gs, q), else: s
      result(s, s1, s0)
    end)
  end

  # trigger_props//1: alle
  defbuiltin "$clpz_trigger_props", [ps, s0, s1] do
    run("trigger_props", [ps, s0, s1], subst(), fn ->
      s = subst_now()
      q = state_q(s0, s)
      {gs, bs, os} = props(ps, s)
      result(s |> then_all(gs, q) |> then_all(bs, q) |> then_all(os, q), s1, s0)
    end)
  end

  defbuiltin "$clpz_trigger_prop", [p, s0, s1] do
    run("trigger_prop", [p, s0, s1], subst(), fn ->
      s = subst_now()
      result(trigger(p, state_q(s0, s), s), s1, s0)
    end)
  end

  # --- Ablegen: put_terminating//3 (fd_put//3) ---

  defp put_clpz(s, v, fields), do: put_att(s, v, mk("clpz", [mk("clpz_attr", fields)]))

  defp yes, do: a("yes")

  defp put_terminating(x, dom, ps, q, s) do
    case ws(dom, s) do
      {:atom, "empty"} ->
        :fail

      {tag, "from_to", [f, t]} = d when tag in [:struct, :gstruct] ->
        if bound(f) == bound(t),
          do: insert(mk("=", [f, mk("n", [x])]), 1, q, s),
          else: put_dom(x, d, dom, ps, q, s)

      _ ->
        put_dom(x, nil, dom, ps, q, s)
    end
  end

  defp put_dom(x, _d, dom, ps, q, s) do
    case PrologEx.walk(x, s) do
      {:var, _} = v ->
        case att(v, s, "clpz", 1) do
          [attr] ->
            case ws(attr, s) do
              {tag, "clpz_attr", [left, right, spread, old_dom, _old_ps, qx]}
              when tag in [:struct, :gstruct] ->
                s = put_clpz(s, v, [left, right, spread, dom, ps, qx])

                if PrologEx.Order.equal?(old_dom, dom, s),
                  do: s,
                  else: changed(v, left, right, spread, old_dom, dom, ps, qx, q, s)

              _ ->
                throw(:fallback)
            end

          nil ->
            put_clpz(s, v, [a("no"), a("no"), a("no"), dom, ps, new_queue()])
        end

      _ ->
        s
    end
  end

  # die Domäne hat sich geändert: Terminierung (Ränder und Spanne höchstens
  # einmal ändern, außer die Domäne ist beschränkt), dann auslösen
  defp changed(v, left, right, spread, old_dom, dom, ps, qx, q, s) do
    l = ws(left, s)
    dot = a(".")
    inf = if l == dot, do: nil, else: edge(dom, :left)
    sup = if l == dot, do: nil, else: edge(dom, :right)

    if l == dot or (is_integer(inf) and is_integer(sup)) do
      s = put_clpz(s, v, [dot, dot, dot, dom, ps, qx])
      trigger4(ps, v, old_dom, dom, q, s)
    else
      leftp = if inf == edge(old_dom, :left), do: left, else: yes()
      rightp = if sup == edge(old_dom, :right), do: right, else: yes()
      old_spread = spread_of(old_dom)
      new_spread = spread_of(dom)

      spreadp =
        cond do
          new_spread == old_spread -> spread
          lt(new_spread, old_spread) -> a("no")
          true -> yes()
        end

      s = put_clpz(s, v, [leftp, rightp, spreadp, dom, ps, qx])
      y = {:atom, "yes"}

      cond do
        ws(rightp, s) == y and ws(right, s) == y -> s
        ws(leftp, s) == y and ws(left, s) == y -> s
        ws(spreadp, s) == y and ws(spread, s) == y -> s
        true -> trigger4(ps, v, old_dom, dom, q, s)
      end
    end
  end

  # domain_spread/2 (Fehlschlag des Originals: das Original rechnet)
  defp spread_of(d) do
    dd = dom(d)

    with s when s != nil <- smallest_finite(dd),
         l when l != nil <- largest_finite(dd) do
      minus(l, s)
    else
      nil -> throw(:fallback)
    end
  end

  defbuiltin "$clpz_put_terminating", [x, dom, ps, s0, s1] do
    run("put_terminating", [x, dom, ps, s0, s1], subst(), fn ->
      s = subst_now()
      result(put_terminating(x, dom, ps, state_q(s0, s), s), s1, s0)
    end)
  end

  # --- Entnehmen: der nächste Eintrag für do_queue//0 ---

  # vorne aus Liste which: {Element, s} oder nil
  defp pop(args, which, s) do
    arg = PrologEx.walk(Enum.at(args, which - 1), s)

    with {:var, _} <- arg,
         [h, t] <- att(arg, s, "queue", 2),
         {e, es} <- cell(h, s) do
      s =
        if match?({:var, _}, PrologEx.walk(es, s)),
          do: del_att(s, arg, "queue", 2),
          else: put_att(s, arg, mk("queue", [es, t]))

      {e, s}
    else
      _ -> nil
    end
  end

  # '$clpz_queue_next'(S0, Next): Next = goal(G), prop(P) oder none (die
  # Queue ist leer oder abgeschaltet), wie queue_enabled//0 und
  # queue_get_goal//1, queue_get_fast//1, queue_get_slow//1 in do_queue//0
  defbuiltin "$clpz_queue_next", [s0, next] do
    run("queue_next", [s0, next], subst(), fn ->
      s = subst_now()

      args =
        case ws(state_q(s0, s), s) do
          {tag, "queue", [_, _, _, _] = args} when tag in [:struct, :gstruct] -> args
          _ -> throw(:fallback)
        end

      aux = PrologEx.walk(Enum.at(args, 3), s)

      {t, s} =
        cond do
          match?({:var, _}, aux) and att(aux, s, "disabled", 0) != nil ->
            {a("none"), s}

          r = pop(args, 1, s) ->
            {e, s} = r
            {mk("goal", [e]), s}

          r = pop(args, 2, s) ->
            {e, s} = r
            {mk("prop", [e]), s}

          r = pop(args, 3, s) ->
            {e, s} = r
            {mk("prop", [e]), s}

          true ->
            {a("none"), s}
        end

      case PrologEx.unify(next, t, s) do
        {:ok, s} -> {:subst, s}
        :error -> :fail
      end
    end)
  end

  # --- Propagatoren: activate_propagator//1 ----------------------------------
  #
  # In Elixir die Zweige, die nur Domänen ändern (fd_put//3, das Ziele für
  # Bindungen in die Queue stellt), Propagatoren töten (kill/1) oder prüfen,
  # dazu Zweige mit einer Bindung als letzter Aktion (bind/3; die Maschine
  # weckt danach wie nach dem Original). Ein Zweig mit mehreren Bindungen
  # oder neuen Bedingungen und jeder andere Propagator: das Original
  # (activate_propagator_ref//1) – vorher ist nichts geändert, Reihenfolge
  # und Wecken bleiben also wie dort.

  @ported ~w(pneq absdiff_neq pexclude pdifferent pplus scalar_product_eq pdistinct pcircuit
             reified_geq reified_and scalar_product_leq pgeq ptimes pmax pmin)

  defbuiltin "$clpz_activate", [prop, s0, s1] do
    run("activate_propagator", [prop, s0, s1], subst(), fn ->
      s = subst_now()
      q = state_q(s0, s)

      {p, state} =
        case ws(prop, s) do
          {tag, "propagator", [p, st]} when tag in [:struct, :gstruct] -> {p, st}
          _ -> throw(:fallback)
        end

      st = PrologEx.walk(state, s)

      cond do
        st == {:atom, "dead"} ->
          finish(s1, s0, s)

        not match?({:var, _}, st) ->
          throw(:fallback)

        true ->
          {name, args} =
            case ws(p, s) do
              {tag, n, args} when tag in [:struct, :gstruct] and n in @ported -> {n, args}
              _ -> throw(:fallback)
            end

          s = del_att(s, st, "clpz_aux", 1)

          # no_reactivation (pdistinct): der laufende Propagator steht in
          # '$clpz_current_propagator' (trigger_prop//1 reiht ihn nicht ein)
          if name == "pdistinct" do
            s = Blackboard.b_put(s, "clpz", "$clpz_current_propagator", st)

            case propagate(name, args, st, q, s) do
              :fail -> :fail
              s -> Blackboard.b_put(s, "clpz", "$clpz_current_propagator", [])
            end
            |> result(s1, s0)
          else
            result(propagate(name, args, st, q, s), s1, s0)
          end
      end
    end)
  end

  # Werte: ganze Zahl, Variable oder (sonst) das Original
  defp val(t, s) do
    case PrologEx.walk(t, s) do
      i when is_integer(i) -> i
      {:var, _} = v -> v
      _ -> throw(:fallback)
    end
  end

  defp var?({:var, _}), do: true
  defp var?(_), do: false

  # kill/1: del_attr(State, clpz_aux), State = dead
  defp kill(st, s) do
    st = PrologEx.walk(st, s)
    s = if var?(st), do: del_att(s, st, "clpz_aux", 1), else: s

    case PrologEx.unify(st, a("dead"), s) do
      {:ok, s} -> s
      :error -> :fail
    end
  end

  # fd_get/3 einer Variablen: {Domäne (dekodiert), Ps}
  defp fdget(v, s) do
    case fd_get(v, s) do
      {d, ps} -> {dom(d), ps}
      :default -> {{:ft, :inf, :sup}, no_props()}
      :fail -> throw(:fallback)
    end
  end

  # fd_put//3 mit einer dekodierten Domäne
  defp fdput(_v, _d, _ps, _q, :fail), do: :fail
  defp fdput(v, d, ps, q, s), do: put_terminating(v, ed(d), ps, q, s)

  # Schritte nacheinander, :fail bricht ab
  defp seq(:fail, _f), do: :fail
  defp seq(s, f), do: f.(s)

  # neq_num//2: x ≠ n
  defp neq_num(x, n, q, s) do
    case val(x, s) do
      {:var, _} = v ->
        {d, ps} = fdget(v, s)
        fdput(v, remove(d, n), ps, q, s)

      i ->
        if i != n, do: s, else: :fail
    end
  end

  # domains_intersection/3: nil (leer) = Fehlschlag
  defp isect(d1, d2) do
    case intersection_(d1, d2) do
      :empty -> nil
      d -> d
    end
  end

  defp put_isect(v, d, d2, ps, q, s) do
    case isect(d, d2) do
      nil -> :fail
      r -> fdput(v, r, ps, q, s)
    end
  end

  defp aux(q, s) do
    case ws(q, s) do
      {tag, "queue", [_, _, _, aux]} when tag in [:struct, :gstruct] ->
        case PrologEx.walk(aux, s) do
          {:var, _} = v -> v
          _ -> throw(:fallback)
        end

      _ ->
        throw(:fallback)
    end
  end

  defp disable_queue(q, s), do: put_att(s, aux(q, s), a("disabled"))
  defp enable_queue(_q, :fail), do: :fail
  defp enable_queue(q, s), do: del_att(s, aux(q, s), "disabled", 0)

  # --- pneq(A, B): A ≠ B ---

  defp propagate("pneq", [a0, b0], st, q, s) do
    case {val(a0, s), val(b0, s)} do
      {a, b} when is_integer(a) and is_integer(b) ->
        if a != b, do: kill(st, s), else: :fail

      {a, {:var, _} = b} when is_integer(a) ->
        {bd, bps} = fdget(b, s)
        bd1 = remove(bd, a)
        s |> kill_then(st) |> then_put(b, bd1, bps, q)

      {{:var, _}, b} when is_integer(b) ->
        propagate("pneq", [b0, a0], st, q, s)

      {a, b} ->
        if a == b do
          :fail
        else
          {ad, _} = fdget(a, s)
          {bd, _} = fdget(b, s)

          cond do
            lt(sup_d(ad), inf_d(bd)) -> kill(st, s)
            gt(inf_d(ad), sup_d(bd)) -> kill(st, s)
            true -> s
          end
        end
    end
  end

  # --- absdiff_neq(X, Y, C): |X - Y| ≠ C ---

  defp propagate("absdiff_neq", [x0, y0, c0], st, q, s) do
    c =
      case val(c0, s) do
        i when is_integer(i) -> i
        _ -> throw(:fallback)
      end

    cond do
      c < 0 ->
        kill(st, s)

      is_integer(val(x0, s)) ->
        x = val(x0, s)
        s = kill(st, s)

        case val(y0, s) do
          y when is_integer(y) ->
            if abs(x - y) != c, do: s, else: :fail

          y ->
            s |> seq(&neq_num(y, x - c, q, &1)) |> seq(&neq_num(y, c + x, q, &1))
        end

      is_integer(val(y0, s)) ->
        y = val(y0, s)
        x = val(x0, s)
        s = kill(st, s)
        s |> seq(&neq_num(x, c + y, q, &1)) |> seq(&neq_num(x, y - c, q, &1))

      true ->
        s
    end
  end

  # --- pexclude(Left, Right, X), pdifferent(Left, Right, X, _) ---

  defp propagate("pdifferent", [l, r, x, _], st, q, s),
    do: propagate("pexclude", [l, r, x], st, q, s)

  defp propagate("pexclude", [l, r, x0], _st, q, s) do
    if ground?(x0, s) do
      x =
        case val(x0, s) do
          i when is_integer(i) -> i
          _ -> throw(:fallback)
        end

      s = disable_queue(q, s)

      s =
        Enum.reduce(list_items(l, s) ++ list_items(r, s), s, fn v, s ->
          seq(s, &neq_num(v, x, q, &1))
        end)

      enable_queue(q, s)
    else
      s
    end
  end

  # --- pplus(X, Y, Z, Morph): X + Y = Z ---

  defp propagate("pplus", [x0, y0, z0, m], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      is_integer(x) ->
        cond do
          x == 0 -> s |> kill_then(st) |> bind(y0, z0)
          # Y == Z: kill(MState), X =:= 0 – scheitert (X ≠ 0)
          y == z -> :fail
          is_integer(y) -> s |> kill_then(st) |> bind(z0, x + y)
          is_integer(z) -> s |> kill_then(st) |> bind(y0, z - x)
          true -> plus_x(x, y, z, q, s)
        end

      is_integer(y) ->
        propagate("pplus", [y0, x0, z0, m], st, q, s)

      is_integer(z) ->
        cond do
          x != y -> plus_z(x, y, z, q, s)
          # kill(MState), even(Z), X is Z // 2
          rem(z, 2) == 0 -> s |> kill_then(st) |> bind(x0, div(z, 2))
          true -> s |> kill_then(st) |> then_fail()
        end

      # morph_into_propagator//4 (ptimes(2, X, Z)): das Original
      x == y ->
        throw(:fallback)

      x == z ->
        s |> kill_then(st) |> bind(y0, 0)

      y == z ->
        s |> kill_then(st) |> bind(x0, 0)

      true ->
        plus_bounds(x, y, z, q, s)
    end
  end

  # --- scalar_product_eq(Cs, Vs, P): Σ C·V = P ---

  defp propagate("scalar_product_eq", [cs0, vs0, p0], st, q, s) do
    p0 =
      case val(p0, s) do
        i when is_integer(i) -> i
        _ -> throw(:fallback)
      end

    {cvs, i} = coeffs_vars(list_items(cs0, s), list_items(vs0, s), s)
    p = p0 - i
    cs = Enum.map(cvs, &elem(&1, 0))

    cond do
      cvs == [] ->
        s = kill(st, s)
        if s != :fail and p == 0, do: s, else: :fail

      match?([_], cvs) ->
        throw(:fallback)

      cs in [[1, 1], [1, -1], [-1, 1], [-1, -1]] ->
        throw(:fallback)

      p == 0 and cs in [[1, 1, -1], [1, -1, 1], [-1, 1, 1]] ->
        throw(:fallback)

      true ->
        if Enum.any?(cs, &(&1 == 0)), do: throw(:fallback)
        {infs, sups, inf, sup} = sum_finite(cvs, s)
        d1 = p - inf
        d2 = sup - p
        s = disable_queue(q, s)

        s =
          cond do
            infs == [] and sups == [] ->
              if inf <= p and p <= sup, do: remove_dist_ul(cvs, d1, d2, q, s), else: :fail

            sups == [] ->
              if p <= sup, do: remove_dist_lower(infs, d2, q, s), else: :fail

            infs == [] ->
              if inf <= p, do: remove_dist_upper(sups, d1, q, s), else: :fail

            match?([_], sups) and match?([_], infs) ->
              s |> seq(&remove_lower(sups, d2, q, &1)) |> seq(&remove_upper(infs, d1, q, &1))

            match?([_], infs) ->
              remove_upper(infs, d1, q, s)

            match?([_], sups) ->
              remove_lower(sups, d2, q, s)

            true ->
              s
          end

        enable_queue(q, s)
    end
  end

  # --- reified_geq(DX, X, DY, Y, Ps, B): B ⇔ X ≥ Y (DX, DY: definiert) ---
  #
  # Bindungen: nur als letzte Aktion eines Zweigs (bind/3 unten), wie im
  # Original; dort weckt die Maschine danach, vor dem nächsten Ziel. Zweige
  # mit mehreren Bindungen oder neuen Bedingungen: das Original.

  defp propagate("reified_geq", [dx0, x0, dy0, y0, ps, b0], st, _q, s) do
    dx = PrologEx.walk(dx0, s)
    dy = PrologEx.walk(dy0, s)
    b = PrologEx.walk(b0, s)

    cond do
      dx == 0 or dy == 0 ->
        s |> kill2(st, ps) |> bind(b0, 0)

      b == 1 ->
        throw(:fallback)

      dx == 1 and dy == 1 ->
        if var?(b) do
          reified_geq_open(val(x0, s), val(y0, s), st, ps, b0, s)
        else
          # B = 0: X #< Y aufstellen (das Original); sonst nichts
          case b do
            0 -> throw(:fallback)
            i when is_integer(i) -> s
            _ -> throw(:fallback)
          end
        end

      true ->
        s
    end
  end

  # --- reified_and(X, Ps1, Y, Ps2, B): B ⇔ X ∧ Y ---

  defp propagate("reified_and", [x0, ps1, y0, ps2, b0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)

    cond do
      is_integer(x) ->
        s = kill(st, s)

        if x == 0,
          do: s |> kill_entailed_all(ps2) |> bind(b0, 0),
          else: bind(s, b0, y0)

      is_integer(y) ->
        propagate("reified_and", [y0, ps2, x0, ps1, b0], st, q, s)

      # X = 1, Y = 1: zwei Bindungen (das Original)
      PrologEx.walk(b0, s) == 1 ->
        throw(:fallback)

      true ->
        s
    end
  end

  # --- scalar_product_leq(Cs, Vs, P): Σ C·V ≤ P ---

  defp propagate("scalar_product_leq", [cs0, vs0, p0], st, q, s) do
    p0 =
      case val(p0, s) do
        i when is_integer(i) -> i
        _ -> throw(:fallback)
      end

    {cvs, i} = coeffs_vars(list_items(cs0, s), list_items(vs0, s), s)
    p = p0 - i

    if cvs == [] do
      s = kill(st, s)
      if s != :fail and p >= 0, do: s, else: :fail
    else
      if Enum.any?(cvs, &(elem(&1, 0) == 0)), do: throw(:fallback)
      {infs, sups, inf, sup} = sum_finite(cvs, s)
      d1 = p - inf
      s = disable_queue(q, s)

      s =
        cond do
          infs == [] and sups == [] ->
            cond do
              inf > p -> :fail
              sup <= p -> kill(st, s)
              true -> remove_dist_upper_leq(cvs, d1, q, s)
            end

          infs == [] ->
            if inf <= p, do: remove_dist_upper(sups, d1, q, s), else: :fail

          match?([_], infs) ->
            remove_upper(infs, d1, q, s)

          true ->
            s
        end

      enable_queue(q, s)
    end
  end

  # --- pgeq(A, B): A ≥ B ---

  defp propagate("pgeq", [a0, b0], st, q, s) do
    a = val(a0, s)
    b = val(b0, s)

    cond do
      a == b ->
        kill(st, s)

      is_integer(a) and is_integer(b) ->
        s = kill(st, s)
        if s != :fail and a >= b, do: s, else: :fail

      is_integer(a) ->
        {bd, bps} = fdget(b, s)
        bd1 = remove_gt(bd, a)
        s |> kill_then(st) |> then_put(b, bd1, bps, q)

      is_integer(b) ->
        {ad, aps} = fdget(a, s)
        ad1 = remove_lt(ad, b)
        s |> kill_then(st) |> then_put(a, ad1, aps, q)

      true ->
        {ad, aps} = fdget(a, s)
        {al, au} = {inf_dec(ad), sup_dec(ad)}
        {bd, _} = fdget(b, s)
        {bl, bu} = {inf_dec(bd), sup_dec(bd)}

        cond do
          not geq(au, bl) ->
            :fail

          geq(al, bu) ->
            kill(st, s)

          # A = B: eine Bindung am Ende
          au == bl ->
            s |> kill_then(st) |> bind(a0, b0)

          true ->
            case isect(ad, {:ft, bmax(al, bl), au}) do
              nil ->
                :fail

              nad ->
                s
                |> seq(&fdput(a, nad, aps, q, &1))
                |> seq(fn s ->
                  case val(b, s) do
                    {:var, _} ->
                      {bd2, bps2} = fdget(b, s)
                      put_isect(b, bd2, {:ft, inf_dec(bd2), bmin(sup_dec(bd2), au)}, bps2, q, s)

                    _ ->
                      s
                  end
                end)
            end
        end
    end
  end

  # --- ptimes(X, Y, Z, Morph): X·Y = Z ---
  #
  # Bindungen nur als letzte Aktion eines Zweigs; neue Bedingungen
  # (X in NR \/ R), morph_into_propagator//4 (X == Y) und die Sonderfälle
  # von min_max_factor/8 (Hilfsbedingungen unter findall/3): das Original

  defp propagate("ptimes", [x0, y0, z0, m], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      is_integer(x) ->
        cond do
          is_integer(y) ->
            s |> kill_then(st) |> bind(z0, x * y)

          x == 0 ->
            s |> kill_then(st) |> bind(z0, 0)

          x == 1 ->
            s |> kill_then(st) |> bind(z0, y0)

          is_integer(z) ->
            s = kill(st, s)

            if s != :fail and rem(z, x) == 0,
              do: bind(s, y0, div(z, x)),
              else: :fail

          y == z ->
            s |> kill_then(st) |> bind(y0, 0)

          true ->
            times_x(x, y, z, q, s)
        end

      is_integer(y) ->
        propagate("ptimes", [y0, x0, z0, m], st, q, s)

      is_integer(z) ->
        if x == y, do: throw(:fallback), else: times_z(x, y, z, st, q, s)

      x == y ->
        throw(:fallback)

      true ->
        times_bounds(x, y, z, st, q, s)
    end
  end

  # --- pmax(X, Y, Z): Z = max(X, Y) ---
  #
  # Ziele über queue_goal//1 wie im Original (keine Bindung hier)

  defp propagate("pmax", [x0, y0, z0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      is_integer(x) ->
        cond do
          is_integer(y) ->
            s |> kill_then(st) |> goal(mk("is", [z0, mk("max", [x0, y0])]), q)

          is_integer(z) ->
            cond do
              z == x -> s |> kill_then(st) |> goal(mk("#>=", [x0, y0]), q)
              z > x -> goal(s, mk("=", [z0, y0]), q)
              true -> :fail
            end

          y == z ->
            s |> kill_then(st) |> goal(mk("#>=", [y0, x0]), q)

          true ->
            {yd, _} = fdget(y, s)

            cond do
              gt(inf_dec(yd), x) ->
                goal(s, mk("=", [z0, y0]), q)

              lt(sup_dec(yd), x) ->
                goal(s, mk("=", [z0, x0]), q)

              is_integer(sup_dec(yd)) ->
                {zd, zps} = fdget(z, s)
                fdput(z, remove_gt(zd, sup_dec(yd)), zps, q, s)

              true ->
                s
            end
        end

      is_integer(y) ->
        propagate("pmax", [y0, x0, z0], st, q, s)

      is_integer(z) ->
        s

      true ->
        {zd, zps} = fdget(z, s)
        {xd, _} = fdget(x, s)
        {yd, _} = fdget(y, s)

        cond do
          gt(inf_dec(yd), sup_dec(xd)) ->
            s |> kill_then(st) |> goal(mk("=", [z0, y0]), q)

          lt(sup_dec(yd), inf_dec(xd)) ->
            s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)

          is_integer(bmax(sup_dec(xd), sup_dec(yd))) ->
            fdput(z, remove_gt(zd, bmax(sup_dec(xd), sup_dec(yd))), zps, q, s)

          true ->
            s
        end
    end
  end

  # --- pmin(X, Y, Z): Z = min(X, Y) ---

  defp propagate("pmin", [x0, y0, z0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      is_integer(x) ->
        cond do
          is_integer(y) ->
            s |> kill_then(st) |> bind(z0, min(x, y))

          is_integer(z) ->
            cond do
              # X #=< Y aufstellen: das Original
              z == x -> throw(:fallback)
              z < x -> bind(s, z0, y0)
              true -> :fail
            end

          y == z ->
            s |> kill_then(st) |> goal(mk("#=<", [y0, x0]), q)

          true ->
            {yd, _} = fdget(y, s)

            cond do
              lt(sup_dec(yd), x) ->
                bind(s, z0, y0)

              gt(inf_dec(yd), x) ->
                bind(s, z0, x0)

              is_integer(inf_dec(yd)) ->
                {zd, zps} = fdget(z, s)
                fdput(z, remove_lt(zd, inf_dec(yd)), zps, q, s)

              true ->
                s
            end
        end

      is_integer(y) ->
        propagate("pmin", [y0, x0, z0], st, q, s)

      is_integer(z) ->
        s

      true ->
        {zd, zps} = fdget(z, s)
        {xd, _} = fdget(x, s)
        {yd, _} = fdget(y, s)

        cond do
          lt(sup_dec(yd), inf_dec(xd)) ->
            s |> kill_then(st) |> bind(z0, y0)

          gt(inf_dec(yd), sup_dec(xd)) ->
            s |> kill_then(st) |> bind(z0, x0)

          is_integer(bmin(inf_dec(xd), inf_dec(yd))) ->
            fdput(z, remove_lt(zd, bmin(inf_dec(xd), inf_dec(yd))), zps, q, s)

          true ->
            s
        end
    end
  end

  # --- pdistinct(Vs), pcircuit(Vs): siehe unten (all_distinct/1, circuit/1) ---

  defp propagate("pdistinct", [vs], _st, q, s), do: distinct(vs, q, s)

  defp propagate("pcircuit", [vs], _st, q, s) do
    case distinct(vs, q, s) do
      :fail -> :fail
      s -> if circuit_connected?(vs, s), do: s, else: :fail
    end
  end

  defp kill_then(s, st), do: kill(st, s)

  defp then_fail(_s), do: :fail

  # X = T als letzte Aktion (die Maschine weckt danach)
  defp bind(:fail, _x, _t), do: :fail

  defp bind(s, x, t) do
    case PrologEx.unify(x, t, s) do
      {:ok, s} -> s
      :error -> :fail
    end
  end

  # kill(State, Ps): kill(State), dann kill_entailed/1 für jedes Element
  defp kill2(s, st, ps), do: s |> kill_then(st) |> kill_entailed_all(ps)

  defp kill_entailed_all(:fail, _ps), do: :fail

  defp kill_entailed_all(s, ps) do
    Enum.reduce(list_items(ps, s), s, fn e, s -> seq(s, &kill_entailed(e, &1)) end)
  end

  defp kill_entailed(e, s) do
    case ws(e, s) do
      {tag, "p", [prop]} when tag in [:struct, :gstruct] ->
        case ws(prop, s) do
          {t2, "propagator", [_, state]} when t2 in [:struct, :gstruct] -> kill(state, s)
          _ -> throw(:fallback)
        end

      {tag, "a", [v]} when tag in [:struct, :gstruct] ->
        del_clpz(v, s)

      {tag, "a", [x, b]} when tag in [:struct, :gstruct] ->
        if PrologEx.walk(x, s) == PrologEx.walk(b, s), do: s, else: del_clpz(b, s)

      {tag, "a", [x, y, b]} when tag in [:struct, :gstruct] ->
        bw = PrologEx.walk(b, s)

        if PrologEx.walk(x, s) == bw or PrologEx.walk(y, s) == bw,
          do: s,
          else: del_clpz(b, s)

      _ ->
        throw(:fallback)
    end
  end

  # del_attr(V, clpz): nur für eine Variable
  defp del_clpz(v, s) do
    case PrologEx.walk(v, s) do
      {:var, _} = var -> del_att(s, var, "clpz", 1)
      _ -> s
    end
  end

  # reified_geq mit DX = DY = 1 und offenem B
  defp reified_geq_open(x, y, st, ps, b0, s) do
    cond do
      is_integer(x) and is_integer(y) ->
        s |> kill_then(st) |> bind(b0, if(x >= y, do: 1, else: 0))

      is_integer(x) ->
        {yd, _} = fdget(y, s)

        cond do
          geq(x, sup_dec(yd)) -> s |> kill2(st, ps) |> bind(b0, 1)
          lt(x, inf_dec(yd)) -> s |> kill2(st, ps) |> bind(b0, 0)
          true -> s
        end

      is_integer(y) ->
        {xd, _} = fdget(x, s)

        cond do
          geq(inf_dec(xd), y) -> s |> kill2(st, ps) |> bind(b0, 1)
          lt(sup_dec(xd), y) -> s |> kill2(st, ps) |> bind(b0, 0)
          true -> s
        end

      x == y ->
        s |> kill2(st, ps) |> bind(b0, 1)

      true ->
        {xd, _} = fdget(x, s)
        {yd, _} = fdget(y, s)

        cond do
          geq(inf_dec(xd), sup_dec(yd)) -> s |> kill2(st, ps) |> bind(b0, 1)
          lt(sup_dec(xd), inf_dec(yd)) -> s |> kill2(st, ps) |> bind(b0, 0)
          true -> s
        end
    end
  end

  # queue_goal//1
  defp goal(:fail, _g, _q), do: :fail
  defp goal(s, g, q), do: insert(g, 1, q, s)

  # domain_contains/2 auf einer dekodierten Domäne
  defp dcontains?(:empty, _), do: false
  defp dcontains?({:ft, f, t}, i), do: leq(f, i) and leq(i, t)

  defp dcontains?({:sp, sp, l, r}, i),
    do: (i < sp and dcontains?(l, i)) or (i > sp and dcontains?(r, i))

  # domain_expand/3, domain_contract/3 (X ≠ 0, 1)
  defp dexpand(d, m) when m < 0, do: expand_(negate(d), -m)
  defp dexpand(d, m), do: expand_(d, m)

  defp dcontract(d, m) do
    {dd, mm} = neg_abs(d, m)

    case contract_(dd, mm) do
      nil -> throw(:fallback)
      r -> r
    end
  end

  # ptimes, X bekannt: Z ∩ X·Y, dann Y ∩ Z/X
  defp times_x(x, y, z, q, s) do
    {yd, _} = fdget(y, s)
    {zd, zps} = fdget(z, s)

    case isect(zd, dexpand(yd, x)) do
      nil ->
        :fail

      zd1 ->
        s
        |> seq(&fdput(z, zd1, zps, q, &1))
        |> seq(fn s ->
          {yd2, yps2} = fdget(y, s)
          put_isect(y, yd2, dcontract(zd1, x), yps2, q, s)
        end)
    end
  end

  # ptimes, Z bekannt
  defp times_z(x, y, z, st, q, s) do
    {xd, xps} = fdget(x, s)
    {xl, xu} = {inf_dec(xd), sup_dec(xd)}
    {yd, _} = fdget(y, s)
    {yl, yu} = {inf_dec(yd), sup_dec(yd)}
    {nxl, nxu} = min_max_factor(z, z, yl, yu, xl, xu)

    s
    |> seq(&update_bounds(x, xd, xps, xl, xu, nxl, nxu, q, &1))
    |> seq(fn s ->
      {yd2, yps2} = fdget(y, s)
      {yl2, yu2} = {inf_dec(yd2), sup_dec(yd2)}
      {nyl, nyu} = min_max_factor(z, z, nxl, nxu, yl2, yu2)
      update_bounds(y, yd2, yps2, yl2, yu2, nyl, nyu, q, s)
    end)
    |> seq(fn s ->
      cond do
        z != 0 -> s |> neq_num_then(x, q) |> neq_num_then(y, q)
        not dcontains?(xd, 0) -> s |> kill_then(st) |> bind(y, 0)
        not dcontains?(yd, 0) -> s |> kill_then(st) |> bind(x, 0)
        true -> s
      end
    end)
  end

  defp neq_num_then(:fail, _v, _q), do: :fail
  defp neq_num_then(s, v, q), do: neq_num(v, 0, q, s)

  # ptimes, alle offen: Schranken
  defp times_bounds(x, y, z, st, q, s) do
    {xd, xps} = fdget(x, s)
    {xl, xu} = {inf_dec(xd), sup_dec(xd)}
    {yd, _} = fdget(y, s)
    {yl, yu} = {inf_dec(yd), sup_dec(yd)}
    {zd, _} = fdget(z, s)
    {zl, zu} = {inf_dec(zd), sup_dec(zd)}

    cond do
      y == z and not dcontains?(zd, 0) ->
        s |> kill_then(st) |> bind(x, 1)

      x == z and not dcontains?(zd, 0) ->
        s |> kill_then(st) |> bind(y, 1)

      true ->
        {nxl, nxu} = min_max_factor(zl, zu, yl, yu, xl, xu)
        s = update_bounds(x, xd, xps, xl, xu, nxl, nxu, q, s)

        {s, nyl, nyu} =
          case s do
            :fail ->
              {:fail, nil, nil}

            s ->
              {yd2, yps2} = fdget(y, s)
              {yl2, yu2} = {inf_dec(yd2), sup_dec(yd2)}
              {nyl, nyu} = min_max_factor(zl, zu, nxl, nxu, yl2, yu2)
              {update_bounds(y, yd2, yps2, yl2, yu2, nyl, nyu, q, s), nyl, nyu}
          end

        seq(s, fn s ->
          {zd2, zps2} = fdget(z, s)
          {zl2, zu2} = {inf_dec(zd2), sup_dec(zd2)}
          nzl = min_product(nxl, nxu, nyl, nyu)
          nzu = max_product(nxl, nxu, nyl, nyu)

          {s, zd3} =
            if leq(nzl, zl2) and geq(nzu, zu2) do
              {s, zd2}
            else
              case isect(zd2, {:ft, nzl, nzu}) do
                nil -> {:fail, nil}
                zd3 -> {fdput(z, zd3, zps2, q, s), zd3}
              end
            end

          cond do
            s == :fail -> :fail
            dcontains?(zd3, 0) -> s
            true -> s |> neq_num_then(x, q) |> neq_num_then(y, q)
          end
        end)
    end
  end

  defp min_product(l1, u1, l2, u2),
    do: bmin(bmin(times(l1, l2), times(l1, u2)), bmin(times(u1, l2), times(u1, u2)))

  defp max_product(l1, u1, l2, u2),
    do: bmax(bmax(times(l1, l2), times(l1, u2)), bmax(times(u1, l2), times(u1, u2)))

  # min_max_factor/8: Schranken von X3 mit X1 = X2·X3 (X1 in L1..U1, X2 in
  # L2..U2, X3 in L3..U3); die beiden Sonderfälle mit Hilfsbedingungen:
  # das Original
  defp min_max_factor(l1, u1, l2, u2, l3, u3) do
    spans2 = lt(l2, 0) and gt(u2, 0) and lt(l3, 0) and gt(u3, 0)

    if spans2 and (lt(u1, 0) or gt(l1, 0)) do
      throw(:fallback)
    else
      {bmax(l3, min_factor(l1, u1, l2, u2)), bmin(u3, max_factor(l1, u1, l2, u2))}
    end
  end

  defp min_factor(l1, u1, l2, u2) do
    cond do
      geq(l1, 0) and gt(l2, 0) and is_integer(u2) ->
        bdiv(minus(plus(l1, u2), 1), u2)

      gt(l1, 0) and lt(u2, 0) ->
        bdiv(u1, u2)

      gt(l1, 0) and geq(l2, 0) ->
        1

      gt(l1, 0) ->
        uminus(u1)

      lt(u1, 0) and leq(u2, 0) ->
        if is_integer(l2), do: bdiv(plus(plus(u1, l2), 1), l2), else: 1

      lt(u1, 0) and geq(l2, 0) ->
        bdiv(l1, l2)

      lt(u1, 0) ->
        l1

      leq(l2, 0) and geq(u2, 0) ->
        :inf

      true ->
        bmin(bmin(bdiv(l1, l2), bdiv(l1, u2)), bmin(bdiv(u1, l2), bdiv(u1, u2)))
    end
  end

  defp max_factor(l1, u1, l2, u2) do
    cond do
      geq(l1, 0) and geq(l2, 0) ->
        bdiv(u1, l2)

      gt(l1, 0) and leq(u2, 0) ->
        if is_integer(l2), do: bdiv(minus(minus(l1, l2), 1), l2), else: -1

      gt(l1, 0) ->
        u1

      lt(u1, 0) and lt(u2, 0) ->
        bdiv(l1, u2)

      lt(u1, 0) and geq(l2, 0) ->
        if is_integer(u2), do: bdiv(plus(minus(u1, u2), 1), u2), else: -1

      lt(u1, 0) ->
        uminus(l1)

      leq(l2, 0) and geq(u2, 0) ->
        :sup

      true ->
        bmax(bmax(bdiv(l1, l2), bdiv(l1, u2)), bmax(bdiv(u1, l2), bdiv(u1, u2)))
    end
  end

  # remove_dist_upper_leq//3: je Variable die Schranke über D1 kürzen
  # (eine unendliche Schranke: das Original scheitert)
  defp remove_dist_upper_leq(cvs, d1, q, s) do
    each_cv(cvs, q, s, fn c, vd ->
      if c < 0 do
        case int_bound(sup_dec(vd)) do
          nil -> nil
          sup -> remove_lt(vd, sup + div(d1, c))
        end
      else
        case int_bound(inf_dec(vd)) do
          nil -> nil
          inf -> remove_gt(vd, inf + div(d1, c))
        end
      end
    end)
  end

  defp then_put(s, v, d, ps, q), do: fdput(v, d, ps, q, s)

  defp inf_d(d), do: inf_dec(d)
  defp sup_d(d), do: sup_dec(d)

  defp inf_dec({:ft, f, _}), do: f
  defp inf_dec({:sp, _, l, _}), do: inf_dec(l)
  defp inf_dec(:empty), do: throw(:fallback)

  defp sup_dec({:ft, _, t}), do: t
  defp sup_dec({:sp, _, _, r}), do: sup_dec(r)
  defp sup_dec(:empty), do: throw(:fallback)

  # pplus, X bekannt: Z ∩ (Y + X), dann Y ∩ (ZD1 - X) mit der berechneten
  # Domäne ZD1 (bei einem einzelnen Wert legt fd_put sie nicht ab)
  defp plus_x(x, y, z, q, s) do
    {zd, zps} = fdget(z, s)
    {yd, _} = fdget(y, s)

    case isect(zd, shift(yd, x)) do
      nil ->
        :fail

      zd1 ->
        s
        |> seq(&fdput(z, zd1, zps, q, &1))
        |> seq(fn s ->
          case val(y, s) do
            {:var, _} ->
              {yd1, yps} = fdget(y, s)
              put_isect(y, yd1, shift(zd1, -x), yps, q, s)

            _ ->
              s
          end
        end)
    end
  end

  # pplus, Z bekannt: Y ∩ (Z - X), dann X ∩ (Z - Y)
  defp plus_z(x, y, z, q, s) do
    {xd, _} = fdget(x, s)
    {yd, yps} = fdget(y, s)

    case isect(yd, shift(negate(xd), z)) do
      nil ->
        :fail

      yd2 ->
        s
        |> seq(&fdput(y, yd2, yps, q, &1))
        |> seq(fn s ->
          case val(x, s) do
            {:var, _} ->
              {xd1, xps} = fdget(x, s)
              put_isect(x, xd1, shift(negate(yd2), z), xps, q, s)

            _ ->
              s
          end
        end)
    end
  end

  # pplus, alle offen: Schranken
  defp plus_bounds(x, y, z, q, s) do
    {xd, xps} = fdget(x, s)
    {xl, xu} = {inf_dec(xd), sup_dec(xd)}
    {yd0, _} = fdget(y, s)
    {yl, yu} = {inf_dec(yd0), sup_dec(yd0)}
    {zd0, _} = fdget(z, s)
    {zl, zu} = {inf_dec(zd0), sup_dec(zd0)}
    nxl = bmax(xl, minus(zl, yu))
    nxu = bmin(xu, minus(zu, yl))
    s = update_bounds(x, xd, xps, xl, xu, nxl, nxu, q, s)

    {s, nyl, nyu} =
      case s do
        :fail ->
          {:fail, nil, nil}

        s ->
          case val(y, s) do
            {:var, _} ->
              {yd2, yps2} = fdget(y, s)
              {yl2, yu2} = {inf_dec(yd2), sup_dec(yd2)}
              nyl = bmax(yl2, minus(zl, nxu))
              nyu = bmin(yu2, minus(zu, nxl))
              {update_bounds(y, yd2, yps2, yl2, yu2, nyl, nyu, q, s), nyl, nyu}

            yi ->
              {s, yi, yi}
          end
      end

    seq(s, fn s ->
      case val(z, s) do
        {:var, _} ->
          {zd2, zps2} = fdget(z, s)
          {zl2, zu2} = {inf_dec(zd2), sup_dec(zd2)}
          nzl = bmax(zl2, plus(nxl, nyl))
          nzu = bmin(zu2, plus(nxu, nyu))
          update_bounds(z, zd2, zps2, zl2, zu2, nzl, nzu, q, s)

        _ ->
          s
      end
    end)
  end

  defp update_bounds(_v, _d, _ps, l, u, l, u, _q, s), do: s

  defp update_bounds(v, d, ps, _l, _u, nl, nu, q, s) do
    put_isect(v, d, {:ft, nl, nu}, ps, q, s)
  end

  # coeffs_variables_const/6: [{C, V}] der offenen Variablen und Σ C·V der
  # bekannten
  defp coeffs_vars([], [], _s), do: {[], 0}

  defp coeffs_vars([c | cs], [v | vs], s) do
    c =
      case val(c, s) do
        i when is_integer(i) -> i
        _ -> throw(:fallback)
      end

    {rest, i} = coeffs_vars(cs, vs, s)

    case val(v, s) do
      {:var, _} = var -> {[{c, var} | rest], i}
      n -> {rest, i + c * n}
    end
  end

  defp coeffs_vars(_, _, _s), do: throw(:fallback)

  # sum_finite_domains/10: {Infs, Sups, Inf, Sup}; Infs/Sups die Glieder
  # C·V mit unendlicher Schranke, in der Reihenfolge des Originals
  defp sum_finite(cvs, s) do
    {infs, sups, inf, sup} =
      Enum.reduce(cvs, {[], [], 0, 0}, fn {c, v}, {infs, sups, inf0, sup0} ->
        {d, _} = fdget(v, s)
        {inf1, sup1} = {inf_dec(d), sup_dec(d)}

        {inf2a, sup2a, infs, sups} =
          if is_integer(inf1) do
            if c < 0,
              do: {nil, sup0 + c * inf1, infs, sups},
              else: {inf0 + c * inf1, nil, infs, sups}
          else
            if c < 0,
              do: {nil, sup0, infs, [{c, v} | sups]},
              else: {inf0, nil, [{c, v} | infs], sups}
          end

        {inf2, sup2, infs, sups} =
          if is_integer(sup1) do
            if c < 0,
              do: {inf0 + c * sup1, sup2a, infs, sups},
              else: {inf2a, sup0 + c * sup1, infs, sups}
          else
            if c < 0,
              do: {inf0, sup2a, [{c, v} | infs], sups},
              else: {inf2a, sup0, infs, [{c, v} | sups]}
          end

        {infs, sups, inf2, sup2}
      end)

    {Enum.reverse(infs), Enum.reverse(sups), inf, sup}
  end

  defp each_cv(cvs, q, s, f) do
    Enum.reduce(cvs, s, fn {c, v}, s ->
      seq(s, fn s ->
        case val(v, s) do
          {:var, _} ->
            {d, ps} = fdget(v, s)

            case f.(c, d) do
              nil -> :fail
              d2 -> fdput(v, d2, ps, q, s)
            end

          _ ->
            s
        end
      end)
    end)
  end

  defp int_bound(b) when is_integer(b), do: b
  defp int_bound(_), do: nil

  defp remove_dist_ul(cvs, d1, d2, q, s) do
    each_cv(cvs, q, s, fn c, vd ->
      if c < 0 do
        with sup when sup != nil <- int_bound(sup_dec(vd)),
             vd1 = remove_lt(vd, sup + div(d1, c)),
             false <- vd1 == :empty,
             inf when inf != nil <- int_bound(inf_dec(vd1)) do
          remove_gt(vd1, inf - div(d2, c))
        else
          _ -> nil
        end
      else
        with inf when inf != nil <- int_bound(inf_dec(vd)),
             vd1 = remove_gt(vd, inf + div(d1, c)),
             false <- vd1 == :empty,
             sup when sup != nil <- int_bound(sup_dec(vd1)) do
          remove_lt(vd1, sup - div(d2, c))
        else
          _ -> nil
        end
      end
    end)
  end

  defp remove_dist_upper(cvs, d, q, s) do
    each_cv(cvs, q, s, fn c, vd ->
      if c < 0 do
        case int_bound(sup_dec(vd)) do
          nil -> vd
          sup -> remove_lt(vd, sup + div(d, c))
        end
      else
        case int_bound(inf_dec(vd)) do
          nil -> vd
          inf -> remove_gt(vd, inf + div(d, c))
        end
      end
    end)
  end

  defp remove_dist_lower(cvs, d, q, s) do
    each_cv(cvs, q, s, fn c, vd ->
      if c < 0 do
        case int_bound(inf_dec(vd)) do
          nil -> vd
          inf -> remove_gt(vd, inf - div(d, c))
        end
      else
        case int_bound(sup_dec(vd)) do
          nil -> vd
          sup -> remove_lt(vd, sup - div(d, c))
        end
      end
    end)
  end

  defp remove_upper(cvs, max, q, s) do
    each_cv(cvs, q, s, fn c, xd ->
      d = div(max, c)
      if c < 0, do: remove_lt(xd, d), else: remove_gt(xd, d)
    end)
  end

  defp remove_lower(cvs, min, q, s) do
    each_cv(cvs, q, s, fn c, xd ->
      d = div(-min, c)
      if c < 0, do: remove_gt(xd, d), else: remove_lt(xd, d)
    end)
  end

  # --- all_distinct/1 (Régin) und circuit/1 ---------------------------------
  #
  # distinct//1 des Originals rechnet in with_local_attributes eine Liste
  # neq_num(V, N) (alle Hilfsattribute werden danach zurückgenommen) und
  # wendet sie bei abgeschalteter Queue an. Entfernt wird eine Kante V–N,
  # die in keiner maximalen Paarung liegt: nicht gepaart, N nicht von einem
  # freien Wert aus erreichbar, V und N in verschiedenen starken
  # Komponenten (Régin) – eine Menge, die nicht davon abhängt, welche
  # maximale Paarung man findet. Die Reihenfolge ist die des Originals:
  # die Variablen in der Reihenfolge der Liste, je Variable die Werte
  # absteigend (append_edge/3 hängt vorne an).

  defp distinct(vs, q, s) do
    case distinct_goals(vs, s) do
      :fail ->
        :fail

      gs ->
        s = disable_queue(q, s)
        s = Enum.reduce(gs, s, fn {v, n}, s -> seq(s, &neq_num(v, n, q, &1)) end)
        enable_queue(q, s)
    end
  end

  # [{Variable, Wert}] in der Reihenfolge des Originals, oder :fail
  defp distinct_goals(vs, s) do
    left =
      for v <- list_items(vs, s),
          var?(PrologEx.walk(v, s)),
          v = PrologEx.walk(v, s),
          {d, _} = fdget(v, s),
          {:ok, ns} <- [to_list(d, [])],
          do: {v, ns}

    if length(Enum.uniq_by(left, &elem(&1, 0))) != length(left), do: throw(:fallback)

    n = length(left)
    doms = left |> Enum.map(&elem(&1, 1)) |> List.to_tuple()
    values = left |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq()

    with true <- n <= length(values),
         {:ok, mv} <- matching(doms, n) do
      removable(left, doms, mv, values)
    else
      _ -> :fail
    end
  end

  # maximale Paarung (augmentierende Pfade); {:ok, %{Variable => Wert}}
  # oder :fail, wenn nicht jede Variable einen Wert bekommt
  defp matching(doms, n) do
    Enum.reduce_while(0..(n - 1)//1, {%{}, %{}}, fn i, {mv, mval} ->
      case augment(i, doms, mv, mval, MapSet.new()) do
        {:ok, mv, mval, _} -> {:cont, {mv, mval}}
        {:none, _} -> {:halt, :fail}
      end
    end)
    |> case do
      :fail -> :fail
      {mv, _} -> {:ok, mv}
    end
  end

  defp augment(i, doms, mv, mval, seen) do
    Enum.reduce_while(elem(doms, i), {:none, seen}, fn val, {:none, seen} ->
      if MapSet.member?(seen, val) do
        {:cont, {:none, seen}}
      else
        seen = MapSet.put(seen, val)

        case Map.fetch(mval, val) do
          :error ->
            {:halt, {:ok, Map.put(mv, i, val), Map.put(mval, val, i), seen}}

          {:ok, j} ->
            case augment(j, doms, mv, mval, seen) do
              {:ok, mv, mval, _seen} ->
                {:halt, {:ok, Map.put(mv, i, val), Map.put(mval, val, i), seen}}

              {:none, seen} ->
                {:cont, {:none, seen}}
            end
        end
      end
    end)
  end

  defp removable(left, doms, mv, values) do
    n = length(left)
    matched = MapSet.new(Map.values(mv))
    # Variablen je Wert
    adj =
      Enum.reduce(0..(n - 1)//1, %{}, fn i, acc ->
        Enum.reduce(elem(doms, i), acc, fn val, acc -> Map.update(acc, val, [i], &[i | &1]) end)
      end)

    # gerichteter Graph: gepaart Variable → Wert, sonst Wert → Variable
    succ = fn
      {:v, i} -> [{:n, Map.fetch!(mv, i)}]
      {:n, val} -> for j <- Enum.reverse(Map.get(adj, val, [])), mv[j] != val, do: {:v, j}
    end

    free = for val <- values, not MapSet.member?(matched, val), do: {:n, val}
    reach = reach(free, succ, MapSet.new(free))
    comp = tarjan(Enum.map(0..(n - 1)//1, &{:v, &1}), succ)

    for {{v, ns}, i} <- Enum.with_index(left),
        val <- Enum.reverse(ns),
        mv[i] != val,
        not MapSet.member?(reach, {:n, val}),
        comp[{:v, i}] != comp[{:n, val}],
        do: {v, val}
  end

  defp reach([], _succ, seen), do: seen

  defp reach([x | xs], succ, seen) do
    new = for y <- succ.(x), not MapSet.member?(seen, y), do: y
    reach(new ++ xs, succ, Enum.reduce(new, seen, &MapSet.put(&2, &1)))
  end

  # starke Zusammenhangskomponenten (Tarjan): %{Knoten => Komponente}
  defp tarjan(roots, succ) do
    st = %{index: 0, idx: %{}, low: %{}, stack: [], on: MapSet.new(), comp: %{}}

    Enum.reduce(roots, st, fn v, st ->
      if Map.has_key?(st.idx, v), do: st, else: strong(v, succ, st)
    end).comp
  end

  defp strong(v, succ, st) do
    st = %{
      st
      | idx: Map.put(st.idx, v, st.index),
        low: Map.put(st.low, v, st.index),
        index: st.index + 1,
        stack: [v | st.stack],
        on: MapSet.put(st.on, v)
    }

    st =
      Enum.reduce(succ.(v), st, fn w, st ->
        cond do
          not Map.has_key?(st.idx, w) ->
            st = strong(w, succ, st)
            %{st | low: Map.put(st.low, v, min(st.low[v], st.low[w]))}

          MapSet.member?(st.on, w) ->
            %{st | low: Map.put(st.low, v, min(st.low[v], st.idx[w]))}

          true ->
            st
        end
      end)

    if st.low[v] == st.idx[v], do: pop_comp(v, st.idx[v], st), else: st
  end

  defp pop_comp(v, c, %{stack: [w | rest]} = st) do
    st = %{st | stack: rest, on: MapSet.delete(st.on, w), comp: Map.put(st.comp, w, c)}
    if w == v, do: st, else: pop_comp(v, c, st)
  end

  # propagate_circuit/1: der Graph Knoten k → Werte von V_k ist stark
  # zusammenhängend (gebundene V_k: ihr Wert; ein Wert außerhalb 1..n oder
  # eine unendliche Domäne: scheitert)
  defp circuit_connected?(vs, s) do
    items = list_items(vs, s)
    n = length(items)

    arcs =
      Enum.map(items, fn v ->
        ns =
          case val(v, s) do
            {:var, _} = var ->
              {d, _} = fdget(var, s)

              case to_list(d, []) do
                {:ok, ns} -> ns
                :fail -> nil
              end

            i ->
              [i]
          end

        if ns != nil and Enum.all?(ns, &(&1 in 1..n//1)), do: ns, else: nil
      end)

    cond do
      Enum.any?(arcs, &is_nil/1) ->
        false

      n == 0 ->
        true

      true ->
        # wie im Original: Tarjan ab Knoten 1, alle in dessen Komponente
        g = arcs |> Enum.with_index(1) |> Map.new(fn {ns, k} -> {k, ns} end)
        comp = tarjan(Enum.to_list(1..n), fn k -> Map.fetch!(g, k) end)
        Enum.all?(1..n, &(comp[&1] == comp[1]))
    end
  end
end
