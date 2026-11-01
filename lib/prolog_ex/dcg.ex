defmodule PrologEx.DCG do
  @moduledoc """
  Übersetzung von DCG-Regeln (`Kopf --> Rumpf`) in normale Klauseln.

      greeting --> [hallo], name.      % wird zu
      greeting(S0, S) :- S0 = [hallo|S1], name(S1, S).

  Unterstützt: Terminallisten (auch Strings, da `double_quotes=chars`),
  Nichtterminale, `,`, `;`, `|`, `->`, `\\+`, `{}`/1, `!`, `[]`,
  `call//N`, `M:Rumpf` und Variablen (über `phrase/3`), Pushback
  (`H, PB --> B`: nach B steht die Liste PB wieder vorn im Rest, wie im
  Entwurf des DCG-Standards, SWI und Scryer).
  """

  import PrologEx, only: [mk: 2, list: 2, a: 1, unmark: 1, uncons: 1]

  @doc "Übersetzt `{kopf, rumpf}` einer DCG-Regel in `{kopf, rumpf}` einer Klausel."
  def rule(head, body) do
    s0 = fresh()
    s = fresh()

    case unmark(head) do
      # Pushback: H(S0, S) :- B(S0, S1), S = PB ++ S1
      {:struct, ",", [nt, pb]} ->
        s1 = fresh()

        items =
          case terminals(pb, []) do
            {:ok, items} -> items
            :partial -> PrologEx.Error.instantiation!()
            :error -> PrologEx.Error.type!("list", pb)
          end

        {add_args(unmark(nt), s0, s),
         mk(",", [body(body, s0, s1), mk("=", [s, list(items, s1)])])}

      h ->
        {add_args(h, s0, s), body(body, s0, s)}
    end
  end

  @doc "Übersetzt einen DCG-Rumpf mit Eingabe `s0` und Rest `s`."
  def body(b, s0, s), do: tr(unmark(b), s0, s)

  @doc """
  Rumpf für phrase/2,3: ungebunden instantiation_error; der übersetzte
  Rumpf muss sich ganz in ein Ziel umwandeln lassen, bevor etwas
  ausgeführt wird (wie call/1; sonst type_error(callable, Ziel)).
  """
  def phrase_goal({:var, _}, _s0, _s, _subst), do: PrologEx.Error.instantiation!()

  def phrase_goal(b, s0, s, subst) do
    goal = body(b, s0, s)
    PrologEx.check_body!(goal, subst)
    goal
  end

  defp tr({:var, _} = v, s0, s), do: mk("phrase", [v, s0, s])

  defp tr({:struct, ",", [x, y]}, s0, s) do
    mid = fresh()
    mk(",", [tr(x, s0, mid), tr(y, mid, s)])
  end

  defp tr({:struct, op, [x, y]}, s0, s) when op in [";", "|"] do
    mk(";", [tr(x, s0, s), tr(y, s0, s)])
  end

  defp tr({:struct, "->", [c, t]}, s0, s) do
    mid = fresh()
    mk("->", [tr(c, s0, mid), tr(t, mid, s)])
  end

  # \+ B: B gleich übersetzt; lässt B sich nicht übersetzen, entscheidet
  # erst die Ausführung (\+ phrase(B, S0, _), wie Scryer und der Entwurf –
  # ein Fehler kommt nur, wenn \+ wirklich ausgeführt wird)
  defp tr({:struct, "\\+", [x]}, s0, s) do
    inner =
      try do
        tr(x, s0, fresh())
      rescue
        PrologEx.Error -> mk("phrase", [x, s0, fresh()])
      end

    mk(",", [mk("\\+", [inner]), mk("=", [s0, s])])
  end

  defp tr({:struct, "{}", [g]}, s0, s), do: mk(",", [g, mk("=", [s0, s])])
  defp tr({:atom, "{}"}, s0, s), do: mk("=", [s0, s])
  defp tr({:atom, "!"}, s0, s), do: mk(",", [a("!"), mk("=", [s0, s])])
  defp tr([], s0, s), do: mk("=", [s0, s])
  defp tr({:struct, "call", args}, s0, s), do: mk("call", args ++ [s0, s])
  # M:Rumpf: der Rumpf im Modul M (wie SWI; z. B. Grammatiken, die ein
  # Meta-Prädikat mit //-Argument qualifiziert weitergibt)
  defp tr({:struct, ":", [m, b]}, s0, s), do: mk(":", [m, tr(unmark(b), s0, s)])

  defp tr([_ | _] = l, s0, s), do: tr_terminals(l, s0, s)

  defp tr(nt, s0, s), do: add_args(nt, s0, s)

  # Terminalliste: Teilliste instantiation_error, keine Liste type_error
  defp tr_terminals(l, s0, s) do
    case terminals(l, []) do
      {:ok, items} -> mk("=", [s0, list(items, s)])
      :partial -> PrologEx.Error.instantiation!()
      :error -> PrologEx.Error.type!("list", l)
    end
  end

  defp terminals(l, acc) do
    case uncons(l) do
      :empty -> {:ok, Enum.reverse(acc)}
      {:cons, h, t} -> terminals(t, [h | acc])
      :other -> if match?({:var, _}, l), do: :partial, else: :error
    end
  end

  defp add_args({:atom, f}, s0, s), do: mk(f, [s0, s])
  defp add_args({:struct, f, args}, s0, s), do: mk(f, args ++ [s0, s])
  defp add_args(t, _, _), do: PrologEx.Error.type!("callable", t)

  defp fresh, do: {:var, PrologEx.Vars.next()}
end
