defmodule PrologEx.Jit.Hints do
  @moduledoc false
  # Hinweise der Aufrufstellen auf die Modi (PrologEx.Jit, call_prefs/3):
  # wie das geladene Programm ein Prädikat ruft, dazu is-Deklarationen.

  alias PrologEx.Jit.Util

  # --- Hinweise der Aufrufstellen -------------------------------------------
  #
  # Für die Wahl unter offenen Modi (candidates/2): an jeder Aufrufstelle
  # eines Prädikats des Ladeschritts – auch in Klauseln, die selbst nicht
  # übersetzt werden – ist ein Argument Eingabe, wenn es dort gebunden ist
  # (ein Term: wenn alle seine Variablen es sind), Ausgabe, wenn es eine
  # freie Variable ist, sonst kein Hinweis. Der Zustand je Variable, die
  # Klausel entlang (clause_hints/5): eine Kopfvariable an einer
  # Eingabestelle des Rufers – oder in einem Kopfargument, das Eingabe ist
  # – ist gebunden, an einer Ausgabestelle frei, sonst unbekannt; eine
  # Variable, die erst im Rumpf vorkommt, frei; `V is E` bindet V, `X = T`
  # X nur, wenn T gebunden ist; functor/3, arg/3 und =../2 geben weiter,
  # was der Term ist; ein Aufruf bindet seine Variablen (in einer Struktur
  # übergeben: danach unbekannt), andere Ziele auch.
  #
  # Die Modi des Rufers: aus den eigenen Klauseln (wie evidence/4, ohne
  # Aufrufe), aus einer is-Deklaration (`:- p(+, -) is det.`) oder wieder
  # aus den Hinweisen – einige Runden. Je Stelle die Mehrheit; Gleichstand:
  # kein Hinweis; eine Deklaration geht den Aufrufstellen vor, die eigenen
  # Klauseln allem. Nur eine Reihenfolge: was eine Belegung übersetzbar
  # macht (Typen, Ausschluss), prüft solve_modes/7 wie zuvor. Ergebnis:
  # %{{key, k} => :in | :out}.
  def call_prefs(preds, parsed, decl) do
    batch = MapSet.new(for {k, _} <- preds, do: k)
    src = for {k, cls} <- preds, {h, b} <- cls, is_tuple(h), do: {k, Util.plain(h), Util.plain(b)}

    declared =
      for {key, ms} <- decl,
          MapSet.member?(batch, key),
          {k, m} <- ms,
          into: %{},
          do: {{key, k}, m}

    local = Map.merge(declared, local_modes(parsed))

    Enum.reduce_while(1..4, local, fn _, pref ->
      votes =
        src
        |> Enum.flat_map(fn {k, h, b} -> clause_hints(k, h, b, batch, pref) end)
        |> Enum.reduce(%{}, fn {pos, m}, acc ->
          Map.update(acc, pos, vote(m), &add_vote(&1, m))
        end)

      new = Map.merge(majority(votes), local)
      if new == pref, do: {:halt, new}, else: {:cont, new}
    end)
  catch
    # (unerwartete Formen: keine Hinweise, wie bisher)
    _, _ -> %{}
  end

  defp vote(:in), do: {1, 0}
  defp vote(:out), do: {0, 1}
  defp add_vote({i, o}, :in), do: {i + 1, o}
  defp add_vote({i, o}, :out), do: {i, o + 1}

  defp majority(votes) do
    for {pos, {i, o}} <- votes, i != o, into: %{}, do: {pos, if(i > o, do: :in, else: :out)}
  end

  # Modi aus den eigenen Klauseln (erste Verwendung einer Kopfvariablen),
  # ohne Aufrufe; widersprechen sie sich, keiner
  defp local_modes(parsed) do
    for {key, p} <- parsed,
        {head, goals} <- p.clauses,
        {a, k} <- Enum.with_index(head),
        match?({:var, _}, a),
        not Util.anon?(a),
        e = first_use(a, goals),
        e in [:in, :out],
        reduce: %{} do
      acc -> Map.update(acc, {key, k}, vote(e), &add_vote(&1, e))
    end
    |> Enum.flat_map(fn
      {pos, {i, 0}} when i > 0 -> [{pos, :in}]
      {pos, {0, o}} when o > 0 -> [{pos, :out}]
      _ -> []
    end)
    |> Map.new()
  end

  defp clause_hints(key, h, b, batch, pref) do
    hargs = Util.args(h)
    m = fn k -> Map.get(pref, {key, k}) end

    nested =
      for {a, i} <- Enum.with_index(hargs),
          not match?({:var, _}, a),
          v <- Enum.uniq(Util.raw_vars(a, [])),
          reduce: %{} do
        acc -> Map.update(acc, v, [i], &[i | &1])
      end

    vs0 =
      Map.new(nested, fn {v, ks} ->
        ms = Enum.map(ks, m)

        {v,
         cond do
           :in in ms -> :bound
           Enum.all?(ms, &(&1 == :out)) -> :free
           true -> :unknown
         end}
      end)

    vs =
      hargs
      |> Enum.with_index()
      |> Enum.reduce(vs0, fn
        {{:var, _} = v, i}, acc ->
          if Map.has_key?(acc, v) and acc[v] == :bound,
            do: acc,
            else: Map.put(acc, v, %{in: :bound, out: :free}[m.(i)] || :unknown)

        _, acc ->
          acc
      end)

    {hints, _} = body_hints(b, %{batch: batch, vs: vs})
    hints
  end

  defp body_hints({:struct, op, [a, b]}, st) when op in [",", "->", "*->"] do
    {h1, st} = body_hints(a, st)
    {h2, st} = body_hints(b, st)
    {h1 ++ h2, st}
  end

  defp body_hints({:struct, ";", [a, b]}, st) do
    {h1, s1} = body_hints(a, st)
    {h2, s2} = body_hints(b, st)

    # nach der Disjunktion: was beide Zweige gleich sehen, sonst unbekannt
    vs =
      for v <- Enum.uniq(Map.keys(s1.vs) ++ Map.keys(s2.vs)), into: %{} do
        x = vstate(v, s1)
        {v, if(x == vstate(v, s2), do: x, else: :unknown)}
      end

    {h1 ++ h2, %{st | vs: vs}}
  end

  defp body_hints({:struct, "\\+", [g]}, st) do
    {h, _} = body_hints(g, st)
    {h, st}
  end

  defp body_hints({:struct, ":", [_, g]}, st), do: body_hints(g, st)

  defp body_hints({:struct, "is", [{:var, _} = v, _]}, st), do: {[], bound(st, [v])}

  defp body_hints({:struct, "=", [x, y]}, st) do
    cond do
      match?({:var, _}, x) and vstate(x, st) != :bound and tstate(y, st) == :bound ->
        {[], bound(st, [x])}

      match?({:var, _}, y) and vstate(y, st) != :bound and tstate(x, st) == :bound ->
        {[], bound(st, [y])}

      match?({:var, _}, x) and vstate(x, st) != :bound ->
        {[], put_vs(st, x, :unknown)}

      match?({:var, _}, y) and vstate(y, st) != :bound ->
        {[], put_vs(st, y, :unknown)}

      true ->
        {[], st}
    end
  end

  defp body_hints({:struct, "functor", [t, n, a]}, st) do
    if tstate(t, st) == :bound,
      do: {[], bound(st, Util.raw_vars([n, a], []))},
      else: {[], if(match?({:var, _}, t), do: put_vs(st, t, :unknown), else: st)}
  end

  defp body_hints({:struct, "arg", [_, t, a]}, st) do
    cond do
      not match?({:var, _}, a) -> {[], st}
      tstate(t, st) == :bound -> {[], bound(st, [a])}
      true -> {[], put_vs(st, a, :unknown)}
    end
  end

  defp body_hints({:struct, "=..", [t, l]}, st) do
    if tstate(t, st) == :bound,
      do: {[], bound(st, Util.raw_vars(l, []))},
      else: {[], if(match?({:var, _}, t), do: put_vs(st, t, :unknown), else: st)}
  end

  defp body_hints({:struct, n, as} = g, st) do
    k = {n, length(as)}

    if MapSet.member?(st.batch, k) do
      hs = for {a, j} <- Enum.with_index(as), m = arg_mode(a, st), m != nil, do: {{k, j}, m}

      st =
        Enum.reduce(as, st, fn
          {:var, _} = v, st ->
            bound(st, [v])

          t, st ->
            Enum.reduce(
              Util.raw_vars(t, []),
              st,
              &if(vstate(&1, &2) == :bound, do: &2, else: put_vs(&2, &1, :unknown))
            )
        end)

      {hs, st}
    else
      {[], bound(st, Util.raw_vars(g, []))}
    end
  end

  defp body_hints(_, st), do: {[], st}

  defp vstate(v, st), do: Map.get(st.vs, v, :free)

  defp tstate({:var, _} = v, st), do: vstate(v, st)

  defp tstate(t, st) do
    if Enum.all?(Util.raw_vars(t, []), &(vstate(&1, st) == :bound)), do: :bound, else: :unknown
  end

  defp bound(st, vars), do: Enum.reduce(vars, st, &put_vs(&2, &1, :bound))
  defp put_vs(st, v, x), do: %{st | vs: Map.put(st.vs, v, x)}

  defp arg_mode({:var, _} = v, st) do
    case vstate(v, st) do
      :bound -> :in
      :free -> :out
      :unknown -> nil
    end
  end

  defp arg_mode(t, st), do: if(tstate(t, st) == :bound, do: :in)

  def evidence(scc, parsed, other) do
    ev =
      for key <- scc,
          {head, goals} <- parsed[key].clauses,
          {a, k} <- Enum.with_index(head),
          match?({:var, _}, a),
          not Util.anon?(a),
          e = first_use(a, goals),
          e not in [nil, :none] do
        case e do
          {:as, ck, j} -> if ck in scc, do: {{key, k}, e}, else: {{key, k}, other.(ck).modes[j]}
          _ -> {{key, k}, e}
        end
      end

    {m0, bad} =
      Enum.reduce(ev, {%{}, []}, fn
        {pos, e}, {m, bad} when e in [:in, :out] -> put_mode(m, pos, e, bad)
        _, acc -> acc
      end)

    case fix_modes(m0, ev, bad) do
      {m, []} -> {:ok, m}
      _ -> :no
    end
  end

  defp put_mode(m, pos, e, bad) do
    case m do
      %{^pos => ^e} -> {m, bad}
      %{^pos => _} -> {m, [pos | bad]}
      _ -> {Map.put(m, pos, e), bad}
    end
  end

  defp fix_modes(m, ev, bad) do
    {m2, bad2} =
      Enum.reduce(ev, {m, bad}, fn
        {pos, {:as, ck, j}}, {acc, bad} ->
          if Map.has_key?(acc, {ck, j}),
            do: put_mode(acc, pos, acc[{ck, j}], bad),
            else: {acc, bad}

        _, acc ->
          acc
      end)

    if m2 == m, do: {m, Enum.uniq(bad2)}, else: fix_modes(m2, ev, bad2)
  end

  # nil: kommt nicht vor; :none: kommt vor, legt aber nichts fest
  defp first_use(_v, []), do: nil
  defp first_use(v, [g | gs]), do: use_in(v, g) || first_use(v, gs)

  defp use_in(v, {:cmp, _, a, b}), do: if(v in (Util.vars(a) ++ Util.vars(b)), do: :in)

  defp use_in(v, {:is, l, r}) do
    cond do
      v in Util.vars(r) -> :in
      l == v -> :out
      true -> nil
    end
  end

  defp use_in(v, {:unify, a, b}), do: if(v in (Util.vars(a) ++ Util.vars(b)), do: :none)
  defp use_in(v, {:tt, _, x}), do: if(v == x, do: :in)
  defp use_in(v, {:idx, g}), do: use_in(v, g)
  defp use_in(v, {:teq, _, a, b}), do: if(v in (Util.vars(a) ++ Util.vars(b)), do: :in)
  defp use_in(v, {:tord, _, a, b}), do: if(v in (Util.vars(a) ++ Util.vars(b)), do: :in)

  defp use_in(v, {:bi, _, ins, outs}) do
    cond do
      v in Enum.flat_map(ins, &Util.vars/1) -> :in
      v in outs -> :out
      v in Enum.flat_map(outs, &Util.vars/1) -> :none
      true -> nil
    end
  end

  # nur die erste Lösung: eine Ausgabe des Gerufenen darf hier schon
  # bestimmt sein (dann ein Muster, nach dem gefiltert wird) – kein Hinweis
  defp use_in(v, {:callo, _ck, as}), do: if(v in Enum.flat_map(as, &Util.vars/1), do: :none)

  defp use_in(v, {:call, ck, as}) do
    case Enum.find_index(as, &(&1 == v)) do
      nil -> if v in Enum.flat_map(as, &Util.vars/1), do: :none
      j -> {:as, ck, j}
    end
  end

  defp use_in(v, {:ite, c, t, e}), do: first_use(v, c) || first_use(v, t) || first_use(v, e)
  defp use_in(v, {:not, g}), do: first_use(v, g)
  defp use_in(_, _), do: nil
end
