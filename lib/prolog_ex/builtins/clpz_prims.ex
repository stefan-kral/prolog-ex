defmodule PrologEx.Builtins.ClpzPrims do
  @moduledoc """
  Teile von `library(clpz)` (`priv/library/clpz.pl`) in Elixir.

  Domänen und Schranken. Eine Schranke ist eine ganze Zahl, `inf`
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

  # die Queue, deren Schleife gerade in Elixir läuft (siehe native/3)
  @nq :clpz_native_queue
  # (und die Argumente ihres Terms – zum Parken, siehe native/3)
  @nqa :clpz_native_queue_args
  alias PrologEx.Builtins.ClpzDom
  alias PrologEx.Store

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

  defp w(t), do: PrologEx.unmark_top(PrologEx.Store.walk(t, subst_now()))

  # die Substitution des laufenden Builtins (im Prozess abgelegt, siehe defb)
  defp subst_now, do: Process.get(:clpz_prims_subst)

  # Schranke dekodieren: :inf | :sup | ganze Zahl
  defp bound(t) do
    case w(t) do
      {:atom, "inf"} -> :inf
      {:atom, "sup"} -> :sup
      i when is_integer(i) -> i
      _ -> throw(:fallback)
    end
  end

  defp int(t) do
    case w(t) do
      i when is_integer(i) -> i
      _ -> throw(:fallback)
    end
  end

  # Domäne dekodieren: die kanonische Intervallliste von PrologEx.Builtins.ClpzDom
  # aus dem Prolog-Term [inf..3, 5, 9..13, 16..sup]. Geprüft wird nur die
  # Form der Elemente, nicht die Ordnung: die Terme stammen aus ClpzDom
  # selbst (is_domain/1 prüft vollständig). Kein solcher Term: ein Fehler –
  # die Domänenoperationen haben kein Original mehr, auf das sie
  # zurückfallen könnten, und clpz ruft sie nur mit Domänen (eine
  # ungebundene Domäne: instantiation_error wie bei jedem Builtin)
  defp dom(t), do: dom_cached(t)

  defp no_domain(t) do
    case w(t) do
      {:var, _} -> PrologEx.Error.instantiation!()
      _ -> PrologEx.Error.type!("clpz_domain", PrologEx.resolve(t, subst_now()))
    end
  end

  # Domänen-Term dekodieren und dabei prüfen, ob er kanonisch ist (ClpzDom.valid?:
  # aufsteigend, Lücken zwischen den Intervallen, Punkte als Zahl, inf nur
  # vorn, sup nur hinten): {:ok, d, kanonisch?} oder :error
  defp dom_pairs_c([], acc, _last, c), do: {:ok, Enum.reverse(acc), c}

  defp dom_pairs_c([h | tl], acc, last, c) do
    case w(h) do
      i when is_integer(i) ->
        dom_pairs_c(w(tl), [{i, i} | acc], i, c and gap?(last, i))

      {tag, "..", [l, u]} when tag in [:struct, :gstruct] ->
        with lb when lb != nil <- tbound(l),
             ub when ub != nil <- tbound(u) do
          dom_pairs_c(w(tl), [{lb, ub} | acc], ub, c and gap?(last, lb) and span?(lb, ub))
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp dom_pairs_c(_, _, _, _), do: :error

  # vor dem ersten Intervall alles erlaubt; danach eine Lücke von mindestens 1
  defp gap?(nil, _l), do: true
  defp gap?(last, l) when is_integer(last) and is_integer(l), do: l > last + 1
  defp gap?(_last, _l), do: false

  # L..U kanonisch: L < U (ein Punkt steht als Zahl da)
  defp span?(l, u) when is_integer(l) and is_integer(u), do: l < u
  defp span?(:inf, u), do: u != :inf
  defp span?(l, :sup), do: l != :sup
  defp span?(_, _), do: false

  defp tbound(t) do
    case w(t) do
      i when is_integer(i) -> i
      {:atom, "inf"} -> :inf
      {:atom, "sup"} -> :sup
      _ -> nil
    end
  end

  # die Elemente als Terme für is_domain/1 (ClpzDom.from_term/1 prüft alles)
  defp dom_items(t, acc) do
    case w(t) do
      [] ->
        {:ok, Enum.reverse(acc)}

      [h | tl] ->
        case w(h) do
          i when is_integer(i) ->
            dom_items(tl, [i | acc])

          {tag, "..", [l, u]} when tag in [:struct, :gstruct] ->
            dom_items(tl, [{:struct, "..", [w(l), w(u)]} | acc])

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  # Merkzettel der letzten Kodierungen und Dekodierungen [{Term, Domäne}]
  # (nur kanonische Paare), erkannt an der physischen Identität des Terms
  # (PrologEx.Share.same?/2, O(1)): Ein gefundener Eintrag ist garantiert
  # die Domäne genau dieses Terms – gleich, was seither geschehen ist. So
  # dekodiert fdget/2 eine eben kodierte Domäne nicht noch einmal, fdput/5
  # erkennt, ob die neue Domäne aus der gespeicherten berechnet wurde, und
  # put_dom/6 vergleicht zwei bekannte Domänen als Listen (=== in C, bei
  # kanonischen Listen genau Mengengleichheit) statt mit ==.
  #
  # Ein Ring fester Größe (ein Tupel, der Index des jüngsten Eintrags vorn):
  # Eintragen ersetzt einen Platz, statt die Liste neu zu bauen; gesucht
  # wird vom jüngsten Eintrag rückwärts.
  @dec_key :clpz_decoded
  @dec_max 8
  @dec_empty {0, :erlang.make_tuple(@dec_max, nil)}

  defp dec_cache, do: Process.get(@dec_key, @dec_empty)

  defp dec_put(t, d) do
    {i, ring} = dec_cache()
    i = if i == @dec_max - 1, do: 0, else: i + 1
    Process.put(@dec_key, {i, put_elem(ring, i, {t, d})})
  end

  defp dom_cached(t, insert \\ false) do
    wt = w(t)

    case dec_find(dec_cache(), wt) do
      nil ->
        case dom_pairs_c(wt, [], nil, true) do
          {:ok, d, canonical} ->
            # nur kanonische Paare eintragen: [5..5] und [5] ergäben sonst
            # dieselbe Liste, == unterscheidet sie aber
            if insert and canonical, do: dec_put(wt, d)

            d

          :error ->
            no_domain(t)
        end

      d ->
        d
    end
  end

  defp dec_find({i, ring}, t), do: dec_find(ring, t, i, @dec_max)

  defp dec_find(_ring, _t, _i, 0), do: nil

  defp dec_find(ring, t, i, n) do
    case elem(ring, i) do
      nil ->
        nil

      {t0, d} ->
        if PrologEx.Share.same?(t0, t),
          do: d,
          else: dec_find(ring, t, if(i == 0, do: @dec_max - 1, else: i - 1), n - 1)
    end
  end

  # kodieren; jede Kodierung kommt in den Merkzettel (siehe dom_cached/1)
  defp ed(d) do
    t = ClpzDom.to_term(d)
    dec_put(t, d)
    t
  end

  # das Intervall l..u als Domäne (leer, wenn l > u)
  defp iv(l, u), do: ClpzDom.interval(l, u)

  # Infimum/Supremum auf dem Term, ohne die Domäne ganz zu dekodieren
  # (die leere Domäne: das Original, es scheitert dort)
  defp edge(t, side) do
    case w(t) do
      [] -> throw(:fallback)
      [h | tl] -> if side == :left, do: elem_bound(h, :left), else: edge_last(h, tl)
      _ -> no_domain(t)
    end
  end

  defp edge_last(h, tl) do
    case w(tl) do
      [] -> elem_bound(h, :right)
      [h2 | tl2] -> edge_last(h2, tl2)
      _ -> throw(:fallback)
    end
  end

  defp elem_bound(h, side) do
    case w(h) do
      i when is_integer(i) ->
        i

      {tag, "..", [l, u]} when tag in [:struct, :gstruct] ->
        bound(if side == :left, do: l, else: u)

      _ ->
        throw(:fallback)
    end
  end

  defp inf_dec([]), do: throw(:fallback)
  defp inf_dec(d), do: ClpzDom.infimum(d)
  defp sup_dec([]), do: throw(:fallback)
  defp sup_dec(d), do: ClpzDom.supremum(d)

  # domain_contains/2 auf dem Term: bis zum ersten Intervall, das i enthält
  # oder hinter i liegt
  defp contains_t(t, i) do
    case w(t) do
      [] ->
        false

      [h | tl] ->
        case w(h) do
          x when is_integer(x) ->
            x == i or (x < i and contains_t(tl, i))

          {tag, "..", [l, u]} when tag in [:struct, :gstruct] ->
            lb = bound(l)
            ub = bound(u)
            (leq(lb, i) and leq(i, ub)) or (lt(ub, i) and contains_t(tl, i))

          _ ->
            no_domain(t)
        end

      _ ->
        no_domain(t)
    end
  end

  defp dcontains?(d, i), do: ClpzDom.contains?(d, i)
  defp remove(d, x), do: ClpzDom.remove(d, x)
  defp remove_gt(d, g), do: ClpzDom.remove_greater_than(d, g)
  defp remove_lt(d, v), do: ClpzDom.remove_smaller_than(d, v)
  defp negate(d), do: ClpzDom.negate(d)
  defp shift(d, o), do: ClpzDom.shift(d, o)
  defp union!(d1, d2), do: ClpzDom.union(d1, d2)
  defp smallest_finite(d), do: ClpzDom.smallest_finite(d)
  defp largest_finite(d), do: ClpzDom.largest_finite(d)

  # negatives m: erst spiegeln, dann mit |m| (wie das Original)
  defp neg_abs(d, m) when m < 0, do: {negate(d), abs(m)}
  defp neg_abs(d, m), do: {d, m}

  defp eb(:inf), do: a("inf")
  defp eb(:sup), do: a("sup")
  defp eb(i) when is_integer(i), do: i

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

  # (die leere Domäne: Fehlschlag, wie das Original)
  defbuiltin "$clpz_domain_infimum", [d, i] do
    run("domain_infimum", [d, i], subst(), fn ->
      case dom(d) do
        [] -> :fail
        dd -> out(i, eb(ClpzDom.infimum(dd)))
      end
    end)
  end

  defbuiltin "$clpz_domain_supremum", [d, s] do
    run("domain_supremum", [d, s], subst(), fn ->
      case dom(d) do
        [] -> :fail
        dd -> out(s, eb(ClpzDom.supremum(dd)))
      end
    end)
  end

  defbuiltin "$clpz_domain_num_elements", [d, n] do
    run("domain_num_elements", [d, n], subst(), fn -> out(n, eb(ClpzDom.num_elements(dom(d)))) end)
  end

  # pit/4: make_propagator/2, new_queue/1, init_propagator_//2,
  # variables_same_queue/1
  defbuiltin "$clpz_pit", [vs, p0, prop, qout] do
    run("pit", [vs, p0, prop, qout], subst(), fn ->
      s = subst_now()
      if Process.get(:clpz_no_fast), do: throw(:fallback)
      p = mk("propagator", [p0, fresh_var()])
      q = new_queue()

      with s when s != :fail <- init_all(vs, p, q, s),
           s when s != :fail <- same_queue(vs, s),
           s = drop_inert_wake(s),
           {:ok, s} <- PrologEx.unify(prop, p, s),
           {:ok, s} <- PrologEx.unify(qout, q, s) do
        {:subst, s}
      else
        _ -> :fail
      end
    end)
  end

  defp constrain_all([], s), do: s

  defp constrain_all([v | vs], s) do
    case put_terminating(v, default_dom(), no_props(), new_queue(), s) do
      :fail -> :fail
      s -> constrain_all(vs, s)
    end
  end

  # a//3, a//2, a//1: die Einträge a(...) für Hilfsvariablen
  defbuiltin "$clpz_a", [t, s0, s1] do
    s = subst()

    items =
      case PrologEx.unmark_top(PrologEx.Store.walk(t, s)) do
        {:struct, "a", [x, y, b]} -> a3(x, y, b, s)
        {:struct, "a", [x, b]} -> a2(x, b, s)
        {:struct, "a", [b]} -> a1(b, s)
      end

    {:unify, [{s0, list(items, s1)}]}
  end

  defp a3(x, y, b, s) do
    cond do
      not var?(PrologEx.Store.walk(x, s)) -> a2(y, b, s)
      not var?(PrologEx.Store.walk(y, s)) -> a2(x, b, s)
      true -> [mk("a", [x, y, b])]
    end
  end

  defp a2(x, b, s), do: if(var?(PrologEx.Store.walk(x, s)), do: [mk("a", [x, b])], else: a1(b, s))
  defp a1(b, s), do: if(var?(PrologEx.Store.walk(b, s)), do: [mk("a", [b])], else: [])

  # --- Konstruktion und Prüfung von Domänen (die einzigen Stellen, an denen
  # lebender Prolog-Code die Darstellung berührt) -----------------------------

  # interval(L, U, D): die Domäne L..U (leer, wenn L > U); L, U Schranken
  defbuiltin "$clpz_interval", [l, u, d] do
    run("interval", [l, u, d], subst(), fn -> out(d, ed(iv(bound(l), bound(u)))) end)
  end

  # singleton(D, V): D besteht aus genau einem Wert V (wie das Muster
  # from_to(F, F) des Originals: V auch inf oder sup, falls so etwas je
  # entsteht – die Aufrufer prüfen integer/1)
  defbuiltin "$clpz_singleton", [d, v] do
    run("singleton", [d, v], subst(), fn ->
      case ClpzDom.singleton(dom(d)) do
        {:ok, x} -> out(v, x)
        :error -> :fail
      end
    end)
  end

  # empty(D): die leere Domäne
  defbuiltin "$clpz_empty", [d] do
    {:unify, [{d, []}]}
  end

  # is_domain(D): ein wohlgeformter Domänenterm (is_domain/1 des Originals)
  # is_domain(D): ein kanonischer Domänenterm (Fehlschlag, kein Fehler)
  defbuiltin "$clpz_is_domain", [d] do
    run("is_domain", [d], subst(), fn ->
      with {:ok, items} <- dom_items(d, []),
           {:ok, _} <- ClpzDom.from_term(items) do
        :ok
      else
        _ -> :fail
      end
    end)
  end

  # Zahl oder Variable mit Domäne (parse_reified_clpz//3, Abkürzer)
  defbuiltin "$clpz_fd_atom", [e] do
    s = subst()

    case if(Process.get(:clpz_no_fast), do: nil, else: PrologEx.Store.walk(e, s)) do
      i when is_integer(i) -> :ok
      {:var, _} = v -> if fdvar?(v, s), do: :ok, else: :fail
      _ -> :fail
    end
  end

  # clpz_in/2: V eine Variable oder Zahl, D eine Zahl oder N..M (Zahlen,
  # inf, sup; N nicht sup, M nicht inf): Dom wie drep_to_domain/2. Sonst
  # scheitert es (das Original rechnet)
  defbuiltin "$clpz_in_dom", [v0, d0, dom] do
    s = subst()

    with nil <- Process.get(:clpz_no_fast),
         true <- var_or_int?(v0, s),
         {:ok, d} <- simple_drep(PrologEx.unmark_top(PrologEx.Store.walk(d0, s)), s) do
      {:unify, [{dom, d}]}
    else
      _ -> :fail
    end
  end

  defp simple_drep(i, _s) when is_integer(i), do: {:ok, ed(iv(i, i))}

  defp simple_drep({:struct, "..", [n0, m0]}, s) do
    with n when n != nil <- drep_bound(PrologEx.Store.walk(n0, s)),
         m when m != nil <- drep_bound(PrologEx.Store.walk(m0, s)),
         true <- n != :sup and m != :inf do
      {:ok, ed(iv(n, m))}
    else
      _ -> :error
    end
  end

  defp simple_drep(_, _s), do: :error

  defp drep_bound(i) when is_integer(i), do: i
  defp drep_bound({:atom, "inf"}), do: :inf
  defp drep_bound({:atom, "sup"}), do: :sup
  defp drep_bound(_), do: nil

  # reifiable/1, wenn es gelingt (reify/3 nimmt die erste Lösung); sonst
  # und bei Fehlern: das Original
  defbuiltin "$clpz_reifiable", [e] do
    run("reifiable", [e], subst(), fn ->
      s = subst_now()
      if Process.get(:clpz_no_fast), do: throw(:fallback)
      Process.put(:clpz_constrain, [])
      ok = reifiable?(e, s, monotonic?(ctx.db))
      vs = Process.delete(:clpz_constrain) |> Enum.reverse() |> Enum.uniq()

      # ?(V)/#(V) mit V ohne Domäne: must_be_fd_integer/1, also
      # constrain_to_integer/1 – V bekommt die Domäne inf..sup (fd_put/3
      # ohne Propagatoren, die Queue bleibt leer). Scheitert der Test, wirft
      # reify/3 ohnehin domain_error (die Bindungen sind dann zurück)
      if ok do
        case constrain_all(vs, s) do
          :fail -> :fail
          s -> {:subst, s}
        end
      else
        # scheitert der Test, sucht das Original weiter (eine Variable
        # passt dann auf ?(E), #E, V in _ und den allgemeinen Fall mit
        # =../2: Bindungen oder instantiation_error): das Original
        throw(:fallback)
      end
    end)
  end

  @reif_cmp ~w(#>= #> #=< #< #= #\\=)
  @reif_bool ~w(#==> #<== #<==> #/\\ #\\/ #\\)

  defp reifiable?(e, s, mono) do
    case PrologEx.unmark_top(PrologEx.Store.walk(e, s)) do
      {:var, _} = v ->
        if mono and not fdvar?(v, s), do: throw(:fallback)
        true

      i when is_integer(i) ->
        i == 0 or i == 1

      {:struct, f, [x]} when f in ["?", "#"] ->
        if var_or_int_fd?(x, s), do: true, else: throw(:fallback)

      {:struct, "in", [v, _]} ->
        if var_or_int?(v, s), do: true, else: throw(:fallback)

      {:struct, op, [_, _]} when op in @reif_cmp ->
        true

      {:struct, op, [l, r]} when op in @reif_bool ->
        reifiable?(l, s, mono) and reifiable?(r, s, mono)

      {:struct, "#\\", [x]} ->
        reifiable?(x, s, mono)

      {:struct, f, _} when f in ["tuples_in", "finite_domain"] ->
        throw(:fallback)

      _ ->
        false
    end
  end

  # eine Zahl oder eine Variable (must_be_fd_integer/1; eine Variable ohne
  # Domäne bekommt danach eine, siehe oben)
  defp var_or_int_fd?(t, s) do
    case PrologEx.Store.walk(t, s) do
      i when is_integer(i) ->
        true

      {:var, _} = v ->
        unless fdvar?(v, s), do: Process.put(:clpz_constrain, [v | Process.get(:clpz_constrain)])
        true

      _ ->
        false
    end
  end

  # left_right_linsum_const/5: Left - Right als Σ Cs·Vs + (CL - CR), wie
  # linsum//3 (Glieder vn(V, N) in Lesereihenfolge, Konstante), die Glieder
  # rechts negiert, nach vn(V, N) stabil sortiert, gleiche V
  # zusammengefasst, Koeffizienten 0 weg, Const = CR - CL. Scheitert wie
  # das Original (nichtlinear, keine Variable). Eine Variable ohne Domäne
  # bei clpz:monotonic (Fehler) und ?(X)/#(X) mit X ohne Domäne (bekommt
  # erst eine): das Original
  defbuiltin "$clpz_linsum", [l, r, cs, vs, c] do
    run("left_right_linsum_const", [l, r, cs, vs, c], subst(), fn ->
      s = subst_now()
      mono = monotonic?(ctx.db)

      # die Glieder rechts negiert gleich dazu; ihre Reihenfolge ist
      # gleich, lin_merge/2 sortiert (gleiche {V, N} sind gleich)
      with {:ok, items, cl} <- lin(l, s, mono, 1, []),
           {:ok, [_ | _] = items, k} <- lin(r, s, mono, -1, items),
           merged = lin_merge(items, s),
           {:ok, s} <- PrologEx.unify(cs, term_coeffs(merged), s),
           {:ok, s} <- PrologEx.unify(vs, term_vars(merged), s),
           {:ok, s} <- PrologEx.unify(c, -(cl + k), s) do
        {:subst, s}
      else
        _ -> :fail
      end
    end)
  end

  # Glieder [{V, N}] wie samsort/2, vns_coeffs_variables/5 und
  # filter_linsum/4: nach vn(V, N) stabil sortiert, gleiche V
  # zusammengefasst, Koeffizienten 0 weg
  defp lin_merge(items, s) do
    items
    |> Enum.sort(fn {v1, n1}, {v2, n2} ->
      case PrologEx.Order.compare(v1, v2, s) do
        :lt -> true
        :gt -> false
        :eq -> n1 <= n2
      end
    end)
    |> merge_terms(s)
  end

  defp merge_terms([], _s), do: []
  defp merge_terms([{v, n} | ts], s), do: merge_terms(ts, v, n, s)

  defp merge_terms([{v, n} | ts], v0, n0, s) do
    if PrologEx.Order.compare(v, v0, s) == :eq,
      do: merge_terms(ts, v0, n0 + n, s),
      else: keep_term(v0, n0, merge_terms(ts, v, n, s), s)
  end

  defp merge_terms([], v0, n0, s), do: keep_term(v0, n0, [], s)

  # Koeffizient 0 fällt weg – bei einer Variablen ohne Domäne nicht:
  # constrain_to_integer/1 gibt ihr eine (das Original)
  defp keep_term({:var, _} = v, 0, ts, s), do: if(fdvar?(v, s), do: ts, else: throw(:fallback))
  defp keep_term(_v, 0, ts, _s), do: ts
  defp keep_term(v, n, ts, _s), do: [{v, n} | ts]

  # die Listen Cs und Vs der Glieder (mit cons/2 wie list/1: ein grundes
  # Ende als glist)
  defp term_coeffs([]), do: []
  defp term_coeffs([{_, n} | ts]), do: cons(n, term_coeffs(ts))

  defp term_vars([]), do: []
  defp term_vars([{v, _} | ts]), do: cons(v, term_vars(ts))

  defp monotonic?(db) do
    case Map.get(db, {"clpz", "monotonic", 0}) do
      nil -> false
      {:pred, [], _, _, _} -> false
      _ -> true
    end
  end

  # Glieder (umgekehrt) mal m, Konstante mal m
  defp lin(t, s, mono, m, acc) do
    case PrologEx.unmark_top(PrologEx.Store.walk(t, s)) do
      {:var, _} = v ->
        if mono and not fdvar?(v, s), do: throw(:fallback)
        {:ok, [{v, m} | acc], 0}

      i when is_integer(i) ->
        {:ok, acc, m * i}

      {:struct, f, [x]} when f in ["?", "#"] ->
        case PrologEx.Store.walk(x, s) do
          i when is_integer(i) -> {:ok, [{i, m} | acc], 0}
          {:var, _} = v -> if fdvar?(v, s), do: {:ok, [{v, m} | acc], 0}, else: throw(:fallback)
          _ -> throw(:fallback)
        end

      {:struct, "-", [a]} ->
        lin(a, s, mono, -m, acc)

      {:struct, "*", [a, b]} ->
        case {PrologEx.Store.walk(a, s), PrologEx.Store.walk(b, s)} do
          {n, _} when is_integer(n) -> lin(b, s, mono, m * n, acc)
          {_, n} when is_integer(n) -> lin(a, s, mono, m * n, acc)
          _ -> :fail
        end

      {:struct, "+", [a, b]} ->
        with {:ok, acc, k1} <- lin(a, s, mono, m, acc),
             {:ok, acc, k2} <- lin(b, s, mono, m, acc),
             do: {:ok, acc, k1 + k2}

      {:struct, "-", [a, b]} ->
        with {:ok, acc, k1} <- lin(a, s, mono, m, acc),
             {:ok, acc, k2} <- lin(b, s, mono, -m, acc),
             do: {:ok, acc, k1 + k2}

      _ ->
        :fail
    end
  end

  # Abkürzer für clpz_neq/2 (A #\\= B): welche Klausel des Matchers das
  # Original als erste nähme, für Formen, bei denen alle früheren Klauseln
  # ohne Wirkung scheitern: v_or_i/1 gelingt dort nur für Zahlen und
  # Variablen mit Domäne (ohne non_monotonic/1-Fehler), sonst scheitert es
  # sofort; nichts davon ist zyklisch. num_a: neq_num(A, B) (B eine Zahl),
  # num_b: neq_num(B, A), pneq: zwei Variablen, absdiff: abs(X-Y) gegen
  # eine Zahl (X, Y Variablen oder Zahlen). Sonst scheitert es (die
  # Klauseln laufen). '$clpz_fast'(off) schaltet ab (für die Tests)
  defbuiltin "$clpz_neq_kind", [a0, b0, k] do
    s = subst()

    kind =
      if Process.get(:clpz_no_fast) do
        nil
      else
        a = PrologEx.unmark_top(PrologEx.Store.walk(a0, s))
        b = PrologEx.unmark_top(PrologEx.Store.walk(b0, s))

        cond do
          simple?(a, s) and is_integer(b) -> "num_a"
          is_integer(a) and simple?(b, s) -> "num_b"
          fdvar?(a, s) and fdvar?(b, s) -> "pneq"
          is_integer(b) and absdiff?(a, s) -> "absdiff"
          true -> nil
        end
      end

    if kind, do: {:unify, [{k, a(kind)}]}, else: :fail
  end

  defbuiltin "$clpz_fast", [onoff] do
    case deref(onoff) do
      {:atom, "off"} -> Process.put(:clpz_no_fast, true)
      _ -> Process.delete(:clpz_no_fast)
    end

    :ok
  end

  defp fdvar?({:var, _} = v, s), do: att(v, s, "clpz", 1) != nil
  defp fdvar?(_, _s), do: false

  defp simple?(i, _s) when is_integer(i), do: true
  defp simple?(t, s), do: fdvar?(t, s)

  defp absdiff?({:struct, "abs", [d]}, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(d, s)) do
      {:struct, "-", [x, y]} -> var_or_int?(x, s) and var_or_int?(y, s)
      _ -> false
    end
  end

  defp absdiff?(_, _s), do: false

  defp var_or_int?(t, s) do
    case PrologEx.Store.walk(t, s) do
      {:var, _} -> true
      i -> is_integer(i)
    end
  end

  # v_or_i/1: eine Zahl oder eine Variable mit clpz-Attribut (fd_var/1);
  # eine Variable ohne: das Original (non_monotonic/1)
  defbuiltin "$clpz_v_or_i", [v] do
    run("v_or_i", [v], subst(), fn ->
      s = subst_now()

      case PrologEx.Store.walk(v, s) do
        i when is_integer(i) -> :ok
        {:var, _} = x -> if att(x, s, "clpz", 1), do: :ok, else: throw(:fallback)
        _ -> :fail
      end
    end)
  end

  defbuiltin "$clpz_domain_contains", [d, i] do
    run("domain_contains", [d, i], subst(), fn ->
      if contains_t(d, int(i)), do: :ok, else: :fail
    end)
  end

  # domain_subdomain(Dom, Sub): Sub ⊆ Dom (Fehlschlag für Dom = [], wie das
  # Original)
  defbuiltin "$clpz_domain_subdomain", [d, sub] do
    run("domain_subdomain", [d, sub], subst(), fn ->
      if ClpzDom.subdomain?(dom(d), dom(sub)), do: :ok, else: :fail
    end)
  end

  # --- Domänen: Entfernen -----------------------------------------------------

  defbuiltin "$clpz_domain_remove", [d, x, r] do
    run("domain_remove", [d, x, r], subst(), fn -> out(r, ed(remove(dom(d), int(x)))) end)
  end

  defbuiltin "$clpz_domain_remove_greater_than", [d, g, r] do
    run("domain_remove_greater_than", [d, g, r], subst(), fn ->
      out(r, ed(remove_gt(dom(d), int(g))))
    end)
  end

  defbuiltin "$clpz_domain_remove_smaller_than", [d, v, r] do
    run("domain_remove_smaller_than", [d, v, r], subst(), fn ->
      out(r, ed(remove_lt(dom(d), int(v))))
    end)
  end

  defbuiltin "$clpz_domain_subtract", [d0, sub, d] do
    run("domain_subtract", [d0, sub, d], subst(), fn ->
      out(d, ed(ClpzDom.subtract(dom(d0), dom(sub))))
    end)
  end

  defbuiltin "$clpz_domain_complement", [d, c] do
    run("domain_complement", [d, c], subst(), fn -> out(c, ed(ClpzDom.complement(dom(d)))) end)
  end

  # --- Domänen: Intervalle, Schnitt, Vereinigung ------------------------------

  # domain_intervals/2: die Intervalle als Liste von Von-Bis
  defbuiltin "$clpz_domain_intervals", [d, is] do
    run("domain_intervals", [d, is], subst(), fn -> out(is, e_intervals(dom(d))) end)
  end

  defp e_intervals([]), do: []
  defp e_intervals([{l, u} | d]), do: cons(mk("-", [eb(l), eb(u)]), e_intervals(d))

  # Liste von Intervallen A-B (Schranken), auch unsortiert oder überlappend
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

      _ ->
        throw(:fallback)
    end
  end

  # domains_intersection/3 scheitert bei leerem Schnitt
  defbuiltin "$clpz_domains_intersection", [d1, d2, i] do
    run("domains_intersection", [d1, d2, i], subst(), fn ->
      case ClpzDom.intersection(dom(d1), dom(d2)) do
        [] -> :fail
        r -> out(i, ed(r))
      end
    end)
  end

  # gcc_neq_goals(Vs, KNs, Gs): der Teil von gcc_global//2 unter
  # with_local_attributes/3 (Wertenetz, Fluss, Komponenten), siehe
  # PrologEx.Builtins.ClpzGcc; Gs die neq_num-Ziele
  defbuiltin "$clpz_gcc_goals", [vs, kns, gs] do
    run("gcc_neq_goals", [vs, kns, gs], subst(), fn ->
      s = subst_now()

      case PrologEx.Builtins.ClpzGcc.goals(gcc_vals(kns, s), var_counts(vs, s)) do
        :fail -> :fail
        goals -> out(gs, neq_goals(goals))
      end
    end)
  end

  # je Paar Key-Num0 mit clpz_gcc_vs: {Key, L, U, Variablen mit Anzahl}
  defp gcc_vals(kns, s) do
    case ws(kns, s) do
      [] ->
        []

      [p | kns] ->
        {key, num0} = gcc_pair_arg(p, s)

        case att(num0, s, "clpz_gcc_vs", 1) do
          nil ->
            gcc_vals(kns, s)

          [gvs] ->
            [num] = att(num0, s, "clpz_gcc_num", 1) || throw(:fallback)
            [occ] = att(num0, s, "clpz_gcc_occurred", 1) || throw(:fallback)
            occ = val(occ, s)
            is_integer(occ) || throw(:fallback)

            {l, u} =
              case val(num, s) do
                i when is_integer(i) ->
                  {i - occ, i - occ}

                {:var, _} = v ->
                  case ibounds(v, s) do
                    {l0, u0} when is_integer(l0) and is_integer(u0) -> {l0 - occ, u0 - occ}
                    _ -> throw(:fallback)
                  end

                _ ->
                  throw(:fallback)
              end

            [{key, l, u, var_counts(gvs, s)} | gcc_vals(kns, s)]
        end

      _ ->
        throw(:fallback)
    end
  end

  # Key-Num0 mit Key einer Zahl und Num0 einer Variablen
  defp gcc_pair_arg(p, s) do
    case ws(p, s) do
      {tag, "-", [k, n0]} when tag in [:struct, :gstruct] ->
        case val(k, s) do
          k when is_integer(k) ->
            case PrologEx.Store.walk(n0, s) do
              {:var, _} = n0 -> {k, n0}
              _ -> throw(:fallback)
            end

          _ ->
            throw(:fallback)
        end

      _ ->
        throw(:fallback)
    end
  end

  defp neq_goals([]), do: []
  defp neq_goals([{v, k} | gs]), do: cons(mk("neq_num", [v, k]), neq_goals(gs))

  # variables_with_num_occurrences/2: die Variablen der Liste vs (stabil
  # sortiert) mit ihrer Anzahl
  defp var_counts(vs, s) do
    vs
    |> ws(s)
    |> open_vars(s)
    |> Enum.sort(fn a, b -> PrologEx.Order.compare(a, b, s) != :gt end)
    |> count_runs()
  end

  # die ungebundenen Variablen einer Liste (unecht: das Original)
  defp open_vars([], _s), do: []

  defp open_vars([v | vs], s) do
    case PrologEx.Store.walk(v, s) do
      {:var, _} = w -> [w | open_vars(ws(vs, s), s)]
      _ -> open_vars(ws(vs, s), s)
    end
  end

  defp open_vars(_, _s), do: throw(:fallback)

  defp count_runs([]), do: []
  defp count_runs([v | vs]), do: count_runs(vs, v, 1)
  defp count_runs([v | vs], v, n), do: count_runs(vs, v, n + 1)
  defp count_runs([w | vs], v, n), do: [{v, n} | count_runs(vs, w, 1)]
  defp count_runs([], v, n), do: [{v, n}]

  defbuiltin "$clpz_domains_union", [d1, d2, u] do
    run("domains_union", [d1, d2, u], subst(), fn -> out(u, ed(union!(dom(d1), dom(d2)))) end)
  end

  # merge_intervals/2: Intervalle sortieren und zusammenfassen
  defbuiltin "$clpz_merge_intervals", [is0, is] do
    run("merge_intervals", [is0, is], subst(), fn ->
      out(is, e_intervals(ClpzDom.from_intervals(interval_list(is0))))
    end)
  end

  defbuiltin "$clpz_intervals_to_domain", [is, d] do
    run("intervals_to_domain", [is, d], subst(), fn ->
      out(d, ed(ClpzDom.from_intervals(interval_list(is))))
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

  defbuiltin "$clpz_list_to_domain", [l, d] do
    run("list_to_domain", [l, d], subst(), fn -> out(d, ed(ClpzDom.from_list(int_list(l)))) end)
  end

  # --- Domänen: Verschieben, Strecken, Stauchen, Spiegeln ---------------------

  defbuiltin "$clpz_domain_shift", [d, o, r] do
    run("domain_shift", [d, o, r], subst(), fn -> out(r, ed(ClpzDom.shift(dom(d), int(o)))) end)
  end

  defbuiltin "$clpz_domain_negate", [d, r] do
    run("domain_negate", [d, r], subst(), fn -> out(r, ed(negate(dom(d)))) end)
  end

  defbuiltin "$clpz_domain_expand", [d0, m, d] do
    run("domain_expand", [d0, m, d], subst(), fn ->
      out(d, ed(ClpzDom.expand(dom(d0), int(m))))
    end)
  end

  defbuiltin "$clpz_domain_expand_more", [d0, m, d] do
    run("domain_expand_more", [d0, m, d], subst(), fn ->
      out(d, ed(ClpzDom.expand_more(dom(d0), int(m))))
    end)
  end

  # Multiplikator 0 beim Stauchen: Division durch null (wie // im Original)
  defp nonzero(m) do
    case int(m) do
      0 -> PrologEx.Error.evaluation!("zero_divisor")
      i -> i
    end
  end

  defbuiltin "$clpz_domain_contract", [d0, m, d] do
    run("domain_contract", [d0, m, d], subst(), fn ->
      out(d, ed(ClpzDom.contract(dom(d0), nonzero(m))))
    end)
  end

  defbuiltin "$clpz_domain_contract_less", [d0, m, d] do
    run("domain_contract_less", [d0, m, d], subst(), fn ->
      out(d, ed(ClpzDom.contract_less(dom(d0), nonzero(m))))
    end)
  end

  # --- Domänen: Spannweite, Liste ---------------------------------------------

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
    run("domain_spread", [d, sp], subst(), fn -> out(sp, maybe_eb(ClpzDom.spread(dom(d)))) end)
  end

  # domain_to_list/2: nur endliche Domänen (sonst scheitert das Original)
  defbuiltin "$clpz_domain_to_list", [d, l] do
    run("domain_to_list", [d, l], subst(), fn ->
      case ClpzDom.to_list(dom(d)) do
        {:ok, ns} -> out(l, list(ns))
        :error -> :fail
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

  defp ws(t, s), do: PrologEx.unmark_top(PrologEx.Store.walk(t, s))

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
    l = v |> PrologEx.get_attrs(s) |> Map.get("clpz", [])
    PrologEx.put_attr(s, v, "clpz", del_items(l, s, name, ar))
  end

  defp del_items(l, s, name, ar) do
    case cell(l, s) do
      nil ->
        []

      {h, tl} ->
        case ws(h, s) do
          {tag, ^name, args} when tag in [:struct, :gstruct] and length(args) == ar ->
            del_items(tl, s, name, ar)

          {:atom, ^name} when ar == 0 ->
            del_items(tl, s, name, ar)

          _ ->
            cons(h, del_items(tl, s, name, ar))
        end
    end
  end

  # append/3 zweier echter Listen (unecht: das Original)
  defp pl_append(x, y, s) do
    case ws(x, s) do
      [] -> proper_list!(y, s)
      [h | t] -> cons(h, pl_append(t, y, s))
      _ -> throw(:fallback)
    end
  end

  defp proper_list!(l, s) do
    case ws(l, s) do
      [] -> []
      [h | t] -> cons(h, proper_list!(t, s))
      _ -> throw(:fallback)
    end
  end

  # Länge einer echten Liste (unecht: das Original)
  defp pl_length(l, s), do: pl_length(ws(l, s), s, 0)
  defp pl_length([], _s, n), do: n
  defp pl_length([_ | t], s, n), do: pl_length(ws(t, s), s, n + 1)
  defp pl_length(_, _s, _n), do: throw(:fallback)

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
  #
  # Merkzettel je Variable wie bei den Domänen (vdom/3): die zuletzt
  # gesehene Liste ihrer clpz-Attribute (physisch, Share.same?/2) und das
  # Ergebnis. Unverändert – dasselbe Ergebnis, ohne die Liste zu durchsuchen
  # und clpz_attr/6 zu zerlegen. Höchstens @fdg_max Einträge, dann von
  # vorn: ein Eintrag hält Attributliste und Propagatoren fest (oft 1000
  # Wörter); mit 100 000 wuchs der Prozess über die 49 151 Sudokus von
  # conformance/clpz_puzzles auf Gigabytes (Variablen erledigter Aufgaben
  # kommen nie wieder). Die Reduktionen der clpz-Benchmarks: gleich.
  @fdg_key :clpz_fdget
  @fdg_max 4096

  defp fd_get(x, s) do
    case PrologEx.Store.walk(x, s) do
      {:var, {:attv, id}} = v ->
        l = s |> Store.attrs(id) |> Map.get("clpz", [])

        case Process.get(@fdg_key, %{}) do
          %{^v => {l0, r}} = m ->
            if PrologEx.Share.same?(l0, l), do: r, else: fd_get_miss(m, v, l, s)

          m ->
            fd_get_miss(m, v, l, s)
        end

      {:var, _} ->
        :default

      _ ->
        :fail
    end
  end

  defp fd_get_miss(m, v, l, s) do
    r =
      case att_find(l, s, "clpz", 1) do
        [a] ->
          case ws(a, s) do
            {tag, "clpz_attr", [_, _, _, d, ps, _]} when tag in [:struct, :gstruct] -> {d, ps}
            _ -> throw(:fallback)
          end

        nil ->
          :default
      end

    m = if map_size(m) >= @fdg_max, do: %{}, else: m
    Process.put(@fdg_key, Map.put(m, v, {l, r}))
    r
  end

  defp default_dom, do: ed(ClpzDom.all())
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
  # (läuft für q gerade die Schleife in Elixir: dort, siehe native/3)
  defp insert(elem, which, q, s) do
    args =
      case ws(q, s) do
        {tag, "queue", [_, _, _, _] = args} when tag in [:struct, :gstruct] -> args
        _ -> throw(:fallback)
      end

    case Process.get(@nq) do
      {key, _, _, _} = nq when key != nil ->
        if PrologEx.Store.walk(hd(args), s) == key,
          do: nq_push(nq, which, elem, s),
          else: insert_term(elem, which, args, s)

      _ ->
        insert_term(elem, which, args, s)
    end
  end

  # Argument which (1..4) von queue(Goals, Fast, Slow, Aux)
  defp qarg([a, _, _, _], 1), do: a
  defp qarg([_, a, _, _], 2), do: a
  defp qarg([_, _, a, _], 3), do: a
  defp qarg([_, _, _, a], 4), do: a

  defp insert_term(elem, which, args, s) do
    arg = PrologEx.Store.walk(qarg(args, which), s)
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
        case PrologEx.Store.walk(state, s) do
          {:atom, "dead"} ->
            s

          # die Zustandsvariable einmal aufgelöst, ihre Attribute einmal
          # gelesen: daraus Prüfung (queued?) und Merker clpz_aux(queued)
          # in einem Schreibzugriff (vorher je ein walk und Lesen mehr)
          {:var, {:attv, id}} = st ->
            attrs = PrologEx.Store.attrs(s, id)

            cond do
              queued_in?(Map.get(attrs, "clpz", []), s) ->
                s

              current?(st, s) ->
                s

              true ->
                s =
                  PrologEx.Builtins.Atts.put_one_attv(
                    s,
                    id,
                    attrs,
                    "clpz",
                    mk("clpz_aux", [a("queued")])
                  )

                insert(p, if(global?(c, s), do: 3, else: 2), q, s)
            end

          {:var, _} = st ->
            if current?(st, s) do
              s
            else
              s = put_att(s, st, mk("clpz_aux", [a("queued")]))
              insert(p, if(global?(c, s), do: 3, else: 2), q, s)
            end

          _ ->
            throw(:fallback)
        end

      _ ->
        throw(:fallback)
    end
  end

  # clpz_aux(queued) in der Attributliste l von clpz
  defp queued_in?(l, s) do
    case att_find(l, s, "clpz_aux", 1) do
      [v] -> ws(v, s) == {:atom, "queued"}
      nil -> false
    end
  end

  # st: aufgelöste Variable; gleich (==) nur derselben Variablen
  defp current?(st, s) do
    case PrologEx.Builtins.Blackboard.b_value("clpz", "$clpz_current_propagator", s) do
      {:ok, c} -> PrologEx.Store.walk(c, s) == st
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
    case ws(ps, s) do
      [] ->
        s

      [p | ps] ->
        case trigger(p, q, s) do
          :fail -> :fail
          s -> trigger_all(ps, q, s)
        end

      _ ->
        throw(:fallback)
    end
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

  # --- Aufstellen: init_propagator_//2, init_propagator/2, reinforce/1 ---

  # constraint_wake/2 des Originals
  @wake_ground ~w(pneq x_neq_y_plus_z absdiff_neq pdifferent pexclude scalar_product_neq
                  x_eq_abs_plus_v)
  @wake_bounds ~w(x_leq_y_plus_c scalar_product_eq scalar_product_leq pplus pgeq pgcc_single
                  pgcc_check_single)

  # insert_propagator/3
  defp insert_propagator(prop, ps, s) do
    {gs, bs, os} = props(ps, s)

    f =
      case ws(prop, s) do
        {tag, "propagator", [c, _]} when tag in [:struct, :gstruct] ->
          case ws(c, s) do
            {t2, f, _} when t2 in [:struct, :gstruct] -> f
            {:atom, f} -> f
            _ -> throw(:fallback)
          end

        _ ->
          throw(:fallback)
      end

    cond do
      f in @wake_ground -> mk("fd_props", [[prop | gs], bs, os])
      f in @wake_bounds -> mk("fd_props", [gs, [prop | bs], os])
      true -> mk("fd_props", [gs, bs, [prop | os]])
    end
  end

  # init_propagator_//2: init_one/4 für jedes Element der Liste vs (eine
  # Prolog- oder Elixir-Liste; unecht: das Original)
  defp init_all(vs, prop, q, s) do
    case ws(vs, s) do
      [] ->
        s

      [v | vs] ->
        case init_one(v, prop, q, s) do
          :fail -> :fail
          s -> init_all(vs, prop, q, s)
        end

      _ ->
        throw(:fallback)
    end
  end

  # init_propagator(V, Prop) für eine Variable, mit der Queue q
  defp init_one(v, prop, q, s) do
    case fd_get(v, s) do
      {d, ps} -> put_terminating(v, d, insert_propagator(prop, ps, s), q, s)
      :default -> put_terminating(v, default_dom(), insert_propagator(prop, no_props(), s), q, s)
      :fail -> s
    end
  end

  defbuiltin "$clpz_init_propagator_", [vs, prop, s0, s1] do
    run("init_propagator_", [vs, prop, s0, s1], subst(), fn ->
      s = subst_now()
      q = state_q(s0, s)

      vs
      |> init_all(prop, q, s)
      |> result(s1, s0)
    end)
  end

  # reinforce/1: put_full/3 mit derselben Domäne – nur die Ränder und die
  # Spanne zurücksetzen (no); ein Einzelwert (F = n(X), Bindung): das
  # Original
  # reinforce_/1 einer Variablen (put_full/3 mit der Domäne: Left, Right,
  # Spread wieder no); eine gebundene oder ohne clpz: nichts
  defp reinforce_one(v, s) do
    v = PrologEx.Store.walk(v, s)

    case var?(v) and att(v, s, "clpz", 1) do
      [attr] ->
        case ws(attr, s) do
          {tag, "clpz_attr", [_, _, _, d, ps, q]} when tag in [:struct, :gstruct] ->
            # (leer oder ein Einzelwert: das Original, es scheitert bzw.
            # bindet)
            case dom(d) do
              [] -> throw(:fallback)
              [{b, b}] -> throw(:fallback)
              _ -> put_clpz(s, v, [a("no"), a("no"), a("no"), d, ps, q])
            end

          _ ->
            throw(:fallback)
        end

      _ ->
        s
    end
  end

  defp reinforce_all([], s), do: s
  defp reinforce_all([v | vs], s), do: reinforce_all(vs, reinforce_one(v, s))

  defbuiltin "$clpz_reinforce", [x] do
    run("reinforce", [x], subst(), fn ->
      s = subst_now()

      {:subst, reinforce_all(PrologEx.Builtins.Order.variables(x, s), s)}
    end)
  end

  # --- variables_same_queue/1: die Warteschlangen der Variablen zusammenlegen ---
  #
  # Wie das Original: die Queues der (ungebundenen) Variablen sortiert, die
  # erste bleibt; append_queues_/3 hängt jede weitere an die vorige an (eine
  # Kette, nicht alle an die erste), dann werden die übrigen geleert und mit
  # der ersten unifiziert (die Maschine bindet die jüngeren Variablen an die
  # älteren). Eine Variable ohne clpz-Attribut: das Original (scheitert)

  defbuiltin "$clpz_variables_same_queue", [vs0] do
    run("variables_same_queue", [vs0], subst(), fn ->
      s = subst_now()

      case same_queue(vs0, s) do
        :fail -> :fail
        s -> {:subst, drop_inert_wake(s)}
      end
    end)
  end

  # vs: Prolog- oder Elixir-Liste (unecht: das Original)
  defp same_queue(vs, s) do
    case var_queues(ws(vs, s), s, []) do
      [] ->
        s

      qs0 ->
        [q | qs] = PrologEx.Order.sort_unique(qs0, s)

        # Queue-Variablen mit fremden Attributen (freeze, …): das Original
        for qi <- qs, v <- queue_args(qi, s), not only_clpz_attrs?(v, s), do: throw(:fallback)

        s
        |> append_queues(queue_args(q, s), qs)
        |> clear_queues(qs)
        |> unify_queues(q, qs)
    end
  end

  # die Queues der ungebundenen Variablen (umgekehrt; sort_unique ordnet)
  defp var_queues([], _s, acc), do: acc

  defp var_queues([v | vs], s, acc) do
    case PrologEx.Store.walk(v, s) do
      {:var, _} = w ->
        with [attr] <- att(w, s, "clpz", 1),
             {tag, "clpz_attr", [_, _, _, _, _, q]} when tag in [:struct, :gstruct] <-
               ws(attr, s) do
          var_queues(ws(vs, s), s, [q | acc])
        else
          _ -> throw(:fallback)
        end

      _ ->
        var_queues(ws(vs, s), s, acc)
    end
  end

  defp var_queues(_, _s, _acc), do: throw(:fallback)

  # append_queues_/3: jede Queue an die vorige
  defp append_queues(s, _args0, []), do: s

  defp append_queues(s, [g0, f0, sl0, _], [qi | qs]) do
    [g, f, sl, _] = argsi = queue_args(qi, s)
    s = s |> append_queue(g0, g) |> append_queue(f0, f) |> append_queue(sl0, sl)
    append_queues(s, argsi, qs)
  end

  defp clear_queues(s, []), do: s
  defp clear_queues(s, [qi | qs]), do: s |> clear_queue(qi) |> clear_queues(qs)

  defp unify_queues(s, _q, []), do: s

  defp unify_queues(s, q, [qi | qs]) do
    case PrologEx.unify(q, qi, s) do
      {:ok, s} -> unify_queues(s, q, qs)
      :error -> :fail
    end
  end

  # Gebundene Queue-Variablen (und andere ohne Domäne, nur mit Attributen
  # von clpz): ihr Wecken tut nichts – verify_attributes/3 von clpz gibt
  # Gs = [], und es gibt keine freeze/dif/when-Suspensionen. Ist clpz das
  # einzige Modul mit verify_attributes/3 (vom Aufrufer geprüft), braucht
  # die Maschine sie also nicht zu wecken
  defp drop_inert_wake(s) do
    case Store.take_wake(s) do
      {ws, s1} -> if all_inert?(ws, s), do: s1, else: s
      :none -> s
    end
  end

  defp all_inert?([], _s), do: true
  defp all_inert?([v | vs], s), do: inert?(v, s) and all_inert?(vs, s)

  defp inert?({:var, {:attv, id}}, s) do
    case Store.attrs(s, id) do
      m when map_size(m) == 0 -> true
      %{"clpz" => l} = m when map_size(m) == 1 -> no_clpz_attr?(l, s)
      _ -> false
    end
  end

  defp inert?(_, _s), do: false

  # kein Eintrag clpz(_) in der Attributliste l
  defp no_clpz_attr?(l, s) do
    case cell(l, s) do
      nil ->
        true

      {t, tl} ->
        case ws(t, s) do
          {tag, "clpz", [_]} when tag in [:struct, :gstruct] -> false
          _ -> no_clpz_attr?(tl, s)
        end
    end
  end

  # die vier Variablen einer Queue queue(Goals, Fast, Slow, Aux)
  defp queue_args(q, s) do
    case ws(q, s) do
      {tag, "queue", args} when tag in [:struct, :gstruct] and length(args) == 4 ->
        for a <- args do
          case PrologEx.Store.walk(a, s) do
            {:var, _} = v -> v
            _ -> throw(:fallback)
          end
        end

      _ ->
        throw(:fallback)
    end
  end

  # append_queue(append, Q0, Q)
  defp append_queue(:fail, _q0, _q), do: :fail

  defp append_queue(s, q0, q) do
    case {att(q0, s, "queue", 2), att(q, s, "queue", 2)} do
      {[ls0, ls], [ms0, ms]} ->
        case PrologEx.unify(ls, ms0, s) do
          {:ok, s} -> put_att(s, q0, mk("queue", [ls0, ms]))
          :error -> :fail
        end

      {nil, [ms0, ms]} ->
        put_att(s, q0, mk("queue", [ms0, ms]))

      _ ->
        s
    end
  end

  defp clear_queue(:fail, _q), do: :fail

  defp clear_queue(s, q) do
    [g, f, sl, aux] = queue_args(q, s)

    s
    |> del_att(g, "queue", 2)
    |> del_att(f, "queue", 2)
    |> del_att(sl, "queue", 2)
    |> del_att(aux, "disabled", 0)
  end

  # --- verify_attributes/3 (Hook bei der Bindung, Var noch ungebunden) ---
  #
  # Var ohne clpz-Attribut: Gs = []. Var = Zahl: in der Domäne?, alle
  # Propagatoren in die Queue der Variablen, Gs = [phrase(do_queue, [Q], _)].
  # Var = Variable mit Domäne, ein anderer Wert (type_error): das Original

  defbuiltin "$clpz_verify_attributes", [var, other, gs] do
    run("verify_attributes", [var, other, gs], subst(), fn ->
      s = subst_now()

      v =
        case PrologEx.Store.walk(var, s) do
          {:var, _} = v -> v
          _ -> throw(:fallback)
        end

      case att(v, s, "clpz", 1) do
        nil ->
          out_gs(gs, [], s)

        [attr] ->
          {dom, ps, q} =
            case ws(attr, s) do
              {tag, "clpz_attr", [_, _, _, dom, ps, q]} when tag in [:struct, :gstruct] ->
                {dom, ps, q}

              _ ->
                throw(:fallback)
            end

          case PrologEx.Store.walk(other, s) do
            {:var, _} = o ->
              verify_vars(v, attr, dom, ps, o, gs, s)

            i when is_integer(i) ->
              if contains_t(dom, i) do
                {pgs, bs, os} = props(ps, s)

                case s |> then_all(pgs, q) |> then_all(bs, q) |> then_all(os, q) do
                  :fail ->
                    :fail

                  s ->
                    out_gs(gs, [do_queue_goal(q)], s)
                end
              else
                :fail
              end

            _ ->
              throw(:fallback)
          end
      end
    end)
  end

  # Var = Other, beide ungebunden: Other mit Domäne – Schnitt, Propagatoren
  # zusammen, Queues zusammenlegen, fd_put//3 und trigger_props//1 mit
  # einer neuen Queue Q0, Gs = [phrase(do_queue, [Q0], _)]; Other ohne
  # Domäne bekommt das Attribut von Var. Das Zusammenlegen bindet
  # Queue-Variablen; andere Hook-Module sehen sie nicht (die Maschine ruft
  # Hooks nur für Variablen mit Attributen des Moduls)
  defp verify_vars(v, attr, dom, ps, o, gs, s) do
    case att(o, s, "clpz", 1) do
      nil ->
        s |> put_att(o, mk("clpz", [attr])) |> then(&out_gs(gs, [], &1))

      [oattr] ->
        {od, ops} =
          case ws(oattr, s) do
            {tag, "clpz_attr", [_, _, _, od, ops, _]} when tag in [:struct, :gstruct] ->
              {od, ops}

            _ ->
              throw(:fallback)
          end

        case isect(dom(od), dom(dom)) do
          nil ->
            :fail

          dom1 ->
            {g0, b0, o0} = props(ps, s)
            {g1, b1, o1} = props(ops, s)

            ps1 =
              mk("fd_props", [pl_append(g0, g1, s), pl_append(b0, b1, s), pl_append(o0, o1, s)])

            q0 = new_queue()

            s
            |> then(&same_queue([v, o], &1))
            |> seq(&put_terminating(o, ed(dom1), ps1, q0, &1))
            |> seq(fn s ->
              {pg, pb, po} = props(ps1, s)
              s |> then_all(pg, q0) |> then_all(pb, q0) |> then_all(po, q0)
            end)
            |> seq(&out_gs(gs, [do_queue_goal(q0)], &1))
        end
    end
  end

  # das Ziel, das die Propagatoren der Queue q laufen lässt: statt
  # phrase(do_queue, [Q], _) (phrase/3, do_queue/2, '$clpz_queue_run'/2,
  # do_queue_/3 – vier Schritte je Bindung) gleich die Schleife
  # (qualifiziert: die Hilfs-Builtins sind nur in clpz sichtbar, das Ziel
  # läuft im Modul des Aufrufers)
  defp do_queue_goal(q), do: mk(":", [a("clpz"), mk("$clpz_do_queue", [q])])

  # '$clpz_do_queue'(Q): phrase(do_queue, [Q], _) – die Schleife in Elixir,
  # braucht sie Prolog, geht es mit do_queue_/3 weiter
  defbuiltin "$clpz_do_queue", [q0] do
    s = subst()
    Process.put(:clpz_prims_subst, s)

    try do
      q = PrologEx.Store.walk(q0, s)
      queue_out(q, native(q, s, &loop_q(q, &1)))
    catch
      :fallback -> {:call, mk(":", [a("clpz"), mk("do_queue", [[q0], fresh_var()])])}
    end
  end

  defp out_gs(gs, l, s) do
    case PrologEx.unify(gs, l, s) do
      {:ok, s} -> {:subst, s}
      :error -> :fail
    end
  end

  # --- Ablegen: put_terminating//3 (fd_put//3) ---

  defp put_clpz(s, v, fields), do: put_att(s, v, mk("clpz", [mk("clpz_attr", fields)]))

  defp yes, do: a("yes")

  defp put_terminating(x, dom, ps, q, s) do
    case ws(dom, s) do
      # Dom \== empty
      [] ->
        :fail

      # ein Einzelwert: queue_goal(X = F)
      [h | tl] = d ->
        case {ws(h, s), ws(tl, s)} do
          {b, []} when is_integer(b) -> insert(mk("=", [x, b]), 1, q, s)
          _ -> put_dom(x, d, dom, ps, q, s)
        end

      _ ->
        no_domain(dom)
    end
  end

  defp put_dom(x, _d, dom, ps, q, s) do
    case PrologEx.Store.walk(x, s) do
      {:var, _} = v ->
        case att(v, s, "clpz", 1) do
          [attr] ->
            case ws(attr, s) do
              {tag, "clpz_attr", [left, right, spread, old_dom, _old_ps, qx]}
              when tag in [:struct, :gstruct] ->
                s = put_clpz(s, v, [left, right, spread, dom, ps, qx])

                if dom_same?(old_dom, dom, s),
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

  # OldDom == Dom: beide im Merkzettel, dann als Listen (exakt, siehe dort)
  defp dom_same?(old, new, s) do
    cache = dec_cache()

    with d0 when d0 != nil <- dec_find(cache, ws(old, s)),
         d1 when d1 != nil <- dec_find(cache, ws(new, s)) do
      d0 === d1
    else
      _ -> PrologEx.Order.equal?(old, new, s)
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
  # domain_spread/2 auf dem Term: nur das erste und das letzte Intervall
  defp spread_of(d) do
    case w(d) do
      [] ->
        throw(:fallback)

      [h | tl] ->
        {l1, u1} = elem_pair(h)
        {ln, un} = last_pair(h, tl)
        # smallest_finite: l1, oder u1 bei l1 = inf; largest_finite: un, oder ln bei un = sup
        sm = if l1 == :inf, do: u1, else: l1
        lg = if un == :sup, do: ln, else: un
        minus(lg, sm)

      _ ->
        no_domain(d)
    end
  end

  defp elem_pair(h) do
    case w(h) do
      i when is_integer(i) -> {i, i}
      {tag, "..", [l, u]} when tag in [:struct, :gstruct] -> {bound(l), bound(u)}
      _ -> throw(:fallback)
    end
  end

  defp last_pair(h, tl) do
    case w(tl) do
      [] -> elem_pair(h)
      [h2 | tl2] -> last_pair(h2, tl2)
      _ -> throw(:fallback)
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
    arg = PrologEx.Store.walk(qarg(args, which), s)

    with {:var, _} <- arg,
         [h, t] <- att(arg, s, "queue", 2),
         {e, es} <- cell(h, s) do
      s =
        if match?({:var, _}, PrologEx.Store.walk(es, s)),
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

      aux = PrologEx.Store.walk(qarg(args, 4), s)

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
             reified_geq reified_and scalar_product_leq pgeq ptimes pmax pmin pabs
             reified_eq reified_neq pexp ptzdiv prem pmod reified_or reified_not pimpl
             x_leq_y_plus_c pelement pgcc_check pgcc_check_single x_neq_y_plus_z
             scalar_product_neq reified_in reified_fd pxor psign)

  @doc "Die Propagatoren, die activate_propagator//1 in Elixir rechnet"
  def ported, do: @ported

  # Ist n einer davon? Eine Klausel je Name: der Compiler macht daraus
  # einen Entscheidungsbaum über die Bytes (select_val); `n in @ported` im
  # Guard wären bis zu 35 Vergleiche nacheinander (bis zu 190 ns)
  for p <- @ported do
    defp ported?(unquote(p)), do: true
  end

  defp ported?(_), do: false

  defbuiltin "$clpz_activate", [prop, s0, s1] do
    run("activate_propagator", [prop, s0, s1], subst(), fn ->
      s = subst_now()

      case activate(prop, state_q(s0, s), s) do
        {:ok, s} -> finish(s1, s0, s)
        :fail -> :fail
        :fallback -> throw(:fallback)
      end
    end)
  end

  # Ein Propagator in Elixir: {:ok, s}, :fail oder :fallback (das Original
  # rechnet; s unverändert). Bindet er Variablen, wecken die Maschine bzw.
  # absorb_wake/3 erst danach, vor dem nächsten Propagator (im Original:
  # mitten im Propagator). Das gilt für freeze, dif, when an
  # Benutzervariablen ebenso wie für die Hooks anderer Module: die ruft die
  # Maschine nur für Variablen mit Attributen des Moduls, die internen
  # Variablen von clpz (Zustand, Queues) sehen sie nicht. Bis November 2026
  # rechnete mit einem weiteren Hook-Modul das Original – drei- bis
  # zwölfmal langsamer.
  defp activate(prop, q, s) do
    Process.put(:clpz_prims_subst, s)
    nq = Process.get(@nq)

    try do
      {p, state} =
        case ws(prop, s) do
          {tag, "propagator", [p, st]} when tag in [:struct, :gstruct] -> {p, st}
          _ -> throw(:fallback)
        end

      st = PrologEx.Store.walk(state, s)

      cond do
        st == {:atom, "dead"} ->
          {:ok, s}

        not match?({:var, _}, st) ->
          :fallback

        true ->
          {name, args} =
            case ws(p, s) do
              {tag, n, args} when tag in [:struct, :gstruct] ->
                if ported?(n), do: {n, args}, else: throw(:fallback)

              _ ->
                throw(:fallback)
            end

          # freeze, dif, when (oder ein anderes Modul) am Zustand: das
          # Original (es weckt sie mitten im Propagator)
          unless only_clpz_attrs?(st, s), do: throw(:fallback)
          s = del_att(s, st, "clpz_aux", 1)

          # no_reactivation (pdistinct): der laufende Propagator steht in
          # '$clpz_current_propagator' (trigger_prop//1 reiht ihn nicht ein)
          r =
            if name == "pdistinct" do
              s = Blackboard.b_put(s, "clpz", "$clpz_current_propagator", st)

              case propagate(name, args, st, q, s) do
                :fail -> :fail
                s -> Blackboard.b_put(s, "clpz", "$clpz_current_propagator", [])
              end
            else
              propagate(name, args, st, q, s)
            end

          if r == :fail, do: :fail, else: {:ok, r}
      end
    catch
      :fallback -> restore_nq(nq, :fallback)
    end
  end

  # ein verworfener Zustand: auch die Queue in Elixir wie vorher
  defp restore_nq(nil, r), do: r

  defp restore_nq(nq, r) do
    Process.put(@nq, nq)
    r
  end

  # --- do_queue//0: die Schleife ----------------------------------------------
  #
  # '$clpz_queue_run'(S0, Next): Propagatoren aus der Queue nacheinander in
  # Elixir, bis Next feststeht: none (leer oder abgeschaltet), goal(G) (ein
  # Ziel: Prolog ruft es), ref(P) (P rechnet das Original) oder again (eine
  # Bindung: erst wecken, dann weiter). Bindungen, deren Wecken nichts tun
  # kann – der Zustand eines getöteten Propagators: nur clpz-interne
  # Attribute, verify_attributes/3 von clpz gibt [] –, gelten als erledigt.

  defbuiltin "$clpz_queue_run", [s0, next] do
    run("queue_run", [s0, next], subst(), fn ->
      s = subst_now()
      q = state_q(s0, s)

      args =
        case ws(q, s) do
          {tag, "queue", [_, _, _, _] = args} when tag in [:struct, :gstruct] -> args
          _ -> throw(:fallback)
        end

      case native(q, s, &queue_loop(q, args, &1)) do
        :fail -> :fail
        {:next, t, s} -> out_next(next, t, s)
      end
    end)
  end

  # fd_put/3 (new_queue/1, put_terminating//3, do_queue//0) und
  # trigger_once_/2 (trigger_prop//1, do_queue//0) in einem Builtin: die
  # Schleife wie '$clpz_queue_run'/2; braucht sie Prolog (ein Ziel, ein
  # Propagator für das Original, Wecken), geht es mit do_queue_/3 weiter,
  # wie im Original nach '$clpz_queue_run'/2
  defbuiltin "$clpz_fd_put", [x, dom, ps] do
    run("fd_put", [x, dom, ps], subst(), fn ->
      s = subst_now()
      if Process.get(:clpz_no_fast), do: throw(:fallback)
      q = new_queue()

      native(q, s, fn s ->
        case put_terminating(x, dom, ps, q, s) do
          :fail -> :fail
          s -> loop_q(q, s)
        end
      end)
      |> then(&queue_out(q, &1))
    end)
  end

  # '$clpz_neq_num'(X, N): neq_num/2 – fd_get/3, domain_remove/3, fd_put/3
  # wie '$clpz_fd_put'/3 in einem Zug; X keine Variable oder N keine Zahl:
  # das Original (X =\= N, Fehler)
  defbuiltin "$clpz_neq_num", [x, n] do
    run("neq_num", [x, n], subst(), fn ->
      s = subst_now()
      if Process.get(:clpz_no_fast), do: throw(:fallback)

      with {:var, _} = v <- PrologEx.Store.walk(x, s),
           k when is_integer(k) <- PrologEx.Store.walk(n, s) do
        {d, ps} = fdget(v, s)

        case remove(d, k) do
          [] ->
            :fail

          d1 ->
            q = new_queue()

            native(q, s, fn s ->
              case fdput(v, d1, ps, q, s) do
                :fail -> :fail
                s -> loop_q(q, s)
              end
            end)
            |> then(&queue_out(q, &1))
        end
      else
        _ -> throw(:fallback)
      end
    end)
  end

  # '$clpz_parse_simple'(E, R): E ist eine ganze Zahl oder eine Variable
  # mit clpz-Attribut (also schon eine Domäne): R = E (der Abkürzer vor
  # parse_clpz/2, siehe make_parse_clpz/1); sonst scheitern
  defbuiltin "$clpz_parse_simple", [e, r] do
    s = subst()

    case PrologEx.Store.walk(e, s) do
      i when is_integer(i) ->
        {:unify, [{r, i}]}

      {:var, _} = v ->
        if Process.get(:clpz_no_fast) == nil and att(v, s, "clpz", 1) != nil,
          do: {:unify, [{r, v}]},
          else: false

      _ ->
        false
    end
  end

  defbuiltin "$clpz_trigger_once", [p, q0] do
    run("trigger_once_", [p, q0], subst(), fn ->
      s = subst_now()
      if Process.get(:clpz_no_fast), do: throw(:fallback)
      q = PrologEx.Store.walk(q0, s)

      native(q, s, fn s ->
        case trigger(p, q, s) do
          :fail -> :fail
          s -> loop_q(q, s)
        end
      end)
      |> then(&queue_out(q, &1))
    end)
  end

  defp loop_q(q, s) do
    args =
      case ws(q, s) do
        {tag, "queue", [_, _, _, _] = args} when tag in [:struct, :gstruct] -> args
        _ -> throw(:fallback)
      end

    queue_loop(q, args, s)
  end

  # Ergebnis der Schleife als Ergebnis des Builtins: leer – fertig; sonst
  # macht do_queue_/3 in Prolog weiter
  defp queue_out(q, r) do
    case r do
      :fail ->
        :fail

      {:next, {:atom, "none"}, s} ->
        {:subst, s}

      {:next, t, s} ->
        {:call, mk(":", [a("clpz"), mk("do_queue_", [t, [q], fresh_var()])]), s}
    end
  end

  # --- Aufstellen: clpz_neq_fast/3 (Abkürzer von X #\\= Y) -----------------------
  #
  # '$clpz_neq_fast'(K, A, B) wie clpz_neq_fast_ref/3: num_a/num_b ein
  # neq_num/2 (fd_put/3 mit frischer Queue, bis zum Fixpunkt), pneq und
  # absdiff pit/4 plus trigger_once_/2 in einem Zug; parse_clpz/2 nur in
  # der einfachen Form ('$clpz_parse_simple'/2: Zahl oder Variable mit
  # Domäne). Anderes: das Original.

  defbuiltin "$clpz_neq_fast", [k, a, b] do
    run("clpz_neq_fast", [k, a, b], subst(), fn ->
      s = subst_now()
      if Process.get(:clpz_no_fast), do: throw(:fallback)

      case w(k) do
        {:atom, "num_a"} ->
          neq_num_post(a, b, s)

        {:atom, "num_b"} ->
          neq_num_post(b, a, s)

        {:atom, "pneq"} ->
          pit_trigger([a, b], mk("pneq", [a, b]), s)

        {:atom, "absdiff"} ->
          {g, h} =
            with {t1, "abs", [d]} when t1 in [:struct, :gstruct] <- ws(a, s),
                 {t2, "-", [g, h]} when t2 in [:struct, :gstruct] <- ws(d, s) do
              {g, h}
            else
              _ -> throw(:fallback)
            end

          i = parse_simple(g, s)
          j = parse_simple(h, s)
          pit_trigger([i, j, b], mk("absdiff_neq", [i, j, b]), s)

        _ ->
          throw(:fallback)
      end
    end)
  end

  # '$clpz_neq_exp'(X0, Y0, XVs, YVs): die Expansion von X0 #\\= Y0 für
  # einfache Seiten (siehe clpz_expansion/2): CondX/CondY sind integer/1
  # für jede Variable in XVs/YVs; beide – X =\\= Y, eine – auswerten und
  # clpz_neq/2, keine – clpz_neq(X0, Y0)
  defbuiltin "$clpz_neq_exp", [x0, y0, xvs, yvs] do
    s = subst()
    cx = all_ints?(xvs, s)
    cy = all_ints?(yvs, s)
    neq = &{:call, mk(":", [a("clpz"), mk("clpz_neq", [&1, &2])])}

    cond do
      cx and cy ->
        PrologEx.Arith.compare_num("=\\=", PrologEx.Arith.eval(x0, s), PrologEx.Arith.eval(y0, s))

      cx ->
        neq.(PrologEx.Arith.eval(x0, s), y0)

      cy ->
        neq.(x0, PrologEx.Arith.eval(y0, s))

      true ->
        neq.(x0, y0)
    end
  end

  # '$clpz_eq_exp'(X0, Y0, XVs, YVs): die Expansion von X0 #= Y0 für
  # einfache Seiten, wie '$clpz_neq_exp'/4: beide – X0 =:= Y0 (ist Y0 eine
  # ungebundene Variable: Y0 is X0), eine – auswerten (die andere eine
  # ungebundene Variable: binden, sonst clpz_equal/2 mit dem Wert), keine
  # – clpz_equal(X0, Y0)
  defbuiltin "$clpz_eq_exp", [x0, y0, xvs, yvs] do
    s = subst()
    cx = all_ints?(xvs, s)
    eq = &{:call, mk(":", [a("clpz"), mk("clpz_equal", [&1, &2])])}

    cond do
      cx ->
        x = PrologEx.Arith.eval(x0, s)

        cond do
          var?(PrologEx.Store.walk(y0, s)) -> {:unify, [{y0, x}]}
          all_ints?(yvs, s) -> PrologEx.Arith.compare_num("=:=", x, PrologEx.Arith.eval(y0, s))
          true -> eq.(x, y0)
        end

      all_ints?(yvs, s) ->
        y = PrologEx.Arith.eval(y0, s)

        if var?(PrologEx.Store.walk(x0, s)), do: {:unify, [{x0, y}]}, else: eq.(x0, y)

      true ->
        eq.(x0, y0)
    end
  end

  defp ints?([]), do: true
  defp ints?([i | l]), do: is_integer(i) and ints?(l)

  defp all_ints?(l, s) do
    case PrologEx.Store.walk(l, s) do
      [] -> true
      [h | t] -> is_integer(PrologEx.Store.walk(h, s)) and all_ints?(t, s)
      {:glist, l} -> ints?(l)
      _ -> false
    end
  end

  # parse_clpz/2 in der Form von '$clpz_parse_simple'/2; sonst das Original
  defp parse_simple(e, s) do
    case PrologEx.Store.walk(e, s) do
      i when is_integer(i) -> i
      {:var, _} = v -> if att(v, s, "clpz", 1) != nil, do: v, else: throw(:fallback)
      _ -> throw(:fallback)
    end
  end

  # neq_num/2: fd_get/3, domain_remove/3, fd_put/3; ohne Domäne X =\\= N
  defp neq_num_post(x, n, s) do
    n = PrologEx.Store.walk(n, s)
    unless is_integer(n), do: throw(:fallback)

    case PrologEx.Store.walk(x, s) do
      {:var, _} = v ->
        {d, ps} = fdget(v, s)
        q = new_queue()

        native(q, s, fn s ->
          case fdput(v, remove(d, n), ps, q, s) do
            :fail -> :fail
            s -> loop_q(q, s)
          end
        end)
        |> then(&queue_out(q, &1))

      i when is_integer(i) ->
        if i != n, do: {:subst, s}, else: :fail

      _ ->
        throw(:fallback)
    end
  end

  # pit/4 und trigger_once_/2 wie '$clpz_pit'/4 und '$clpz_trigger_once'/2
  defp pit_trigger(vs, p0, s) do
    p = mk("propagator", [p0, fresh_var()])
    q = new_queue()

    vs
    |> init_all(p, q, s)
    |> seq(&same_queue(vs, &1))
    |> case do
      :fail ->
        :fail

      s ->
        s = drop_inert_wake(s)

        native(q, s, fn s ->
          case trigger(p, q, s) do
            :fail -> :fail
            s -> loop_q(q, s)
          end
        end)
        |> then(&queue_out(q, &1))
    end
  end

  # --- Aufstellen: Vs ins D ----------------------------------------------------
  #
  # '$clpz_ins'(Vs, D) wie ins_ref/2 für eine echte Liste aus Variablen und
  # Zahlen und D eine Zahl oder N..M (wie '$clpz_in_dom'/3): je Element
  # domain/2 – eine Zahl muss in D liegen; eine Variable: fd_get/3,
  # Schnitt, fd_put/3 (frische Queue bis zum Fixpunkt), reinforce/1. Braucht
  # die Queue Prolog, macht do_queue_/3 weiter, danach reinforce/1 und
  # domains/2 über den Rest. Anderes: das Original

  defbuiltin "$clpz_ins", [vs, d0] do
    run("ins", [vs, d0], subst(), fn ->
      s = subst_now()
      if Process.get(:clpz_no_fast), do: throw(:fallback)
      # erst die ganze Liste prüfen: braucht ein Element Prolog, machen
      # domains/2 dort weiter, und die prüfen nichts mehr
      vars_or_ints!(vs, s)

      dt =
        case simple_drep(ws(d0, s), s) do
          {:ok, dt} -> dt
          :error -> throw(:fallback)
        end

      ins_items(vs, dom(dt), dt, s)
    end)
  end

  # eine echte Liste aus Variablen und Zahlen, sonst das Original
  defp vars_or_ints!(l, s) do
    case ws(l, s) do
      [] -> :ok
      [x | t] -> if var_or_int?(x, s), do: vars_or_ints!(t, s), else: throw(:fallback)
      _ -> throw(:fallback)
    end
  end

  defp ins_items(l, dd, dt, s) do
    case ws(l, s) do
      [] -> {:subst, s}
      [x | rest] -> ins_item(x, rest, dd, dt, s)
    end
  end

  defp ins_item(x, rest, dd, dt, s) do
    case PrologEx.Store.walk(x, s) do
      i when is_integer(i) ->
        if ClpzDom.contains?(dd, i), do: ins_items(rest, dd, dt, s), else: :fail

      {:var, _} = v ->
        {d0, ps} = fdget(v, s)

        case ClpzDom.intersection(dd, d0) do
          [] ->
            :fail

          d1 ->
            q = new_queue()

            native(q, s, fn s ->
              case fdput(v, d1, ps, q, s) do
                :fail -> :fail
                s -> loop_q(q, s)
              end
            end)
            |> case do
              :fail ->
                :fail

              {:next, {:atom, "none"}, s} ->
                ins_items(rest, dd, dt, reinforce_one(v, s))

              {:next, t, s} ->
                goal =
                  mk(",", [
                    mk("do_queue_", [t, [q], fresh_var()]),
                    mk(",", [mk("reinforce", [v]), mk("domains", [rest, dt])])
                  ])

                {:call, mk(":", [a("clpz"), goal]), s}
            end
        end
    end
  end

  # --- Aufstellen: sum/3, scalar_product/4 mit #= ------------------------------
  #
  # '$clpz_sum'(Vs, Op, Value) und '$clpz_scalar_product'(Cs, Vs, Op, Value)
  # wie die Originale (sum_ref/3, scalar_product_ref/4), wenn Op #= ist,
  # Value eine Zahl, Cs eine echte Liste aus Zahlen und Vs eine gleich
  # lange aus Zahlen und Variablen mit Domäne: alle Vs Zahlen – die Summe
  # vergleichen; sonst left_right_linsum_const/5 (wie '$clpz_linsum'/5),
  # scalar_product_/4 (gcd, teilen) und pit/4 mit trigger_once_/2 in einem
  # Zug. Eine Konstante 0 (multiples/3), keine Glieder, Variablen ohne
  # Domäne, andere Relationen, Fehler: das Original

  defbuiltin "$clpz_sum", [vs, op, value] do
    run("sum", [vs, op, value], subst(), fn -> sp_post(:ones, vs, op, value, subst_now()) end)
  end

  defbuiltin "$clpz_scalar_product", [cs, vs, op, value] do
    run("scalar_product", [cs, vs, op, value], subst(), fn ->
      s = subst_now()
      sp_post(ws(cs, s), vs, op, value, s)
    end)
  end

  # cs: die Koeffizienten (walked) oder :ones (sum/3)
  defp sp_post(cs, vs, op, value, s) do
    if Process.get(:clpz_no_fast), do: throw(:fallback)
    unless ws(op, s) == a("#="), do: throw(:fallback)

    r =
      case PrologEx.Store.walk(value, s) do
        r when is_integer(r) -> r
        _ -> throw(:fallback)
      end

    case sp_terms(cs, ws(vs, s), s, [], true) do
      # ground(Vs): foldl(coeff_int_linsum, Cs, Vs, 0, Right)
      {terms, true} ->
        if dot_terms(terms, 0) == r, do: {:subst, s}, else: :fail

      {terms, false} ->
        case lin_merge(terms, s) do
          [] -> throw(:fallback)
          _ when r == 0 -> throw(:fallback)
          merged -> sp_eq(merged, r, s)
        end
    end
  end

  # die Glieder {X, C} (umgekehrt: lin_merge/2 sortiert ohnehin) und ob
  # alle X Zahlen sind; X eine Zahl oder Variable mit Domäne, C eine Zahl,
  # beide Listen echt und gleich lang, sonst das Original
  defp sp_terms(:ones, [x | xs], s, acc, g), do: sp_term(1, :ones, x, xs, s, acc, g)

  defp sp_terms([c | cs], [x | xs], s, acc, g) do
    case PrologEx.Store.walk(c, s) do
      c when is_integer(c) -> sp_term(c, ws(cs, s), x, xs, s, acc, g)
      _ -> throw(:fallback)
    end
  end

  defp sp_terms(:ones, [], _s, acc, g), do: {acc, g}
  defp sp_terms([], [], _s, acc, g), do: {acc, g}
  defp sp_terms(_, _, _s, _acc, _g), do: throw(:fallback)

  defp sp_term(c, cs, x, xs, s, acc, g) do
    case PrologEx.Store.walk(x, s) do
      i when is_integer(i) ->
        sp_terms(cs, ws(xs, s), s, [{i, c} | acc], g)

      {:var, _} = v ->
        if fdvar?(v, s),
          do: sp_terms(cs, ws(xs, s), s, [{v, c} | acc], false),
          else: throw(:fallback)

      _ ->
        throw(:fallback)
    end
  end

  defp dot_terms([], sum), do: sum
  defp dot_terms([{x, c} | ts], sum), do: dot_terms(ts, sum + c * x)

  # '$clpz_sp_eq'(Cs0, Vs, S0): scalar_product_//4 mit #= wie sp_eq_ref/3
  # (aus dem Matcher von X #= Y, scalar_product_ref/4 & Co.) für Cs0 eine
  # nicht leere Liste aus Zahlen ungleich 0, Vs eine gleich lange aus
  # Variablen und Zahlen, S0 eine Zahl ungleich 0; sonst das Original
  defbuiltin "$clpz_sp_eq", [cs, vs, s0] do
    run("sp_eq", [cs, vs, s0], subst(), fn ->
      s = subst_now()
      if Process.get(:clpz_no_fast), do: throw(:fallback)

      r =
        case PrologEx.Store.walk(s0, s) do
          r when is_integer(r) and r != 0 -> r
          _ -> throw(:fallback)
        end

      case sp_pairs(ws(cs, s), ws(vs, s), s) do
        [] -> throw(:fallback)
        merged -> sp_eq(merged, r, s)
      end
    end)
  end

  # [{X, C}] in der Reihenfolge der Listen: C eine Zahl ungleich 0, X eine
  # Zahl oder Variable, beide Listen echt und gleich lang (sonst das
  # Original)
  defp sp_pairs([], [], _s), do: []

  defp sp_pairs([c | cs], [x | xs], s) do
    c =
      case PrologEx.Store.walk(c, s) do
        c when is_integer(c) and c != 0 -> c
        _ -> throw(:fallback)
      end

    case PrologEx.Store.walk(x, s) do
      x when is_integer(x) -> [{x, c} | sp_pairs(ws(cs, s), ws(xs, s), s)]
      {:var, _} = x -> [{x, c} | sp_pairs(ws(cs, s), ws(xs, s), s)]
      _ -> throw(:fallback)
    end
  end

  defp sp_pairs(_, _, _s), do: throw(:fallback)

  # '$clpz_eq_linear'(X, Y): keine Klausel des Matchers von X #= Y vor der
  # für lineare Summen kann greifen (die ersten fünf verlangen auf einer
  # Seite eine Variable oder Zahl und auf der anderen eine solche oder
  # A+B, A-B, A*B, -A aus solchen); beide Seiten azyklisch (die erste
  # Klausel prüft das), kein ?(_)/#(_) an diesen Stellen, nicht monotonic
  # (dort prüft schon v_or_i/1). Sonst scheitert es: der Matcher
  defbuiltin "$clpz_eq_linear", [x0, y0] do
    s = subst()

    with nil <- Process.get(:clpz_no_fast),
         false <- monotonic?(ctx.db),
         x = PrologEx.unmark_top(PrologEx.Store.walk(x0, s)),
         y = PrologEx.unmark_top(PrologEx.Store.walk(y0, s)),
         vx when vx != :unsafe <- vlike(x),
         vy when vy != :unsafe <- vlike(y),
         false <- vx and vy,
         false <- vx and vform(y, s),
         false <- vy and vform(x, s),
         true <- PrologEx.Builtins.Terms.acyclic?(x, s),
         true <- PrologEx.Builtins.Terms.acyclic?(y, s) do
      true
    else
      _ -> false
    end
  end

  # Variable oder Zahl (v_or_i/1 ohne monotonic), ?(_)/#(_): :unsafe
  defp vlike({:var, _}), do: true
  defp vlike(i) when is_integer(i), do: true
  defp vlike({tag, f, [_]}) when tag in [:struct, :gstruct] and f in ["?", "#"], do: :unsafe
  defp vlike(_), do: false

  # A+B, A-B, A*B, -A mit A, B wie vlike/1 (:unsafe zählt als ja: dann
  # entscheidet der Matcher)
  defp vform({tag, f, [a, b]}, s) when tag in [:struct, :gstruct] and f in ["+", "-", "*"],
    do: vlike(ww(a, s)) != false and vlike(ww(b, s)) != false

  defp vform({tag, "-", [a]}, s) when tag in [:struct, :gstruct], do: vlike(ww(a, s)) != false
  defp vform(_, _s), do: false

  defp ww(t, s), do: PrologEx.unmark_top(PrologEx.Store.walk(t, s))

  # scalar_product_(#=, Cs0, Vs, S0) mit S0 =/= 0
  defp sp_eq([{_, c} | rest] = merged, s0, s) do
    g = gcd_terms(rest, c)

    if rem(s0, g) == 0 do
      vs = term_vars(merged)
      pit_trigger(vs, mk("scalar_product_eq", [div_coeffs(merged, g), vs, div(s0, g)]), s)
    else
      :fail
    end
  end

  # gcd/3 des Originals: mit C anfangen (bei einem Glied bleibt sein
  # Vorzeichen)
  defp gcd_terms([], g), do: g
  defp gcd_terms([{_, n} | ts], g), do: gcd_terms(ts, Integer.gcd(n, g))

  defp div_coeffs([], _g), do: []
  defp div_coeffs([{_, n} | ts], g), do: cons(div(n, g), div_coeffs(ts, g))

  # --- Aufstellen: all_distinct/1, all_different/1 ---------------------------
  #
  # Nach den Typprüfungen (in Prolog) der Rest wie im Original, in Elixir:
  # die Anhänge-Schleife (distinct_attach//3 bzw. all_different//3: für
  # eine Variable die Propagatoren anlegen, anhängen und einreihen, für eine
  # Zahl exclude_fire//3), dann do_queue//0 auf der frischen Queue, bei
  # all_distinct/1 danach variables_same_queue/1. Braucht die Schleife
  # Prolog, geht es mit do_queue_/3 weiter; Unerwartetes: das Original
  # (all_distinct_post_ref/1, all_different_post_ref/2).

  defbuiltin "$clpz_all_distinct_post", [ls] do
    run("all_distinct_post", [ls], subst(), fn ->
      prop = mk("propagator", [mk("pdistinct", [ls]), fresh_var()])

      post_with_queue(subst_now(), fn q, s ->
        s
        |> distinct_attach(ls, prop, [], q)
        |> seq(&trigger(prop, q, &1))
      end)
      |> post_out(fn s -> same_queue(ls, s) end, [
        mk(":", [a("clpz"), mk("variables_same_queue", [ls])])
      ])
    end)
  end

  defbuiltin "$clpz_all_different_post", [ls, orig] do
    run("all_different_post", [ls, orig], subst(), fn ->
      post_with_queue(subst_now(), fn q, s ->
        all_different_attach(s, ls, [], orig, q)
      end)
      |> post_out(fn s -> s end, [])
    end)
  end

  # frische Queue, f stellt auf, dann die Schleife: :fail, {:ok, s} oder
  # {:prolog, t, q, s} (do_queue_/3 mit t muss weitermachen)
  defp post_with_queue(s, f) do
    q = new_queue()
    {_, _, qargs} = q

    native(q, s, fn s ->
      case f.(q, s) do
        :fail -> :fail
        s -> queue_loop(q, qargs, s)
      end
    end)
    |> case do
      :fail -> :fail
      {:next, {:atom, "none"}, s} -> {:ok, s}
      {:next, t, s} -> {:prolog, t, q, s}
    end
  end

  # Ergebnis des Builtins; danach: rest (in Elixir) bzw. die Ziele then (in
  # Prolog, wenn die Schleife dort weitermacht)
  defp post_out(r, rest, then) do
    case r do
      :fail ->
        :fail

      {:ok, s} ->
        case rest.(s) do
          :fail -> :fail
          s -> {:subst, s}
        end

      {:prolog, t, q, s} ->
        goal = mk(":", [a("clpz"), mk("do_queue_", [t, [q], fresh_var()])])
        {:call, then_goals(goal, then), s}
    end
  end

  defp then_goals(goal, []), do: goal
  defp then_goals(goal, [g | gs]), do: then_goals(mk(",", [goal, g]), gs)

  # distinct_attach//3
  defp distinct_attach(:fail, _l, _prop, _right, _q), do: :fail

  defp distinct_attach(s, l, prop, right, q) do
    case cell(l, s) do
      nil ->
        if ws(l, s) == [], do: s, else: throw(:fallback)

      {x, xs} ->
        xw = PrologEx.Store.walk(x, s)

        s =
          if var?(xw) do
            p1 = mk("propagator", [mk("pexclude", [xs, right, x]), fresh_var()])

            s
            |> then(&init_one(x, prop, q, &1))
            |> seq(&init_one(x, p1, q, &1))
            |> seq(&trigger(p1, q, &1))
          else
            exclude_fire(s, xs, right, xw, q)
          end

        distinct_attach(s, xs, prop, [x | right], q)
    end
  end

  # all_different//3
  defp all_different_attach(:fail, _l, _left, _orig, _q), do: :fail

  defp all_different_attach(s, l, left, orig, q) do
    case cell(l, s) do
      nil ->
        if ws(l, s) == [], do: s, else: throw(:fallback)

      {x, right} ->
        xw = PrologEx.Store.walk(x, s)

        s =
          if var?(xw) do
            p = mk("propagator", [mk("pdifferent", [left, right, x, orig]), fresh_var()])

            s
            |> then(&init_one(x, p, q, &1))
            |> seq(&trigger(p, q, &1))
          else
            exclude_fire(s, left, right, xw, q)
          end

        all_different_attach(s, right, [x | left], orig, q)
    end
  end

  # exclude_fire//3: all_neq//2 über Left, dann über Right
  defp exclude_fire(s, left, right, e, q) do
    unless is_integer(e), do: throw(:fallback)

    s |> neq_list(left, e, q) |> neq_list(right, e, q)
  end

  # neq_num(Y, E) für jedes Y der Liste l (Prolog oder Elixir; unecht: das
  # Original)
  defp neq_list(:fail, _l, _e, _q), do: :fail

  defp neq_list(s, l, e, q) do
    case ws(l, s) do
      [] -> s
      [y | l] -> y |> neq_num(e, q, s) |> neq_list(l, e, q)
      _ -> throw(:fallback)
    end
  end

  # --- Restziele: unwrap_with/3 ----------------------------------------------
  #
  # '$clpz_residuals'(Mode, Gs0, Gs): je Ziel G0 aus Gs0 clpz:G (Restziele
  # von attribute_goals//1; das Original: maplist(unwrap_with(...)) und
  # maplist(with_clpz)). G ist G0 mit jedem #(V0) bei Mode plain durch V0
  # ersetzt (unwrap_with(=)), bei bare durch V0, wenn V0 eine ganze Zahl
  # ist, sonst bleibt es (unwrap_with(bare_integer)); in V0 hinein nicht.
  # Das Original zerlegte jeden Teilterm mit =.. – bei 1000 Restzielen gut
  # 70 ms

  defbuiltin "$clpz_residuals", [mode, gs0, gs] do
    s = subst()
    bare = PrologEx.Store.walk(mode, s) == {:atom, "bare"}

    out =
      for g <- PrologEx.Builtins.Lists.items(gs0, s),
          do: mk(":", [a("clpz"), unwrap(PrologEx.resolve(g, s), bare)])

    {:unify, [{gs, PrologEx.list(out)}]}
  end

  defp unwrap({:struct, "#", [x]} = h, bare),
    do: if(bare and not is_integer(x), do: h, else: x)

  defp unwrap({:struct, f, args}, bare), do: {:struct, f, Enum.map(args, &unwrap(&1, bare))}
  defp unwrap([h | t], bare), do: [unwrap(h, bare) | unwrap(t, bare)]
  defp unwrap(t, _bare), do: t

  # '$clpz_attr_goals'(Ps, Mode, Compact, Items): attributes_goals//2 für
  # die Propagatoren Ps einer Variablen in einem Schritt. Ein Propagator mit
  # gebundenem Zustand ist schon erledigt (fällt weg); für die häufigen
  # (Tabelle unten, wie attribute_goal_//1) gleich die Ziele clpz:G, wie
  # '$clpz_residuals'/3 ausgepackt (Mode), und der Zustand wird wie im
  # Original erledigt: del_attr(State, clpz_aux), State = processed. Die
  # übrigen bleiben als p(propagator(P, State)) für Prolog (in der
  # Reihenfolge). Compact: Wert des Flags clpz_residuals (x_leq_y_plus_c:
  # residual_leq/4)
  defbuiltin "$clpz_attr_goals", [ps, mode, compact, items] do
    s = subst()
    bare = PrologEx.Store.walk(mode, s) == {:atom, "bare"}
    compact = PrologEx.Store.walk(compact, s) == {:atom, "compact"}

    {out, s} =
      Enum.reduce(PrologEx.Builtins.Lists.items(ps, s), {[], s}, fn p, {out, s} ->
        attr_item(p, bare, compact, out, s)
      end)

    case PrologEx.unify(items, PrologEx.list(Enum.reverse(out)), s) do
      {:ok, s} -> {:subst, s}
      :error -> :fail
    end
  end

  defp attr_item(p, bare, compact, out, s) do
    fallback = {[mk("p", [p]) | out], s}

    with {:struct, "propagator", [prop, st]} <- ws(p, s),
         {:state, {:var, _} = st} <- {:state, PrologEx.Store.walk(st, s)},
         {:struct, f, args} <- ws(prop, s),
         {:ok, gs} <- attr_goal(f, Enum.map(args, &PrologEx.Store.walk(&1, s)), compact),
         s = del_att(s, st, "clpz_aux", 1),
         {:ok, s} <- PrologEx.unify(st, a("processed"), s) do
      gs = for g <- gs, do: mk(":", [a("clpz"), unwrap(PrologEx.resolve(g, s), bare)])
      {Enum.reverse(gs, out), s}
    else
      # Zustand gebunden (dead, processed): wie ground(State); sonst Prolog
      {:state, {:atom, _}} -> {out, s}
      _ -> fallback
    end
  end

  defp h(x), do: mk("#", [x])

  # attribute_goal_//1 des Originals (Auswahl): {:ok, Ziele} oder :no
  defp attr_goal("pgeq", [x, y], _), do: {:ok, [mk("#>=", [h(x), h(y)])]}
  defp attr_goal("pplus", [x, y, z, _], _), do: {:ok, [mk("#=", [mk("+", [h(x), h(y)]), h(z)])]}
  defp attr_goal("pneq", [x, y], _), do: {:ok, [mk("#\\=", [h(x), h(y)])]}
  defp attr_goal("ptimes", [x, y, z, _], _), do: {:ok, [mk("#=", [mk("*", [h(x), h(y)]), h(z)])]}

  defp attr_goal("absdiff_neq", [x, y, c], _),
    do: {:ok, [mk("#\\=", [mk("abs", [mk("-", [h(x), h(y)])]), c])]}

  defp attr_goal("x_eq_abs_plus_v", [x, v], _),
    do: {:ok, [mk("#=", [h(x), mk("+", [mk("abs", [h(x)]), h(v)])])]}

  defp attr_goal("x_neq_y_plus_z", [x, y, z], _),
    do: {:ok, [mk("#\\=", [h(x), mk("+", [h(y), h(z)])])]}

  defp attr_goal("ptzdiv", [x, y, z, _], _), do: {:ok, [mk("#=", [mk("//", [h(x), h(y)]), h(z)])]}
  defp attr_goal("pexp", [x, y, z, _], _), do: {:ok, [mk("#=", [mk("^", [h(x), h(y)]), h(z)])]}
  defp attr_goal("psign", [x, y], _), do: {:ok, [mk("#=", [h(y), mk("sign", [h(x)])])]}
  defp attr_goal("pabs", [x, y], _), do: {:ok, [mk("#=", [h(y), mk("abs", [h(x)])])]}
  defp attr_goal("pmod", [x, m, k], _), do: {:ok, [mk("#=", [mk("mod", [h(x), h(m)]), h(k)])]}
  defp attr_goal("prem", [x, y, z], _), do: {:ok, [mk("#=", [mk("rem", [h(x), h(y)]), h(z)])]}
  defp attr_goal("pmax", [x, y, z], _), do: {:ok, [mk("#=", [h(z), mk("max", [h(x), h(y)])])]}
  defp attr_goal("pmin", [x, y, z], _), do: {:ok, [mk("#=", [h(z), mk("min", [h(x), h(y)])])]}
  defp attr_goal("pxor", [x, y, z], _), do: {:ok, [mk("#=", [h(z), mk("xor", [h(x), h(y)])])]}
  defp attr_goal("ppopcount", [x, y], _), do: {:ok, [mk("#=", [h(y), mk("popcount", [h(x)])])]}

  defp attr_goal("x_leq_y_plus_c", [x, y, c], compact) when is_integer(c),
    do: {:ok, [residual_leq(x, y, c, compact)]}

  defp attr_goal("reified_and", [x, _, y, _, b], _),
    do: {:ok, [mk("#<==>", [mk("#/\\", [h(x), h(y)]), h(b)])]}

  defp attr_goal("reified_or", [x, _, y, _, b], _),
    do: {:ok, [mk("#<==>", [mk("#\\/", [h(x), h(y)]), h(b)])]}

  defp attr_goal("reified_not", [x, y], _),
    do: {:ok, [mk("#<==>", [mk("#\\", [h(x)]), h(y)])]}

  defp attr_goal("pimpl", [x, y, _], _), do: {:ok, [mk("#==>", [h(x), h(y)])]}

  defp attr_goal("reified_fd", [v, b], _),
    do: {:ok, [mk("#<==>", [mk("finite_domain", [v]), h(b)])]}

  defp attr_goal(_, _, _), do: :no

  # residual_leq/4: X #=< Y + C lesbar (siehe clpz.pl)
  defp residual_leq(x, y, c, true) do
    c1 = c + 1

    if abs(c1) < abs(c),
      do: mk("#<", [h(x), plus_const(h(y), c1)]),
      else: mk("#=<", [h(x), plus_const(h(y), c)])
  end

  defp residual_leq(x, y, c, false), do: mk("#=<", [h(x), mk("+", [h(y), c])])

  defp plus_const(y, 0), do: y
  defp plus_const(y, c) when c < 0, do: mk("-", [y, -c])
  defp plus_const(y, c), do: mk("+", [y, c])

  # --- Labeling: select_var/4 -------------------------------------------------
  #
  # '$clpz_select_var'(Selection, Vars, Var, RVars) wie select_var/4 des
  # Originals (select_var_ref/4): leftmost, ff, ffc, min, max mit fd_size_/2,
  # ffc_lt/2, min_lt/2, max_gt/2 und delete_eq/3 – auch deren Eigenheiten
  # (eine Größe, die keine ganze Zahl ist, scheitert; delete_eq/3 lässt
  # gebundene Elemente nur vor dem Treffer weg). Anderes: das Original

  defbuiltin "$clpz_select_var", [sel, vars, var, rvars] do
    run("select_var", [sel, vars, var, rvars], subst(), fn ->
      s = subst_now()

      r =
        case cell(vars, s) do
          nil -> throw(:fallback)
          {v, tl} -> select_first(w(sel), v, tl, vars, s)
        end

      case r do
        {:ok, v, rest} -> {:unify, [{var, v}, {rvars, rest}]}
        :fail -> :fail
      end
    end)
  end

  # --- Labeling: ein Schritt von label/5 (step, upto_ground) ------------------
  #
  # '$clpz_label_step'(Vars, Selection, Order, Step) wie label_step_ref/4:
  # gebundene Variablen vorn überspringen, mit select_var/4 wählen (eine
  # gebundene: weiter mit RVars), dann fd_get/3 und order_dom_next/3 – Step
  # ist done (alles gebunden) oder step(Var, Next, RVars, Vars0); scheitert,
  # wo das Original scheitert (Schranke unendlich, eine Größe keine Zahl).
  # Anderes: das Original

  defbuiltin "$clpz_label_step", [vars, sel, order, step] do
    run("label_step", [vars, sel, order, step], subst(), fn ->
      s = subst_now()

      up =
        case w(order) do
          {:atom, "up"} -> true
          {:atom, "down"} -> false
          _ -> throw(:fallback)
        end

      case label_step(vars, w(sel), up, s) do
        :done -> {:unify, [{step, a("done")}]}
        :fail -> :fail
        {var, next, rvars, vars0} -> {:unify, [{step, mk("step", [var, next, rvars, vars0])}]}
      end
    end)
  end

  # '$clpz_conc_step'(Vars, Sel, Order, Vs, Step) für die Suchschleife von
  # clpz_concurrent (sstep/7): '$clpz_label_step'/4 und '$conc_node'/5 in
  # einem Aufruf – Step = done oder step(X, V, RVars, Vars0, I, T, Req),
  # I die Stelle von X in Vs, T und Req wie bei '$conc_node'/5. Anderes:
  # clpz_concurrent:conc_step_ref/5 (die beiden einzeln)
  defbuiltin "$clpz_conc_step", [vars, sel, order, vs, step] do
    s = subst()
    Process.put(:clpz_prims_subst, s)

    try do
      up =
        case w(order) do
          {:atom, "up"} -> true
          {:atom, "down"} -> false
          _ -> throw(:fallback)
        end

      case label_step(vars, w(sel), up, s) do
        :done ->
          {:unify, [{step, a("done")}]}

        :fail ->
          :fail

        {var, next, rvars, vars0} ->
          case PrologEx.Builtins.Concurrent.node_info(vs, var, s) do
            {:ok, i, t, req} ->
              {:unify, [{step, mk("step", [var, next, rvars, vars0, i, t, a(req)])}]}

            :error ->
              throw(:fallback)
          end
      end
    catch
      :fallback ->
        {:call,
         mk(":", [a("clpz_concurrent"), mk("conc_step_ref", [vars, sel, order, vs, step])])}
    end
  end

  defp label_step(vars, sel, up, s) do
    case cell(vars, s) do
      nil ->
        if ws(vars, s) == [], do: :done, else: throw(:fallback)

      {v, tl} ->
        if var?(PrologEx.Store.walk(v, s)) do
          case select_first(sel, v, tl, vars, s) do
            :fail ->
              :fail

            {:ok, x, rvars} ->
              case PrologEx.Store.walk(x, s) do
                {:var, _} = var ->
                  {d, _} = fdget_ro(var, s)
                  next = if up, do: inf_dec(d), else: sup_dec(d)
                  if is_integer(next), do: {var, next, rvars, vars}, else: :fail

                _ ->
                  label_step(rvars, sel, up, s)
              end
          end
        else
          label_step(tl, sel, up, s)
        end
    end
  end

  # select_var/4 für Vars = [v | tl]
  defp select_first({:atom, "leftmost"}, v, tl, _vars, _s), do: {:ok, v, tl}
  defp select_first({:atom, "ff"}, v, tl, vars, s), do: sel_ff(v, tl, vars, s)
  defp select_first({:atom, "ffc"}, v, tl, vars, s), do: sel_by(v, tl, vars, s, :ffc)
  defp select_first({:atom, "min"}, v, tl, vars, s), do: sel_by(v, tl, vars, s, :min)
  defp select_first({:atom, "max"}, v, tl, vars, s), do: sel_by(v, tl, vars, s, :max)
  defp select_first(_, _v, _tl, _vars, _s), do: throw(:fallback)

  # fd_size_/2: Anzahl der Elemente (:sup unendlich), 1 für eine Zahl
  defp fd_size(v, s) do
    case fd_get(v, s) do
      {d, _} -> ClpzDom.num_elements(dom(d))
      :default -> :sup
      :fail -> 1
    end
  end

  # Kleiner als 2 wird keine ungebundene Variable: eine Domäne aus einem
  # Wert bindet sie (put_terminating//3 reiht X = F als Ziel ein, das vor
  # jedem Propagator läuft), und gewählt wird erst nach dem Fixpunkt. Die
  # erste Variable mit 2 Werten ist also schon die, die das Original wählt
  # (die erste mit der kleinsten Größe) – der Rest der Liste bleibt
  # ungesehen
  defp sel_ff(v, tl, vars, s) do
    case fd_size(v, s) do
      n when is_integer(n) ->
        best = if n <= 2, do: v, else: find_ff(tl, v, n, s)
        {:ok, best, delete_eq(vars, best, s)}

      _ ->
        :fail
    end
  end

  defp find_ff(l, best, n0, s) do
    case cell(l, s) do
      nil ->
        if ws(l, s) == [], do: best, else: throw(:fallback)

      {v, vs} ->
        w = PrologEx.Store.walk(v, s)

        if match?({:var, _}, w) do
          case fd_size(w, s) do
            n when is_integer(n) and n < n0 ->
              if n <= 2, do: w, else: find_ff(vs, w, n, s)

            _ ->
              find_ff(vs, best, n0, s)
          end
        else
          find_ff(vs, best, n0, s)
        end
    end
  end

  # find_ffc/3, find_min/3, find_max/3: lt(V, Bisher) wählt V
  defp sel_by(v, tl, vars, s, kind) do
    best = best_by(ws(tl, s), v, kind, s)
    {:ok, best, delete_eq(vars, best, s)}
  end

  defp best_by([], b, _kind, _s), do: b
  defp best_by([x | l], b, kind, s), do: best_by(ws(l, s), better(kind, x, b, s), kind, s)
  defp best_by(_, _b, _kind, _s), do: throw(:fallback)

  defp better(:ffc, x, b, s), do: if(ffc_lt(x, b, s), do: x, else: b)
  defp better(:min, x, b, s), do: if(min_lt(x, b, s), do: x, else: b)
  defp better(:max, x, b, s), do: if(max_gt(x, b, s), do: x, else: b)

  # ffc_lt/2: weniger Elemente, bei Gleichstand mehr Propagatoren
  defp ffc_lt(x, y, s) do
    with {nx, px} when is_integer(nx) <- size_props(x, s),
         {ny, py} when is_integer(ny) <- size_props(y, s) do
      cond do
        nx < ny -> true
        nx == ny and px != nil and py != nil -> props_number(px, s) > props_number(py, s)
        true -> false
      end
    else
      _ -> false
    end
  end

  # {Anzahl, Propagatoren}; eine Zahl: {1, nil} (props_number/2 scheitert)
  defp size_props(x, s) do
    case fd_get(x, s) do
      {d, ps} -> {ClpzDom.num_elements(dom(d)), ps}
      :default -> {:sup, nil}
      :fail -> {1, nil}
    end
  end

  defp props_number(ps, s) do
    {gs, bs, os} = props(ps, s)
    pl_length(gs, s) + pl_length(bs, s) + pl_length(os, s)
  end

  defp min_lt(x, y, s) do
    with {lx, _} <- int_bounds(x, s), {ly, _} <- int_bounds(y, s), do: lx < ly, else: (_ -> false)
  end

  defp max_gt(x, y, s) do
    with {_, ux} <- int_bounds(x, s), {_, uy} <- int_bounds(y, s), do: ux > uy, else: (_ -> false)
  end

  # bounds/3 mit ganzzahligen Schranken; nil: scheitert. Eine gebundene
  # Nicht-Zahl (der Vergleich würfe): das Original
  defp int_bounds(x, s) do
    case fd_get(x, s) do
      {d, _} ->
        dd = dom(d)

        case {ClpzDom.infimum(dd), ClpzDom.supremum(dd)} do
          {l, u} when is_integer(l) and is_integer(u) -> {l, u}
          _ -> nil
        end

      :default ->
        nil

      :fail ->
        case PrologEx.Store.walk(x, s) do
          i when is_integer(i) -> {i, i}
          _ -> throw(:fallback)
        end
    end
  end

  # delete_eq/3: gebundene Elemente vor dem Treffer weg, den Treffer weg,
  # der Rest dahinter unverändert
  defp delete_eq(l, y, s) do
    yw = PrologEx.Store.walk(y, s)
    delete_eq_(l, yw, s, [])
  end

  defp delete_eq_(l, y, s, acc) do
    case cell(l, s) do
      nil ->
        if ws(l, s) == [], do: Enum.reverse(acc), else: throw(:fallback)

      {x, tl} ->
        xw = PrologEx.Store.walk(x, s)

        cond do
          not match?({:var, _}, xw) -> delete_eq_(tl, y, s, acc)
          # (der Rest kann eine gebundene Variable sein: :lists.reverse/2
          # nimmt jeden Term als Ende, Enum.reverse/2 nur Aufzählbares)
          xw == y -> :lists.reverse(acc, plain_tail(tl))
          true -> delete_eq_(tl, y, s, [x | acc])
        end
    end
  end

  defp plain_tail({:glist, l}), do: l
  defp plain_tail(t), do: t

  # --- Die Queue in Elixir ----------------------------------------------------
  #
  # Im Term ist jede der drei Listen (Ziele, schnelle, langsame
  # Propagatoren) eine Differenzliste im Attribut einer Variablen: jedes
  # Einreihen und Entnehmen schreibt in die Substitution. Solange die
  # Schleife in Elixir läuft (native/3), liegen die Listen stattdessen
  # unter @nq als :queue – Schlüssel ist die erste Variable des Terms nach
  # walk (Queues, die variables_same_queue/1 gleichgesetzt hat, teilen
  # sie). Vorher werden die Einträge aus dem Term geholt, am Rand zu Prolog
  # (ein Ziel, ein Propagator fürs Original, Wecken, abgeschaltete Queue)
  # wieder angehängt: Reihenfolge und Inhalt wie mit dem Term. Wo ein
  # Zustand verworfen wird (activate/4 fällt aufs Original zurück,
  # absorb_wake/3 gibt auf), wird auch @nq zurückgesetzt. Läuft geschachtelt
  # die Schleife einer anderen Queue (der neue Propagator einer Vereinfachung,
  # das Wecken über eine andere Queue), wird die äußere solange in ihren Term
  # geparkt.

  defp native(q, s, fun) do
    args =
      case ws(q, s) do
        {tag, "queue", [_, _, _, _] = args} when tag in [:struct, :gstruct] -> args
        _ -> throw(:fallback)
      end

    case Process.get(@nq) do
      nil ->
        own_queue(args, s, fun)

      {okey, _, _, _} = outer ->
        if PrologEx.Store.walk(hd(args), s) == okey do
          # (dieselbe Queue, geschachtelt: sie läuft schon in Elixir)
          fun.(s)
        else
          # eine andere: die äußere parken (zurück in ihren Term), die
          # innere in Elixir, danach die äußere wieder holen – wie der Weg
          # über Prolog
          oargs = Process.get(@nqa)
          s = flush(oargs, s)

          case own_queue(args, s, fun) do
            :fail ->
              Process.put(@nq, outer)
              :fail

            {:next, t, s} ->
              {g, s} = drain_list(oargs, 1, s, [])
              {f, s} = drain_list(oargs, 2, s, [])
              {sl, s} = drain_list(oargs, 3, s, [])
              # (der Schlüssel neu: das Parken gab der Variablen ein
              # Attribut, walk/2 liefert sie jetzt anders)
              key = PrologEx.Store.walk(hd(oargs), s)
              Process.put(@nq, {key, g, f, sl})

              Process.put(@nqa, oargs)
              {:next, t, s}
          end
        end
    end
  end

  # Hat variables_same_queue/1 die Queue umgebogen, die gerade in Elixir
  # läuft (ihr Schlüssel löst anders auf), gehörten ihre Einträge nicht mehr
  # dazu: dann das Original
  defp nq_intact(s) do
    case Process.get(@nq) do
      {key, _, _, _} ->
        if PrologEx.Store.walk(hd(Process.get(@nqa)), s) != key, do: throw(:fallback)
        s

      nil ->
        s
    end
  end

  defp own_queue(args, s, fun) do
    {g, s} = drain_list(args, 1, s, [])
    {f, s} = drain_list(args, 2, s, [])
    {sl, s} = drain_list(args, 3, s, [])
    key = PrologEx.Store.walk(hd(args), s)
    unless match?({:var, _}, key), do: throw(:fallback)
    prev = Process.get(@nqa)
    Process.put(@nq, {key, g, f, sl})
    Process.put(@nqa, args)

    try do
      case fun.(s) do
        :fail -> :fail
        {:next, t, s} -> {:next, t, flush(args, s)}
      end
    after
      Process.delete(@nq)
      if prev, do: Process.put(@nqa, prev), else: Process.delete(@nqa)
    end
  end

  # alle Einträge der Liste k aus dem Term holen: {:queue, s}
  defp drain_list(args, k, s, acc) do
    case pop(args, k, s) do
      {e, s} -> drain_list(args, k, s, [e | acc])
      nil -> {:queue.from_list(:lists.reverse(acc)), s}
    end
  end

  # die übrigen Einträge zurück in den Term
  defp flush(args, s) do
    {_, g, f, sl} = Process.delete(@nq)

    s
    |> insert_all(:queue.to_list(g), 1, args)
    |> insert_all(:queue.to_list(f), 2, args)
    |> insert_all(:queue.to_list(sl), 3, args)
    |> case do
      :fail -> throw(:fallback)
      s -> s
    end
  end

  defp insert_all(:fail, _es, _k, _args), do: :fail
  defp insert_all(s, [], _k, _args), do: s

  defp insert_all(s, [e | es], k, args),
    do: e |> insert_term(k, args, s) |> insert_all(es, k, args)

  defp nq_push({key, g, f, sl}, which, e, s) do
    Process.put(
      @nq,
      case which do
        1 -> {key, :queue.in(e, g), f, sl}
        2 -> {key, g, :queue.in(e, f), sl}
        3 -> {key, g, f, :queue.in(e, sl)}
      end
    )

    s
  end

  # vorne aus der Liste which: {Element, s} oder nil
  defp nq_pop(which) do
    {key, g, f, sl} = Process.get(@nq)
    qu = elem({g, f, sl}, which - 1)

    case :queue.out(qu) do
      {{:value, e}, rest} ->
        Process.put(@nq, put_elem({key, g, f, sl}, which, rest))
        e

      {:empty, _} ->
        nil
    end
  end

  # läuft für diese Queue (args) die Schleife in Elixir?
  defp native?(args, s) do
    case Process.get(@nq) do
      {key, _, _, _} -> PrologEx.Store.walk(hd(args), s) == key
      _ -> false
    end
  end

  defp queue_loop(q, args, s) do
    case next_entry(args, s) do
      {:prop, e, s} ->
        case activate(e, q, s) do
          :fail ->
            :fail

          :fallback ->
            {:next, mk("ref", [e]), s}

          {:ok, s} ->
            after_bind(q, args, s)
        end

      # ein Ziel X = N (put_terminating//3): selbst binden und weiter wie
      # nach einer Bindung im Propagator – so wie Prolog es mit call/1 und
      # dem Wecken täte; ein anderes Ziel: Prolog
      {:goal, e, s} ->
        case bind_goal(e, s) do
          {:ok, s} -> after_bind(q, args, s)
          :fail -> :fail
          _ -> {:next, mk("goal", [e]), s}
        end

      {:none, s} ->
        {:next, a("none"), s}
    end
  end

  # nach einem Schritt: wurde gebunden, das Wecken gleich hier (absorb_wake/3)
  # oder zurück nach Prolog (again: die Maschine weckt, dann weiter)
  defp after_bind(q, args, s) do
    case Store.take_wake(s) do
      {ws, s0} ->
        case absorb_wake(ws, q, s0) do
          {:ok, s} -> queue_loop(q, args, s)
          :fail -> :fail
          :no -> {:next, a("again"), s}
        end

      _ ->
        queue_loop(q, args, s)
    end
  end

  # X = N mit einer ganzen Zahl N: {:ok, s} (gebunden; geweckt wird
  # danach), :fail, oder :no (ein anderes Ziel)
  defp bind_goal(e, s) do
    with {tag, "=", [x, b]} when tag in [:struct, :gstruct] <- ws(e, s),
         n when is_integer(n) <- PrologEx.Store.walk(b, s) do
      case PrologEx.Store.walk(x, s) do
        ^n ->
          {:ok, s}

        {:var, _} = v ->
          case PrologEx.unify(v, n, s) do
            {:ok, s} -> {:ok, s}
            :error -> :fail
          end

        _ ->
          :fail
      end
    else
      _ -> :no
    end
  end

  # Das Wecken nach einer Bindung im Propagator gleich hier, wie es die
  # Maschine täte (für Variablen nur mit clpz-Attributen ruft sie nur den
  # Hook von clpz): die
  # Bindungen zurücknehmen, für jede Variable der Hook (eine Zahl in der
  # Domäne: alle ihre Propagatoren in ihre Queue, Gs = [phrase(do_queue,
  # [Q], _)]; ohne Domäne Gs = []), die Bindungen wiederherstellen. Sind
  # alle Q die laufende Queue, leert das geschachtelte do_queue//0 genau
  # diese Queue, und die äußere Schleife fände sie danach leer – dasselbe,
  # wie hier weiterzumachen. Teilen sie eine andere Queue, läuft deren
  # do_queue//0 hier geschachtelt (run_other/2). Sonst (verschiedene
  # Queues, andere Attribute als clpz, kein ganzzahliger Wert): :no,
  # zurück nach Prolog (again)
  defp absorb_wake(ws, q, s) do
    nq = Process.get(@nq)

    if absorbable?(ws, s) do
      # die Bindungen in der Reihenfolge des Weckens (ws ist umgekehrt)
      pairs = wake_bindings(ws, s, [])
      s0 = unbind_all(ws, s)
      Process.put(:clpz_prims_subst, s0)

      try do
        case absorb_all(pairs, s0, []) do
          :fail ->
            :fail

          {s1, qs} ->
            s2 = rebind_all(pairs, s1)

            cond do
              all_equal?(qs, q, s1) ->
                {:ok, s2}

              # alle in einer anderen Queue: deren do_queue//0 läuft
              # geschachtelt bis zum Fixpunkt, dann geht es hier weiter
              all_equal?(qs, hd(qs), s1) ->
                case run_other(hd(qs), s2) do
                  :no -> restore_nq(nq, :no)
                  r -> r
                end

              true ->
                restore_nq(nq, :no)
            end
        end
      catch
        :fallback -> restore_nq(nq, :no)
      after
        Process.put(:clpz_prims_subst, s)
      end
    else
      :no
    end
  end

  # do_queue//0 einer anderen Queue bis zum Fixpunkt: {:ok, s}, :fail oder
  # :no (sie braucht Prolog)
  defp run_other(qv, s) do
    qv = PrologEx.Store.walk(qv, s)

    qargs =
      case ws(qv, s) do
        {tag, "queue", [_, _, _, _] = args} when tag in [:struct, :gstruct] -> args
        _ -> throw(:fallback)
      end

    case native(qv, s, &queue_loop(qv, qargs, &1)) do
      :fail -> :fail
      {:next, {:atom, "none"}, s} -> {:ok, s}
      {:next, _, _} -> :no
    end
  end

  # alle geweckten Variablen gebunden, nur mit Attributen von clpz
  defp absorbable?([], _s), do: true

  defp absorbable?([{:var, {:attv, _}} = v | ws], s),
    do: only_clpz_attrs?(v, s) and absorbable?(ws, s)

  defp absorbable?(_, _s), do: false

  defp wake_bindings([], _s, acc), do: acc

  defp wake_bindings([v | ws], s, acc) do
    {:ok, val} = Store.binding(s, v)
    wake_bindings(ws, s, [{v, val} | acc])
  end

  defp unbind_all([], s), do: s
  defp unbind_all([v | ws], s), do: unbind_all(ws, Store.unbind(s, v))

  defp rebind_all([], s), do: s
  defp rebind_all([{v, val} | ps], s), do: rebind_all(ps, Store.put_binding(s, v, val))

  defp all_equal?([], _q, _s), do: true
  defp all_equal?([x | xs], q, s), do: PrologEx.Order.equal?(x, q, s) and all_equal?(xs, q, s)

  # absorb_hook/3 für jedes Paar: {s, Queues} oder :fail
  defp absorb_all([], s, qs), do: {s, qs}

  defp absorb_all([p | ps], s, qs) do
    case absorb_hook(p, s, qs) do
      {:cont, {s, qs}} -> absorb_all(ps, s, qs)
      {:halt, :fail} -> :fail
    end
  end

  # verify_attributes/3 von clpz für V = Val (Val eine Zahl)
  defp absorb_hook({v, val}, s, qs) do
    case att(v, s, "clpz", 1) do
      nil ->
        {:cont, {s, qs}}

      [attr] ->
        {dom, ps, qv} =
          case ws(attr, s) do
            {tag, "clpz_attr", [_, _, _, dom, ps, qv]} when tag in [:struct, :gstruct] ->
              {dom, ps, qv}

            _ ->
              throw(:fallback)
          end

        i =
          case PrologEx.Store.walk(val, s) do
            i when is_integer(i) -> i
            _ -> throw(:fallback)
          end

        if contains_t(dom, i) do
          {pgs, bs, os} = props(ps, s)

          case s |> then_all(pgs, qv) |> then_all(bs, qv) |> then_all(os, qv) do
            :fail -> {:halt, :fail}
            s -> {:cont, {s, [qv | qs]}}
          end
        else
          {:halt, :fail}
        end
    end
  end

  # nur Attribute im Modul clpz (oder keine)
  defp only_clpz_attrs?({:var, {:attv, id}}, s) do
    case Store.attrs(s, id) do
      m when map_size(m) == 0 -> true
      %{"clpz" => _} = m when map_size(m) == 1 -> true
      _ -> false
    end
  end

  defp only_clpz_attrs?(_, _s), do: true

  defp out_next(next, t, s) do
    case PrologEx.unify(next, t, s) do
      {:ok, s} -> {:subst, s}
      :error -> :fail
    end
  end

  # nächster Eintrag wie queue_enabled//0, queue_get_goal//1,
  # queue_get_fast//1, queue_get_slow//1
  defp next_entry(args, s) do
    aux = PrologEx.Store.walk(qarg(args, 4), s)

    cond do
      match?({:var, _}, aux) and att(aux, s, "disabled", 0) != nil ->
        {:none, s}

      native?(args, s) ->
        cond do
          e = nq_pop(1) -> {:goal, e, s}
          e = nq_pop(2) -> {:prop, e, s}
          e = nq_pop(3) -> {:prop, e, s}
          true -> {:none, s}
        end

      r = pop(args, 1, s) ->
        {e, s} = r
        {:goal, e, s}

      r = pop(args, 2, s) ->
        {e, s} = r
        {:prop, e, s}

      r = pop(args, 3, s) ->
        {e, s} = r
        {:prop, e, s}

      true ->
        {:none, s}
    end
  end

  # Werte: ganze Zahl, Variable oder (sonst) das Original
  defp val(t, s) do
    case PrologEx.Store.walk(t, s) do
      i when is_integer(i) -> i
      {:var, _} = v -> v
      _ -> throw(:fallback)
    end
  end

  defp var?({:var, _}), do: true
  defp var?(_), do: false

  # kill/1: del_attr(State, clpz_aux), State = dead
  # Vereinfachung von scalar_product_eq wie im Original: kill(MState), dann
  # { L #= R } – der Matcher macht daraus pplus(X, Y, Z, _) (var/1 passt dort
  # auch auf Zahlen), aufgestellt mit pit/4 (eigene, frische Queue) und
  # trigger_once_/2 (die läuft gleich bis zum Fixpunkt), danach
  # reinforce(L) mit den Variablen von L. Braucht die Schleife Prolog (ein
  # Ziel, Wecken über eine andere Queue): das Original
  defp sp_simplify(st, pargs, left, s) do
    if Process.get(:clpz_no_fast), do: throw(:fallback)

    case kill(st, s) do
      :fail ->
        :fail

      s ->
        p = mk("propagator", [mk("pplus", pargs ++ [fresh_var()]), fresh_var()])
        vs = PrologEx.Builtins.Order.variables(pargs, s)
        q = new_queue()
        {_, _, qargs} = q

        vs
        |> init_all(p, q, s)
        |> seq(&same_queue(vs, &1))
        |> seq(&nq_intact/1)
        |> seq(&drop_inert_wake/1)
        |> seq(fn s ->
          native(q, s, fn s ->
            case trigger(p, q, s) do
              :fail -> :fail
              s -> queue_loop(q, qargs, s)
            end
          end)
          |> case do
            :fail ->
              :fail

            {:next, {:atom, "none"}, s} ->
              reinforce_all(left, s)

            {:next, _, _} ->
              throw(:fallback)
          end
        end)
    end
  end

  defp kill(st, s) do
    st = PrologEx.Store.walk(st, s)
    s = if var?(st), do: del_att(s, st, "clpz_aux", 1), else: s

    case PrologEx.unify(st, a("dead"), s) do
      {:ok, s} -> s
      :error -> :fail
    end
  end

  # fd_get/3 einer Variablen: {Domäne (dekodiert), Ps}
  # (trägt die Dekodierung in den Merkzettel ein: ein fdput/5 derselben
  # Variablen erkennt die Domäne dann wieder)
  defp fdget(v, s) do
    case fd_get(v, s) do
      {d, ps} ->
        dd = vdom(v, d, s)
        dec_put(w(d), dd)
        {dd, ps}

      :default ->
        {ClpzDom.all(), no_props()}

      :fail ->
        throw(:fallback)
    end
  end

  # nur lesen (Ps verworfen, kein fdput folgt): nicht in den Ring, das
  # verdrängte nur Einträge, die gebraucht werden
  defp fdget_ro(v, s) do
    case fd_get(v, s) do
      {d, ps} -> {vdom(v, d, s), ps}
      :default -> {ClpzDom.all(), no_props()}
      :fail -> throw(:fallback)
    end
  end

  # Zweiter Merkzettel, je Variable: %{Variable => {Domänen-Term, Domäne}}.
  # Hat sich die Domäne einer Variablen seit dem letzten Lesen nicht
  # geändert, liegt dort physisch derselbe Term (Share.same?/2) – auch nach
  # Backtracking ist ein Treffer also die Domäne genau dieses Terms. Der
  # Ring oben kennt nur die letzten Kodierungen; Propagatoren über viele
  # Variablen (Summen) lesen meist unveränderte Domänen anderer Variablen.
  @vdom_key :clpz_vdom
  @vdom_max 100_000

  defp vdom(v, d, s) do
    v = PrologEx.Store.walk(v, s)
    wt = w(d)
    m = Process.get(@vdom_key, %{})

    case m do
      %{^v => {t0, dd}} ->
        if PrologEx.Share.same?(t0, wt), do: dd, else: vdom_miss(m, v, wt, d)

      _ ->
        vdom_miss(m, v, wt, d)
    end
  end

  defp vdom_miss(m, v, wt, d) do
    case dom_pairs_c(wt, [], nil, true) do
      {:ok, dd, canonical} ->
        if canonical do
          m = if map_size(m) >= @vdom_max, do: %{}, else: m
          Process.put(@vdom_key, Map.put(m, v, {wt, dd}))
        end

        dd

      :error ->
        no_domain(d)
    end
  end

  # die Domäne, wenn der Term die zuletzt gelesene/geschriebene von v ist
  defp vdom_peek(v, wt) do
    case Process.get(@vdom_key, %{}) do
      %{^v => {t0, dd}} -> if PrologEx.Share.same?(t0, wt), do: dd
      _ -> nil
    end
  end

  defp vdom_put(v, wt, dd) do
    m = Process.get(@vdom_key, %{})
    m = if map_size(m) >= @vdom_max, do: %{}, else: m
    Process.put(@vdom_key, Map.put(m, v, {wt, dd}))
  end

  @doc """
  Die Merkzettel (Domänen, fd_get) vergessen – zu Beginn jeder Anfrage:
  Treffer prüfen die physische Identität, falsch werden sie nie; aber
  übrig gebliebene Einträge hielten die Terme der vorigen Anfrage am
  Leben.
  """
  def forget do
    Process.delete(@dec_key)
    Process.delete(@vdom_key)
    Process.delete(@fdg_key)
    :ok
  end

  # fd_put//3 mit einer dekodierten Domäne
  defp fdput(_v, _d, _ps, _q, :fail), do: :fail

  defp fdput(v, d, ps, q, s) do
    case fdput_known(v, d, ps, q, s) do
      :unknown -> put_terminating(v, ed(d), ps, q, s)
      r -> r
    end
  end

  # Ist die gespeicherte Domäne (physisch) eine, die fdget dekodiert hat, so
  # entscheidet d === d0 exakt (beide kanonisch), ob sich etwas geändert hat
  # – put_dom/6 ohne die neue Domäne zu kodieren und mit == zu vergleichen.
  # Gleich: das Attribut wie im Original neu (Ps vom Aufrufer), mit dem
  # alten Term. Leer, Einzelwert, ohne Attribut, unbekannt: put_terminating.
  defp fdput_known(_v, [], _ps, _q, _s), do: :unknown
  defp fdput_known(_v, [{x, x}], _ps, _q, _s) when is_integer(x), do: :unknown

  defp fdput_known(v, d, ps, q, s) do
    with {:var, _} = vv <- PrologEx.Store.walk(v, s),
         [attr] <- att(vv, s, "clpz", 1),
         {tag, "clpz_attr", [left, right, spread, old_dom, old_ps, qx]}
         when tag in [:struct, :gstruct] <- ws(attr, s),
         wold = ws(old_dom, s),
         d0 when d0 != nil <- vdom_peek(vv, wold) || dec_find(dec_cache(), wold) do
      cond do
        # dieselbe Domäne, physisch dieselben Propagatoren: das neue
        # Attribut wäre gleich dem alten – es bleibt (und mit ihm die
        # Merkzettel dieser Variablen)
        d === d0 and PrologEx.Share.same?(old_ps, ps) ->
          s

        d === d0 ->
          put_clpz(s, vv, [left, right, spread, old_dom, ps, qx])

        true ->
          dom = ed(d)
          vdom_put(vv, dom, d)
          s = put_clpz(s, vv, [left, right, spread, dom, ps, qx])
          changed(vv, left, right, spread, old_dom, dom, ps, qx, q, s)
      end
    else
      _ -> :unknown
    end
  end

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
  # Schnitt, nil wenn leer (Fehlschlag)
  defp isect(d1, d2) do
    case ClpzDom.intersection(d1, d2) do
      [] -> nil
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
        case PrologEx.Store.walk(aux, s) do
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
          {ad, _} = fdget_ro(a, s)
          {bd, _} = fdget_ro(b, s)

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

      s = s |> neq_list(l, x, q) |> neq_list(r, x, q)
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

    {cvs, i} = coeffs_vars(cs0, vs0, s)
    p = p0 - i

    case cvs do
      [] ->
        s = kill(st, s)
        if s != :fail and p == 0, do: s, else: :fail

      # V = [V], Cs = [C]: kill, P mod C =:= 0, V is P // C
      [{c, v}] ->
        if c == 0, do: throw(:fallback)

        case kill(st, s) do
          :fail -> :fail
          s -> if rem(p, c) == 0, do: bind(s, v, div(p, c)), else: :fail
        end

      # zwei oder (P = 0) drei Variablen: das Original tötet sich und stellt
      # { L #= R } auf – pplus/4 über pit/4 und trigger_once_/2, danach
      # reinforce(L); siehe sp_simplify/5
      [{1, a}, {1, b}] ->
        sp_simplify(st, [a, b, p], [a, b], s)

      [{1, a}, {-1, b}] ->
        sp_simplify(st, [p, b, a], [a], s)

      [{-1, a}, {1, b}] ->
        sp_simplify(st, [p, a, b], [b], s)

      [{-1, a}, {-1, b}] ->
        sp_simplify(st, [a, b, -p], [a, b], s)

      [{1, a}, {1, b}, {-1, c}] when p == 0 ->
        sp_simplify(st, [a, b, c], [a, b], s)

      [{1, a}, {-1, b}, {1, c}] when p == 0 ->
        sp_simplify(st, [a, c, b], [a, c], s)

      [{-1, a}, {1, b}, {1, c}] when p == 0 ->
        sp_simplify(st, [b, c, a], [b, c], s)

      _ ->
        if zero_coeff?(cvs), do: throw(:fallback)
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
    dx = PrologEx.Store.walk(dx0, s)
    dy = PrologEx.Store.walk(dy0, s)
    b = PrologEx.Store.walk(b0, s)

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

  # --- reified_eq/reified_neq(DX, X, DY, Y, Ps, B): B ⇔ X = Y bzw. X ≠ Y ---
  #
  # B = 1 (eq: zwei Bindungen; neq: X #\= Y aufstellen) und B = 0 bei eq
  # (X #\= Y aufstellen): das Original; B = 0 bei neq: X = Y als letzte
  # Aktion

  defp propagate(name, [dx0, x0, dy0, y0, ps, b0], st, _q, s)
       when name in ["reified_eq", "reified_neq"] do
    dx = PrologEx.Store.walk(dx0, s)
    dy = PrologEx.Store.walk(dy0, s)
    b = PrologEx.Store.walk(b0, s)
    eq = name == "reified_eq"

    cond do
      dx == 0 or dy == 0 ->
        s |> kill2(st, ps) |> bind(b0, 0)

      b == 1 ->
        throw(:fallback)

      dx == 1 and dy == 1 ->
        cond do
          var?(b) -> eq_open(eq, val(x0, s), val(y0, s), st, ps, b0, s)
          b == 0 and eq -> throw(:fallback)
          b == 0 -> s |> kill_then(st) |> bind(x0, y0)
          is_integer(b) -> s
          true -> throw(:fallback)
        end

      true ->
        s
    end
  end

  # --- ptzdiv(X, Y, Z, Morph): X // Y = Z (zur Null gerundet) ---
  #
  # Y = -1 (morph_into_propagator//4): das Original

  defp propagate("ptzdiv", [x0, y0, z0, _m], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      is_integer(x) and is_integer(y) ->
        if y == 0, do: :fail, else: s |> kill_then(st) |> bind(z0, div(x, y))

      is_integer(x) ->
        {yd, yps} = fdget(y, s)
        {yl, yu} = {inf_dec(yd), sup_dec(yd)}

        cond do
          z == 0 ->
            # (wie das Prolog: interval/3 und domains_union/3 statt eines
            # festen split(0, …) – derselbe Term, nicht nur dieselbe Menge)
            put_isect(
              y,
              yd,
              union!(iv(:inf, -abs(x) - 1), iv(abs(x) + 1, :sup)),
              yps,
              q,
              s
            )

          is_integer(z) ->
            {nyl, nyu} =
              if sign(x) == sign(z),
                do: {bmax(div(x, z + sign(z)) + 1, yl), bmin(div(x, z), yu)},
                else: {bmax(div(x, z), yl), bmin(div(x, z + sign(z)) - 1, yu)}

            update_bounds(y, yd, yps, yl, yu, nyl, nyu, q, s)

          true ->
            {zd, zps} = fdget(z, s)
            {zl, zu} = {inf_dec(zd), sup_dec(zd)}
            away = gt(yl, 0) or lt(yu, 0)

            {nzl, nzu} =
              cond do
                x >= 0 and away -> {bmax(slash(x, yu), zl), bmin(slash(x, yl), zu)}
                x < 0 and away -> {bmax(slash(x, yl), zl), bmin(slash(x, yu), zu)}
                true -> {bmax(-abs(x), zl), bmin(abs(x), zu)}
              end

            s
            |> seq(&update_bounds(z, zd, zps, zl, zu, nzl, nzu, q, &1))
            |> seq(fn s ->
              if x >= 0 and gt(nzl, 0) do
                {yd1, yps1} = fdget(y, s)
                nyl = plus(slash(x, plus(nzu, 1)), 1)
                put_isect(y, yd1, iv(nyl, slash(x, nzl)), yps1, q, s)
              else
                s
              end
            end)
        end

      is_integer(y) ->
        cond do
          y == 0 ->
            :fail

          y == 1 ->
            s |> kill_then(st) |> bind(x0, z0)

          y == -1 ->
            throw(:fallback)

          true ->
            {xd, xps} = fdget(x, s)
            {xl, xu} = {inf_dec(xd), sup_dec(xd)}

            if is_integer(z) do
              {nxl, nxu} =
                cond do
                  sign(z) == sign(y) ->
                    {bmax(z * y, xl), bmin((abs(z) + 1) * abs(y) - 1, xu)}

                  z == 0 ->
                    {bmax(-abs(y) + 1, xl), bmin(abs(y) - 1, xu)}

                  true ->
                    {bmax((z + sign(z)) * y + 1, xl), bmin(z * y, xu)}
                end

              s |> kill_then(st) |> seq(&update_bounds(x, xd, xps, xl, xu, nxl, nxu, q, &1))
            else
              {zd, zps} = fdget(z, s)
              {dd, mm} = neg_abs(xd, y)

              contracted = ClpzDom.contract_less(dd, mm)

              case isect_e(zd, contracted) do
                nil ->
                  :fail

                nzd ->
                  s
                  |> seq(&fdput(z, nzd, zps, q, &1))
                  |> seq(fn s ->
                    {xd2, xps2} = fdget(x, s)
                    {ed, em} = neg_abs(nzd, y)
                    put_isect(x, xd2, ClpzDom.expand_more(ed, em), xps2, q, s)
                  end)
              end
            end
        end

      is_integer(z) ->
        {xd, xps} = fdget(x, s)
        {xl, xu} = {inf_dec(xd), sup_dec(xd)}
        {yd, _} = fdget_ro(y, s)
        {yl, yu} = {inf_dec(yd), sup_dec(yd)}

        {nxl, nxu} =
          if geq(yl, 0) and geq(xl, 0),
            do: {bmax(times(yl, z), xl), bmin(minus(times(yu, z + 1), 1), xu)},
            else: {xl, xu}

        update_bounds(x, xd, xps, xl, xu, nxl, nxu, q, s)

      x == y ->
        s |> kill_then(st) |> bind(z0, 1)

      true ->
        {xd, _} = fdget_ro(x, s)
        {xl, xu} = {inf_dec(xd), sup_dec(xd)}
        {yd, _} = fdget_ro(y, s)
        {zd, zps} = fdget(z, s)
        nzu = bmax(babs(xl), xu)

        case isect(zd, iv(uminus(nzu), nzu)) do
          nil ->
            :fail

          nzd0 ->
            nzd1 = if geq(xl, 0) and geq(inf_dec(yd), 0), do: remove_lt(nzd0, 0), else: nzd0
            fdput(z, nzd1, zps, q, s)
        end
    end
  end

  # --- prem(X, Y, Z): X rem Y = Z ---
  #
  # Das Original: X bekannt, Y offen (Z in L..U aufstellen) und der Zweig,
  # der Z = X mitten im Propagator bindet

  defp propagate("prem", [x0, y0, z0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      is_integer(x) and is_integer(y) ->
        if y == 0, do: :fail, else: s |> kill_then(st) |> bind(z0, rem(x, y))

      is_integer(x) ->
        throw(:fallback)

      is_integer(y) and y == 0 ->
        :fail

      is_integer(y) and abs(y) == 1 ->
        s |> kill_then(st) |> bind(z0, 0)

      is_integer(y) and not is_integer(z) ->
        rem_y(x, y, z, q, s)

      is_integer(y) ->
        rem_yz(x, y, z, q, s)

      x == y ->
        s |> kill_then(st) |> bind(z0, 0)

      is_integer(z) ->
        s

      true ->
        {zd, zps} = fdget(z, s)
        {yd, _} = fdget_ro(y, s)
        {xd, _} = fdget_ro(x, s)
        {yinf, ysup} = {inf_dec(yd), sup_dec(yd)}
        {xinf, xsup} = {inf_dec(xd), sup_dec(xd)}
        m = bmax(babs(yinf), ysup)
        inf0 = if geq(xinf, 0), do: 0, else: xinf
        sup0 = if leq(xsup, 0), do: 0, else: xsup
        ninf = bmax(bmax(inf0, plus(uminus(m), 1)), bmin(xinf, uminus(xsup)))
        nsup = bmin(bmin(sup0, minus(m, 1)), bmax(babs(xinf), xsup))
        put_isect(z, zd, iv(ninf, nsup), zps, q, s)
    end
  end

  # --- pmod(X, Y, Z): X mod Y = Z (mit pmodz und pmody) ---

  defp propagate("pmod", [x0, y0, z0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    s =
      cond do
        y == 0 -> :fail
        y == z -> :fail
        x == y -> s |> kill_then(st) |> goal(mk("=", [z0, 0]), q)
        true -> s
      end

    seq(s, fn s ->
      cond do
        is_integer(x) and is_integer(y) ->
          s |> kill_then(st) |> bind(z0, Integer.mod(x, y))

        is_integer(y) and is_integer(z) ->
          mod_yz(x, y, z, q, s)

        is_integer(z) and is_integer(x) ->
          mod_zx(x, y, z, st, q, s)

        true ->
          s
          |> seq(&pmodz(x, y, z, x0, z0, st, q, &1))
          |> seq(&pmody(y, z, q, &1))
      end
    end)
  end

  # --- pexp(X, Y, Z, Morph): X^Y = Z ---
  #
  # Das Original: X = 0 (Ziel und morph_into_propagator//4), Y == Z (zwei
  # Schritte: Bindung, dann Ziel) und X^Y = Z mit geradem Y (X in -R \/ R
  # aufstellen)

  defp propagate("pexp", [x0, y0, z0, _m], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      x == 1 -> s |> kill_then(st) |> bind(z0, 1)
      x == 0 -> throw(:fallback)
      y == 0 -> s |> kill_then(st) |> bind(z0, 1)
      y == 1 -> s |> kill_then(st) |> bind(z0, x0)
      y == z -> throw(:fallback)
      is_integer(x) -> exp_x(x, y, z, y0, z0, st, q, s)
      is_integer(z) -> exp_z(x, y, z, x0, st, q, s)
      is_integer(y) and y > 0 -> exp_y(x, y, z, q, s)
      true -> exp_rest(x, y, z, q, s)
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
      PrologEx.Store.walk(b0, s) == 1 ->
        throw(:fallback)

      true ->
        s
    end
  end

  # --- pgcc_check(Pairs), pgcc_check_single(Pairs): gcc_check//1 ---
  #
  # Bei abgeschalteter Queue für jedes Paar Key-Num0 (Num0 mit den
  # Attributen clpz_gcc_vs, clpz_gcc_num, clpz_gcc_occurred). Das Original
  # bindet Num oder die übrigen Variablen mitten in der Schleife (der Hook
  # reiht nur ein, die Queue ist ja abgeschaltet); hier nur eine einzige
  # Bindung im letzten Paar, und nur, wenn die Variable keine oder die
  # laufende Queue hat: dann nach enable_queue als letzte Aktion (die
  # Maschine weckt danach, do_queue rechnet die Queue wie die äußere
  # Schleife). Sonst das Original.

  defp propagate(name, [pairs0], _st, q, s) when name in ["pgcc_check", "pgcc_check_single"] do
    # disable_queue//0 entfällt: hier liest nichts den Schalter (fd_put//3
    # reiht nur ein), enable_queue//0 am Ende wie im Original
    {s, pending} = gcc_pairs(ws(pairs0, s), q, s)
    s = enable_queue(q, s)

    case pending do
      nil ->
        s

      {v, t} ->
        same_queue_or_none?(v, q, s) || throw(:fallback)
        bind(s, v, t)
    end
  end

  # --- pelement(N, Is, V): das N-te Element von Is ist V ---

  defp propagate("pelement", [n0, is0, v0], st, q, s) do
    case val(n0, s) do
      {:var, _} = n ->
        case val(v0, s) do
          {:var, _} = v ->
            {nd, _} = fdget_ro(n, s)
            {vd, vps} = fdget(v, s)

            # integers_remaining/5: Vereinigung der Domänen der möglichen
            # Elemente (in einem Schritt zusammengefügt)
            vd1 = ClpzDom.from_intervals(element_doms(ws(is0, s), 1, nd, s))

            put_isect(v, vd, vd1, vps, q, s)

          _ ->
            s
        end

      n when is_integer(n) ->
        case nth_item(ws(is0, s), n, s) do
          nil -> s |> kill_then(st) |> then_fail()
          e -> s |> kill_then(st) |> bind(e, v0)
        end

      _ ->
        throw(:fallback)
    end
  end

  # --- reified_or(X, Ps1, Y, Ps2, B): B ⇔ X ∨ Y ---

  defp propagate("reified_or", [x0, ps1, y0, ps2, b0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)

    cond do
      is_integer(x) ->
        s = kill(st, s)

        if x == 1,
          do: s |> kill_entailed_all(ps2) |> bind(b0, 1),
          else: bind(s, b0, y0)

      is_integer(y) ->
        propagate("reified_or", [y0, ps2, x0, ps1, b0], st, q, s)

      # X = 0, Y = 0: zwei Bindungen (das Original)
      PrologEx.Store.walk(b0, s) == 0 ->
        throw(:fallback)

      true ->
        s
    end
  end

  # --- reified_not(X, Y): Y ⇔ ¬X ---

  defp propagate("reified_not", [x0, y0], st, _q, s) do
    case {val(x0, s), val(y0, s)} do
      {0, _} -> s |> kill_then(st) |> bind(y0, 1)
      {1, _} -> s |> kill_then(st) |> bind(y0, 0)
      {_, 0} -> s |> kill_then(st) |> bind(x0, 1)
      {_, 1} -> s |> kill_then(st) |> bind(x0, 0)
      _ -> s
    end
  end

  # --- pimpl(X, Y, Ps): X ⇒ Y ---

  defp propagate("pimpl", [x0, y0, ps], st, _q, s) do
    x = val(x0, s)
    y = val(y0, s)

    cond do
      is_integer(x) ->
        s = kill(st, s)
        if x == 1, do: bind(s, y0, 1), else: kill_entailed_all(s, ps)

      is_integer(y) ->
        s = kill(st, s)
        if y == 0, do: bind(s, x0, 0), else: kill_entailed_all(s, ps)

      true ->
        s
    end
  end

  # --- x_leq_y_plus_c(X, Y, C): X ≤ Y + C ---

  defp propagate("x_leq_y_plus_c", [x0, y0, c0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)

    c =
      case val(c0, s) do
        i when is_integer(i) -> i
        _ -> throw(:fallback)
      end

    cond do
      is_integer(x) and is_integer(y) ->
        s = kill(st, s)
        if s != :fail and x <= y + c, do: s, else: :fail

      is_integer(x) ->
        s |> kill_then(st) |> seq(&put_with(y, fn d -> remove_lt(d, x - c) end, q, &1))

      is_integer(y) ->
        s |> kill_then(st) |> seq(&put_with(x, fn d -> remove_gt(d, y + c) end, q, &1))

      x == y ->
        if c >= 0, do: kill(st, s), else: :fail

      true ->
        s
        |> then(fn s ->
          case ibounds(y, s) do
            {_, ysup} when is_integer(ysup) -> put_with(x, &remove_gt(&1, ysup + c), q, s)
            _ -> s
          end
        end)
        |> seq(fn s ->
          # die Domäne von X nach fd_put (ein einzelner Wert wird nicht
          # abgelegt, wie im Original)
          {xd2, _} = fdget_ro(x, s)
          xinf = inf_dec(xd2)

          if is_integer(xinf) do
            {yd1, yps1} = fdget(y, s)
            yd2 = remove_lt(yd1, xinf - c)
            xsup = sup_dec(xd2)

            s =
              with true <- yd2 != [],
                   yinf when is_integer(yinf) <- inf_dec(yd2),
                   true <- is_integer(xsup) and xsup <= yinf + c do
                kill(st, s)
              else
                _ -> s
              end

            seq(s, &fdput(y, yd2, yps1, q, &1))
          else
            s
          end
        end)
    end
  end

  # --- x_neq_y_plus_z(X, Y, Z): X ≠ Y + Z ---
  #
  # neq(X, Z) bzw. neq(X, Y) (neue Bedingung): das Original

  defp propagate("x_neq_y_plus_z", [x0, y0, z0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      is_integer(x) and is_integer(y) and is_integer(z) ->
        s = kill(st, s)
        if s != :fail and x != y + z, do: s, else: :fail

      is_integer(x) and is_integer(y) ->
        s |> kill_then(st) |> seq(&neq_num(z0, x - y, q, &1))

      is_integer(x) and is_integer(z) ->
        s |> kill_then(st) |> seq(&neq_num(y0, x - z, q, &1))

      is_integer(x) ->
        s

      is_integer(y) and is_integer(z) ->
        s |> kill_then(st) |> seq(&neq_num(x0, y + z, q, &1))

      y == 0 or z == 0 ->
        throw(:fallback)

      true ->
        s
    end
  end

  # --- scalar_product_neq(Cs, Vs, P): Σ C·V ≠ P ---
  #
  # Die Zweige, die neue Bedingungen aufstellen (eine Variable, zwei oder
  # drei mit Koeffizienten ±1): das Original

  defp propagate("scalar_product_neq", [cs0, vs0, p0], st, _q, s) do
    p0 =
      case val(p0, s) do
        i when is_integer(i) -> i
        _ -> throw(:fallback)
      end

    {cvs, i} = coeffs_vars(cs0, vs0, s)
    p = p0 - i

    case cvs do
      [] ->
        s = kill(st, s)
        if s != :fail and p != 0, do: s, else: :fail

      [_] ->
        throw(:fallback)

      [{c1, _}, {c2, _}] when (c1 == 1 and c2 == -1) or (c1 == -1 and c2 == 1) ->
        throw(:fallback)

      [{c1, _}, {c2, _}, {c3, _}]
      when p == 0 and c1 in [1, -1] and c2 in [1, -1] and c3 in [1, -1] and c1 + c2 + c3 == 1 ->
        throw(:fallback)

      _ ->
        s
    end
  end

  # --- reified_in(V, Dom, B): B ⇔ V in Dom ---
  #
  # B schon 0 oder 1 bei offenem V (domain/2, eine neue Ablage mit eigener
  # Queue): das Original

  defp propagate("reified_in", [v0, dom0, b0], st, _q, s) do
    dom = dom(dom0)

    case val(v0, s) do
      v when is_integer(v) ->
        s |> kill_then(st) |> bind(b0, if(dcontains?(dom, v), do: 1, else: 0))

      v ->
        b = val(b0, s)
        if b == 0 or b == 1, do: throw(:fallback)
        {vd, _} = fdget_ro(v, s)

        case isect(vd, dom) do
          nil -> s |> kill_then(st) |> bind(b0, 0)
          ^vd -> s |> kill_then(st) |> bind(b0, 1)
          _ -> s
        end
    end
  end

  # --- reified_fd(V, B): B = 1, sobald V endlich ist ---

  defp propagate("reified_fd", [v0, b0], st, _q, s) do
    case val(v0, s) do
      v when is_integer(v) ->
        s |> kill_then(st) |> bind(b0, 1)

      v ->
        case ibounds(v, s) do
          {inf, sup} when is_integer(inf) and is_integer(sup) ->
            s |> kill_then(st) |> bind(b0, 1)

          _ ->
            s
        end
    end
  end

  # --- pxor(X, Y, Z): Z = X xor Y ---

  defp propagate("pxor", [x0, y0, z0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)
    z = val(z0, s)

    cond do
      is_integer(x) and is_integer(y) -> s |> kill_then(st) |> bind(z0, Bitwise.bxor(x, y))
      is_integer(y) and is_integer(z) -> s |> kill_then(st) |> bind(x0, Bitwise.bxor(y, z))
      is_integer(z) and is_integer(x) -> s |> kill_then(st) |> bind(y0, Bitwise.bxor(z, x))
      x == y -> s |> kill_then(st) |> goal(mk("=", [z0, 0]), q)
      y == z -> s |> kill_then(st) |> goal(mk("=", [x0, 0]), q)
      z == x -> s |> kill_then(st) |> goal(mk("=", [y0, 0]), q)
      x == 0 -> s |> kill_then(st) |> goal(mk("=", [y0, z0]), q)
      y == 0 -> s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)
      z == 0 -> s |> kill_then(st) |> goal(mk("=", [x0, y0]), q)
      true -> s
    end
  end

  # --- psign(X, Y): Y = sign(X) ---

  defp propagate("psign", [x0, y0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)

    cond do
      is_integer(x) ->
        s |> kill_then(st) |> goal(mk("is", [y0, mk("sign", [x0])]), q)

      y == -1 ->
        s |> kill_then(st) |> goal(mk("#<", [x0, 0]), q)

      y == 0 ->
        s |> kill_then(st) |> goal(mk("=", [x0, 0]), q)

      y == 1 ->
        s |> kill_then(st) |> goal(mk("#>", [x0, 0]), q)

      true ->
        case ibounds(x, s) do
          {l, _} when is_integer(l) and l > 0 -> s |> kill_then(st) |> goal(mk("=", [y0, 1]), q)
          {_, u} when is_integer(u) and u < 0 -> s |> kill_then(st) |> goal(mk("=", [y0, -1]), q)
          _ -> s
        end
    end
  end

  # --- scalar_product_leq(Cs, Vs, P): Σ C·V ≤ P ---

  defp propagate("scalar_product_leq", [cs0, vs0, p0], st, q, s) do
    p0 =
      case val(p0, s) do
        i when is_integer(i) -> i
        _ -> throw(:fallback)
      end

    {cvs, i} = coeffs_vars(cs0, vs0, s)
    p = p0 - i

    if cvs == [] do
      s = kill(st, s)
      if s != :fail and p >= 0, do: s, else: :fail
    else
      if zero_coeff?(cvs), do: throw(:fallback)
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
        {bd, _} = fdget_ro(b, s)
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
            case isect(ad, iv(bmax(al, bl), au)) do
              nil ->
                :fail

              nad ->
                s
                |> seq(&fdput(a, nad, aps, q, &1))
                |> seq(fn s ->
                  case val(b, s) do
                    {:var, _} ->
                      {bd2, bps2} = fdget(b, s)
                      put_isect(b, bd2, iv(inf_dec(bd2), bmin(sup_dec(bd2), au)), bps2, q, s)

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

  # --- pabs(X, Y): Y = abs(X) ---
  #
  # Y bekannt: X in -Y \/ Y aufstellen – das Original

  defp propagate("pabs", [x0, y0], st, q, s) do
    x = val(x0, s)
    y = val(y0, s)

    cond do
      is_integer(x) ->
        s |> kill_then(st) |> bind(y0, abs(x))

      is_integer(y) ->
        if y < 0, do: :fail, else: throw(:fallback)

      x == y ->
        kill(st, s)

      true ->
        {xd, xps} = fdget(x, s)
        {yd, _} = fdget_ro(y, s)

        case isect(xd, union!(yd, negate(yd))) do
          nil ->
            :fail

          xd2 ->
            s
            |> seq(&fdput(x, xd2, xps, q, &1))
            |> seq(fn s ->
              {yd1, yps1} = fdget(y, s)
              yd3 = remove_lt(union!(xd2, negate(xd2)), 0)
              put_isect(y, yd1, yd3, yps1, q, s)
            end)
        end
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
            {yd, _} = fdget_ro(y, s)

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
        {xd, _} = fdget_ro(x, s)
        {yd, _} = fdget_ro(y, s)

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
            {yd, _} = fdget_ro(y, s)

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
        {xd, _} = fdget_ro(x, s)
        {yd, _} = fdget_ro(y, s)

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

  # B offen: t/f sind die Werte von B für "gleich"/"verschieden"
  defp eq_open(eq, x, y, st, ps, b0, s) do
    {t, f} = if eq, do: {1, 0}, else: {0, 1}

    cond do
      is_integer(x) and is_integer(y) ->
        s |> kill_then(st) |> bind(b0, if(x == y, do: t, else: f))

      is_integer(x) ->
        {yd, _} = fdget_ro(y, s)
        if dcontains?(yd, x), do: s, else: s |> kill2(st, ps) |> bind(b0, f)

      is_integer(y) ->
        eq_open(eq, y, x, st, ps, b0, s)

      x == y ->
        s |> kill_then(st) |> bind(b0, t)

      true ->
        {xd, _} = fdget_ro(x, s)
        {yd, _} = fdget_ro(y, s)

        if gt(inf_dec(xd), sup_dec(yd)) or gt(inf_dec(yd), sup_dec(xd)),
          do: s |> kill2(st, ps) |> bind(b0, f),
          else: s
    end
  end

  # X bekannt
  defp exp_x(x, y, z, y0, z0, st, q, s) do
    cond do
      is_integer(y) ->
        if y >= 0 or x == -1,
          do: s |> kill_then(st) |> bind(z0, ipow(x, y)),
          else: :fail

      is_integer(z) ->
        cond do
          z <= 1 ->
            s

          abs(x) <= 1 ->
            :fail

          true ->
            case integer_log_b(z, x, 1) do
              nil -> :fail
              l -> s |> kill_then(st) |> bind(y0, l)
            end
        end

      true ->
        {yd, _} = fdget_ro(y, s)
        {zd, zps} = fdget(z, s)

        s =
          if x > 0 and geq(inf_dec(yd), 0) do
            case isect(zd, iv(exp(x, inf_dec(yd)), exp(x, sup_dec(yd)))) do
              nil -> :fail
              nzd -> fdput(z, nzd, zps, q, s)
            end
          else
            s
          end

        seq(s, fn s ->
          {zd2, _} = fdget_ro(z, s)
          zmax = sup_dec(zd2)

          if x > 0 and is_integer(zmax) and zmax > 0 do
            ycl = floor_integer_log_b(zmax, x, 1)
            goal(s, mk("in", [y, mk("..", [a("inf"), ycl])]), q)
          else
            s
          end
        end)
    end
  end

  # Z bekannt, X offen
  defp exp_z(x, y, z, x0, st, q, s) do
    if is_integer(y) do
      case integer_kth_root(z, y) do
        nil ->
          :fail

        r ->
          # gerades Y: X in -R \/ R aufstellen (das Original)
          if rem(y, 2) == 0, do: throw(:fallback)
          s |> kill_then(st) |> bind(x0, r)
      end
    else
      {xd, _} = fdget_ro(x, s)
      nxl = inf_dec(xd)

      with true <- is_integer(nxl) and nxl > 1 and z > 1,
           e when e != nil <- first_exp_over(nxl, nxl, z) do
        {yd, yps} = fdget(y, s)

        case isect(yd, iv(1, e - 1)) do
          nil ->
            :fail

          yd1 ->
            s
            |> seq(&fdput(y, yd1, yps, q, &1))
            |> seq(fn s ->
              case integer_kth_root_leq(z, inf_dec(yd1)) do
                nil ->
                  :fail

                ru ->
                  {xd2, xps} = fdget(x, s)
                  put_isect(x, xd2, iv(nxl, ru), xps, q, s)
              end
            end)
        end
      else
        _ -> s
      end
    end
  end

  # between(NXL, Z, Exp), NXL^Exp > Z: das erste solche Exp
  defp first_exp_over(b, e, z) do
    cond do
      e > z -> nil
      ipow(b, e) > z -> e
      true -> first_exp_over(b, e + 1, z)
    end
  end

  # Y > 0 bekannt, X und Z offen
  defp exp_y(x, y, z, q, s) do
    even = rem(y, 2) == 0

    s =
      if even do
        {zd0, zps0} = fdget(z, s)
        fdput(z, remove_lt(zd0, 0), zps0, q, s)
      else
        s
      end

    seq(s, fn s ->
      {xd, _} = fdget_ro(x, s)
      {xl, xu} = {inf_dec(xd), sup_dec(xd)}
      {zd, zps} = fdget(z, s)
      {zl, zu} = {inf_dec(zd), sup_dec(zd)}
      xd1 = if dcontains?(zd, 0), do: xd, else: remove(xd, 0)
      zd1 = if dcontains?(xd, 0), do: zd, else: remove(zd, 0)

      zd2 =
        cond do
          even ->
            nzl =
              cond do
                geq(xl, 0) -> exp(xl, y)
                leq(xu, 0) -> exp(xu, y)
                true -> 0
              end

            isect(zd1, iv(nzl, exp(bmax(babs(xl), babs(xu)), y)))

          is_integer(xl) ->
            isect(zd1, iv(exp(xl, y), exp(xu, y)))

          true ->
            if zd1 == [], do: nil, else: zd1
        end

      nxd =
        cond do
          even and is_integer(zu) ->
            with ru when ru != nil <- integer_kth_root_leq(zu, y) do
              rl =
                if geq(xl, 0) and is_integer(zl) and zl >= 0,
                  do: root_up(zl, y),
                  else: -ru

              if rl <= ru, do: iv(rl, ru), else: nil
            end

          not even and geq(zl, 0) and is_integer(zu) ->
            unless is_integer(zl), do: throw(:fallback)
            ru = integer_kth_root_leq(zu, y)
            rl = root_up(zl, y)
            if rl <= ru, do: iv(rl, ru), else: nil

          true ->
            xd1
        end

      cond do
        zd2 == nil or nxd == nil ->
          :fail

        true ->
          s
          |> seq(&fdput(z, zd2, zps, q, &1))
          |> seq(fn s ->
            {xd2, xps} = fdget(x, s)

            with xd3 when xd3 != nil <- isect_e(xd2, xd1),
                 xd4 when xd4 != nil <- isect_e(xd3, nxd) do
              fdput(x, xd4, xps, q, s)
            else
              _ -> :fail
            end
          end)
      end
    end)
  end

  # kleinste R mit R^K >= N (integer_kth_root_leq, dann aufrunden)
  defp root_up(n, k) do
    r0 = integer_kth_root_leq(n, k)
    if ipow(r0, k) < n, do: r0 + 1, else: r0
  end

  defp isect_e(a, b), do: isect(a, b)

  # die übrigen Fälle: X, Y > 0 nach unten beschränkt
  defp exp_rest(x, y, z, q, s) do
    with true <- var?(x) and var?(y) and var?(z),
         {xd, _} = fdget_ro(x, s),
         true <- gt(inf_dec(xd), 0),
         {yd, _} = fdget_ro(y, s),
         true <- gt(inf_dec(yd), 0),
         nzl when is_integer(nzl) <- exp(inf_dec(xd), inf_dec(yd)) do
      {zd, zps} = fdget(z, s)
      fdput(z, remove_lt(zd, nzl), zps, q, s)
    else
      _ -> s
    end
  end

  # X^Y für ganze Zahlen (Y < 0 nur bei X = ±1, wie (^)/2)
  defp ipow(x, y) when y >= 0, do: Integer.pow(x, y)
  defp ipow(1, _y), do: 1
  defp ipow(-1, y), do: if(rem(y, 2) == 0, do: 1, else: -1)

  # integer_log_b/4 (nil: Fehlschlag)
  defp integer_log_b(n, b, l) do
    t = ipow(b, l)

    cond do
      t == n -> l
      t < n -> integer_log_b(n, b, l + 1)
      true -> nil
    end
  end

  # floor_integer_log_b/4
  defp floor_integer_log_b(n, b, l) do
    t = ipow(b, l)

    cond do
      t > n -> l - 1
      t == n -> l
      true -> floor_integer_log_b(n, b, l + 1)
    end
  end

  # integer_kth_root/3: R mit R^K = N (nil: keine)
  defp integer_kth_root(n, k) do
    cond do
      rem(k, 2) == 0 and n < 0 -> nil
      k < 0 and n == 1 -> 1
      k < 0 and n == -1 -> if rem(k, 2) != 0, do: -1, else: nil
      k < 0 -> nil
      n < 0 -> if rem(k, 2) != 0, do: kroot(n, 0, n, k), else: nil
      true -> kroot(0, n, n, k)
    end
  end

  defp kroot(l, u, n, k) do
    cond do
      l == u ->
        if ipow(l, k) == n, do: l, else: nil

      l + 1 == u ->
        cond do
          ipow(l, k) == n -> l
          ipow(u, k) == n -> u
          true -> nil
        end

      true ->
        mid = div(l + u, 2)
        if ipow(mid, k) > n, do: kroot(l, mid, n, k), else: kroot(mid, u, n, k)
    end
  end

  # integer_kth_root_leq/3: größtes R mit R^K =< N (nil: Fehlschlag)
  defp integer_kth_root_leq(n, k) do
    cond do
      rem(k, 2) == 0 and n < 0 -> nil
      n < 0 -> if rem(k, 2) != 0, do: kroot_leq(n, 0, n, k), else: nil
      true -> kroot_leq(0, n, n, k)
    end
  end

  defp kroot_leq(l, u, n, k) do
    cond do
      l == u ->
        l

      l + 1 == u ->
        if ipow(u, k) <= n, do: u, else: l

      true ->
        mid = div(l + u, 2)
        if ipow(mid, k) > n, do: kroot_leq(l, mid, n, k), else: kroot_leq(mid, u, n, k)
    end
  end

  # --- Hilfen für prem und pmod ---

  # Domäne der Variablen v mit f ändern und ablegen
  defp put_with(v, f, q, s) do
    {d, ps} = fdget(v, s)
    fdput(v, f.(d), ps, q, s)
  end

  # gcc_check_//1 für ein Paar: {s, nil} oder {s, {V, T}} (die eine
  # Bindung V = T steht noch aus, gcc_done/1 ist schon gerechnet)
  defp gcc_pair(key, num0, q, s) do
    case att(num0, s, "clpz_gcc_vs", 1) do
      nil ->
        {s, nil}

      [vs] ->
        [num] = att(num0, s, "clpz_gcc_num", 1) || throw(:fallback)

        occ0 =
          case att(num0, s, "clpz_gcc_occurred", 1) do
            [o] -> val(o, s)
            _ -> throw(:fallback)
          end

        is_integer(occ0) || throw(:fallback)
        {min, os} = vs_key_min_others(ws(vs, s), key, s, 0, [])
        occ1 = occ0 + min

        s =
          s
          |> put_att(num0, mk("clpz_gcc_vs", [PrologEx.list(os)]))
          |> put_att(num0, mk("clpz_gcc_occurred", [occ1]))
          |> geq_var_int(num, occ1, q)

        if s == :fail, do: {:fail, nil}, else: gcc_pair_rest(key, num0, num, occ1, os, q, s)
    end
  end

  defp gcc_pair_rest(key, num0, num, occ1, os, q, s) do
    numv = val(num, s)

    cond do
      numv == occ1 ->
        s = neq_list(s, os, key, q)
        {seq(s, &gcc_done(num0, &1)), nil}

      os == [] ->
        s = gcc_done(num0, s)

        case numv do
          {:var, _} = v -> {s, {v, occ1}}
          _ -> {:fail, nil}
        end

      true ->
        l = length(os)
        s = int_geq_var(occ1 + l, num, q, s)

        if s == :fail do
          {:fail, nil}
        else
          diff =
            case val(num, s) do
              i when is_integer(i) ->
                i - occ1

              {:var, _} = v ->
                case inf_dec(elem(fdget_ro(v, s), 0)) do
                  ninf when is_integer(ninf) -> ninf - occ1
                  _ -> throw(:fallback)
                end
            end

          cond do
            l < diff ->
              {:fail, nil}

            l == diff ->
              # Num is Occ1 + Diff (mit bekanntem Num gilt das schon),
              # maplist(=(Key), Os), gcc_done/1: nur eine Bindung
              case {val(num, s), os} do
                {i, [o]} when is_integer(i) -> {gcc_done(num0, s), {o, key}}
                _ -> throw(:fallback)
              end

            true ->
              {s, nil}
          end
        end
    end
  end

  # vs_key_min_others/5: wie oft Key schon vorkommt, die Variablen, die Key
  # noch annehmen können
  # gcc_pair/4 für jedes Paar Key-Num0: {s, nil}, {:fail, nil} oder – nur
  # beim letzten Paar – {s, {V, Wert}} (eine Bindung danach)
  defp gcc_pairs([], _q, s), do: {s, nil}

  defp gcc_pairs([p | ps], q, s) do
    {key, num0} = gcc_pair_arg(p, s)
    ps = ws(ps, s)

    case gcc_pair(key, num0, q, s) do
      {:fail, _} -> {:fail, nil}
      {s, nil} -> gcc_pairs(ps, q, s)
      {s, b} when ps == [] -> {s, b}
      _ -> throw(:fallback)
    end
  end

  defp gcc_pairs(_, _q, _s), do: throw(:fallback)

  # die Intervalle der Elemente mit Index in nd (unecht: das Original)
  defp element_doms([], _i, _nd, _s), do: []

  defp element_doms([e | es], i, nd, s) do
    if dcontains?(nd, i),
      do: element_dom(e, s) ++ element_doms(ws(es, s), i + 1, nd, s),
      else: element_doms(ws(es, s), i + 1, nd, s)
  end

  defp element_doms(_, _i, _nd, _s), do: throw(:fallback)

  # das n-te Element (ab 1) oder nil; die Liste muss ganz echt sein
  defp nth_item([], _n, _s), do: nil
  defp nth_item([e | es], 1, s), do: if(proper_list?(es, s), do: e, else: throw(:fallback))
  defp nth_item([_ | es], n, s), do: nth_item(ws(es, s), n - 1, s)
  defp nth_item(_, _n, _s), do: throw(:fallback)

  defp proper_list?(l, s) do
    case ws(l, s) do
      [] -> true
      [_ | t] -> proper_list?(t, s)
      _ -> false
    end
  end

  defp vs_key_min_others([], _key, _s, min, os), do: {min, :lists.reverse(os)}

  defp vs_key_min_others([v | vs], key, s, min, os) do
    case val(v, s) do
      {:var, _} = x ->
        if dcontains?(elem(fdget_ro(x, s), 0), key),
          do: vs_key_min_others(ws(vs, s), key, s, min, [x | os]),
          else: vs_key_min_others(ws(vs, s), key, s, min, os)

      ^key ->
        vs_key_min_others(ws(vs, s), key, s, min + 1, os)

      i when is_integer(i) ->
        vs_key_min_others(ws(vs, s), key, s, min, os)
    end
  end

  defp vs_key_min_others(_, _key, _s, _min, _os), do: throw(:fallback)

  defp gcc_done(_num0, :fail), do: :fail

  defp gcc_done(num0, s) do
    s
    |> del_att(num0, "clpz_gcc_vs", 1)
    |> del_att(num0, "clpz_gcc_num", 1)
    |> del_att(num0, "clpz_gcc_occurred", 1)
  end

  # geq//2 mit Zahl rechts: A ≥ N
  defp geq_var_int(:fail, _a, _n, _q), do: :fail

  defp geq_var_int(s, a, n, q) do
    case val(a, s) do
      {:var, _} = v ->
        {d, ps} = fdget(v, s)
        if geq(inf_dec(d), n), do: s, else: fdput(v, remove_lt(d, n), ps, q, s)

      i when is_integer(i) ->
        if i >= n, do: s, else: :fail

      _ ->
        throw(:fallback)
    end
  end

  # geq//2 mit Zahl links: M ≥ B
  defp int_geq_var(m, b, q, s) do
    case val(b, s) do
      {:var, _} = v -> put_with(v, &remove_gt(&1, m), q, s)
      i when is_integer(i) -> if m >= i, do: s, else: :fail
      _ -> throw(:fallback)
    end
  end

  # die Variable hat keine Domäne oder dieselbe Queue (abgeschaltet: der Hook
  # des Originals reiht nur ein)
  defp same_queue_or_none?(v, q, s) do
    case att(v, s, "clpz", 1) do
      nil ->
        true

      [attr] ->
        case ws(attr, s) do
          {tag, "clpz_attr", [_, _, _, _, _, qx]} when tag in [:struct, :gstruct] ->
            aux(qx, s) == aux(q, s)

          _ ->
            false
        end
    end
  end

  # element_domain/2: Domäne einer Variablen, sonst der Wert allein
  defp element_dom(e, s) do
    case val(e, s) do
      i when is_integer(i) -> iv(i, i)
      {:var, _} = v -> elem(fdget_ro(v, s), 0)
      _ -> throw(:fallback)
    end
  end

  # endliche Schranken einer Variablen: {L, U} (nil, wenn unendlich)
  defp ibounds(v, s) do
    {d, _} = fdget_ro(v, s)
    {int_or_nil(inf_dec(d)), int_or_nil(sup_dec(d))}
  end

  defp int_or_nil(i) when is_integer(i), do: i
  defp int_or_nil(_), do: nil

  # prem, Y bekannt, Z offen
  defp rem_y(x, y, z, q, s) do
    yp = abs(y) - 1
    yn = -yp

    {zl, zu} =
      case ibounds(x, s) do
        {xl, xu} when y > 0 and is_integer(xl) and is_integer(xu) ->
          # Z = X mitten im Propagator: das Original
          if abs(xl) < y and xu < y, do: throw(:fallback)

          zl =
            cond do
              xl < 0 and abs(xl) < y -> xl
              xl >= 0 -> 0
              true -> yn
            end

          zu =
            cond do
              xu > 0 and xu < y -> xu
              xu < 0 -> 0
              true -> yp
            end

          {zl, zu}

        _ ->
          {yn, yp}
      end

    {zd, zps} = fdget(z, s)

    case isect(zd, iv(zl, zu)) do
      nil ->
        :fail

      zd1 ->
        s
        |> seq(&fdput(z, zd1, zps, q, &1))
        |> seq(fn s ->
          case ibounds(x, s) do
            {min, _} when is_integer(min) ->
              if dcontains?(zd1, rem(min, y)), do: s, else: neq_num(x, min, q, s)

            _ ->
              s
          end
        end)
        |> seq(fn s ->
          case ibounds(x, s) do
            {_, max} when is_integer(max) ->
              if dcontains?(zd1, rem(max, y)), do: s, else: neq_num(x, max, q, s)

            _ ->
              s
          end
        end)
    end
  end

  # prem, Y und Z bekannt
  defp rem_yz(x, y, z, q, s) do
    s
    |> seq(fn s ->
      case ibounds(x, s) do
        {min, _} when is_integer(min) ->
          cond do
            rem(min, y) == z ->
              s

            y > 0 and min > 0 ->
              nxt = Integer.floor_div(min - z + y - 1, y) * y + z
              put_with(x, &remove_lt(&1, nxt), q, s)

            true ->
              neq_num(x, min, q, s)
          end

        _ ->
          s
      end
    end)
    |> seq(fn s ->
      case ibounds(x, s) do
        {_, max} when is_integer(max) ->
          cond do
            rem(max, y) == z ->
              s

            y > 0 and max > 0 ->
              prev = Integer.floor_div(max - z, y) * y + z
              put_with(x, &remove_gt(&1, prev), q, s)

            true ->
              neq_num(x, max, q, s)
          end

        _ ->
          s
      end
    end)
  end

  # pmod, Y und Z bekannt
  defp mod_yz(x, y, z, q, s) do
    ok = if y > 0, do: z >= 0 and z < y, else: z <= 0 and z > y

    if not ok do
      :fail
    else
      s
      |> seq(fn s ->
        case ibounds(x, s) do
          {xl, _} when is_integer(xl) ->
            xmin =
              if Integer.mod(xl - z, y) != 0,
                do: z + y * (Integer.floor_div(xl - z, y) + 1),
                else: xl

            put_with(x, &remove_lt(&1, xmin), q, s)

          _ ->
            s
        end
      end)
      |> seq(fn s ->
        case ibounds(x, s) do
          {_, xu} when is_integer(xu) ->
            xmax = z + y * Integer.floor_div(xu - z, y)
            put_with(x, &remove_gt(&1, xmax), q, s)

          _ ->
            s
        end
      end)
    end
  end

  # pmod, Z und X bekannt
  defp mod_zx(x, y, z, st, q, s) do
    ok =
      cond do
        z > 0 -> x < 0 or (x >= z and (x - z <= 0 or x - z > z))
        z < 0 -> x > 0 or (x <= z and (x - z >= 0 or x - z < z))
        true -> true
      end

    if not ok do
      :fail
    else
      {yl, yu} = ibounds(y, s)

      cond do
        is_integer(yu) and yu < x and x <= 0 ->
          s = kill(st, s)
          if s != :fail and z == x, do: s, else: :fail

        is_integer(yl) and yl > x and x >= 0 ->
          s = kill(st, s)
          if s != :fail and z == x, do: s, else: :fail

        z > 0 and x < 0 ->
          put_with(y, &(&1 |> remove_lt(z + 1) |> remove_gt(z - x)), q, s)

        z < 0 and x > 0 ->
          put_with(y, &(&1 |> remove_gt(z - 1) |> remove_lt(z - x)), q, s)

        z > 0 ->
          put_with(y, &remove_lt(&1, z + 1), q, s)

        z < 0 ->
          put_with(y, &remove_gt(&1, z - 1), q, s)

        x == 0 ->
          kill(st, s)

        true ->
          put_with(y, &(&1 |> remove_lt(-abs(x)) |> remove_gt(abs(x))), q, s)
      end
    end
  end

  # pmodz//3 (höchstens eine von X, Y, Z bekannt)
  defp pmodz(x, y, z, x0, z0, st, q, s) do
    cond do
      is_integer(z) ->
        s

      is_integer(x) and x == 0 ->
        s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)

      is_integer(x) ->
        {yl, yu} = ibounds(y, s)

        s =
          cond do
            x > 0 and is_integer(yl) and yl > x ->
              s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)

            x > 0 ->
              put_with(z, &remove_gt(&1, x), q, s)

            is_integer(yu) and yu < x ->
              s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)

            true ->
              put_with(z, &remove_lt(&1, x), q, s)
          end

        seq(s, &z_by_y_sign(y, z, q, &1, false))

      is_integer(y) ->
        cond do
          abs(y) == 1 ->
            s |> kill_then(st) |> goal(mk("=", [z0, 0]), q)

          y < 0 ->
            case ibounds(x, s) do
              {xl, xu} when is_integer(xl) and is_integer(xu) and xu <= 0 and y < xl ->
                s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)

              _ ->
                put_with(z, &(&1 |> remove_gt(0) |> remove_lt(y + 1)), q, s)
            end

          true ->
            case ibounds(x, s) do
              {xl, xu} when is_integer(xl) and is_integer(xu) and xl >= 0 and y > xu ->
                s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)

              _ ->
                put_with(z, &(&1 |> remove_lt(0) |> remove_gt(y - 1)), q, s)
            end
        end

      true ->
        {xl, xu} = ibounds(x, s)
        {yl, yu} = ibounds(y, s)
        xfin = is_integer(xl) and is_integer(xu)

        cond do
          xfin and xl >= 0 and is_integer(yl) and xu < yl ->
            s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)

          xfin and xu <= 0 and is_integer(yu) and xl > yu ->
            s |> kill_then(st) |> goal(mk("=", [z0, x0]), q)

          true ->
            s =
              cond do
                xfin and xl >= 0 -> put_with(z, &remove_gt(&1, xu), q, s)
                xfin and xu <= 0 -> put_with(z, &remove_lt(&1, xl), q, s)
                true -> s
              end

            seq(s, &z_by_y_sign(y, z, q, &1, true))
        end
    end
  end

  # Z nach dem Vorzeichen von Y beschränken (pmodz); more: auch Y um 0 und
  # halb unendliche Y (der Fall ohne bekannte Variable)
  defp z_by_y_sign(y, z, q, s, more) do
    {yl, yu} = ibounds(y, s)
    fin = is_integer(yl) and is_integer(yu)

    cond do
      fin and yl > 0 ->
        put_with(z, &(&1 |> remove_lt(0) |> remove_gt(yu - 1)), q, s)

      fin and yu < 0 ->
        put_with(z, &(&1 |> remove_gt(0) |> remove_lt(yl + 1)), q, s)

      not more ->
        s

      fin and yl < 0 and yu > 0 ->
        put_with(z, &(&1 |> remove_gt(yu - 1) |> remove_lt(yl + 1)), q, s)

      is_integer(yu) and yu > 0 ->
        put_with(z, &remove_gt(&1, yu - 1), q, s)

      is_integer(yl) and yl < 0 ->
        put_with(z, &remove_lt(&1, yl + 1), q, s)

      true ->
        s
    end
  end

  # pmody//3
  defp pmody(y, z, q, s) do
    cond do
      is_integer(y) ->
        s

      is_integer(z) ->
        cond do
          z > 0 -> put_with(y, &remove_lt(&1, z + 1), q, s)
          z < 0 -> put_with(y, &remove_gt(&1, z - 1), q, s)
          true -> s
        end

      true ->
        case ibounds(z, s) do
          {zl, _} when is_integer(zl) and zl > 0 -> put_with(y, &remove_lt(&1, zl + 1), q, s)
          {_, zu} when is_integer(zu) and zu < 0 -> put_with(y, &remove_gt(&1, zu - 1), q, s)
          _ -> s
        end
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
    case ws(ps, s) do
      [] -> s
      [e | ps] -> e |> kill_entailed(s) |> kill_entailed_all(ps)
      _ -> throw(:fallback)
    end
  end

  defp kill_entailed(e, s) do
    case ws(e, s) do
      {tag, "p", [prop]} when tag in [:struct, :gstruct] ->
        case ws(prop, s) do
          {t2, "propagator", [_, state]} when t2 in [:struct, :gstruct] ->
            kill(state, s)

          # noch kein Propagator (Teilausdruck ohne eigenen): wie
          # propagator_state/2 und kill/1 – Prop = propagator(_, dead);
          # eine gewöhnliche Variable, nichts zu wecken
          {:var, id} = v when not is_tuple(id) or elem(id, 0) != :attv ->
            bind(s, v, mk("propagator", [fresh_var(), a("dead")]))

          _ ->
            throw(:fallback)
        end

      {tag, "a", [v]} when tag in [:struct, :gstruct] ->
        del_clpz(v, s)

      {tag, "a", [x, b]} when tag in [:struct, :gstruct] ->
        if PrologEx.Store.walk(x, s) == PrologEx.Store.walk(b, s), do: s, else: del_clpz(b, s)

      {tag, "a", [x, y, b]} when tag in [:struct, :gstruct] ->
        bw = PrologEx.Store.walk(b, s)

        if PrologEx.Store.walk(x, s) == bw or PrologEx.Store.walk(y, s) == bw,
          do: s,
          else: del_clpz(b, s)

      _ ->
        throw(:fallback)
    end
  end

  # del_attr(V, clpz): nur für eine Variable
  defp del_clpz(v, s) do
    case PrologEx.Store.walk(v, s) do
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
        {yd, _} = fdget_ro(y, s)

        cond do
          geq(x, sup_dec(yd)) -> s |> kill2(st, ps) |> bind(b0, 1)
          lt(x, inf_dec(yd)) -> s |> kill2(st, ps) |> bind(b0, 0)
          true -> s
        end

      is_integer(y) ->
        {xd, _} = fdget_ro(x, s)

        cond do
          geq(inf_dec(xd), y) -> s |> kill2(st, ps) |> bind(b0, 1)
          lt(sup_dec(xd), y) -> s |> kill2(st, ps) |> bind(b0, 0)
          true -> s
        end

      x == y ->
        s |> kill2(st, ps) |> bind(b0, 1)

      true ->
        {xd, _} = fdget_ro(x, s)
        {yd, _} = fdget_ro(y, s)

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

  # domain_expand/3, domain_contract/3 in Propagatoren (X ≠ 0 dort
  # sichergestellt; sonst das Original)
  defp dexpand(d, m), do: ClpzDom.expand(d, nonzero_i(m))
  defp dcontract(d, m), do: ClpzDom.contract(d, nonzero_i(m))

  defp nonzero_i(0), do: throw(:fallback)
  defp nonzero_i(i), do: i

  # ptimes, X bekannt: Z ∩ X·Y, dann Y ∩ Z/X
  defp times_x(x, y, z, q, s) do
    {yd, _} = fdget_ro(y, s)
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
    {yd, _} = fdget_ro(y, s)
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
    {yd, _} = fdget_ro(y, s)
    {yl, yu} = {inf_dec(yd), sup_dec(yd)}
    {zd, _} = fdget_ro(z, s)
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
              case isect(zd2, iv(nzl, nzu)) do
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

  defp then_put(s, v, d, ps, q), do: fdput(v, d, ps, q, s)

  defp inf_d(d), do: inf_dec(d)
  defp sup_d(d), do: sup_dec(d)

  # pplus, X bekannt: Z ∩ (Y + X), dann Y ∩ (ZD1 - X) mit der berechneten
  # Domäne ZD1 (bei einem einzelnen Wert legt fd_put sie nicht ab)
  defp plus_x(x, y, z, q, s) do
    {zd, zps} = fdget(z, s)
    {yd, _} = fdget_ro(y, s)

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
    {xd, _} = fdget_ro(x, s)
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
    {yd0, _} = fdget_ro(y, s)
    {yl, yu} = {inf_dec(yd0), sup_dec(yd0)}
    {zd0, _} = fdget_ro(z, s)
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
    put_isect(v, d, iv(nl, nu), ps, q, s)
  end

  # coeffs_variables_const/6 gleich über den Prolog-Listen Cs und Vs:
  # [{C, V}] der offenen Variablen (in ihrer Reihenfolge) und Σ C·V der
  # bekannten
  defp coeffs_vars(cs, vs, s), do: coeffs_vars(ws(cs, s), ws(vs, s), s, [], 0)

  defp coeffs_vars([], [], _s, acc, i), do: {:lists.reverse(acc), i}

  defp coeffs_vars([c | cs], [v | vs], s, acc, i) do
    c =
      case val(c, s) do
        c when is_integer(c) -> c
        _ -> throw(:fallback)
      end

    case val(v, s) do
      {:var, _} = var -> coeffs_vars(ws(cs, s), ws(vs, s), s, [{c, var} | acc], i)
      n -> coeffs_vars(ws(cs, s), ws(vs, s), s, acc, i + c * n)
    end
  end

  defp coeffs_vars(_, _, _s, _acc, _i), do: throw(:fallback)

  defp zero_coeff?([{0, _} | _]), do: true
  defp zero_coeff?([_ | cvs]), do: zero_coeff?(cvs)
  defp zero_coeff?([]), do: false

  # sum_finite_domains/10: {Infs, Sups, Inf, Sup}; Infs/Sups die Glieder
  # C·V mit unendlicher Schranke, in der Reihenfolge des Originals
  defp sum_finite(cvs, s), do: sum_finite(cvs, s, [], [], 0, 0)

  defp sum_finite([], _s, infs, sups, inf, sup),
    do: {:lists.reverse(infs), :lists.reverse(sups), inf, sup}

  defp sum_finite([{c, v} = cv | cvs], s, infs, sups, inf, sup) do
    {d, _} = fdget_ro(v, s)
    l = inf_dec(d)
    u = sup_dec(d)

    # C < 0: die untere Schranke von V trägt zu Sup bei, die obere zu Inf
    cond do
      c < 0 ->
        case {is_integer(l), is_integer(u)} do
          {true, true} -> sum_finite(cvs, s, infs, sups, inf + c * u, sup + c * l)
          {true, false} -> sum_finite(cvs, s, [cv | infs], sups, inf, sup + c * l)
          {false, true} -> sum_finite(cvs, s, infs, [cv | sups], inf + c * u, sup)
          {false, false} -> sum_finite(cvs, s, [cv | infs], [cv | sups], inf, sup)
        end

      true ->
        case {is_integer(l), is_integer(u)} do
          {true, true} -> sum_finite(cvs, s, infs, sups, inf + c * l, sup + c * u)
          {true, false} -> sum_finite(cvs, s, infs, [cv | sups], inf + c * l, sup)
          {false, true} -> sum_finite(cvs, s, [cv | infs], sups, inf, sup + c * u)
          {false, false} -> sum_finite(cvs, s, [cv | infs], [cv | sups], inf, sup)
        end
    end
  end

  # Je offene Variable V der Glieder {C, V}: Domäne D durch narrow/5 ersetzen
  # (nil: leer) und ablegen; kind wählt die Regel, a und b sind ihre Werte
  defp each_cv([], _kind, _a, _b, _q, s), do: s

  defp each_cv([{c, v} | cvs], kind, a, b, q, s) do
    case val(v, s) do
      {:var, _} ->
        {d, ps} = fdget(v, s)

        case narrow(kind, c, d, a, b) do
          nil ->
            :fail

          d2 ->
            case fdput(v, d2, ps, q, s) do
              :fail -> :fail
              s -> each_cv(cvs, kind, a, b, q, s)
            end
        end

      _ ->
        each_cv(cvs, kind, a, b, q, s)
    end
  end

  # remove_dist_upper_lower//4
  defp narrow(:ul, c, vd, d1, d2) when c < 0 do
    with sup when sup != nil <- int_bound(sup_dec(vd)),
         vd1 = remove_lt(vd, sup + div(d1, c)),
         false <- vd1 == [],
         inf when inf != nil <- int_bound(inf_dec(vd1)) do
      remove_gt(vd1, inf - div(d2, c))
    else
      _ -> nil
    end
  end

  defp narrow(:ul, c, vd, d1, d2) do
    with inf when inf != nil <- int_bound(inf_dec(vd)),
         vd1 = remove_gt(vd, inf + div(d1, c)),
         false <- vd1 == [],
         sup when sup != nil <- int_bound(sup_dec(vd1)) do
      remove_lt(vd1, sup - div(d2, c))
    else
      _ -> nil
    end
  end

  # remove_dist_upper//2
  defp narrow(:upper, c, vd, d, _) when c < 0 do
    case int_bound(sup_dec(vd)) do
      nil -> vd
      sup -> remove_lt(vd, sup + div(d, c))
    end
  end

  defp narrow(:upper, c, vd, d, _) do
    case int_bound(inf_dec(vd)) do
      nil -> vd
      inf -> remove_gt(vd, inf + div(d, c))
    end
  end

  # remove_dist_upper_leq//3: wie :upper, ohne endliche Schranke leer
  defp narrow(:upper_leq, c, vd, d1, _) when c < 0 do
    case int_bound(sup_dec(vd)) do
      nil -> nil
      sup -> remove_lt(vd, sup + div(d1, c))
    end
  end

  defp narrow(:upper_leq, c, vd, d1, _) do
    case int_bound(inf_dec(vd)) do
      nil -> nil
      inf -> remove_gt(vd, inf + div(d1, c))
    end
  end

  # remove_dist_lower//2
  defp narrow(:lower, c, vd, d, _) when c < 0 do
    case int_bound(inf_dec(vd)) do
      nil -> vd
      inf -> remove_gt(vd, inf - div(d, c))
    end
  end

  defp narrow(:lower, c, vd, d, _) do
    case int_bound(sup_dec(vd)) do
      nil -> vd
      sup -> remove_lt(vd, sup - div(d, c))
    end
  end

  # remove_upper//2
  defp narrow(:max, c, xd, max, _) do
    d = div(max, c)
    if c < 0, do: remove_lt(xd, d), else: remove_gt(xd, d)
  end

  # remove_lower//2
  defp narrow(:min, c, xd, min, _) do
    d = div(-min, c)
    if c < 0, do: remove_gt(xd, d), else: remove_lt(xd, d)
  end

  defp remove_dist_ul(cvs, d1, d2, q, s), do: each_cv(cvs, :ul, d1, d2, q, s)
  defp remove_dist_upper(cvs, d, q, s), do: each_cv(cvs, :upper, d, nil, q, s)
  defp remove_dist_upper_leq(cvs, d1, q, s), do: each_cv(cvs, :upper_leq, d1, nil, q, s)
  defp remove_dist_lower(cvs, d, q, s), do: each_cv(cvs, :lower, d, nil, q, s)
  defp remove_upper(cvs, max, q, s), do: each_cv(cvs, :max, max, nil, q, s)
  defp remove_lower(cvs, min, q, s), do: each_cv(cvs, :min, min, nil, q, s)

  defp int_bound(b) when is_integer(b), do: b
  defp int_bound(_), do: nil

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
        s = neq_pairs(gs, q, s)
        enable_queue(q, s)
    end
  end

  defp neq_pairs(_gs, _q, :fail), do: :fail
  defp neq_pairs([], _q, s), do: s
  defp neq_pairs([{v, n} | gs], q, s), do: neq_pairs(gs, q, neq_num(v, n, q, s))

  # [{Variable, Wert}] in der Reihenfolge des Originals, oder :fail
  defp distinct_goals(vs, s) do
    {left, n} = distinct_left(ws(vs, s), s, %{}, [], 0)
    doms = List.to_tuple(left_doms(left))
    # Wert => Variablen (aufsteigend); die Schlüssel sind die vorkommenden Werte
    adj = adjacency(n - 1, doms, %{})

    with true <- n <= map_size(adj),
         {:ok, mv} <- matching(doms, n) do
      removable(left, mv, adj)
    else
      _ -> :fail
    end
  end

  # [{Variable, Werte}] der ungebundenen Variablen mit endlicher Domäne,
  # in der Reihenfolge der Liste, und ihre Anzahl; eine Variable doppelt
  # oder eine unechte Liste: das Original
  defp distinct_left([], _s, _seen, acc, n), do: {:lists.reverse(acc), n}

  defp distinct_left([v | vs], s, seen, acc, n) do
    case PrologEx.Store.walk(v, s) do
      {:var, _} = v ->
        {d, _} = fdget_ro(v, s)

        case ClpzDom.to_list(d) do
          {:ok, ns} ->
            if is_map_key(seen, v), do: throw(:fallback)
            distinct_left(ws(vs, s), s, Map.put(seen, v, true), [{v, ns} | acc], n + 1)

          :error ->
            distinct_left(ws(vs, s), s, seen, acc, n)
        end

      _ ->
        distinct_left(ws(vs, s), s, seen, acc, n)
    end
  end

  defp distinct_left(_, _s, _seen, _acc, _n), do: throw(:fallback)

  defp left_doms([]), do: []
  defp left_doms([{_, ns} | left]), do: [ns | left_doms(left)]

  # (von hinten her vorangestellt, also aufsteigend; ohne Closure je Paar)
  defp adjacency(i, _doms, acc) when i < 0, do: acc
  defp adjacency(i, doms, acc), do: adjacency(i - 1, doms, adj_add(elem(doms, i), i, acc))

  defp adj_add([], _i, acc), do: acc

  defp adj_add([val | vals], i, acc) do
    acc =
      case acc do
        %{^val => is} -> %{acc | val => [i | is]}
        _ -> Map.put(acc, val, [i])
      end

    adj_add(vals, i, acc)
  end

  # maximale Paarung (augmentierende Pfade); {:ok, %{Variable => Wert}}
  # oder :fail, wenn nicht jede Variable einen Wert bekommt.
  # (Mengen hier als Maps mit is_map_key, Schleifen als direkte Rekursion:
  # MapSet, Access und reduce_while-Closures kosteten bei vielen Variablen
  # über die Hälfte der Zeit; Reihenfolge und Ergebnis unverändert)
  defp matching(doms, n), do: matching(0, n, doms, %{}, %{})

  defp matching(i, n, _doms, mv, _mval) when i >= n, do: {:ok, mv}

  defp matching(i, n, doms, mv, mval) do
    case augment(elem(doms, i), i, doms, mv, mval, %{}) do
      {:ok, mv, mval, _seen} -> matching(i + 1, n, doms, mv, mval)
      {:none, _seen} -> :fail
    end
  end

  # augmentierender Pfad ab Variable i über ihre Werte; seen: besuchte Werte
  defp augment([], _i, _doms, _mv, _mval, seen), do: {:none, seen}

  defp augment([val | vals], i, doms, mv, mval, seen) do
    if is_map_key(seen, val) do
      augment(vals, i, doms, mv, mval, seen)
    else
      seen = Map.put(seen, val, true)

      case mval do
        %{^val => j} ->
          case augment(elem(doms, j), j, doms, mv, mval, seen) do
            {:ok, mv, mval, _seen} -> {:ok, Map.put(mv, i, val), Map.put(mval, val, i), seen}
            {:none, seen} -> augment(vals, i, doms, mv, mval, seen)
          end

        _ ->
          {:ok, Map.put(mv, i, val), Map.put(mval, val, i), seen}
      end
    end
  end

  # Knoten als Zahlen (Tarjan und Erreichbarkeit rechnen in Maps mit den
  # Knoten als Schlüsseln; mit {:v, i} und {:n, Wert} ging ein Zehntel des
  # Sudoku in Hashen und Vergleichen der Schlüssel): Variable i → i, die
  # vorkommenden Werte → n, n + 1, …
  defp removable(left, mv, adj) do
    n = length(left)
    vals = Map.keys(adj)
    vnode = number_vals(vals, n, %{})
    matched = matched_vals(Map.values(mv), %{})

    # gerichteter Graph: gepaart Variable → Wert, sonst Wert → Variable
    succ = List.to_tuple(var_succ(0, n, mv, vnode, val_succ(vals, adj, mv)))

    # (Reihenfolge gleichgültig: reach liefert eine Menge)
    free = free_nodes(vals, matched, vnode)
    reach = reach(free, succ, set_of(free, %{}))
    comp = tarjan(int_nodes(0, n - 1), &elem(succ, &1))
    removable_edges(left, 0, mv, vnode, reach, comp)
  end

  defp number_vals([v | vs], k, acc), do: number_vals(vs, k + 1, Map.put(acc, v, k))
  defp number_vals([], _k, acc), do: acc

  defp matched_vals([v | vs], acc), do: matched_vals(vs, Map.put(acc, v, true))
  defp matched_vals([], acc), do: acc

  defp set_of([x | xs], acc), do: set_of(xs, Map.put(acc, x, true))
  defp set_of([], acc), do: acc

  # Nachfolger der Variablenknoten 0..n-1, davor gehängt an rest
  defp var_succ(i, n, _mv, _vnode, rest) when i >= n, do: rest

  defp var_succ(i, n, mv, vnode, rest),
    do: [[:erlang.map_get(:erlang.map_get(i, mv), vnode)] | var_succ(i + 1, n, mv, vnode, rest)]

  # Nachfolger der Wertknoten (in der Reihenfolge von vals): die
  # Variablen, mit denen der Wert nicht gepaart ist
  defp val_succ([val | vals], adj, mv),
    do: [unpaired(:erlang.map_get(val, adj), val, mv) | val_succ(vals, adj, mv)]

  defp val_succ([], _adj, _mv), do: []

  defp unpaired([j | js], val, mv) do
    if Map.get(mv, j) != val, do: [j | unpaired(js, val, mv)], else: unpaired(js, val, mv)
  end

  defp unpaired([], _val, _mv), do: []

  defp free_nodes([val | vals], matched, vnode) do
    if is_map_key(matched, val),
      do: free_nodes(vals, matched, vnode),
      else: [:erlang.map_get(val, vnode) | free_nodes(vals, matched, vnode)]
  end

  defp free_nodes([], _matched, _vnode), do: []

  # je Variable i die Werte (absteigend), deren Kante weg kann
  defp removable_edges([], _i, _mv, _vnode, _reach, _comp), do: []

  defp removable_edges([{v, ns} | left], i, mv, vnode, reach, comp) do
    removable_vals(
      :lists.reverse(ns),
      v,
      Map.get(mv, i),
      Map.get(comp, i),
      vnode,
      reach,
      comp,
      removable_edges(left, i + 1, mv, vnode, reach, comp)
    )
  end

  defp removable_vals([], _v, _mi, _ci, _vnode, _reach, _comp, rest), do: rest

  defp removable_vals([val | vals], v, mi, ci, vnode, reach, comp, rest) do
    vals = removable_vals(vals, v, mi, ci, vnode, reach, comp, rest)
    k = :erlang.map_get(val, vnode)

    if mi != val and not is_map_key(reach, k) and ci != Map.get(comp, k),
      do: [{v, val} | vals],
      else: vals
  end

  # erreichbare Knoten (Map als Menge); succ: Tupel der Nachfolger
  defp reach([], _succ, seen), do: seen

  defp reach([x | xs], succ, seen) do
    {new, seen} = unseen(elem(succ, x), seen, [])
    reach(new ++ xs, succ, seen)
  end

  defp unseen([], seen, acc), do: {:lists.reverse(acc), seen}

  defp unseen([y | ys], seen, acc) do
    if is_map_key(seen, y),
      do: unseen(ys, seen, acc),
      else: unseen(ys, Map.put(seen, y, true), [y | acc])
  end

  # starke Zusammenhangskomponenten (Tarjan): %{Knoten => Komponente}
  defp tarjan(roots, succ) do
    st = %{index: 0, idx: %{}, low: %{}, stack: [], on: %{}, comp: %{}}

    tarjan_roots(roots, succ, st).comp
  end

  defp tarjan_roots([], _succ, st), do: st

  defp tarjan_roots([v | vs], succ, st) do
    st = if is_map_key(st.idx, v), do: st, else: strong(v, succ, st)
    tarjan_roots(vs, succ, st)
  end

  defp strong(v, succ, st) do
    i = st.index

    st = %{
      st
      | idx: Map.put(st.idx, v, i),
        low: Map.put(st.low, v, i),
        index: i + 1,
        stack: [v | st.stack],
        on: Map.put(st.on, v, true)
    }

    st = strong_succ(succ.(v), v, succ, st)
    if :erlang.map_get(v, st.low) == i, do: pop_comp(v, i, st), else: st
  end

  defp strong_succ([], _v, _succ, st), do: st

  defp strong_succ([w | ws], v, succ, st) do
    st =
      cond do
        not is_map_key(st.idx, w) ->
          st = strong(w, succ, st)
          low = min(:erlang.map_get(v, st.low), :erlang.map_get(w, st.low))
          %{st | low: Map.put(st.low, v, low)}

        is_map_key(st.on, w) ->
          low = min(:erlang.map_get(v, st.low), :erlang.map_get(w, st.idx))
          %{st | low: Map.put(st.low, v, low)}

        true ->
          st
      end

    strong_succ(ws, v, succ, st)
  end

  defp pop_comp(v, c, %{stack: [w | rest]} = st) do
    st = %{st | stack: rest, on: Map.delete(st.on, w), comp: Map.put(st.comp, w, c)}
    if w == v, do: st, else: pop_comp(v, c, st)
  end

  # propagate_circuit/1: der Graph Knoten k → Werte von V_k ist stark
  # zusammenhängend (gebundene V_k: ihr Wert; ein Wert außerhalb 1..n oder
  # eine unendliche Domäne: scheitert)
  defp circuit_connected?(vs, s) do
    n = pl_length(vs, s)

    case circuit_arcs(ws(vs, s), 1, n, s, %{}) do
      nil ->
        false

      _ when n == 0 ->
        true

      g ->
        # wie im Original: Tarjan ab Knoten 1, alle in dessen Komponente
        comp = tarjan(int_nodes(1, n), &:erlang.map_get(&1, g))
        same_comp?(2, n, comp, :erlang.map_get(1, comp))
    end
  end

  # %{k => Nachfolger}, nil bei einem Wert außerhalb 1..n oder einer
  # unendlichen Domäne (die Liste wird trotzdem ganz gelesen: val/2 wirft
  # bei Unerwartetem, wie zuvor)
  defp circuit_arcs([], _k, _n, _s, g), do: g

  defp circuit_arcs([v | vs], k, n, s, g) do
    ns =
      case val(v, s) do
        {:var, _} = var ->
          {d, _} = fdget_ro(var, s)

          case ClpzDom.to_list(d) do
            {:ok, ns} -> ns
            :error -> nil
          end

        i ->
          [i]
      end

    g = if g != nil and ns != nil and all_in?(ns, n), do: Map.put(g, k, ns), else: nil
    circuit_arcs(ws(vs, s), k + 1, n, s, g)
  end

  defp all_in?([], _n), do: true
  defp all_in?([i | is], n), do: i >= 1 and i <= n and all_in?(is, n)

  defp int_nodes(i, n) when i > n, do: []
  defp int_nodes(i, n), do: [i | int_nodes(i + 1, n)]

  defp same_comp?(k, n, _comp, _c) when k > n, do: true

  defp same_comp?(k, n, comp, c),
    do: :erlang.map_get(k, comp) == c and same_comp?(k + 1, n, comp, c)
end
