defmodule PrologEx.PropertyTest do
  # Zufallstests ohne externe Abhängigkeit (eigener Generator über :rand).
  use ExUnit.Case, async: true
  import PrologEx

  @runs 2000

  # ---------------------------------------------------------------------
  # Generator
  # ---------------------------------------------------------------------

  # Baut Terme ausschließlich über die öffentlichen Konstruktoren, und zwar
  # absichtlich auch über s(".", ...) und a("[]") – die müssen kanonisieren.
  defp gen_term(vars, depth) do
    case :rand.uniform(if depth <= 0, do: 4, else: 9) do
      1 -> Enum.random(vars)
      2 -> a(Enum.random(["a", "b", "[]"]))
      3 -> :rand.uniform(3) - 1
      4 -> Enum.random(vars)
      5 -> s("f", [gen_term(vars, depth - 1)])
      6 -> s("g", [gen_term(vars, depth - 1), gen_term(vars, depth - 1)])
      7 -> s(".", [gen_term(vars, depth - 1), gen_term(vars, depth - 1)])
      8 -> list([gen_term(vars, depth - 1)], gen_term(vars, depth - 1))
      9 -> list([gen_term(vars, depth - 1), gen_term(vars, depth - 1)])
    end
  end

  # Linearer Term: jede Variable höchstens einmal. Mit einem linearen Ziel
  # entstehen auch ohne Occurs-Check keine zyklischen Terme.
  defp linearize(t) do
    {t, _} = lin(t, 0)
    t
  end

  defp lin({:var, _}, i), do: {v("X#{i}"), i + 1}

  defp lin({:struct, f, args}, i) do
    {args, i} = Enum.map_reduce(args, i, &lin/2)
    {{:struct, f, args}, i}
  end

  defp lin([h | t], i) do
    {h, i} = lin(h, i)
    {t, i} = lin(t, i)
    {[h | t], i}
  end

  defp lin(t, i), do: {t, i}

  # ---------------------------------------------------------------------
  # Kanonische Form
  # ---------------------------------------------------------------------

  # Kanonisch heißt: kein '.'/2-Tupel, kein {:atom, "[]"}, keine 0-stellige
  # Struktur, UND: jeder variablenfreie zusammengesetzte Term ist markiert,
  # und markierte Terme enthalten nur markierte/atomare Teilterme.
  defp canonical?({:struct, ".", [_, _]}), do: false
  defp canonical?({:struct, _, []}), do: false
  defp canonical?({:atom, "[]"}), do: false

  defp canonical?({:struct, _, args} = t),
    do: not ground_unmarked?(t) and Enum.all?(args, &canonical?/1)

  defp canonical?([h | tl] = t),
    do: not ground_unmarked?(t) and canonical?(h) and canonical?(tl)

  defp canonical?({:gstruct, f, args}),
    do: f != "." and args != [] and Enum.all?(args, &marked_inner?/1)

  defp canonical?({:glist, [_ | _] = l}), do: glist_chain?(l)
  defp canonical?({:glist, _}), do: false
  defp canonical?(_), do: true

  defp ground_unmarked?(t), do: PrologEx.Compiler.ground?(t)

  # Teilterm eines markierten Terms: atomar oder selbst kanonisch markiert
  defp marked_inner?({:var, _}), do: false
  defp marked_inner?({:struct, _, _}), do: false
  defp marked_inner?([_ | _]), do: false
  defp marked_inner?(t), do: canonical?(t)

  # roh verkettete Rest-Zellen, Elemente markiert/atomar, Ende kein glist
  defp glist_chain?([h | t]), do: marked_inner?(h) and glist_chain?(t)
  defp glist_chain?({:glist, _}), do: false
  defp glist_chain?(t), do: marked_inner?(t)

  # ---------------------------------------------------------------------
  # Referenz-Unifikation (naiv, mit Occurs-Check)
  # ---------------------------------------------------------------------

  defp ref_walk({:var, _} = x, s) do
    case Map.fetch(s, x) do
      {:ok, t} -> ref_walk(t, s)
      :error -> x
    end
  end

  defp ref_walk(t, _), do: t

  defp ref_unify(x, y, s) do
    x = ref_walk(x, s)
    y = ref_walk(y, s)

    cond do
      x == y -> {:ok, s}
      match?({:var, _}, x) -> ref_bind(x, y, s)
      match?({:var, _}, y) -> ref_bind(y, x, s)
      true -> ref_args(ref_parts(x), ref_parts(y), s)
    end
  end

  defp ref_bind(var, t, s),
    do: if(ref_occurs?(var, t, s), do: :occurs, else: {:ok, Map.put(s, var, t)})

  defp ref_occurs?(var, t, s) do
    case ref_walk(t, s) do
      ^var -> true
      {:struct, _, args} -> Enum.any?(args, &ref_occurs?(var, &1, s))
      [h | tl] -> ref_occurs?(var, h, s) or ref_occurs?(var, tl, s)
      _ -> false
    end
  end

  # Zerlegung als (Funktor, Argumente) – unabhängig von der Darstellung
  defp ref_parts({:struct, f, args}), do: {f, args}
  defp ref_parts([h | t]), do: {".", [h, t]}
  defp ref_parts(t), do: {:atomic, t}

  defp ref_args({f, xs}, {f, ys}, s) when length(xs) == length(ys) do
    Enum.zip(xs, ys)
    |> Enum.reduce_while({:ok, s}, fn {x, y}, {:ok, s} ->
      case ref_unify(x, y, s) do
        {:ok, s} -> {:cont, {:ok, s}}
        other -> {:halt, other}
      end
    end)
  end

  defp ref_args(_, _, _), do: :error

  defp ref_resolve(t, s) do
    case ref_walk(t, s) do
      {:struct, f, args} -> {:struct, f, Enum.map(args, &ref_resolve(&1, s))}
      [h | tl] -> [ref_resolve(h, s) | ref_resolve(tl, s)]
      other -> other
    end
  end

  # Variablen in Reihenfolge des ersten Auftretens durchnummerieren, damit
  # Ergebnisse unabhängig von internen Variablennamen vergleichbar sind.
  defp normalize(t) do
    {t, _} = norm(t, %{})
    t
  end

  defp norm({:var, _} = x, m) do
    case Map.fetch(m, x) do
      {:ok, i} ->
        {{:v, i}, m}

      :error ->
        i = map_size(m)
        {{:v, i}, Map.put(m, x, i)}
    end
  end

  defp norm({:struct, f, args}, m) do
    {args, m} = Enum.map_reduce(args, m, &norm/2)
    {{:struct, f, args}, m}
  end

  defp norm([h | t], m) do
    {h, m} = norm(h, m)
    {t, m} = norm(t, m)
    {[h | t], m}
  end

  defp norm(t, m), do: {t, m}

  defp vars_in({:var, _} = x), do: [x]
  defp vars_in({:struct, _, args}), do: Enum.flat_map(args, &vars_in/1)
  defp vars_in([h | t]), do: vars_in(h) ++ vars_in(t)
  defp vars_in(_), do: []

  # ---------------------------------------------------------------------
  # Eigenschaften
  #
  # Alle Eigenschaften laufen zweimal: normal und mit Kompaktierung bei
  # jedem Schritt (dabei werden Terme nachträglich als ground markiert).
  # ---------------------------------------------------------------------

  defp q(db, goal), do: query(db, goal, compact_threshold: Process.get(:threshold, 4096))

  setup context do
    :rand.seed(:exsss, {1, 2, 3})
    Process.put(:threshold, context[:threshold] || 4096)
    :ok
  end

  defp lin_anon({:var, "_"}, i), do: {v({:anon, i}), i + 1}

  defp lin_anon({:struct, f, args}, i) do
    {args, i} = Enum.map_reduce(args, i, &lin_anon/2)
    {{:struct, f, args}, i}
  end

  defp lin_anon([h | t], i) do
    {h, i} = lin_anon(h, i)
    {t, i} = lin_anon(t, i)
    {[h | t], i}
  end

  defp lin_anon(t, i), do: {t, i}

  # Ground-Term (markiert) und daraus ein Muster: zufällige Teilterme
  # durch frische Variablen ersetzt, Rest roh (unmarkiert) nachgebaut.
  defp gen_ground(depth), do: gen_term([a("z"), 7], depth)

  defp punch(t, i) do
    if i < 6 and :rand.uniform(4) == 1 do
      x = v("P#{i}")
      {x, i + 1, [{x, t}]}
    else
      case uncons(t) do
        {:cons, h, tl} ->
          {h, i, b1} = punch(h, i)
          {tl, i, b2} = punch(tl, i)
          {[h | tl], i, b1 ++ b2}

        _ ->
          case t do
            {tag, f, args} when tag in [:struct, :gstruct] ->
              {args, {i, bs}} =
                Enum.map_reduce(args, {i, []}, fn arg, {i, bs} ->
                  {arg, i, b} = punch(arg, i)
                  {arg, {i, bs ++ b}}
                end)

              {{:struct, f, args}, i, bs}

            _ ->
              {t, i, []}
          end
      end
    end
  end

  for th <- [4096, 1] do
    @tag threshold: th
    test "Konstruktoren liefern immer kanonische Terme [Schwelle #{th}]" do
      for _ <- 1..@runs do
        t = gen_term([v("X"), v("Y")], 4)
        assert canonical?(t), "nicht kanonisch: #{inspect(t)}"
      end
    end

    # Kopf p(H) gegen Ziel p(G): Der Interpreter muss genau dann Erfolg haben,
    # wenn die Referenz-Unifikation Erfolg hat, und G gleich instanziieren.
    # Mehrfache Variablen im Kopf testen den Fall "zweites Vorkommen".
    @tag threshold: th
    test "Klauselkopf-Unifikation stimmt mit Referenz überein [Schwelle #{th}]" do
      head_vars = [v("A"), v("B"), v("C")]

      checked =
        for _ <- 1..@runs, reduce: 0 do
          n ->
            h = gen_term(head_vars, 3)
            g = linearize(gen_term([v("_")], 3))
            db = consult([fact(s("p", [h]))])
            gvars = vars_in(unmark(g))

            case ref_unify(unmark(g), unmark(h), %{}) do
              :occurs ->
                n

              :error ->
                assert Enum.take(q(db, s("p", [g])), 1) == [],
                       "Interpreter erfolgreich, Referenz nicht: #{format(h)} = #{format(g)}"

                n + 1

              {:ok, rs} ->
                assert [ans] = Enum.take(q(db, s("p", [g])), 1),
                       "Interpreter scheitert: #{format(h)} = #{format(g)}"

                mine = normalize(Enum.map(gvars, fn {:var, name} -> ans[name] end))
                ref = normalize(Enum.map(gvars, &ref_resolve(&1, rs)))
                assert mine == ref, "verschieden bei #{format(h)} = #{format(g)}"
                # Antworten werden ohne Markierungen ausgeliefert
                assert mine == unmark(mine)
                n + 1
            end
        end

      # sicherstellen, dass nicht fast alles übersprungen wurde
      assert checked > @runs * 0.9
    end

    # Regel p(H, R) :- R = T. T enthält Kopfvariablen (Slots) und reine
    # Rumpfvariablen (frisch). Erwartet: G = H unifiziert, R = Instanz von T.
    @tag threshold: th
    test "Rumpf-Instanziierung stimmt mit Referenz überein [Schwelle #{th}]" do
      head_vars = [v("A"), v("B"), v("C")]
      body_vars = head_vars ++ [v("D"), v("E"), v("_")]

      for _ <- 1..@runs do
        h = gen_term(head_vars, 3)
        t = gen_term(body_vars, 3)
        g = linearize(gen_term([v("_")], 3))
        r = v("R")
        db = consult([rule(s("p", [h, r]), [s("=", [r, t])])])
        qvars = vars_in(unmark(g)) ++ [r]

        case ref_unify(unmark(g), unmark(h), %{}) do
          :occurs ->
            :skip

          :error ->
            assert Enum.take(q(db, s("p", [g, r])), 1) == []

          {:ok, rs} ->
            # "_" im Rumpf ist bei jedem Vorkommen eine eigene Variable
            {t_ref, _} = lin_anon(unmark(t), 0)
            rs = Map.put(rs, r, t_ref)
            assert [ans] = Enum.take(q(db, s("p", [g, r])), 1)
            mine = normalize(Enum.map(qvars, fn {:var, name} -> ans[name] end))
            ref = normalize(Enum.map(qvars, &ref_resolve(&1, rs)))
            assert mine == ref, "verschieden bei p(#{format(h)}, R) :- R = #{format(t)}"
        end
      end
    end

    # Mehrere Gleichungen nacheinander: Variablen werden schrittweise
    # gebunden. Mit Schwelle 1 wird zwischen allen Schritten kompaktiert –
    # ein fälschlich als ground markierter Term würde spätere Bindungen
    # verschlucken.
    # Markierung muss unsichtbar sein: markierter ground Term gegen
    # rohes Muster mit Löchern, in beiden Richtungen und als Klauselkopf.
    @tag threshold: th
    test "markierte Terme passen auf rohe Muster [Schwelle #{th}]" do
      for _ <- 1..@runs do
        g = gen_ground(4)
        {pat, _, holes} = punch(g, 0)
        expected = Enum.map(holes, fn {{:var, n}, t} -> {n, unmark(t)} end) |> Map.new()

        db = consult([fact(s("p", [g])), fact(s("r", [pat]))])

        for goal <- [s("=", [g, pat]), s("=", [pat, g]), s("p", [pat])] do
          assert [ans] = Enum.take(q(db, goal), 1), "scheitert: #{format(goal)}"
          assert ans == expected, "falsche Bindung: #{format(goal)}"
        end

        # Kopf mit Löchern, Ziel markiert ground
        assert [_] = Enum.take(q(db, s("r", [g])), 1), "scheitert: r(#{format(g)})"
      end
    end

    @tag threshold: th
    test "Gleichungsketten stimmen mit Referenz überein [Schwelle #{th}]" do
      db = consult([fact(s("dummy", [0]))])
      vars = [v("A"), v("B"), v("C"), v("D")]

      for _ <- 1..@runs do
        eqs =
          for _ <- 1..4 do
            {Enum.random(vars), gen_term(vars, 3)}
          end

        goal = conj(Enum.map(eqs, fn {x, t} -> s("=", [x, t]) end))

        ref =
          Enum.reduce_while(eqs, {:ok, %{}}, fn {x, t}, {:ok, rs} ->
            case ref_unify(x, unmark(t), rs) do
              {:ok, rs} -> {:cont, {:ok, rs}}
              other -> {:halt, other}
            end
          end)

        case ref do
          :occurs ->
            :skip

          :error ->
            assert Enum.take(q(db, goal), 1) == []

          {:ok, rs} ->
            assert [ans] = Enum.take(q(db, goal), 1),
                   "Interpreter scheitert: #{format(goal)}"

            qv = goal |> unmark() |> vars_in() |> Enum.uniq()
            mine = normalize(Enum.map(qv, fn {:var, n} -> ans[n] end))

            assert mine == normalize(Enum.map(qv, &ref_resolve(&1, rs))),
                   "verschieden bei #{format(goal)}"
        end
      end
    end

    @tag threshold: th
    test "=/2 stimmt mit Referenz überein [Schwelle #{th}]" do
      db = consult([fact(s("dummy", [0]))])

      for _ <- 1..@runs do
        x = linearize(gen_term([v("_")], 3))
        y = gen_term([v("A"), v("B")], 3)
        xvars = vars_in(unmark(x))

        case ref_unify(unmark(x), unmark(y), %{}) do
          :occurs ->
            :skip

          :error ->
            assert Enum.take(q(db, s("=", [x, y])), 1) == []

          {:ok, rs} ->
            assert [ans] = Enum.take(q(db, s("=", [x, y])), 1)
            mine = normalize(Enum.map(xvars, fn {:var, name} -> ans[name] end))
            assert mine == normalize(Enum.map(xvars, &ref_resolve(&1, rs)))
        end
      end
    end
  end
end
