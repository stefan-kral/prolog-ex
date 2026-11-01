defmodule PrologEx.Builtins.Coroutining do
  @moduledoc """
  Coroutining wie SICStus: freeze/2, frozen/2, dif/2, when/2, dazu ?=/2
  und ground/1.

  Grundlage sind attributierte Variablen (siehe `PrologEx.put_attr/4`):
  eine verzögerte Bedingung hängt als Suspension an den Variablen, auf die
  sie wartet (Attribut `"$susp"`, neuester Eintrag vorn). Wird eine davon
  gebunden, verarbeitet die Maschine die Suspensionen selbst
  (`PrologEx.wake_builtin/4`), vor dem nächsten Ziel. Die Formen:

      '$fz'(M:G)          freeze: G läuft, wenn die Variable gebunden ist
      '$wh'(C, M:G)       when: Bedingung C wartet auf genau diese Variable
      '$wh'(Done, C, M:G) when: C wartet auf mehrere Variablen
      '$df'(L, R)         dif: die Front L = R wartet auf genau eine Variable
      '$df'(Done, L, R)   dif: die Front wartet auf mehrere Variablen

  Eine Suspension auf genau einer Variablen ist erledigt, sobald die
  Variable gebunden ist – ihre Attribute werden dann nie mehr gelesen.
  Wartet eine Bedingung auf mehrere Variablen, hängt derselbe Eintrag an
  allen; `Done` ist eine Variable je Bedingung: gebunden heißt erledigt,
  die übrigen Einträge sind tot (die Kompaktierung wirft sie weg).
  Geweckt heißt: die Bedingung noch einmal stellen (dif/2, when/2,
  freeze/2); ist sie weiter offen, wartet sie auf den dann passenden
  Variablen – eine Variable an eine andere gebunden: der Eintrag wandert
  mit. Das hält die Logik einfach und korrekt; dif/2 prüft dabei die
  ganze Front neu.

  dif/2 mit einer Front Variable = ground Wert benutzt stattdessen die
  Ausschlussmenge der Variablen (Attribut "$difset", siehe exclude/3,
  check_excluded/3).

  Restziele (`frozen/2`, Antworten im Toplevel) werden aus den aktiven
  Einträgen abgeleitet: `freeze(X, M:G)`, `dif(L, R)`, `when(C, M:G)`.
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.Lists
  alias PrologEx.Builtins.Order

  # freeze(X, G): G läuft, sobald X gebunden ist (sofort, wenn schon)
  defbuiltin "freeze", [x, g] do
    goal = qualify(g, context_module(), subst())

    case freeze(x, goal, subst()) do
      {:call, goal} -> {:call, goal}
      {:ok, s} -> {:subst, s}
    end
  end

  @doc false
  # freeze mit qualifiziertem Ziel: {:call, Ziel} oder {:ok, s} (wartet).
  # Auch für das Wecken in der Maschine.
  def freeze(x, goal, s) do
    case PrologEx.walk(x, s) do
      {:var, _} = v -> {:ok, PrologEx.suspend(s, [v], mk("$fz", [goal]))}
      _ -> {:call, goal}
    end
  end

  @doc false
  # when mit qualifiziertem Ziel und gültiger Bedingung: {:call, Ziel} oder
  # {:ok, s} (wartet). Auch für das Wecken.
  def when_(c, goal, s) do
    case condition(c, s) do
      true ->
        {:call, goal}

      {:wait, [v]} ->
        {:ok, PrologEx.suspend(s, [v], mk("$wh", [c, goal]))}

      {:wait, vars} ->
        susp = mk("$wh", [fresh_var(), c, goal])
        {:ok, PrologEx.suspend(s, Enum.uniq(vars), susp)}
    end
  end

  @doc false
  # Restziel einer Suspension an der Variablen v (für $susp_goals und den
  # Toplevel)
  def residual(susp, v) do
    case PrologEx.unmark_top(susp) do
      {:struct, "$fz", [g]} -> mk("freeze", [v, g])
      {:struct, "$wh", [c, g]} -> mk("when", [c, g])
      {:struct, "$wh", [_, c, g]} -> mk("when", [c, g])
      {:struct, "$df", [l, r]} -> mk("dif", [l, r])
      {:struct, "$df", [_, l, r]} -> mk("dif", [l, r])
    end
  end

  @doc false
  # Done-Variable einer Suspension (nil bei Suspensionen auf einer Variablen)
  def done_var(susp) do
    case PrologEx.unmark_top(susp) do
      {:struct, "$wh", [d, _, _]} -> d
      {:struct, "$df", [d, _, _]} -> d
      _ -> nil
    end
  end

  @doc false
  # Ist die Suspension noch aktiv (Done ungebunden bzw. kein Done)?
  def active?(susp, s) do
    case done_var(susp) do
      nil -> true
      d -> match?({:var, _}, PrologEx.walk(d, s))
    end
  end

  # Restziele der eingebauten Bedingungen an Variable V (freeze, dif, when)
  defbuiltin "$susp_goals", [v, l] do
    goals =
      case deref(v) do
        {:var, _} = var ->
          excluded = for c <- excluded(var, subst()), do: mk("dif", [var, c])

          excluded ++ for s <- PrologEx.suspensions(var, subst()), do: residual(s, var)

        _ ->
          []
      end

    {:unify, [{l, list(goals)}]}
  end

  # Attributmodule mit Restzielen, in Deklarationsreihenfolge: M mit
  # attribute_goal/2 (SICStus), dcg(M) mit attribute_goals//1 (Scryer, SWI)
  defbuiltin "$attr_goal_modules", [ms] do
    db = db()

    mods =
      for m <- Map.get(db, :attr_modules, []),
          g = residual_hook(db, m),
          g != nil,
          do: g

    {:unify, [{ms, list(mods)}]}
  end

  defp residual_hook(db, m) do
    cond do
      Map.has_key?(db, {m, "attribute_goal", 2}) -> a(m)
      Map.has_key?(db, {m, "attribute_goals", 3}) -> mk("dcg", [a(m)])
      true -> nil
    end
  end

  # Attributmodule mit project_attributes/2 (Scryer, SWI)
  defbuiltin "$project_modules", [ms] do
    db = db()

    mods =
      for m <- Map.get(db, :attr_modules, []),
          Map.has_key?(db, {m, "project_attributes", 2}),
          do: a(m)

    {:unify, [{ms, list(mods)}]}
  end

  # term_attvars(T, Vs): attributierte Variablen in T – auch die, die erst
  # über Attribute erreichbar sind –, in Reihenfolge des Auftretens
  defbuiltin "term_attvars", [t, vs] do
    {:unify, [{vs, list(PrologEx.term_attvars(t, subst()))}]}
  end

  defbuiltin "$list_conj", [l, g] do
    {:unify, [{g, PrologEx.conj(Lists.items(l, subst()))}]}
  end

  # dif(X, Y): X und Y sind verschieden – scheitert, sobald sie gleich
  # werden; wartet, solange es offen ist
  defbuiltin "dif", [x, y] do
    case dif(x, y, subst()) do
      :fail -> :fail
      {:ok, s} -> {:subst, s}
    end
  end

  @doc false
  # dif(X, Y) auf der Substitution: :fail oder {:ok, neue Substitution}
  # (unverändert, wenn verschieden; sonst mit Suspension an der Front).
  # Auch für das Wecken in der Maschine (siehe PrologEx, $difs).
  def dif(x, y, s) do
    case unifier(x, y, s) do
      :different ->
        {:ok, s}

      :identical ->
        :fail

      {:maybe, [v], [{v, c}]} ->
        # Front aus einem Paar Variable = ground Term: in die
        # Ausschlussmenge der Variablen (siehe exclude/3)
        if Order.variables(c, s) == [],
          do: {:ok, exclude(s, v, PrologEx.resolve(c, s))},
          else: {:ok, suspend_dif(s, [v], [{v, c}])}

      {:maybe, vars, pairs} ->
        {:ok, suspend_dif(s, vars, pairs)}
    end
  end

  # nur die Front merken: die Paare des Unifikators (siehe Moduldoku); auf
  # einer Variablen ohne Done
  defp suspend_dif(s, [v], pairs) do
    {l, r} = frontier(pairs)
    PrologEx.suspend(s, [v], mk("$df", [l, r]))
  end

  defp suspend_dif(s, vars, pairs) do
    {l, r} = frontier(pairs)
    PrologEx.suspend(s, vars, mk("$df", [fresh_var(), l, r]))
  end

  # --- Ausschlussmengen ---------------------------------------------------
  #
  # dif(V, c) mit ungebundenem V und ground c steht nicht als Suspension an
  # V, sondern als Element einer Menge im Attribut "$difset" von V:
  # {:difset, MapSet der Werte, Werte in umgekehrter Reihenfolge des
  # Hinzufügens}. Die Werte sind kanonisch (resolve/2: ohne Markierungen,
  # ohne gebundene Variablen) und ground – die Kompaktierung lässt das
  # Attribut also unverändert. Wird V gebunden (check_excluded/3):
  #   - an einen ground Wert: ein Nachschlagen in der Menge, O(log k)
  #   - an eine Variable W: die Menge geht an W über
  #   - an einen anderen Term: dif(Wert, c) für jedes c, wie bisher
  # Statt k Weckziele für k dif-Bedingungen also eine Prüfung.

  @doc false
  def exclude(s, v, c), do: exclude_all(s, v, [c])

  @doc false
  # mehrere Werte (in Reihenfolge) in die Ausschlussmenge von v, mit einem
  # Schreibzugriff
  def exclude_all(s, v, cs) do
    PrologEx.update_attr(s, v, "$difset", fn
      nil ->
        {set, rev} = add_excluded(cs, MapSet.new(), [])
        {:difset, set, rev}

      {:difset, set, rev} ->
        {set, rev} = add_excluded(cs, set, rev)
        {:difset, set, rev}
    end)
  end

  defp add_excluded([], set, rev), do: {set, rev}

  defp add_excluded([c | cs], set, rev) do
    if MapSet.member?(set, c),
      do: add_excluded(cs, set, rev),
      else: add_excluded(cs, MapSet.put(set, c), [c | rev])
  end

  @doc false
  # Werte der Ausschlussmenge der Variablen v, in Reihenfolge des Hinzufügens
  def excluded(v, s) do
    case PrologEx.get_attrs(v, s) |> Map.get("$difset") do
      nil -> []
      {:difset, _, rev} -> Enum.reverse(rev)
    end
  end

  @doc false
  # Die Variable mit der Ausschlussmenge data ist jetzt x (gebunden oder
  # eine andere Variable): :fail oder {:ok, s}
  def check_excluded(x, {:difset, set, rev}, s) do
    case PrologEx.walk(x, s) do
      {:var, _} = w ->
        {:ok, exclude_all(s, w, Enum.reverse(rev))}

      val ->
        if Order.variables(val, s) == [] do
          if MapSet.member?(set, PrologEx.resolve(val, s)), do: :fail, else: {:ok, s}
        else
          rev
          |> Enum.reverse()
          |> Enum.reduce_while({:ok, s}, fn c, {:ok, s} ->
            case dif(val, c, s) do
              :fail -> {:halt, :fail}
              ok -> {:cont, ok}
            end
          end)
        end
    end
  end

  # Front als Termpaar: ein Paar V=T -> {V, T}, mehrere -> {f(V1..), f(T1..)}
  defp frontier([{v, t}]), do: {v, t}

  defp frontier(pairs) do
    {vs, ts} = Enum.unzip(pairs)
    {mk("f", vs), mk("f", ts)}
  end

  # when(Bedingung, G): Bedingung aus nonvar/1, ground/1, ?=/2, (,), (;)
  defbuiltin "when", [c, g] do
    goal = qualify(g, context_module(), subst())

    case when_(c, goal, subst()) do
      {:call, goal} -> {:call, goal}
      {:ok, s} -> {:subst, s}
    end
  end

  # ?=(X, Y): ob X und Y gleich oder verschieden sind, steht schon fest
  defbuiltin "?=", [x, y] do
    unifier(x, y, subst()) in [:different, :identical]
  end

  defbuiltin "ground", [t] do
    Order.variables(t, subst()) == []
  end

  def meta, do: [{"system", "call_residue_vars", [0, "-"]}]

  # --- call_residue_vars/2 (SWI, SICStus) ---------------------------------
  # Vs: die während G entstandenen attributierten Variablen, die nach
  # einer Lösung noch ungebunden sind und eine aktive Bedingung tragen
  # (blockiertes Ziel, dif, Attribut eines Moduls). Kennungen steigen
  # monoton (PrologEx.attv_id/0): entstanden = Kennung über der Marke.

  @crv :prolog_ex_crv_marks

  defbuiltin "$crv_mark", [m] do
    {:unify, [{m, PrologEx.attv_id()}]}
  end

  # offene Marken: die Kompaktierung behält solange auch unerreichbare
  # attributierte Variablen über der ältesten
  defbuiltin "$crv_open", [m] do
    Process.put(@crv, [deref(m) | Process.get(@crv, [])])
    :ok
  end

  defbuiltin "$crv_close", [m] do
    Process.put(@crv, List.delete(Process.get(@crv, []), deref(m)))
    :ok
  end

  defbuiltin "$crv_vars", [m, vs] do
    mark = deref(m)
    s = subst()

    vars =
      for {{:attrs, id}, attrs} <- s,
          id > mark,
          v = {:var, {:attv, id}},
          PrologEx.walk(v, s) == v,
          attrs_active?(attrs, s) do
        {id, v}
      end
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))

    {:unify, [{vs, PrologEx.list(vars)}]}
  end

  # aktiv: ein Attribut eines Moduls, eine Ausschlussmenge (dif; sie wächst
  # nur, ist also nie leer) oder eine Suspension mit ungebundenem Done
  defp attrs_active?(attrs, s) do
    Enum.any?(attrs, fn
      {"$susp", l} ->
        Enum.any?(PrologEx.prolog_items(l), &active?(&1, s))

      _ ->
        true
    end)
  end

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, rule: 2, fact: 1]
    g = v("G")

    [vs, v1, ms, m, g0, g1, g2, ag, l, t, cp, b, h, r, m0, x, xs, q, qs, avs] =
      Enum.map(~w(Vs V Ms M G0 G1 G2 AG L T Copy Body H R M0 X Xs Q QVs AVs), &v/1)

    w = v("_")

    [
      rule(s("call_residue_vars", [g, vs]), [
        s("$crv_mark", [m]),
        s("setup_call_cleanup", [
          s("$crv_open", [m]),
          s(",", [s("call", [g]), s("$crv_vars", [m, vs])]),
          s("$crv_close", [m])
        ])
      ]),
      # Restziele attributierter Variablen: eingebaute Bedingungen und
      # M:attribute_goal/2 aller Attributmodule (wie SICStus)
      rule(s("$residuals", [vs, g]), [
        s("$attr_goal_modules", [ms]),
        s("$res_vars", [vs, ms, g, []])
      ]),
      fact(s("$res_vars", [[], w, g, g])),
      rule(s("$res_vars", [[v1 | vs], ms, g0, g]), [
        s("$susp_goals", [v1, l]),
        s("$res_app", [l, g0, g1]),
        s("$res_mods", [ms, v1, g1, g2]),
        s("$res_vars", [vs, ms, g2, g])
      ]),
      fact(s("$res_mods", [[], w, g, g])),
      rule(s("$res_mods", [[m0 | ms], v1, g0, g]), [
        s(";", [
          # attribute_goals//1: Ziele ohne Modul bekommen M davor
          s("->", [
            s("=", [m0, s("dcg", [m])]),
            s(",", [
              s(";", [
                s("->", [s(":", [m, s("attribute_goals", [v1, l, []])]), a("true")]),
                s("=", [l, []])
              ]),
              s("$res_qual", [l, m, g0, g1])
            ])
          ]),
          s(";", [
            s("->", [
              s(":", [m0, s("attribute_goal", [v1, ag])]),
              s("=", [g0, [s(":", [m0, ag]) | g1]])
            ]),
            s("=", [g0, g1])
          ])
        ]),
        s("$res_mods", [ms, v1, g1, g])
      ]),
      fact(s("$res_qual", [[], w, g, g])),
      rule(s("$res_qual", [[x | xs], m, [q | g0], g]), [
        s(";", [
          s("->", [s("=", [x, s(":", [w, w])]), s("=", [q, x])]),
          s("=", [q, s(":", [m, x])])
        ]),
        s("$res_qual", [xs, m, g0, g])
      ]),
      # project_attributes(QueryVars, AttrVars) der Attributmodule (für den
      # Toplevel, vor den Restzielen)
      rule(s("$res_project", [qs, avs]), [
        s("$project_modules", [ms]),
        s("$res_proj", [ms, qs, avs])
      ]),
      fact(s("$res_proj", [[], w, w])),
      rule(s("$res_proj", [[m | ms], qs, avs]), [
        s(";", [
          s("->", [s(":", [m, s("project_attributes", [qs, avs])]), a("true")]),
          a("true")
        ]),
        s("$res_proj", [ms, qs, avs])
      ]),
      fact(s("$res_app", [[], g, g])),
      rule(s("$res_app", [[h | t], [h | g0], g]), [s("$res_app", [t, g0, g])]),
      # frozen(T, G): auf Variablen von T wartende Ziele als Konjunktion
      rule(s("frozen", [t, g]), [
        s("term_attvars", [t, vs]),
        s("$residuals", [vs, l]),
        s("$list_conj", [l, g])
      ]),
      # copy_term(T, Copy, Body): Kopie ohne Attribute; Body stellt sie her.
      # In findall/3: Restziele mancher Module (attribute_goals//1) bauen
      # dabei Attribute ab – das Original bleibt so unberührt (wie Scryer)
      rule(s("copy_term", [t, cp, b]), [
        s("term_attvars", [t, vs]),
        s("findall", [s("-", [t, l]), s("$residuals", [vs, l]), [s("-", [cp, r])]]),
        s("$list_conj", [r, b])
      ])
    ]
  end

  # ---------------------------------------------------------------------

  @doc false
  def qualify(g, mod, s) do
    case PrologEx.walk(g, s) do
      {:var, _} -> PrologEx.Error.instantiation!()
      {tag, ":", [_, _]} = q when tag in [:struct, :gstruct] -> q
      _ -> mk(":", [a(mod), g])
    end
  end

  @doc false
  # Bedingung von when/2: true oder {:wait, variablen} (auch für when_si/2)
  def condition(c, s) do
    case PrologEx.unmark_top(PrologEx.walk(c, s)) do
      {:var, _} ->
        PrologEx.Error.instantiation!()

      {:struct, "nonvar", [x]} ->
        case PrologEx.walk(x, s) do
          {:var, _} = v -> {:wait, [v]}
          _ -> true
        end

      {:struct, "ground", [x]} ->
        # wie SICStus: auf eine Variable warten, dann neu prüfen
        case Order.first_var(x, s) do
          nil -> true
          v -> {:wait, [v]}
        end

      {:struct, "?=", [x, y]} ->
        case unifier(x, y, s) do
          {:maybe, vars, _pairs} -> {:wait, vars}
          _ -> true
        end

      {:struct, ",", [a1, b1]} ->
        case condition(a1, s) do
          true ->
            condition(b1, s)

          wait ->
            # Form von B gleich prüfen (Fehler sofort, wie SICStus)
            _ = condition(b1, s)
            wait
        end

      {:struct, ";", [a1, b1]} ->
        case condition(a1, s) do
          true ->
            true

          {:wait, va} ->
            case condition(b1, s) do
              true -> true
              {:wait, vb} -> {:wait, va ++ vb}
            end
        end

      other ->
        PrologEx.Error.domain!("when_condition", PrologEx.resolve(other, s))
    end
  end

  @doc """
  Unifikator von x und y unter s, ohne zu binden: `:different` (nicht
  unifizierbar), `:identical` (schon gleich) oder `{:maybe, variablen, paare}` –
  die Variablen, deren Bindung die Frage entscheiden kann.
  """
  def unifier(x, y, s) do
    case uni(x, y, s, {%{}, []}) do
      :error ->
        :different

      {:ok, {_, []}} ->
        :identical

      {:ok, {_, rev}} ->
        pairs = Enum.reverse(rev)

        vars =
          Enum.flat_map(pairs, fn {v, t} ->
            case t do
              {:var, _} -> [v, t]
              _ -> [v]
            end
          end)

        {:maybe, Enum.uniq(vars), pairs}
    end
  end

  # acc = {Bindungen, Paare in Reihenfolge (umgekehrt)}
  defp w(t, s, {m, _} = acc) do
    case PrologEx.walk(t, s) do
      {:var, _} = v ->
        case Map.fetch(m, v) do
          {:ok, t2} -> w(t2, s, acc)
          :error -> v
        end

      other ->
        other
    end
  end

  defp put_pair({m, l}, v, t), do: {Map.put(m, v, t), [{v, t} | l]}

  defp uni(x, y, s, acc) do
    x = w(x, s, acc)
    y = w(y, s, acc)

    cond do
      x === y -> {:ok, acc}
      match?({:var, _}, x) -> {:ok, put_pair(acc, x, y)}
      match?({:var, _}, y) -> {:ok, put_pair(acc, y, x)}
      true -> uni_struct(PrologEx.unmark_top(x), PrologEx.unmark_top(y), s, acc)
    end
  end

  defp uni_struct({:struct, f, xs}, {:struct, f, ys}, s, acc) when length(xs) == length(ys),
    do: uni_args(xs, ys, s, acc)

  defp uni_struct([xh | xt], [yh | yt], s, acc) do
    case uni(xh, yh, s, acc) do
      {:ok, acc} -> uni(xt, yt, s, acc)
      :error -> :error
    end
  end

  defp uni_struct(_, _, _, _), do: :error

  defp uni_args([], [], _s, acc), do: {:ok, acc}

  defp uni_args([x | xs], [y | ys], s, acc) do
    case uni(x, y, s, acc) do
      {:ok, acc} -> uni_args(xs, ys, s, acc)
      :error -> :error
    end
  end
end
