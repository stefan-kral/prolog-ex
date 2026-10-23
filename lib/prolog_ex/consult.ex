defmodule PrologEx.Consult do
  @moduledoc """
  Lädt gelesene Terme (siehe `PrologEx.Reader`) in eine Datenbank.

    * Klauseln (`H :- B`, Fakten) und DCG-Regeln (`H --> B`) werden pro
      Prädikat gesammelt. Ein Prädikat, das in einem Ladevorgang vorkommt,
      ERSETZT seine bisherige Definition (Reconsult); alle Klauseln
      desselben Ladevorgangs werden zusammengefasst.
    * Direktiven `:- G` werden an ihrer Stelle ausgeführt; vorher wird
      kompiliert, was bis dahin geladen ist, damit G darauf zugreifen kann.
      Besonders behandelt: `dynamic/1`, `initialization/1`, `op/3` (das
      Einlesen hat gprolog schon erledigt), `discontiguous/1`,
      `ensure_loaded/1` (ignoriert).
    * `initialization(G)` läuft am Ende des Ladevorgangs.

  Ergebnis: `{db, meldungen}`; Meldungen sind Strings (Warnungen/Fehler).
  """

  alias PrologEx.{Compiler, DCG}

  def load(db, items) do
    st = %{db: db, pending: %{}, order: [], msgs: [], init: []}

    st =
      items
      |> Enum.reduce(st, &item/2)
      |> flush()

    st = Enum.reduce(Enum.reverse(st.init), st, &run_directive(&1, &2, "initialization"))
    {st.db, Enum.reverse(st.msgs)}
  end

  # ---------------------------------------------------------------------

  defp item({:error, msg}, st), do: msg(st, msg)

  defp item({:term, t, _names}, st) do
    case PrologEx.unmark_top(t) do
      {:struct, ":-", [d]} -> directive(PrologEx.unmark(d), st)
      {:struct, "?-", [d]} -> directive(PrologEx.unmark(d), st)
      {:struct, "-->", [h, b]} -> add_clause(DCG.rule(h, b), st)
      {:struct, ":-", [h, b]} -> add_clause({h, b}, st)
      fact -> add_clause({fact, PrologEx.a("true")}, st)
    end
  rescue
    e in RuntimeError -> msg(st, "Fehler: #{e.message}")
  end

  defp add_clause({head, _} = cl, st) do
    key = Compiler.key(head)

    if PrologEx.Builtins.protected?(key) do
      {name, arity} = key
      raise "permission_error(modify, static_procedure, #{name}/#{arity})"
    end

    case Map.fetch(st.pending, key) do
      {:ok, cls} ->
        %{st | pending: Map.put(st.pending, key, [cl | cls])}

      :error ->
        %{st | pending: Map.put(st.pending, key, [cl]), order: [key | st.order]}
    end
  end

  # Alles bisher Gesammelte kompilieren (pending bleibt erhalten, damit
  # spätere Klauseln desselben Prädikats angehängt statt ersetzt werden)
  defp flush(st) do
    clauses = Enum.flat_map(st.pending, fn {_, cls} -> Enum.reverse(cls) end)
    %{st | db: PrologEx.consult(st.db, clauses)}
  end

  defp directive({:struct, "dynamic", [spec]}, st) do
    Enum.reduce(specs(spec), st, fn key, st -> %{st | db: PrologEx.declare(st.db, key)} end)
  end

  defp directive({:struct, "initialization", [g | _]}, st), do: %{st | init: [g | st.init]}
  defp directive({:struct, "op", [_, _, _]}, st), do: st
  defp directive({:struct, "discontiguous", [_]}, st), do: st
  defp directive({:struct, "ensure_loaded", [_]}, st), do: st
  defp directive(g, st), do: run_directive(g, flush(st), "Direktive")

  defp run_directive(g, st, what) do
    result = Enum.take(PrologEx.query(st.db, g), 1)
    # Direktiven dürfen die Datenbank ändern (assert/retract)
    st = %{st | db: PrologEx.current_db()}

    case result do
      [_] -> st
      [] -> msg(st, "Warnung: #{what} gescheitert: #{PrologEx.format(g)}")
    end
  rescue
    e in RuntimeError -> msg(st, "Fehler in #{what} #{PrologEx.format(g)}: #{e.message}")
  end

  # foo/1, (foo/1, bar/2) oder [foo/1, bar/2]
  defp specs({:struct, ",", [a, b]}), do: specs(a) ++ specs(b)
  defp specs({:struct, "/", [{:atom, n}, ar]}) when is_integer(ar), do: [{n, ar}]
  defp specs([h | t]), do: specs(h) ++ specs(t)
  defp specs([]), do: []
  defp specs(other), do: raise("type_error(predicate_indicator, #{PrologEx.format(other)})")

  defp msg(st, m), do: %{st | msgs: [m | st.msgs]}
end
