defmodule PrologEx.Cyclic do
  @moduledoc """
  Zyklische Terme (rationale Bäume). Ohne Occurs-Check (Flag
  `occurs_check` = `false`, Standard) macht `X = f(X)` einen Term, der über
  eine Bindung auf sich selbst zeigt. Ein Zyklus läuft immer über eine
  gebundene Variable – die Terme selbst sind endliche Elixir-Daten.

  Erkennen ohne Zusatzkosten für endliche Terme: Wer einen Term abläuft,
  zählt auf dem aktuellen Pfad die Stellen, an denen er über eine Bindung
  ging. In einem endlichen Term liegt jede Bindung höchstens einmal auf
  einem Pfad (bei zwei Termen nebeneinander: höchstens zweimal); ist der
  Zähler größer als (2 ×) die Zahl der Einträge der Substitution, ist ein
  Zyklus im Spiel. Dann wirft der Durchlauf `:"$cyclic"`, und es wird von
  vorn mit einer zyklenfesten Fassung gerechnet (die nur zyklische Terme
  bezahlen) – oder, wo ein Ergebnis keinen Zyklus darstellen kann (ein
  aufgelöster Term), der Fehler `representation_error(cyclic_term)`.

  Zyklenfest gibt es hier: `compare/3` (Standardordnung, koinduktiv: ein
  Paar, das schon verglichen wird, gilt als gleich), `vars/2` (die
  Variablen, über die Zyklen laufen) und Kopieren mit Zyklen
  (`copy/3`). Die Unifikation steht in `PrologEx` (u_cyc/5).
  """

  alias PrologEx.Store
  import PrologEx, only: [is_marked: 1]

  @doc """
  Ein Schritt des Zählers für einen Durchlauf über einen Term: t ist
  `Store.walk(t0, s)`; lief das über eine Bindung, +1, und mehr als
  Einträge in `s` heißt Zyklus: `throw(:"$cyclic")`.
  """
  defmacro step(t, t0, d, s) do
    quote do
      if unquote(t) === unquote(t0) do
        unquote(d)
      else
        d = unquote(d) + 1
        if d > map_size(unquote(s)), do: throw(:"$cyclic"), else: d
      end
    end
  end

  @doc "Fehler für Ergebnisse, die keinen Zyklus darstellen können"
  def error! do
    PrologEx.Error.throw!(
      {:struct, "error",
       [{:struct, "representation_error", [{:atom, "cyclic_term"}]}, {:var, PrologEx.Vars.next()}]}
    )
  end

  # ---------------------------------------------------------------------
  # Standardordnung
  # ---------------------------------------------------------------------

  @doc """
  Standardordnung auf rationalen Bäumen: wie `PrologEx.Order.compare/3`,
  aber ein Paar zusammengesetzter Terme, das gerade schon verglichen wird,
  gilt als gleich (koinduktiv; so auch SWI). Schlüssel eines Paars ist je
  Seite die letzte Variable, über die sie lief (sonst der Term selbst).
  """
  def compare(a, b, subst) do
    {r, _seen} = cmp(a, b, subst, MapSet.new())
    r
  end

  defp cmp(a0, b0, s, seen) do
    {a, va} = walk_last(a0, s, nil)
    {b, vb} = walk_last(b0, s, nil)

    with {fa, xs} <- parts(a),
         {fb, ys} <- parts(b) do
      key = if va == nil and vb == nil, do: nil, else: {va || a, vb || b}

      cond do
        key != nil and MapSet.member?(seen, key) ->
          {:eq, seen}

        true ->
          seen = if key, do: MapSet.put(seen, key), else: seen

          case ord(length(xs), length(ys)) do
            :eq ->
              case ord(fa, fb) do
                :eq -> cmp_args(xs, ys, s, seen)
                other -> {other, seen}
              end

            other ->
              {other, seen}
          end
      end
    else
      # eine Seite nicht zusammengesetzt: die Ordnung steht nach der Klasse
      # (oder dem Wert) fest, ohne in einen Zyklus zu laufen
      _ -> {PrologEx.Order.compare(a, b, s), seen}
    end
  end

  defp cmp_args([], [], _s, seen), do: {:eq, seen}

  defp cmp_args([x | xs], [y | ys], s, seen) do
    case cmp(x, y, s, seen) do
      {:eq, seen} -> cmp_args(xs, ys, s, seen)
      other -> other
    end
  end

  defp ord(x, y) when x < y, do: :lt
  defp ord(x, y) when x > y, do: :gt
  defp ord(_, _), do: :eq

  # Name und Argumente eines zusammengesetzten Terms (Listen: '.'/2)
  defp parts({:glist, [h | t]}), do: {".", [h, glist_tail(t)]}
  defp parts({tag, f, args}) when tag in [:struct, :gstruct], do: {f, args}
  defp parts([h | t]), do: {".", [h, t]}
  defp parts(_), do: :atomic

  defp glist_tail([_ | _] = t), do: {:glist, t}
  defp glist_tail(t), do: t

  # ---------------------------------------------------------------------
  # Kopieren
  # ---------------------------------------------------------------------

  @doc """
  Kopie eines (zyklischen) Terms mit frischen Variablen: `{kopie,
  gleichungen}`. Jede Variable, über die ein Zyklus läuft
  (`PrologEx.cycle_vars/2`), wird in der Kopie eine frische Variable V; ihr
  kopierter Wert kommt als `{V, Wert}` in die Gleichungen, die der
  Empfänger bindet (`PrologEx.bind_eqs/2`). So bleibt der Zyklus erhalten.
  """
  def copy(t, s) do
    cyc = PrologEx.cycle_vars([t], s)
    {c, {map, pend}} = cp(t, s, cyc, {%{}, []})
    {c, close(pend, s, cyc, map, [])}
  end

  defp close([], _s, _cyc, _map, eqs), do: eqs

  defp close([v | vs], s, cyc, map, eqs) do
    {:ok, b} = Store.binding(s, v)
    {cb, {map, pend}} = cp(b, s, cyc, {map, []})
    close(pend ++ vs, s, cyc, map, [{Map.fetch!(map, v), cb} | eqs])
  end

  defp cp({:var, _} = v, s, cyc, {map, pend} = acc) do
    case map do
      %{^v => f} ->
        {f, acc}

      _ ->
        cond do
          MapSet.member?(cyc, v) ->
            f = fresh()
            {f, {Map.put(map, v, f), [v | pend]}}

          true ->
            case Store.binding(s, v) do
              {:ok, b} ->
                cp(b, s, cyc, acc)

              :error ->
                f = fresh()
                {f, {Map.put(map, v, f), pend}}
            end
        end
    end
  end

  defp cp(t, _s, _cyc, acc) when is_marked(t), do: {t, acc}

  defp cp({:struct, f, args}, s, cyc, acc) do
    {args, acc} = Enum.map_reduce(args, acc, &cp(&1, s, cyc, &2))
    {{:struct, f, args}, acc}
  end

  defp cp([h | t], s, cyc, acc) do
    {h, acc} = cp(h, s, cyc, acc)
    {t, acc} = cp(t, s, cyc, acc)
    {[h | t], acc}
  end

  defp cp(t, _s, _cyc, acc), do: {t, acc}

  defp fresh, do: {:var, PrologEx.Vars.next()}

  @doc false
  # Store.walk/2, dazu die letzte gebundene Variable des Wegs
  def walk_last({:var, _} = v, s, last) do
    case Store.binding(s, v) do
      {:ok, t} -> walk_last(t, s, v)
      :error -> {v, last}
    end
  end

  def walk_last(t, _s, last), do: {t, last}
end
