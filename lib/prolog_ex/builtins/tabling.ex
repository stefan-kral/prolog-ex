defmodule PrologEx.Builtins.Tabling do
  @moduledoc """
  Die Tabellen von `library(tabling)` (Prolog-Teil: `priv/library/tabling.pl`).

  Auswertung als Fixpunkt je stark zusammenhängender Komponente (SCC), ohne
  Eingriff in die Maschine:

    * Jede Variante eines getablten Aufrufs hat eine Tabelle (Schlüssel wie
      bei `library(memo)`: `PrologEx.Builtins.Memo.variant_key/2`), mit den
      Antworten als Menge (Varianten) in der Reihenfolge des Findens.
    * Eine neue Tabelle kommt auf einen Stapel (Index, lowlink wie bei
      Tarjan) und wird ausgewertet: alle Antworten der Klauseln sammeln
      (findall im Prolog-Teil). Ruft die Auswertung eine Tabelle, die noch
      unvollständig auf dem Stapel liegt, bekommt sie deren bisherige
      Antworten, und ihr lowlink sinkt auf deren Index.
    * Ist danach lowlink = Index, ist die Tabelle Anführer ihrer Komponente
      (alles über ihr auf dem Stapel). Der Anführer wiederholt Runden: sich
      selbst und jedes Mitglied, das in dieser Runde noch nicht dran war,
      neu auswerten – bis eine Runde keine neue Antwort bringt oder niemand
      eine unvollständige Tabelle gelesen hat. Dann sind alle Tabellen der
      Komponente vollständig und verlassen den Stapel.
    * Sinkt der lowlink eines Anführers während seiner Runden doch noch
      (ein neuer Weg zu einer Tabelle weiter unten), gibt er die Führung ab:
      seine Komponente gehört dann zu der darunter, deren Anführer weiter
      rundet.
    * Antworten sind immer korrekt (aus gültigen Ableitungen), nur
      Vollständigkeit braucht den Fixpunkt. Eine Ausnahme in einer
      Auswertung verwirft die Tabelle und alles über ihr auf dem Stapel.

  Zustand im Prozess (`:prolog_ex_tabling`), überlebt die Anfragen der
  Sitzung wie die Datenbank. Interne Prädikate siehe `tabling.pl`.
  """
  use PrologEx.Builtin
  alias PrologEx.Builtins.Memo

  @key :prolog_ex_tabling

  defp state do
    Process.get(@key) ||
      %{tables: %{}, ids: %{}, next_id: 0, stack: [], frames: [], round: 0, adds: 0, snaps: 0}
  end

  defp put_state(st), do: Process.put(@key, st)

  defp entry(st, id), do: Map.fetch!(st.tables, Map.fetch!(st.ids, id))
  defp put_entry(st, e), do: put_in(st.tables[Map.fetch!(st.ids, e.id)], e)

  # '$tbl_lookup'(+Spec, +G, +I, -R): R = complete(As), incomplete(As),
  # evaluate(Id) (neu) oder reevaluate(Id) (in dieser Runde noch nicht dran)
  defbuiltin "$tbl_lookup", [spec, g, i, r] do
    s = subst()
    tkey = {pk!(spec, s), Memo.variant_key(g, s)}
    st = state()

    case st.tables do
      %{^tkey => %{status: :complete} = e} ->
        {:unify, [{r, mk("complete", [retrieve(e)])}]}

      %{^tkey => e} ->
        if e.stamp < st.round and e.id not in st.frames do
          # in dieser Runde noch nicht ausgewertet: jetzt einmal (ohne
          # Führung – die hat, wer die Tabelle angelegt hat)
          put_state(put_entry(st, %{e | stamp: st.round}))
          {:unify, [{r, mk("reevaluate", [e.id])}]}
        else
          st = depend(%{st | snaps: st.snaps + 1}, e.index)
          put_state(st)
          {:unify, [{r, mk("incomplete", [retrieve(e)])}]}
        end

      _ ->
        id = st.next_id
        index = length(st.stack)

        e = %{
          id: id,
          status: :incomplete,
          answers: [],
          aset: MapSet.new(),
          index: index,
          lowlink: index,
          stamp: st.round,
          goal: PrologEx.copy_fresh(mk("-", [g, i]), s),
          round_adds: st.adds,
          round_snaps: st.snaps
        }

        put_state(%{
          st
          | tables: Map.put(st.tables, tkey, e),
            ids: Map.put(st.ids, id, tkey),
            next_id: id + 1,
            stack: [id | st.stack]
        })

        {:unify, [{r, mk("evaluate", [id])}]}
    end
  end

  # die gerade auswertende Tabelle hängt von einer unvollständigen ab
  defp depend(%{frames: [f | _]} = st, low) do
    e = entry(st, f)
    if low < e.lowlink, do: put_entry(st, %{e | lowlink: low}), else: st
  end

  defp depend(st, _low), do: st

  defbuiltin "$tbl_frame", [id] do
    st = state()
    put_state(%{st | frames: [deref(id) | st.frames]})
    :ok
  end

  # '$tbl_unframe'(+Id, +Antworten, -Anführer)
  defbuiltin "$tbl_unframe", [id, answers, leader] do
    s = subst()
    id = deref(id)
    st = state()
    [^id | frames] = st.frames
    e = entry(st, id)

    {e, added} =
      Enum.reduce(PrologEx.Builtins.Lists.items(answers, s), {e, 0}, fn ans, {e, n} ->
        k = Memo.variant_key(ans, s)

        if MapSet.member?(e.aset, k),
          do: {e, n},
          else: {%{e | aset: MapSet.put(e.aset, k), answers: [store(ans, s) | e.answers]}, n + 1}
      end)

    # der Aufrufer hängt von dieser Tabelle ab (liegt er tiefer im Stapel,
    # ändert das nichts)
    put_state(depend(put_entry(%{st | frames: frames, adds: st.adds + added}, e), e.lowlink))
    {:unify, [{leader, a(if e.lowlink == e.index, do: "true", else: "false")}]}
  end

  # '$tbl_round'(+Id, -S): S = again (neue Runde), done (Komponente
  # vollständig) oder merged (Führung abgegeben)
  defbuiltin "$tbl_round", [id, res] do
    st = state()
    e = entry(st, deref(id))

    cond do
      e.lowlink < e.index ->
        put_state(depend(st, e.lowlink))
        {:unify, [{res, a("merged")}]}

      st.adds != e.round_adds and st.snaps != e.round_snaps ->
        round = st.round + 1
        e = %{e | stamp: round, round_adds: st.adds, round_snaps: st.snaps}
        put_state(put_entry(%{st | round: round}, e))
        {:unify, [{res, a("again")}]}

      true ->
        {members, rest} = Enum.split_while(st.stack, &(&1 != e.id))
        [_ | below] = rest

        tables =
          Enum.reduce([e.id | members], st.tables, fn mid, tables ->
            Map.update!(tables, Map.fetch!(st.ids, mid), &%{&1 | status: :complete, goal: nil})
          end)

        put_state(%{st | tables: tables, stack: below})
        {:unify, [{res, a("done")}]}
    end
  end

  # '$tbl_next_stale'(+Id, -M, -G, -I): ein Mitglied der Komponente von Id,
  # das in dieser Runde noch nicht ausgewertet wurde
  defbuiltin "$tbl_next_stale", [id, m, g, i] do
    st = state()
    e = entry(st, deref(id))

    stale =
      st.stack
      |> Enum.take_while(&(&1 != e.id))
      |> Enum.map(&entry(st, &1))
      |> Enum.find(&(&1.stamp < st.round and &1.id not in st.frames))

    case stale do
      nil ->
        :fail

      x ->
        put_state(put_entry(st, %{x | stamp: st.round}))
        {:struct, "-", [g2, i2]} = PrologEx.copy_fresh(x.goal, %{})
        {:unify, [{m, x.id}, {g, g2}, {i, i2}]}
    end
  end

  defbuiltin "$tbl_answers", [id, answers] do
    st = state()
    e = entry(st, deref(id))
    if e.status == :incomplete, do: put_state(%{st | snaps: st.snaps + 1})
    {:unify, [{answers, retrieve(e)}]}
  end

  # Ausnahme in der Auswertung von Id: Id und alles darüber verwerfen
  defbuiltin "$tbl_abandon", [id] do
    st = state()
    id = deref(id)

    case st.ids do
      %{^id => tkey} ->
        case st.tables do
          %{^tkey => %{status: :incomplete}} ->
            {gone, rest} = Enum.split_while(st.stack, &(&1 != id))
            gone = [id | gone]
            [_ | below] = rest
            keys = Enum.map(gone, &Map.fetch!(st.ids, &1))

            put_state(%{
              st
              | tables: Map.drop(st.tables, keys),
                ids: Map.drop(st.ids, gone),
                stack: below,
                frames: Enum.reject(st.frames, &(&1 in gone))
            })

          _ ->
            :ok
        end

      _ ->
        :ok
    end

    :ok
  end

  # '$tbl_abolish'(+Was): all oder M:N/A; unvollständige Tabellen (eine
  # Auswertung läuft gerade) bleiben
  defbuiltin "$tbl_abolish", [what] do
    s = subst()
    st = state()

    keep? =
      case PrologEx.resolve(what, s) do
        {:atom, "all"} ->
          fn {_k, e} -> e.status == :incomplete end

        {:struct, ":", [{:atom, m}, {:struct, "/", [{:atom, n}, ar]}]} ->
          fn {{pk, _}, e} -> pk != {m, n, ar} or e.status == :incomplete end
      end

    tables = st.tables |> Enum.filter(keep?) |> Map.new()
    live = MapSet.new(Map.values(tables), & &1.id)
    put_state(%{st | tables: tables, ids: Map.filter(st.ids, fn {id, _} -> id in live end)})
    :ok
  end

  # '$tbl_count'(+M:N/A, -Vollständig, -Antworten): für Tests und Statistik
  defbuiltin "$tbl_count", [pi, n_tables, n_answers] do
    {:struct, ":", [{:atom, m}, {:struct, "/", [{:atom, n}, ar]}]} =
      PrologEx.resolve(pi, subst())

    es = for {{{^m, ^n, ^ar}, _}, %{status: :complete} = e} <- state().tables, do: e
    {:unify, [{n_tables, length(es)}, {n_answers, Enum.sum_by(es, &length(&1.answers))}]}
  end

  defp pk!(spec, s) do
    case PrologEx.resolve(spec, s) do
      {:struct, "$tbl", [{:atom, m}, {:atom, n}, ar]} when is_integer(ar) -> {m, n, ar}
    end
  end

  defp store(ans, s) do
    r = PrologEx.resolve(ans, s)
    if PrologEx.Compiler.ground?(r), do: {:ground, PrologEx.mark(r)}, else: {:copy, r}
  end

  defp retrieve(e) do
    e.answers
    |> Enum.reverse()
    |> Enum.map(fn
      {:ground, t} -> t
      {:copy, t} -> PrologEx.copy_fresh(t, %{})
    end)
    |> PrologEx.list()
  end
end
