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

  # frozen(X, G): G ist die Konjunktion der auf X wartenden Ziele (oder true)
  defbuiltin "frozen", [x, g] do
    goals =
      case deref(x) do
        {:var, _} = v ->
          for s <- PrologEx.suspensions(v, subst()) do
            {_, "$s", [_, _, residual]} = PrologEx.unmark_top(s)
            residual
          end

        _ ->
          []
      end

    {:unify, [{g, PrologEx.conj(goals)}]}
  end

  # dif(X, Y): X und Y sind verschieden – scheitert, sobald sie gleich
  # werden; wartet, solange es offen ist
  defbuiltin "dif", [x, y] do
    case unifier(x, y, subst()) do
      :different ->
        :ok

      :identical ->
        :fail

      {:maybe, vars} ->
        done = fresh_var()
        susp = s3(done, mk("$dif_retry", [done, x, y]), mk("dif", [x, y]))
        {:subst, PrologEx.suspend(subst(), vars, susp)}
    end
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
    import PrologEx, only: [s: 2, v: 1, a: 1, rule: 2]
    [d, x, y, g, c] = Enum.map(~w(D X Y G C), &v/1)

    retry = fn name, args, again ->
      rule(s(name, [d | args]), [
        s(";", [
          s("->", [s("nonvar", [d]), a("true")]),
          s(",", [s("=", [d, a("true")]), again])
        ])
      ])
    end

    [
      retry.("$freeze_retry", [x, g], s("freeze", [x, g])),
      retry.("$dif_retry", [x, y], s("dif", [x, y])),
      retry.("$when_retry", [c, g], s("when", [c, g]))
    ]
  end

  # ---------------------------------------------------------------------

  defp s3(done, wake, residual), do: mk("$s", [done, wake, residual])

  defp qualify(g, mod, s) do
    case PrologEx.walk(g, s) do
      {:var, _} -> PrologEx.Error.instantiation!()
      {tag, ":", [_, _]} = q when tag in [:struct, :gstruct] -> q
      _ -> mk(":", [a(mod), g])
    end
  end

  # Bedingung von when/2: :true oder {:wait, variablen}
  defp condition(c, s) do
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
          {:maybe, vars} -> {:wait, vars}
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
  unifizierbar), `:identical` (schon gleich) oder `{:maybe, variablen}` –
  die Variablen, deren Bindung die Frage entscheiden kann.
  """
  def unifier(x, y, s) do
    case uni(x, y, s, %{}) do
      :error ->
        :different

      {:ok, acc} when acc == %{} ->
        :identical

      {:ok, acc} ->
        vars =
          Enum.flat_map(acc, fn {v, t} ->
            case t do
              {:var, _} -> [v, t]
              _ -> [v]
            end
          end)

        {:maybe, Enum.uniq(vars)}
    end
  end

  defp w(t, s, acc) do
    case PrologEx.walk(t, s) do
      {:var, _} = v ->
        case Map.fetch(acc, v) do
          {:ok, t2} -> w(t2, s, acc)
          :error -> v
        end

      other ->
        other
    end
  end

  defp uni(x, y, s, acc) do
    x = w(x, s, acc)
    y = w(y, s, acc)

    cond do
      x === y -> {:ok, acc}
      match?({:var, _}, x) -> {:ok, Map.put(acc, x, y)}
      match?({:var, _}, y) -> {:ok, Map.put(acc, y, x)}
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
