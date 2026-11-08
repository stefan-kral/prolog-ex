defmodule PrologEx.Builtins.Tabling do
  @moduledoc """
  Die Tabellen von `library(tabling)` (Prolog-Teil: `priv/library/tabling.pl`).

  Auswertung als Fixpunkt je stark zusammenhängender Komponente (SCC), ohne
  Eingriff in die Maschine:

    * Jede Variante eines getablten Aufrufs hat eine Tabelle (Schlüssel wie
      bei `library(memo)`: `PrologEx.Builtins.Memo.variant_key/2`), mit den
      Antworten als Menge (Varianten) in der Reihenfolge des Findens.
    * Eine neue Tabelle kommt auf einen Stapel (Index, lowlink wie bei
      Tarjan) und wird ausgewertet: im ersten Lauf alle Antworten der
      Klauseln sammeln und eintragen (findall im Prolog-Teil), in späteren
      Läufen jede Antwort sofort eintragen. Ruft die Auswertung eine
      Tabelle, die noch unvollständig auf dem Stapel liegt, liest sie deren
      Antworten live ('$tbl_chunk': auch die, die während des Lesens
      dazukommen – so schließt Links-Rekursion in einer Runde), und ihr
      lowlink sinkt auf deren Index.
    * Ist danach lowlink = Index, ist die Tabelle Anführer ihrer Komponente
      (alles über ihr auf dem Stapel). Der Anführer wiederholt Runden: sich
      selbst und jedes Mitglied, das in dieser Runde noch nicht dran war,
      neu auswerten – solange jemand eine Antwort verpasst hat: das Ende
      einer Tabelle schon gelesen, als noch eine dazukam (mit Modi: eine
      Tabelle überhaupt gelesen, bevor sich ein Wert verbesserte). Dann
      sind alle Tabellen der Komponente vollständig und verlassen den
      Stapel.
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
      %{tables: %{}, ids: %{}, next_id: 0, stack: [], frames: [], round: 0, missed: 0}
  end

  defp put_state(st), do: Process.put(@key, st)

  defp entry(st, id), do: Map.fetch!(st.tables, Map.fetch!(st.ids, id))
  defp put_entry(st, e), do: put_in(st.tables[Map.fetch!(st.ids, e.id)], e)

  # '$tbl_lookup'(+Spec, +G, +I, -R): R = complete(As), incomplete(Id)
  # (live lesen: '$tbl_chunk'/4), evaluate(Id) (neu) oder reevaluate(Id) (in
  # dieser Runde noch nicht dran)
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
          st = depend(st, e.index)
          put_state(st)

          {:unify, [{r, mk("incomplete", [e.id])}]}
        end

      _ ->
        id = st.next_id
        index = length(st.stack)

        e = %{
          id: id,
          status: :incomplete,
          # Antworten, die neueste zuerst (mit Modi: die Schlüssel, aset
          # Schlüssel -> beste Antwort); aset ohne Modi: die Varianten
          alist: [],
          n: 0,
          aset: if(moded?(spec, s), do: %{}, else: MapSet.new()),
          index: index,
          lowlink: index,
          stamp: st.round,
          moded: moded?(spec, s),
          goal: PrologEx.copy_fresh(mk("t", [spec, g, i]), s),
          # in dieser Runde: hat jemand das Ende gelesen bzw. überhaupt
          # gelesen (dann verpasst er, was jetzt noch dazukommt)
          end_seen: false,
          read_any: false,
          round_missed: st.missed
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

  # '$tbl_add'(+Id, +Antwort): sofort eintragen, wenn neu (wer die Tabelle
  # gerade liest, sieht sie noch); '$tbl_add_all'(+Id, +Antworten): alle
  defbuiltin "$tbl_add", [id, ans] do
    s = subst()
    st = state()
    e = entry(st, deref(id))

    # schon da (der häufige Fall in späteren Runden): nichts ändern
    unless MapSet.member?(e.aset, Memo.variant_key(ans, s)),
      do: put_state(add_answers(st, e, [ans], s))

    :ok
  end

  defbuiltin "$tbl_add_all", [id, answers] do
    s = subst()
    st = state()
    put_state(add_answers(st, entry(st, deref(id)), PrologEx.Builtins.Lists.items(answers, s), s))
    :ok
  end

  defp add_answers(st, e, answers, s) do
    {e, added} =
      Enum.reduce(answers, {e, 0}, fn ans, {e, added} ->
        k = Memo.variant_key(ans, s)

        if MapSet.member?(e.aset, k) do
          {e, added}
        else
          e = %{
            e
            | aset: MapSet.put(e.aset, k),
              alist: [store(ans, s) | e.alist],
              n: e.n + 1
          }

          {e, added + 1}
        end
      end)

    if added == 0 do
      st
    else
      # wer das Ende schon gelesen hat, verpasst die neuen
      missed = if e.end_seen, do: st.missed + 1, else: st.missed
      put_entry(%{st | missed: missed}, e)
    end
  end

  # '$tbl_chunk'(+Id, +I, -As, -I2): die Antworten ab Nummer I (ab 0), die es
  # schon gibt, und die Nummer danach; scheitert, wenn es keine neuen gibt
  # (auch bei einer verworfenen Tabelle)
  defbuiltin "$tbl_chunk", [id, i, as, i2] do
    st = state()

    with {:ok, tkey} <- Map.fetch(st.ids, deref(id)),
         {:ok, e} <- Map.fetch(st.tables, tkey) do
      i = deref(i)
      # (inzwischen vollständig: nur noch den Rest liefern)
      incomplete? = e.status == :incomplete

      cond do
        i < e.n ->
          if incomplete? and not e.read_any, do: put_state(put_entry(st, %{e | read_any: true}))
          # die n - i neuesten, in der Reihenfolge des Findens
          l = e.alist |> Enum.take(e.n - i) |> Enum.reverse() |> Enum.map(&one(stored(e, &1)))
          {:unify, [{as, PrologEx.list(l)}, {i2, e.n}]}

        incomplete? ->
          # das Ende gelesen: was jetzt noch dazukommt, verpasst dieser Leser
          put_state(put_entry(st, %{e | end_seen: true, read_any: true}))
          :fail

        true ->
          :fail
      end
    else
      _ -> :fail
    end
  end

  # '$tbl_unframe'(+Id, -Anführer)
  defbuiltin "$tbl_unframe", [id, leader] do
    id = deref(id)
    st = state()
    [^id | frames] = st.frames
    e = entry(st, id)

    # der Aufrufer hängt von dieser Tabelle ab (liegt er tiefer im Stapel,
    # ändert das nichts)
    put_state(depend(%{st | frames: frames}, e.lowlink))
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

      st.missed != e.round_missed ->
        # jemand hat eine Antwort verpasst (das Ende einer Tabelle schon
        # gelesen, als noch etwas dazukam): noch eine Runde
        round = st.round + 1
        {members, _} = Enum.split_while(st.stack, &(&1 != e.id))

        tables =
          Enum.reduce(members, st.tables, fn mid, tables ->
            Map.update!(
              tables,
              Map.fetch!(st.ids, mid),
              &%{&1 | end_seen: false, read_any: false}
            )
          end)

        e = %{e | stamp: round, round_missed: st.missed, end_seen: false, read_any: false}
        put_state(put_entry(%{st | round: round, tables: tables}, e))
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

  # '$tbl_next_stale'(+Id, -M, -Spec, -G, -I): ein Mitglied der Komponente
  # von Id, das in dieser Runde noch nicht ausgewertet wurde
  defbuiltin "$tbl_next_stale", [id, m, spec, g, i] do
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
        # (ein grundiertes Ziel ist markiert)
        {:struct, "t", [spec2, g2, i2]} = PrologEx.unmark_top(PrologEx.copy_fresh(x.goal, %{}))
        {:unify, [{m, x.id}, {spec, spec2}, {g, g2}, {i, i2}]}
    end
  end

  # '$tbl_answers'(+Id, -R): R = complete(As) oder incomplete(Id)
  defbuiltin "$tbl_answers", [id, r] do
    st = state()
    e = entry(st, deref(id))

    if e.status == :incomplete do
      {:unify, [{r, mk("incomplete", [e.id])}]}
    else
      {:unify, [{r, mk("complete", [retrieve(e)])}]}
    end
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

  # '$tbl_status'(+M:G, -S): S = complete, incomplete oder none – der Stand
  # der Tabelle für die Variante G (für tnot/1)
  defbuiltin "$tbl_status", [mg, res] do
    s = subst()
    {:struct, ":", [m, g]} = PrologEx.unmark_top(deref(mg))
    {:atom, mod} = deref(m)

    {n, ar} =
      case PrologEx.unmark_top(deref(g)) do
        {:atom, n} -> {n, 0}
        {:struct, n, args} -> {n, length(args)}
      end

    status =
      case Map.get(state().tables, {{mod, n, ar}, Memo.variant_key(g, s)}) do
        %{status: :complete} -> "complete"
        %{status: :incomplete} -> "incomplete"
        nil -> "none"
      end

    {:unify, [{res, a(status)}]}
  end

  defp moded?(spec, s) do
    match?({:struct, "$tbl", [_, _, _, _]}, PrologEx.resolve(spec, s))
  end

  # '$tbl_mget'(+Id, +Schlüssel, -R): R = none oder some(Antwort) – die
  # bisher beste Antwort zu den Indexargumenten Schlüssel
  defbuiltin "$tbl_mget", [id, key, r] do
    s = subst()
    e = entry(state(), deref(id))

    case Map.fetch(e.aset, Memo.variant_key(key, s)) do
      {:ok, stored} -> {:unify, [{r, mk("some", [one(stored)])}]}
      :error -> {:unify, [{r, a("none")}]}
    end
  end

  # '$tbl_mput'(+Id, +Schlüssel, +Antwort): Antwort ist die neue beste zu
  # Schlüssel (zählt als Änderung)
  defbuiltin "$tbl_mput", [id, key, ans] do
    s = subst()
    st = state()
    e = entry(st, deref(id))
    k = Memo.variant_key(key, s)

    # neu: verpasst, wer das Ende schon gelesen hat; verbessert: wer die
    # Tabelle überhaupt schon gelesen hat (er sah den alten Wert)
    {e, miss?} =
      if Map.has_key?(e.aset, k),
        do: {e, e.read_any},
        else: {%{e | alist: [k | e.alist], n: e.n + 1}, e.end_seen}

    e = %{e | aset: Map.put(e.aset, k, store(ans, s))}
    put_state(put_entry(%{st | missed: st.missed + if(miss?, do: 1, else: 0)}, e))
    :ok
  end

  defp pk!(spec, s) do
    case PrologEx.resolve(spec, s) do
      {:struct, "$tbl", [{:atom, m}, {:atom, n}, ar | _]} when is_integer(ar) -> {m, n, ar}
    end
  end

  defp store(ans, s) do
    r = PrologEx.resolve(ans, s)
    if PrologEx.Compiler.ground?(r), do: {:ground, PrologEx.mark(r)}, else: {:copy, r}
  end

  # gespeicherte Antwort zu einem Eintrag von alist (mit Modi: die beste
  # zum Schlüssel)
  defp stored(%{moded: true} = e, k), do: Map.fetch!(e.aset, k)
  defp stored(_e, a), do: a

  defp retrieve(e) do
    e.alist
    |> Enum.reverse()
    |> Enum.map(&one(stored(e, &1)))
    |> PrologEx.list()
  end

  defp one({:ground, t}), do: t
  defp one({:copy, t}), do: PrologEx.copy_fresh(t, %{})
end
