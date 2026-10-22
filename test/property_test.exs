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

  defp canonical?({:struct, ".", [_, _]}), do: false
  defp canonical?({:struct, _, []}), do: false
  defp canonical?({:struct, _, args}), do: Enum.all?(args, &canonical?/1)
  defp canonical?({:atom, "[]"}), do: false
  defp canonical?([h | t]), do: canonical?(h) and canonical?(t)
  defp canonical?(_), do: true

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
    do: if(occurs?(var, t, s), do: :occurs, else: {:ok, Map.put(s, var, t)})

  defp occurs?(var, t, s) do
    case ref_walk(t, s) do
      ^var -> true
      {:struct, _, args} -> Enum.any?(args, &occurs?(var, &1, s))
      [h | tl] -> occurs?(var, h, s) or occurs?(var, tl, s)
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
  # ---------------------------------------------------------------------

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  test "Konstruktoren liefern immer kanonische Terme" do
    for _ <- 1..@runs do
      t = gen_term([v("X"), v("Y")], 4)
      assert canonical?(t), "nicht kanonisch: #{inspect(t)}"
    end
  end

  # Kopf p(H) gegen Ziel p(G): Der Interpreter muss genau dann Erfolg haben,
  # wenn die Referenz-Unifikation Erfolg hat, und G gleich instanziieren.
  # Mehrfache Variablen im Kopf testen den Fall "zweites Vorkommen".
  test "Klauselkopf-Unifikation stimmt mit Referenz überein" do
    head_vars = [v("A"), v("B"), v("C")]

    checked =
      for _ <- 1..@runs, reduce: 0 do
        n ->
          h = gen_term(head_vars, 3)
          g = linearize(gen_term([v("_")], 3))
          db = consult([fact(s("p", [h]))])
          gvars = vars_in(g)

          case ref_unify(g, h, %{}) do
            :occurs ->
              n

            :error ->
              assert Enum.take(query(db, s("p", [g])), 1) == [],
                     "Interpreter erfolgreich, Referenz nicht: #{format(h)} = #{format(g)}"

              n + 1

            {:ok, rs} ->
              assert [ans] = Enum.take(query(db, s("p", [g])), 1),
                     "Interpreter scheitert: #{format(h)} = #{format(g)}"

              mine = normalize(Enum.map(gvars, fn {:var, name} -> ans[name] end))
              ref = normalize(Enum.map(gvars, &ref_resolve(&1, rs)))
              assert mine == ref, "verschieden bei #{format(h)} = #{format(g)}"
              assert canonical?(mine)
              n + 1
          end
      end

    # sicherstellen, dass nicht fast alles übersprungen wurde
    assert checked > @runs * 0.9
  end

  # Regel p(H, R) :- R = T. T enthält Kopfvariablen (Slots) und reine
  # Rumpfvariablen (frisch). Erwartet: G = H unifiziert, R = Instanz von T.
  test "Rumpf-Instanziierung stimmt mit Referenz überein" do
    head_vars = [v("A"), v("B"), v("C")]
    body_vars = head_vars ++ [v("D"), v("E"), v("_")]

    for _ <- 1..@runs do
      h = gen_term(head_vars, 3)
      t = gen_term(body_vars, 3)
      g = linearize(gen_term([v("_")], 3))
      r = v("R")
      db = consult([rule(s("p", [h, r]), [s("=", [r, t])])])
      qvars = vars_in(g) ++ [r]

      case ref_unify(g, h, %{}) do
        :occurs ->
          :skip

        :error ->
          assert Enum.take(query(db, s("p", [g, r])), 1) == []

        {:ok, rs} ->
          # "_" im Rumpf ist bei jedem Vorkommen eine eigene Variable
          {t_ref, _} = lin_anon(t, 0)
          rs = Map.put(rs, r, t_ref)
          assert [ans] = Enum.take(query(db, s("p", [g, r])), 1)
          mine = normalize(Enum.map(qvars, fn {:var, name} -> ans[name] end))
          ref = normalize(Enum.map(qvars, &ref_resolve(&1, rs)))
          assert mine == ref, "verschieden bei p(#{format(h)}, R) :- R = #{format(t)}"
      end
    end
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

  test "=/2 stimmt mit Referenz überein" do
    db = consult([fact(s("dummy", [0]))])

    for _ <- 1..@runs do
      x = linearize(gen_term([v("_")], 3))
      y = gen_term([v("A"), v("B")], 3)
      xvars = vars_in(x)

      case ref_unify(x, y, %{}) do
        :occurs ->
          :skip

        :error ->
          assert Enum.take(query(db, s("=", [x, y])), 1) == []

        {:ok, rs} ->
          assert [ans] = Enum.take(query(db, s("=", [x, y])), 1)
          mine = normalize(Enum.map(xvars, fn {:var, name} -> ans[name] end))
          assert mine == normalize(Enum.map(xvars, &ref_resolve(&1, rs)))
      end
    end
  end
end
