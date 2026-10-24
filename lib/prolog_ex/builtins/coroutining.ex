defmodule PrologEx.Builtins.Coroutining do
  @moduledoc """
  Coroutining wie SICStus: freeze/2, frozen/2, dif/2, when/2, dazu ?=/2
  und ground/1.

  Grundlage sind attributierte Variablen (siehe `PrologEx.put_attr/4`):
  eine verzögerte Bedingung hängt als `'$s'(Done, Weckziel, Restziel)` an
  den Variablen, auf die sie wartet. Wird eine davon gebunden, läuft das
  Weckziel – vor dem nächsten Ziel. Die Weckziele sind einheitlich

      '$..._retry'(Done, ...) :- ( nonvar(Done) -> true ; Done = true, <neu prüfen> ).

  Done ist eine Variable je Bedingung; ist sie gebunden, ist die Bedingung
  erledigt, und ihre übrigen Einträge (an anderen Variablen) sind tot.
  Neu prüfen heißt: dieselbe Bedingung noch einmal stellen (dif/2, when/2,
  freeze/2); ist sie weiter offen, wartet sie mit einem neuen Done auf
  den dann passenden Variablen. Das hält die Logik einfach und korrekt;
  dif/2 prüft dabei den ganzen Term neu.

  Restziele (`frozen/2`, Antworten im Toplevel) sind die Restziel-Teile
  der aktiven Einträge: `freeze(X, M:G)`, `dif(X, Y)`, `when(C, M:G)`.
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.Lists
  alias PrologEx.Builtins.Order

  # freeze(X, G): G läuft, sobald X gebunden ist (sofort, wenn schon)
  defbuiltin "freeze", [x, g] do
    goal = qualify(g, context_module(), subst())

    case deref(x) do
      {:var, _} = v ->
        done = fresh_var()
        susp = s3(done, mk("$freeze_retry", [done, v, goal]), mk("freeze", [v, goal]))
        {:subst, PrologEx.suspend(subst(), [v], susp)}

      _ ->
        {:call, goal}
    end
  end

  # Restziele der eingebauten Bedingungen an Variable V (freeze, dif, when)
  defbuiltin "$susp_goals", [v, l] do
    goals =
      case deref(v) do
        {:var, _} = var ->
          for s <- PrologEx.suspensions(var, subst()) do
            {_, "$s", [_, _, residual]} = PrologEx.unmark_top(s)
            residual
          end

        _ ->
          []
      end

    {:unify, [{l, list(goals)}]}
  end

  # Attributmodule mit attribute_goal/2, in Deklarationsreihenfolge
  defbuiltin "$attr_goal_modules", [ms] do
    db = db()

    mods =
      for m <- Map.get(db, :attr_modules, []),
          Map.has_key?(db, {m, "attribute_goal", 2}),
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

      {:maybe, vars, pairs} ->
        # nur die Front merken: die Paare des Unifikators (siehe Moduldoku)
        {l, r} = frontier(pairs)
        done = fresh_var()
        susp = s3(done, mk("$dif_retry", [done, l, r]), mk("dif", [l, r]))
        {:ok, PrologEx.suspend(s, vars, susp)}
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

    case condition(c, subst()) do
      true ->
        {:call, goal}

      {:wait, vars} ->
        done = fresh_var()
        cond_t = resolve(c)
        susp = s3(done, mk("$when_retry", [done, cond_t, goal]), mk("when", [cond_t, goal]))
        {:subst, PrologEx.suspend(subst(), Enum.uniq(vars), susp)}
    end
  end

  # ?=(X, Y): ob X und Y gleich oder verschieden sind, steht schon fest
  defbuiltin "?=", [x, y] do
    unifier(x, y, subst()) in [:different, :identical]
  end

  defbuiltin "ground", [t] do
    Order.variables(t, subst()) == []
  end

  def library do
    import PrologEx, only: [s: 2, v: 1, a: 1, rule: 2, fact: 1]
    [d, x, y, g, c] = Enum.map(~w(D X Y G C), &v/1)

    retry = fn name, args, again ->
      rule(s(name, [d | args]), [
        s(";", [
          s("->", [s("nonvar", [d]), a("true")]),
          s(",", [s("=", [d, a("true")]), again])
        ])
      ])
    end

    [vs, v1, ms, m, g0, g1, g2, ag, l, t, cp, b, h, r] =
      Enum.map(~w(Vs V Ms M G0 G1 G2 AG L T Copy Body H R), &v/1)

    w = v("_")

    [
      retry.("$freeze_retry", [x, g], s("freeze", [x, g])),
      retry.("$dif_retry", [x, y], s("dif", [x, y])),
      retry.("$when_retry", [c, g], s("when", [c, g])),
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
      rule(s("$res_mods", [[m | ms], v1, g0, g]), [
        s(";", [
          s("->", [
            s(":", [m, s("attribute_goal", [v1, ag])]),
            s("=", [g0, [s(":", [m, ag]) | g1]])
          ]),
          s("=", [g0, g1])
        ]),
        s("$res_mods", [ms, v1, g1, g])
      ]),
      fact(s("$res_app", [[], g, g])),
      rule(s("$res_app", [[h | t], [h | g0], g]), [s("$res_app", [t, g0, g])]),
      # frozen(T, G): auf Variablen von T wartende Ziele als Konjunktion
      rule(s("frozen", [t, g]), [
        s("term_attvars", [t, vs]),
        s("$residuals", [vs, l]),
        s("$list_conj", [l, g])
      ]),
      # copy_term(T, Copy, Body): Kopie ohne Attribute; Body stellt sie her
      rule(s("copy_term", [t, cp, b]), [
        s("term_attvars", [t, vs]),
        s("$residuals", [vs, l]),
        s("copy_term", [s("-", [t, l]), s("-", [cp, r])]),
        s("$list_conj", [r, b])
      ])
    ]
  end

  # ---------------------------------------------------------------------

  defp s3(done, wake, residual), do: mk("$s", [done, wake, residual])

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
        case Order.variables(x, s) do
          [] -> true
          [v | _] -> {:wait, [v]}
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
