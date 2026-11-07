defmodule PrologEx.Builtins.Memo do
  @moduledoc """
  Die Tabellen von `library(memo)` (Prolog-Teil: `priv/library/memo.pl`).

  Je Prädikat `{Modul, Name, Stelligkeit}` eine Tabelle: Variante des
  Aufrufs → Antworten. Gespeichert wird erst, wenn der Aufruf ganz
  durchgerechnet ist; solange er läuft, steht dort `:running` (ein
  Selbstaufruf derselben Variante ist dann erkennbar).

    * Schlüssel: der Aufruf mit seinen Variablen in der Reihenfolge des
      ersten Auftretens durchnummeriert, Markierungen entfernt –
      `p(X, a)` und `p(Y, a)` teilen sich einen Eintrag, `p(a, a)` nicht.
      Attributierte Variablen im Aufruf: `representation_error`.
    * Antworten: aufgelöst und von jeder Substitution gelöst; eine
      variablenfreie Antwort wird markiert gespeichert und ohne Kopie
      wiederverwendet, sonst bei jedem Abruf mit frischen Variablen kopiert.
    * Verdrängung (`lru(N)`, `fifo(N)`): nur fertige Einträge. Jeder Eintrag
      hat einen Zeitstempel (LRU: letzter Zugriff, FIFO: Eintragen), in
      einem `:gb_trees` nach Stempel geordnet; über N Einträgen fällt der
      älteste.
    * Zähler je Prädikat: Treffer, Fehlgriffe, Verdrängungen.

  Alles liegt im Prozess (Schlüssel `:prolog_ex_memo`) und überlebt
  Anfragen der Sitzung wie die Datenbank.

  Interne Prädikate (vom Prolog-Teil gerufen):

    * `'$memo_lookup'(+Spec, +Ziel, -R)`: R = `answers(Liste)` (Treffer),
      `miss(Marke)` (jetzt als laufend vermerkt) oder `running`.
    * `'$memo_store'(+Marke, +Antworten)`, `'$memo_drop'(+Marke)`.
    * `'$memo_abolish'(+Was)`: `all` oder `M:N/A`.
    * `'$memo_stats'(+M:N/A, -Liste)`.

  Spec ist `'$memo'(M, N, A, opts(Policy, First, Reentrant))` mit Policy
  `none`, `lru(N)` oder `fifo(N)` (vom Prolog-Teil geprüft). Die Direktive
  leert die Tabelle (neu laden, andere Optionen).
  """
  use PrologEx.Builtin
  alias PrologEx.Error

  @key :prolog_ex_memo

  defp state, do: Process.get(@key) || %{preds: %{}, running: %{}, next: 0}
  defp put_state(st), do: Process.put(@key, st)

  defp new_table(policy) do
    %{
      policy: policy,
      entries: %{},
      order: :gb_trees.empty(),
      clock: 0,
      hits: 0,
      misses: 0,
      evictions: 0
    }
  end

  defbuiltin "$memo_lookup", [spec, goal, r] do
    s = subst()
    {pk, policy} = spec!(spec, s)
    key = variant_key(goal, s)
    st = state()

    t =
      case st.preds do
        %{^pk => t} -> t
        _ -> new_table(policy)
      end

    case t.entries do
      %{^key => :running} ->
        put_state(put_in(st.preds[pk], t))
        {:unify, [{r, a("running")}]}

      %{^key => {answers, stamp}} ->
        t = %{t | hits: t.hits + 1}
        t = if match?({:lru, _}, policy), do: touch(t, key, answers, stamp), else: t
        put_state(put_in(st.preds[pk], t))
        {:unify, [{r, mk("answers", [retrieve(answers)])}]}

      _ ->
        token = st.next
        t = %{t | misses: t.misses + 1, entries: Map.put(t.entries, key, :running)}

        put_state(%{
          st
          | preds: Map.put(st.preds, pk, t),
            running: Map.put(st.running, token, {pk, key}),
            next: token + 1
        })

        {:unify, [{r, mk("miss", [token])}]}
    end
  end

  defbuiltin "$memo_store", [token, answers] do
    s = subst()
    st = state()
    tok = deref(token)

    case Map.pop(st.running, tok) do
      {nil, _} ->
        # inzwischen abgeschafft (abolish_memo): nichts ablegen
        :ok

      {{pk, key}, running} ->
        st = %{st | running: running}

        case st.preds do
          %{^pk => t} ->
            stored = store(answers, s)
            stamp = t.clock

            t = %{
              t
              | clock: stamp + 1,
                entries: Map.put(t.entries, key, {stored, stamp}),
                order: :gb_trees.insert(stamp, key, t.order)
            }

            put_state(%{st | preds: Map.put(st.preds, pk, evict(t))})

          _ ->
            put_state(st)
        end

        :ok
    end
  end

  defbuiltin "$memo_drop", [token] do
    st = state()

    case Map.pop(st.running, deref(token)) do
      {nil, _} ->
        :ok

      {{pk, key}, running} ->
        preds =
          case st.preds do
            %{^pk => %{entries: %{^key => :running}} = t} ->
              Map.put(st.preds, pk, %{t | entries: Map.delete(t.entries, key)})

            preds ->
              preds
          end

        put_state(%{st | preds: preds, running: running})
        :ok
    end
  end

  defbuiltin "$memo_abolish", [what] do
    s = subst()
    st = state()

    case PrologEx.resolve(what, s) do
      {:atom, "all"} ->
        put_state(%{st | preds: %{}, running: %{}})

      {:struct, ":", [{:atom, m}, {:struct, "/", [{:atom, n}, ar]}]} when is_integer(ar) ->
        # laufende Aufrufe des Prädikats legen danach nichts ab ('$memo_store'
        # findet die Tabelle nicht mehr)
        put_state(%{st | preds: Map.delete(st.preds, {m, n, ar})})
    end

    :ok
  end

  defbuiltin "$memo_stats", [pi, stats] do
    s = subst()

    {:struct, ":", [{:atom, m}, {:struct, "/", [{:atom, n}, ar]}]} = PrologEx.resolve(pi, s)

    t =
      case state().preds do
        %{{^m, ^n, ^ar} => t} -> t
        _ -> new_table(:none)
      end

    done = Enum.count(t.entries, fn {_, v} -> v != :running end)

    l =
      PrologEx.list([
        mk("entries", [done]),
        mk("hits", [t.hits]),
        mk("misses", [t.misses]),
        mk("evictions", [t.evictions])
      ])

    {:unify, [{stats, l}]}
  end

  # --- Spec -----------------------------------------------------------------------

  defp spec!(spec, s) do
    case PrologEx.resolve(spec, s) do
      {:struct, "$memo", [{:atom, m}, {:atom, n}, ar, {:struct, "opts", [policy | _]}]}
      when is_integer(ar) ->
        {{m, n, ar}, policy(policy)}
    end
  end

  defp policy({:atom, "none"}), do: :none
  defp policy({:struct, "lru", [n]}) when is_integer(n), do: {:lru, n}
  defp policy({:struct, "fifo", [n]}) when is_integer(n), do: {:fifo, n}

  # --- Verdrängung --------------------------------------------------------------

  # LRU: der Zugriff gibt einen neuen Stempel
  defp touch(t, key, answers, stamp) do
    order = :gb_trees.insert(t.clock, key, :gb_trees.delete(stamp, t.order))

    %{
      t
      | clock: t.clock + 1,
        order: order,
        entries: Map.put(t.entries, key, {answers, t.clock})
    }
  end

  defp evict(%{policy: :none} = t), do: %{t | order: :gb_trees.empty()}

  defp evict(%{policy: {_, max}} = t) do
    if :gb_trees.size(t.order) > max do
      {_stamp, key, order} = :gb_trees.take_smallest(t.order)

      evict(%{
        t
        | order: order,
          entries: Map.delete(t.entries, key),
          evictions: t.evictions + 1
      })
    else
      t
    end
  end

  # --- Antworten ------------------------------------------------------------------

  # [{:ground, markierter Term} | {:copy, Term mit losen Variablen}]
  defp store(answers, s) do
    for ans <- PrologEx.Builtins.Lists.items(answers, s) do
      r = PrologEx.resolve(ans, s)
      if PrologEx.Compiler.ground?(r), do: {:ground, PrologEx.mark(r)}, else: {:copy, r}
    end
  end

  defp retrieve(stored) do
    stored
    |> Enum.map(fn
      {:ground, t} -> t
      {:copy, t} -> PrologEx.copy_fresh(t, %{})
    end)
    |> PrologEx.list()
  end

  # --- Variantenschlüssel ---------------------------------------------------------

  @doc false
  def variant_key(t, s) do
    {k, _} = canon(t, s, %{})
    k
  end

  defp canon(t, s, vars) do
    case PrologEx.Store.walk(t, s) do
      {:var, {:attv, _}} ->
        Error.representation!("memo_attributed_variable")

      {:var, _} = v ->
        case vars do
          %{^v => n} ->
            {{:"$v", n}, vars}

          _ ->
            n = map_size(vars)
            {{:"$v", n}, Map.put(vars, v, n)}
        end

      {:struct, f, args} ->
        {args, vars} = canon_list(args, s, vars)
        {{:struct, f, args}, vars}

      {:gstruct, _, _} = g ->
        {PrologEx.unmark(g), vars}

      {:glist, l} ->
        {PrologEx.unmark(l), vars}

      [h | tl] ->
        {h, vars} = canon(h, s, vars)
        {tl, vars} = canon(tl, s, vars)
        {[h | tl], vars}

      other ->
        {other, vars}
    end
  end

  defp canon_list([], _s, vars), do: {[], vars}

  defp canon_list([a | as], s, vars) do
    {a, vars} = canon(a, s, vars)
    {as, vars} = canon_list(as, s, vars)
    {[a | as], vars}
  end
end
