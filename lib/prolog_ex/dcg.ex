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

  defp tr({:struct, "\\+", [x]}, s0, s) do
    mk(",", [mk("\\+", [tr(x, s0, fresh())]), mk("=", [s0, s])])
  end

  defp tr({:struct, "{}", [g]}, s0, s), do: mk(",", [g, mk("=", [s0, s])])
  defp tr({:atom, "{}"}, s0, s), do: mk("=", [s0, s])
  defp tr({:atom, "!"}, s0, s), do: mk(",", [a("!"), mk("=", [s0, s])])
  defp tr([], s0, s), do: mk("=", [s0, s])
  defp tr({:struct, "call", args}, s0, s), do: mk("call", args ++ [s0, s])
  # M:Rumpf: der Rumpf im Modul M (wie SWI; z. B. Grammatiken, die ein
  # Meta-Prädikat mit //-Argument qualifiziert weitergibt)
  defp tr({:struct, ":", [m, b]}, s0, s), do: mk(":", [m, tr(unmark(b), s0, s)])

  defp tr([_ | _] = l, s0, s) do
    case terminals(l, []) do
      {:ok, items} -> mk("=", [s0, list(items, s)])
      :error -> PrologEx.Error.type!("list", l)
    end
  end

  defp tr(nt, s0, s), do: add_args(nt, s0, s)

  defp terminals(l, acc) do
    case uncons(l) do
      :empty -> {:ok, Enum.reverse(acc)}
      {:cons, h, t} -> terminals(t, [h | acc])
      :other -> :error
    end
  end

  defp add_args({:atom, f}, s0, s), do: mk(f, [s0, s])
  defp add_args({:struct, f, args}, s0, s), do: mk(f, args ++ [s0, s])
  defp add_args(t, _, _), do: PrologEx.Error.type!("callable", t)

  defp fresh, do: {:var, "_S#{System.unique_integer([:positive])}"}
end
