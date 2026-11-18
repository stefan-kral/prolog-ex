defmodule PrologEx.ClauseCode do
  @moduledoc """
  Klauseln als BEAM-Code (für oft gerufene Prädikate): je Kopf eine
  Funktion, die dasselbe tut wie `PrologEx.match_args/6` mit den Mustern
  der Klausel, und je Rumpf eine, die dasselbe tut wie
  `PrologEx.inst_goals/6` mit den Vorlagen – nur ohne Muster und Vorlagen
  zur Laufzeit zu durchlaufen.

  Kopf `c_j(args, s, nv, mode)`: Ergebnis wie match_args/6
  (`{:ok, env, s, nv}` oder `:error`), dazu `:interp` – dann übernimmt der
  Interpreter die ganze Klausel (Schreibmodus in einem geschachtelten
  Muster, selten). Kopfvariablen (Slots) sind Variablen des Codes; das
  Umfeld (Tupel der Slots) entsteht erst am Ende, statt je Slot kopiert zu
  werden.

  Listen- und Strukturmuster auf oberster Ebene verzweigen (Lesemodus:
  zerlegen; Schreibmodus: bauen und binden wie der Interpreter). Damit der
  Rest des Kopfs nicht in beiden Zweigen steht, geht es danach in einer
  eigenen Funktion `k_N` weiter, die beide Zweige rufen.

  Rumpf `b_j(env, base, barrier, mod, rest)`: die Zielliste. Ob ein
  gebauter Teilterm ground markiert wird (`PrologEx.mk_struct/2`,
  `PrologEx.cons/2`), steht meist schon beim Übersetzen fest; nur mit
  Slots darin zur Laufzeit.

  Erzeugt wird Erlang-Abstraktcode (`:compile.forms/2`): ohne den
  Elixir-Compiler davor – der kostete ein Mehrfaches.
  """

  @pex :"Elixir.PrologEx"
  @store :"Elixir.PrologEx.Store"

  @doc """
  Die Klauseln eines Prädikats (`{:pred, ...}`) übersetzt: das Prädikat
  zurück, jede Klausel mit `{Kopf, Rumpf}` im 8. Feld (Rumpf nil für
  Fakten, Kopf nil, wo er sich nicht lohnt). Klauseln, die schon Code
  haben, bleiben.
  """
  def attach(pred) do
    {cls, big} = pred |> collect(%{}) |> Map.keys() |> Enum.split_with(&small?/1)

    heads =
      cls
      |> Enum.map(&{elem(&1, 2), elem(&1, 3)})
      |> Enum.filter(&worth?/1)
      |> Enum.uniq()
      |> Enum.with_index()

    bodies =
      cls
      |> Enum.map(&elem(&1, 5))
      |> Enum.reject(&(&1 == []))
      |> Enum.uniq()
      |> Enum.with_index()

    # (sha256: phash2 trifft zu oft dasselbe – #(0,1,0) und #(0,0,1,0))
    hash = :crypto.hash(:sha256, :erlang.term_to_binary({heads, bodies}))
    name = :"Elixir.PrologEx.CC#{binary_part(Base.encode16(hash, case: :lower), 0, 20)}"

    if :erlang.module_loaded(name) or load(name, heads, bodies) do
      hnum = Map.new(heads)
      bnum = Map.new(bodies)

      repl =
        Map.new(cls, fn c ->
          h =
            case Map.fetch(hnum, {elem(c, 2), elem(c, 3)}) do
              {:ok, j} -> Function.capture(name, :"c#{j}", 4)
              :error -> nil
            end

          b =
            case Map.fetch(bnum, elem(c, 5)) do
              {:ok, j} -> Function.capture(name, :"b#{j}", 5)
              :error -> nil
            end

          {c, put_elem(c, 7, {h, b})}
        end)

      # zu große bleiben beim Interpreter (ohne weiter zu zählen)
      repl = Enum.reduce(big, repl, &Map.put(&2, &1, put_elem(&1, 7, nil)))
      replace(pred, repl)
    else
      # ließ sich nicht übersetzen: Interpreter, ohne weiter zu zählen
      replace(pred, Map.new(cls ++ big, &{&1, put_elem(&1, 7, nil)}))
    end
  end

  # Lohnt ein übersetzter Kopf? Nicht bei nur Konstanten, anonymen und
  # wenigen Variablen auf oberster Ebene (Fakten wie p(1)): das macht
  # match_args/6 schon direkt, der Aufruf über die Funktion kostete mehr
  defp worth?({nslots, pats}), do: nslots > 2 or Enum.any?(pats, &(not simple?(&1)))

  defp simple?(:void), do: true
  defp simple?({:first, _}), do: true
  defp simple?({:const, _}), do: true
  defp simple?(_), do: false

  # Grenzen: der BEAM-Compiler braucht für tief geschachtelten Code
  # überproportional lange, Funktionen haben höchstens 255 Parameter (die
  # Fortsetzungen nehmen die Slots)
  @max_nodes 400
  @max_slots 100

  defp small?({:clause, _, nslots, pats, _, tmpls, _, _}),
    do: nslots <= @max_slots and nodes(pats, 0) <= @max_nodes and nodes(tmpls, 0) <= @max_nodes

  # Knoten in Mustern und Vorlagen (Literale je einer), ab der Grenze nicht
  # weiter gezählt
  defp nodes(_, n) when n > @max_nodes, do: n
  defp nodes([x | xs], n), do: nodes(xs, nodes(x, n))
  defp nodes({:list, h, t}, n), do: nodes(t, nodes(h, n + 1))
  defp nodes({:struct, _, _, ps}, n), do: nodes(ps, n + 1)
  defp nodes({:t_list, h, t}, n), do: nodes(t, nodes(h, n + 1))
  defp nodes({:t_struct, _, as}, n), do: nodes(as, n + 1)
  defp nodes({:t_arith, _, o, _, ls}, n), do: nodes(ls, nodes(o, n + 1))
  # (große Literale: der Compiler geht auch sie durch)
  defp nodes({tag, c}, n) when tag in [:ground, :t_lit],
    do: n + 1 + div(:erts_debug.flat_size(c), 8)

  defp nodes([], n), do: n
  defp nodes(_, n), do: n + 1

  defp collect({:clause, _, _, _, _, _, _, {h, _}}, acc) when is_function(h), do: acc
  defp collect({:clause, _, _, _, _, _, _, _} = c, acc), do: Map.put(acc, c, true)
  defp collect(t, acc) when is_tuple(t), do: collect(Tuple.to_list(t), acc)
  defp collect([x | xs], acc), do: collect(xs, collect(x, acc))
  defp collect(m, acc) when is_map(m), do: collect(Map.values(m), acc)
  defp collect(_, acc), do: acc

  defp replace({:clause, _, _, _, _, _, _, _} = c, r), do: Map.get(r, c, c)
  defp replace(t, r) when is_tuple(t), do: t |> Tuple.to_list() |> replace(r) |> List.to_tuple()
  defp replace([x | xs], r), do: [replace(x, r) | replace(xs, r)]
  defp replace(m, r) when is_map(m), do: Map.new(m, fn {k, v} -> {k, replace(v, r)} end)
  defp replace(x, _), do: x

  # der Code ist schlicht: die Optimierungen lohnen ihre Zeit nicht
  @opts [:no_ssa_opt, :no_bool_opt, :no_share_opt, :no_recv_opt, :no_type_opt, :no_module_opt]

  # übersetzen und laden; false, wenn der Compiler scheitert
  defp load(name, heads, bodies) do
    with {:ok, ^name, bin} <- :compile.forms(forms(name, heads, bodies), [:binary | @opts]),
         {:module, ^name} <- :code.load_binary(name, ~c"clause_code", bin) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc "Abstraktcode des Moduls `name` (Köpfe `{{nslots, pats}, j}`, Rümpfe `{templates, j}`)"
  def forms(name, heads, bodies) do
    {hfuns, _} =
      Enum.flat_map_reduce(heads, 0, fn {{nslots, pats}, j}, n ->
        {main, st} = head_fun(:"c#{j}", nslots, pats, n)
        {[main | st.fns], st.n}
      end)

    bfuns = for {b, j} <- bodies, do: body_fun(:"b#{j}", b)

    exports =
      for({_, j} <- heads, do: {:"c#{j}", 4}) ++ for({_, j} <- bodies, do: {:"b#{j}", 5})

    [{:attribute, 0, :module, name}, {:attribute, 0, :export, exports} | hfuns ++ bfuns]
  end

  # --- Kopf -------------------------------------------------------------

  defp head_fun(fname, nslots, pats, n) do
    st = %{fns: [], n: n, nslots: nslots}
    args = for i <- 0..(length(pats) - 1)//1, do: v(:"A#{i}")
    ctx = %{slots: [], s: v(:S), nv: v(:NV)}
    work = for {p, x} <- Enum.zip(pats, args), do: {:m, p, x, true}
    {body, st} = gen(work, ctx, st)

    fun =
      {:function, 0, fname, 4,
       [
         {:clause, 0, [list(args, {nil, 0}), v(:S), v(:NV), v(:Mode)], [], body},
         {:clause, 0, [v(:_), v(:_), v(:_), v(:_)], [], [a(:error)]}
       ]}

    {fun, st}
  end

  # gen(Arbeit, ctx, st) -> {Ausdrücke, st}. Arbeit: Liste von {:m, Muster,
  # Variable, oberste Ebene?} und am Ende evtl. {:jump, Name, Slots,
  # Variablen} (Aufruf einer Fortsetzung). ctx.slots: die schon belegten
  # Slots (Slot i steht immer in der Variablen X_i). Jede Variable wird
  # auf einem Pfad nur einmal gebunden (in Erlang wäre ein zweites Mal ein
  # Vergleich).

  defp gen([], ctx, st), do: {[tup([a(:ok), env(ctx.slots, st), ctx.s, ctx.nv])], st}

  defp gen([{:jump, name, slots, vars}], ctx, st),
    do: {[lcall(name, Enum.map(slots, &slot/1) ++ vars ++ [ctx.s, ctx.nv, v(:Mode)])], st}

  defp gen([{:m, :void, _, _} | rest], ctx, st), do: gen(rest, ctx, st)

  defp gen([{:m, {:first, i}, t, _} | rest], ctx, st) do
    {code, st} = gen(rest, %{ctx | slots: [i | ctx.slots]}, st)
    {[{:match, 0, slot(i), t} | code], st}
  end

  defp gen([{:m, {:val, i}, t, _} | rest], ctx, st) do
    {s2, st} = fresh(st)
    {code, st} = gen(rest, %{ctx | s: s2}, st)

    {[
       case_(rcall(@pex, :unify, [slot(i), t, ctx.s, v(:Mode)]), [
         {:clause, 0, [tup([a(:ok), s2])], [], code},
         {:clause, 0, [v(:_)], [], [a(:error)]}
       ])
     ], st}
  end

  defp gen([{:m, {:const, c}, t, _} | rest], ctx, st),
    do: gen_subst(rcall(@pex, :cc_const, [t, lit(c), ctx.s]), rest, ctx, st)

  defp gen([{:m, {:ground, c}, t, _} | rest], ctx, st),
    do: gen_subst(rcall(@pex, :cc_ground, [t, lit(c), ctx.s, v(:Mode)]), rest, ctx, st)

  # geschachtelt: im Schreibmodus :interp – so verzweigt nur die oberste
  # Ebene, und der Code bleibt klein (jeder Schreibzweig trägt sein Muster
  # als Literal)
  defp gen([{:m, {:list, ph, pt}, t, false} | rest], ctx, st) do
    {h, st} = fresh(st)
    {tl, st} = fresh(st)
    {read, st} = gen([{:m, ph, h, false}, {:m, pt, tl, false} | rest], ctx, st)
    {[list_case(t, ctx, h, tl, read, [a(:interp)], v(:_))], st}
  end

  defp gen([{:m, {:struct, f, n, ps}, t, false} | rest], ctx, st) do
    {ys, st} = Enum.map_reduce(1..n, st, fn _, st -> fresh(st) end)
    {tag, st} = fresh(st)
    {read, st} = gen(Enum.zip_with(ps, ys, &{:m, &1, &2, false}) ++ rest, ctx, st)
    {[struct_case(t, ctx, tag, f, ys, read, [a(:interp)], v(:_))], st}
  end

  defp gen([{:m, {:list, ph, pt} = p, t, true} | rest], ctx, st) do
    {h, st} = fresh(st)
    {tl, st} = fresh(st)
    {var, st} = fresh(st)
    {jump, st} = cont(rest, slots_after(p, ctx.slots), st)
    {read, st} = gen([{:m, ph, h, false}, {:m, pt, tl, false} | jump], ctx, st)
    {write, st} = gen_write(p, var, jump, ctx, st)
    {[list_case(t, ctx, h, tl, read, write, var)], st}
  end

  defp gen([{:m, {:struct, f, n, ps} = p, t, true} | rest], ctx, st) do
    {ys, st} = Enum.map_reduce(1..n, st, fn _, st -> fresh(st) end)
    {tag, st} = fresh(st)
    {var, st} = fresh(st)
    {jump, st} = cont(rest, slots_after(p, ctx.slots), st)
    {read, st} = gen(Enum.zip_with(ps, ys, &{:m, &1, &2, false}) ++ jump, ctx, st)
    {write, st} = gen_write(p, var, jump, ctx, st)
    {[struct_case(t, ctx, tag, f, ys, read, write, var)], st}
  end

  # Aufruf, der die neue Bindung oder error liefert; weiter mit ihr
  defp gen_subst(call, rest, ctx, st) do
    {s2, st} = fresh(st)
    {code, st} = gen(rest, %{ctx | s: s2}, st)

    {[
       case_(call, [
         {:clause, 0, [a(:error)], [], [a(:error)]},
         {:clause, 0, [s2], [], code}
       ])
     ], st}
  end

  defp list_case(t, ctx, h, tl, read, write, var) do
    case_(rcall(@pex, :cc_list, [t, ctx.s]), [
      {:clause, 0, [{:cons, 0, h, tl}], [], read},
      {:clause, 0, [{:match, 0, tup([a(:var), v(:_)]), var}], [], write},
      {:clause, 0, [v(:_)], [], [a(:error)]}
    ])
  end

  defp struct_case(t, ctx, tag, f, ys, read, write, var) do
    guard = [[{:op, 0, :"=:=", tag, a(:struct)}], [{:op, 0, :"=:=", tag, a(:gstruct)}]]

    case_(rcall(@store, :walk, [t, ctx.s]), [
      {:clause, 0, [tup([tag, lit(f), list(ys, {nil, 0})])], guard, read},
      {:clause, 0, [{:match, 0, tup([a(:var), v(:_)]), var}], [], write},
      {:clause, 0, [v(:_)], [], [a(:error)]}
    ])
  end

  # Schreibmodus (die ungebundene Variable in var): bauen und binden wie
  # der Interpreter (PrologEx.cc_write/6, mit dem Umfeld bis hier), dann
  # die neu belegten Slots aus dem Umfeld
  defp gen_write(p, var, jump, ctx, st) do
    {s2, st} = fresh(st)
    {nv2, st} = fresh(st)
    {e, st} = fresh(st)
    after_ = slots_after(p, ctx.slots)
    {code, st} = gen(jump, %{ctx | s: s2, nv: nv2, slots: after_}, st)

    gets =
      for i <- Enum.uniq(after_ -- ctx.slots),
          do: {:match, 0, slot(i), rcall(:erlang, :element, [int(i + 1), e])}

    call = rcall(@pex, :cc_write, [var, lit(p), env(ctx.slots, st), ctx.s, ctx.nv, v(:Mode)])

    {[
       case_(call, [
         {:clause, 0, [tup([a(:ok), e, s2, nv2])], [], gets ++ code},
         {:clause, 0, [v(:_)], [], [a(:error)]}
       ])
     ], st}
  end

  # Fortsetzung nach einem verzweigenden Muster: [] (gleich das Ende), der
  # schon vorhandene Sprung oder ein neuer – der Rest in eigener Funktion
  # mit den belegten Slots und den Variablen, die er noch braucht
  defp cont([], _slots, st), do: {[], st}
  defp cont([{:jump, _, _, _}] = j, _slots, st), do: {j, st}

  defp cont(rest, slots, st) do
    name = :"k#{st.n}"
    st = %{st | n: st.n + 1}
    slots = slots |> Enum.uniq() |> Enum.sort()
    vars = rest_vars(rest)
    {body, st} = gen(rest, %{slots: slots, s: v(:S), nv: v(:NV)}, st)
    params = Enum.map(slots, &slot/1) ++ vars ++ [v(:S), v(:NV), v(:Mode)]
    fun = {:function, 0, name, length(params), [{:clause, 0, params, [], body}]}
    {[{:jump, name, slots, vars}], %{st | fns: [fun | st.fns]}}
  end

  defp rest_vars(rest) do
    rest
    |> Enum.flat_map(fn
      {:m, _, t, _} -> [t]
      {:jump, _, _, vs} -> vs
    end)
    |> Enum.uniq()
  end

  # Slots, die nach dem Muster belegt sind
  defp slots_after({:first, i}, sl), do: [i | sl]
  defp slots_after({:list, ph, pt}, sl), do: slots_after(pt, slots_after(ph, sl))
  defp slots_after({:struct, _, _, ps}, sl), do: Enum.reduce(ps, sl, &slots_after/2)
  defp slots_after(_, sl), do: sl

  # das Umfeld: Tupel der Slots (unbelegte nil)
  defp env(slots, st),
    do: tup(for i <- 0..(st.nslots - 1)//1, do: if(i in slots, do: slot(i), else: a(nil)))

  # --- Rumpf ------------------------------------------------------------

  defp body_fun(name, tmpls) do
    used = tmpls |> Enum.flat_map(&slots_in/1) |> Enum.uniq() |> Enum.sort()

    gets =
      for i <- used, do: {:match, 0, slot(i), rcall(:erlang, :element, [int(i + 1), v(:Env)])}

    goals =
      List.foldr(tmpls, v(:Rest), fn g, acc ->
        {t, _} = tm(g)
        {:cons, 0, tup([t, v(:Barrier), v(:Mod)]), acc}
      end)

    params = [v(:Env), v(:Base), v(:Barrier), v(:Mod), v(:Rest)]
    {:function, 0, name, 5, [{:clause, 0, params, [], gets ++ [goals]}]}
  end

  defp slots_in({:t_slot, i}), do: [i]
  defp slots_in({:t_list, h, t}), do: slots_in(h) ++ slots_in(t)
  defp slots_in({:t_struct, _, as}), do: Enum.flat_map(as, &slots_in/1)
  defp slots_in({:t_arith, _, out, _, ls}), do: Enum.flat_map([out | ls], &slots_in/1)
  defp slots_in(_), do: []

  # {Ausdruck, Art}: :ground (sicher ground markiert), :nonground (sicher
  # nicht) oder :unknown (erst zur Laufzeit)
  defp tm({:t_slot, i}), do: {slot(i), :unknown}
  defp tm({:t_fresh, j}), do: {tup([a(:var), {:op, 0, :+, v(:Base), int(j)}]), :nonground}

  defp tm({:t_lit, t}),
    do: {lit(t), if(PrologEx.cc_known_ground?(t), do: :ground, else: :nonground)}

  defp tm({:t_list, h, t}) do
    {ha, hk} = tm(h)
    {ta, tk} = tm(t)

    cond do
      hk == :nonground or tk == :nonground -> {{:cons, 0, ha, ta}, :nonground}
      hk == :ground and tk == :ground -> {rcall(@pex, :cons, [ha, ta]), :ground}
      true -> {rcall(@pex, :cons, [ha, ta]), :unknown}
    end
  end

  defp tm({:t_struct, f, args}) do
    {as, ks} = args |> Enum.map(&tm/1) |> Enum.unzip()

    cond do
      :nonground in ks ->
        {tup([a(:struct), lit(f), list(as, {nil, 0})]), :nonground}

      Enum.all?(ks, &(&1 == :ground)) ->
        {tup([a(:gstruct), lit(f), list(as, {nil, 0})]), :ground}

      true ->
        {rcall(@pex, :mk_struct, [lit(f), list(as, {nil, 0})]), :unknown}
    end
  end

  defp tm({:t_arith, :is, out, code, leaves}) do
    {o, _} = tm(out)
    ls = Enum.map(leaves, &elem(tm(&1), 0))
    arith = tup([a(:arith), lit(code)])
    {tup([a(:struct), lit("$is"), list([o, arith | ls], {nil, 0})]), :nonground}
  end

  defp tm({:t_arith, :cmp, nil, code, leaves}) do
    ls = Enum.map(leaves, &elem(tm(&1), 0))
    arith = tup([a(:arith), lit(code)])
    {tup([a(:struct), lit("$cmp"), list([arith | ls], {nil, 0})]), :nonground}
  end

  # --- Abstraktcode -----------------------------------------------------

  defp slot(i), do: v(:"X#{i}")
  defp v(n), do: {:var, 0, n}
  defp a(x), do: {:atom, 0, x}
  defp int(i), do: {:integer, 0, i}
  defp lit(t), do: :erl_parse.abstract(t)
  defp tup(xs), do: {:tuple, 0, xs}
  defp list(xs, tail), do: List.foldr(xs, tail, &{:cons, 0, &1, &2})
  defp case_(e, clauses), do: {:case, 0, e, clauses}
  defp rcall(m, f, as), do: {:call, 0, {:remote, 0, a(m), a(f)}, as}
  defp lcall(f, as), do: {:call, 0, a(f), as}
  defp fresh(st), do: {v(:"V#{st.n}"), %{st | n: st.n + 1}}
end
