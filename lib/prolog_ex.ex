# PrologEx – Prolog-Kern in Elixir
#
# Listen sind native BEAM-Listen: '.'(H, T) ist [H | T], '[]' ist [].
# Eine Liste mit offenem Rest ist eine improper list, z. B. [1, 2 | {:var, 7}].
#
# Gegenüber Version 1 (Closures als Continuations) ist die Maschine jetzt
# "defunktionalisiert": Ziel-Stack und Choice-Point-Stack sind gewöhnliche
# Daten. Dadurch:
#
#   * Last-Call-Optimierung: das letzte Ziel eines Rumpfs ersetzt den
#     Aufruf, der Ziel-Stack wächst bei Endrekursion nicht.
#   * Klauseln werden beim Laden kompiliert (PrologEx.Compiler): Kopf-
#     variablen beim ersten Vorkommen werden nicht umbenannt und nicht
#     gebunden, der Rumpf wird erst gebaut, wenn der Kopf passt.
#   * Kein Choice Point für die letzte passende Klausel; vorberechneter
#     Index nach dem ersten Argument. Deterministische Schleifen
#     hinterlassen so gar keine Choice Points.
#   * Garbage Collection der Bindungen: Weil wir sehen können, welche
#     Terme noch erreichbar sind (Ziel-Stack + Anfragevariablen), wird die
#     Substitution periodisch "kompaktiert" – Bindungen werden in die
#     lebenden Terme eingesetzt und die Map wird geleert. Choice Points
#     halten ihren eigenen Map-Schnappschuss, bleiben also korrekt.

defmodule PrologEx do
  # ---------------------------------------------------------------------
  # Terme
  #   {:var, "X"}                Variable aus der Anfrage
  #   {:var, 42}                 frische Variable
  #   {:atom, "foo"}             Atom – bewusst KEIN Elixir-Atom!
  #   integer, float             Zahl
  #   {:struct, "f", [args]}     Struktur f(args...), Stelligkeit >= 1
  #   []                         das Atom '[]'
  #   [h | t]                    die Struktur '.'(h, t)
  #
  # Ground-Markierungen (beim Bauen ausgestellte Bescheinigung "enthält
  # keine Variable"; einseitig: unmarkierte Terme können trotzdem ground
  # sein):
  #   {:gstruct, "f", [args]}    variablenfreie Struktur
  #   {:glist, [h | t]}          variablenfreie Liste (auch improper, z. B.
  #                              [1 | 2]); die Cons-Kette darin ist roh
  #
  # Kanonische Form:
  #   * '.'/2 ist IMMER eine Cons-Zelle (bzw. glist), '[]' IMMER [].
  #   * Innerhalb eines markierten Terms ist jeder zusammengesetzte
  #     Teilterm markiert – außer den Rest-Zellen der glist-Kette selbst.
  #     Zwei markierte Terme sind deshalb genau dann gleich, wenn == gilt.
  # Terme werden ausschließlich über a/1, mk/2, cons/2, list/2 gebaut.
  # Antworten (resolve/2) werden ohne Markierungen ausgeliefert.
  # ---------------------------------------------------------------------

  defguard is_marked(t)
           when is_tuple(t) and (elem(t, 0) == :gstruct or elem(t, 0) == :glist)

  # atomar oder markiert = sicher ground, ohne hineinzuschauen
  defguard is_known_ground(t)
           when is_number(t) or t == [] or is_marked(t) or
                  (is_tuple(t) and elem(t, 0) == :atom)

  def v(name), do: {:var, name}

  def a("[]"), do: []
  def a(name), do: {:atom, name}

  def mk(".", [h, t]), do: cons(h, t)
  def mk(name, []), do: a(name)
  def mk(name, args), do: mk_struct(name, args)

  def mk_struct(f, args) do
    if all_known_ground?(args), do: {:gstruct, f, args}, else: {:struct, f, args}
  end

  defp all_known_ground?([]), do: true
  defp all_known_ground?([x | xs]) when is_known_ground(x), do: all_known_ground?(xs)
  defp all_known_ground?(_), do: false

  def s(name, args), do: mk(name, args)

  # Ein ground Kopf vor einer markierten Liste ergibt in O(1) wieder eine.
  def cons(h, t) when is_known_ground(h) and is_known_ground(t) do
    case t do
      {:glist, l} -> {:glist, [h | l]}
      _ -> {:glist, [h | t]}
    end
  end

  def cons(h, t), do: [h | t]

  # [x1, ..., xn | tail]
  def list(items, tail \\ []), do: List.foldr(items, tail, &cons/2)

  # Einheitlicher Listenzugriff
  def uncons([h | t]), do: {:cons, h, t}
  def uncons({:glist, [h | t]}), do: {:cons, h, glist_tail(t)}
  def uncons([]), do: :empty
  def uncons(_), do: :other

  defp glist_tail([_ | _] = t), do: {:glist, t}
  defp glist_tail(t), do: t

  # Markiert einen (beliebig markierten) variablenfreien Term vollständig
  @doc false
  def mark({:struct, f, args}), do: mk_struct(f, Enum.map(args, &mark/1))
  def mark([h | t]), do: cons(mark(h), mark(t))
  def mark(t), do: t

  # Entfernt alle Markierungen
  def unmark({:gstruct, f, args}), do: {:struct, f, Enum.map(args, &unmark/1)}
  def unmark({:glist, l}), do: unmark(l)
  def unmark({:struct, f, args}), do: {:struct, f, Enum.map(args, &unmark/1)}
  def unmark([h | t]), do: [unmark(h) | unmark(t)]
  def unmark(t), do: t

  # Oberste Ebene ohne Markierung (für Zielauswahl und Arithmetik)
  @doc false
  def unmark_top({:gstruct, f, args}), do: {:struct, f, args}
  def unmark_top({:glist, l}), do: l
  def unmark_top(t), do: t

  def fact(head), do: {head, a("true")}
  def rule(head, goals), do: {head, conj(goals)}

  def conj([]), do: a("true")
  def conj([g]), do: g
  def conj([g | rest]), do: s(",", [g, conj(rest)])

  # ---------------------------------------------------------------------
  # Unifikation
  # ---------------------------------------------------------------------

  def walk({:var, _} = var, subst) do
    case Map.fetch(subst, var) do
      {:ok, t} -> walk(t, subst)
      :error -> var
    end
  end

  def walk(t, _subst), do: t

  # Einzige Stelle, an der Variablen gebunden werden. Hier kommt später
  # der Hook für Attributvariablen (Coroutining) hinein.
  def bind({:var, _} = var, t, subst), do: Map.put(subst, var, t)

  def unify(x, y, subst) do
    x = walk(x, subst)
    y = walk(y, subst)

    cond do
      x == y -> {:ok, subst}
      match?({:var, _}, x) -> {:ok, bind(x, y, subst)}
      match?({:var, _}, y) -> {:ok, bind(y, x, subst)}
      true -> unify_struct(x, y, subst)
    end
  end

  # Zwei markierte Terme sind nur bei == gleich – und das wurde schon geprüft.
  defp unify_struct(x, y, _subst) when is_marked(x) and is_marked(y), do: :error

  defp unify_struct({t1, f, xs}, {t2, f, ys}, subst)
       when t1 in [:struct, :gstruct] and t2 in [:struct, :gstruct] and
              length(xs) == length(ys),
       do: unify_args(xs, ys, subst)

  defp unify_struct({:glist, [x | xs]}, [y | ys], subst) do
    case unify(x, y, subst) do
      {:ok, s} -> unify(glist_tail(xs), ys, s)
      :error -> :error
    end
  end

  defp unify_struct([x | xs], {:glist, [y | ys]}, subst) do
    case unify(x, y, subst) do
      {:ok, s} -> unify(xs, glist_tail(ys), s)
      :error -> :error
    end
  end

  # Listen: Kopf unifizieren, dann per Tail Call mit dem Rest weiter –
  # keine Rekursionstiefe entlang der Liste.
  defp unify_struct([x | xs], [y | ys], subst) do
    case unify(x, y, subst) do
      {:ok, s} -> unify(xs, ys, s)
      :error -> :error
    end
  end

  defp unify_struct(_, _, _), do: :error

  defp unify_args([], [], subst), do: {:ok, subst}

  defp unify_args([x | xs], [y | ys], subst) do
    case unify(x, y, subst) do
      {:ok, s} -> unify_args(xs, ys, s)
      :error -> :error
    end
  end

  # Vollständig auflösen, ohne Markierungen (für Antworten / Interop)
  def resolve(t, subst) do
    case walk(t, subst) do
      {:struct, f, args} -> {:struct, f, Enum.map(args, &resolve(&1, subst))}
      [h | t] -> [resolve(h, subst) | resolve(t, subst)]
      t when is_marked(t) -> unmark(t)
      other -> other
    end
  end

  # ---------------------------------------------------------------------
  # Datenbank
  #   %{{name, arity} => {:pred, alle, nach_schlüssel, nur_var_klauseln, quelle}}
  # quelle: die Klauseln als Terme ({kopf, rumpf}) für listing/clause
  # nach_schlüssel: für jeden Erstargument-Schlüssel die passenden
  # Klauseln (inkl. derer mit Variable an erster Stelle) in Originalreihenfolge.
  # ---------------------------------------------------------------------

  alias PrologEx.Compiler

  def consult(clauses), do: consult(%{}, clauses)

  @doc """
  Fügt Klauseln hinzu. Jedes Prädikat, das in `clauses` vorkommt, ERSETZT
  eine bestehende Definition (Reconsult-Semantik); andere bleiben erhalten.
  """
  def consult(db, clauses) do
    new =
      clauses
      |> Enum.group_by(fn {head, _} -> Compiler.key(head) end)
      |> Map.new(fn {k, cls} -> {k, build_pred(cls)} end)

    Map.merge(db, new)
  end

  @doc "Deklariert ein Prädikat ohne Klauseln (Aufrufe scheitern statt Fehler)."
  def declare(db, key), do: Map.put_new(db, key, build_pred([]))

  defp build_pred(source) do
    cls = Enum.map(source, &Compiler.compile_clause/1)
    keys = cls |> Enum.map(&elem(&1, 1)) |> Enum.reject(&(&1 == :any)) |> Enum.uniq()

    by_key = Map.new(keys, fn k -> {k, Enum.filter(cls, &(elem(&1, 1) in [k, :any]))} end)

    {:pred, cls, by_key, Enum.filter(cls, &(elem(&1, 1) == :any)), source}
  end

  # Hauptfunktor als Indexschlüssel; :any = Variable (passt auf alles)
  @doc false
  def index_key({:var, _}), do: :any
  def index_key({:struct, f, args}), do: {f, length(args)}
  def index_key({:gstruct, f, args}), do: {f, length(args)}
  def index_key([_ | _]), do: {".", 2}
  def index_key({:glist, _}), do: {".", 2}
  def index_key(t), do: t

  defp candidates({:pred, all, by_key, var_only, _source}, args, subst) do
    case args do
      [] ->
        all

      [x | _] ->
        case walk(x, subst) do
          {:var, _} -> all
          t -> Map.get(by_key, index_key(t), var_only)
        end
    end
  end

  # --- Kopf matchen (Read-Modus) ---------------------------------------

  defp match_args([], [], env, s, nv), do: {:ok, env, s, nv}

  defp match_args([p | ps], [t | ts], env, s, nv) do
    case m(p, t, env, s, nv) do
      {:ok, env, s, nv} -> match_args(ps, ts, env, s, nv)
      :error -> :error
    end
  end

  defp m(:void, _t, env, s, nv), do: {:ok, env, s, nv}
  defp m({:first, i}, t, env, s, nv), do: {:ok, put_elem(env, i, t), s, nv}

  defp m({:val, i}, t, env, s, nv) do
    case unify(elem(env, i), t, s) do
      {:ok, s} -> {:ok, env, s, nv}
      :error -> :error
    end
  end

  defp m({:const, c}, t, env, s, nv) do
    case walk(t, s) do
      ^c -> {:ok, env, s, nv}
      {:var, _} = v -> {:ok, env, bind(v, c, s), nv}
      _ -> :error
    end
  end

  defp m({:ground, c}, t, env, s, nv) do
    case walk(t, s) do
      {:var, _} = v ->
        {:ok, env, bind(v, c, s), nv}

      t ->
        case unify(t, c, s) do
          {:ok, s} -> {:ok, env, s, nv}
          :error -> :error
        end
    end
  end

  defp m({:list, ph, pt} = p, t, env, s, nv) do
    case walk(t, s) do
      [h | tl] ->
        case m(ph, h, env, s, nv) do
          {:ok, env, s, nv} -> m(pt, tl, env, s, nv)
          :error -> :error
        end

      {:glist, [h | tl]} ->
        case m(ph, h, env, s, nv) do
          {:ok, env, s, nv} -> m(pt, glist_tail(tl), env, s, nv)
          :error -> :error
        end

      {:var, _} = v ->
        {term, env, nv} = build(p, env, nv)
        {:ok, env, bind(v, term, s), nv}

      _ ->
        :error
    end
  end

  defp m({:struct, f, n, ps} = p, t, env, s, nv) do
    case walk(t, s) do
      {tag, ^f, args} when tag in [:struct, :gstruct] and length(args) == n ->
        match_args(ps, args, env, s, nv)

      {:var, _} = v ->
        {term, env, nv} = build(p, env, nv)
        {:ok, env, bind(v, term, s), nv}

      _ ->
        :error
    end
  end

  # --- Kopf bauen (Write-Modus) ----------------------------------------
  # Nur frische Variablen entstehen hier – sie können keine Attribute
  # tragen, also braucht der Write-Modus nie die allgemeine Unifikation.

  @doc false
  def build(:void, env, nv), do: {{:var, nv}, env, nv + 1}

  def build({:first, i}, env, nv) do
    var = {:var, nv}
    {var, put_elem(env, i, var), nv + 1}
  end

  def build({:val, i}, env, nv), do: {elem(env, i), env, nv}
  def build({:const, c}, env, nv), do: {c, env, nv}
  def build({:ground, c}, env, nv), do: {c, env, nv}

  def build({:list, ph, pt}, env, nv) do
    {h, env, nv} = build(ph, env, nv)
    {t, env, nv} = build(pt, env, nv)
    {cons(h, t), env, nv}
  end

  def build({:struct, f, _n, ps}, env, nv) do
    {args, env, nv} = build_args(ps, env, nv)
    {mk_struct(f, args), env, nv}
  end

  defp build_args([], env, nv), do: {[], env, nv}

  defp build_args([p | ps], env, nv) do
    {a, env, nv} = build(p, env, nv)
    {as, env, nv} = build_args(ps, env, nv)
    {[a | as], env, nv}
  end

  # --- Rumpf instanziieren ---------------------------------------------

  defp inst_goals([], _env, _base, _barrier, rest), do: rest

  defp inst_goals([g | gs], env, base, barrier, rest),
    do: [{inst(g, env, base), barrier} | inst_goals(gs, env, base, barrier, rest)]

  defp inst({:t_slot, i}, env, _base), do: elem(env, i)
  defp inst({:t_fresh, j}, _env, base), do: {:var, base + j}
  defp inst({:t_lit, t}, _env, _base), do: t
  defp inst({:t_list, h, t}, env, base), do: cons(inst(h, env, base), inst(t, env, base))
  defp inst({:t_struct, f, args}, env, base), do: mk_struct(f, inst_args(args, env, base))

  defp inst_args([], _env, _base), do: []
  defp inst_args([a | as], env, base), do: [inst(a, env, base) | inst_args(as, env, base)]

  # ---------------------------------------------------------------------
  # Maschinenzustand
  #   goals   – Ziel-Stack: [{term, cut_barrier}]
  #   cps     – Choice-Point-Stack, height = Länge
  #   answer  – [{name, term}] der Anfragevariablen
  # Ein Cut entfernt alle Choice Points oberhalb von cut_barrier.
  # ---------------------------------------------------------------------

  @min_threshold 4096

  defstruct goals: [],
            subst: %{},
            cps: [],
            height: 0,
            db: %{},
            next_var: 0,
            answer: [],
            threshold: @min_threshold,
            min_threshold: @min_threshold

  defp run(st) do
    st = maybe_compact(st)

    case st.goals do
      [] -> {:sol, st}
      [{goal, cutb} | rest] -> step(unmark_top(walk(goal, st.subst)), cutb, rest, st)
    end
  end

  defp step({:atom, "true"}, _cutb, rest, st), do: run(%{st | goals: rest})
  defp step({:atom, "fail"}, _cutb, _rest, st), do: backtrack(st)

  defp step({:atom, "!"}, cutb, rest, st) do
    cps = Enum.drop(st.cps, st.height - cutb)
    run(%{st | goals: rest, cps: cps, height: cutb})
  end

  defp step({:struct, ",", [g1, g2]}, cutb, rest, st),
    do: run(%{st | goals: [{g1, cutb}, {g2, cutb} | rest]})

  defp step({:struct, ";", [g1, g2]}, cutb, rest, st) do
    case unmark_top(walk(g1, st.subst)) do
      {:struct, "->", [c, t]} ->
        if_then_else(c, t, g2, cutb, rest, st)

      _ ->
        st = push(st, {:alt, {g2, cutb}, rest, st.subst, st.answer})
        run(%{st | goals: [{g1, cutb} | rest]})
    end
  end

  defp step({:struct, "->", [c, t]}, cutb, rest, st),
    do: if_then_else(c, t, {:atom, "fail"}, cutb, rest, st)

  # Interne Markierung: Choice Points bis zur Höhe h abschneiden
  defp step({:"$cut_to", h}, _cutb, rest, st) do
    cps = Enum.drop(st.cps, st.height - h)
    run(%{st | goals: rest, cps: cps, height: h})
  end

  # call/1: Cut darin ist lokal (Barriere = aktuelle Höhe)
  defp step({:struct, "call", [g | extra]}, _cutb, rest, st) do
    goal = add_args(unmark_top(walk(g, st.subst)), extra)
    run(%{st | goals: [{goal, st.height} | rest]})
  end

  defp step({:struct, "not", [g]}, cutb, rest, st),
    do: step({:struct, "\\+", [g]}, cutb, rest, st)

  defp step({:struct, "=", [x, y]}, _cutb, rest, st) do
    case unify(x, y, st.subst) do
      {:ok, s1} -> run(%{st | goals: rest, subst: s1})
      :error -> backtrack(st)
    end
  end

  # Negation: eigener Lauf mit leerem Choice-Point-Stack (Cut darin ist lokal)
  defp step({:struct, "\\+", [g]}, _cutb, rest, st) do
    case run(%{st | goals: [{g, 0}], cps: [], height: 0, answer: []}) do
      {:sol, _} -> backtrack(st)
      :done -> run(%{st | goals: rest})
    end
  end

  defp step({:struct, "is", [x, expr]}, _cutb, rest, st) do
    case unify(x, eval(expr, st.subst), st.subst) do
      {:ok, s1} -> run(%{st | goals: rest, subst: s1})
      :error -> backtrack(st)
    end
  end

  defp step({:struct, op, [x, y]}, _cutb, rest, st)
       when op in ["<", ">", ">=", "=<", "=:=", "=\\="] do
    if compare(op, eval(x, st.subst), eval(y, st.subst)),
      do: run(%{st | goals: rest}),
      else: backtrack(st)
  end

  defp step({:var, _}, _cutb, _rest, _st), do: raise("instantiation_error")

  # time(G): wie call/1, meldet danach die verstrichene Zeit. Ein Choice
  # Point direkt unter G meldet auch einen Fehlschlag. Hat G bei Erfolg
  # keine eigenen Choice Points hinterlassen, wird dieser Melde-Choice-Point
  # sofort entfernt – time(G) ist dann so deterministisch wie G.
  defp step({:struct, "time", [g]}, _cutb, rest, st) do
    t0 = System.monotonic_time(:microsecond)
    h = st.height
    st = push(st, {:time_fail, t0, st.subst, st.answer})
    goal = unmark_top(walk(g, st.subst))
    run(%{st | goals: [{goal, h + 1}, {{:"$time_exit", t0, h}, 0} | rest]})
  end

  defp step({:"$time_exit", t0, h}, _cutb, rest, st) do
    report_time(t0)

    if st.height == h + 1,
      do: run(%{st | goals: rest, cps: tl(st.cps), height: h}),
      else: run(%{st | goals: rest})
  end

  # Benutzerprädikate zuerst; nur bei Fehltreffer die Builtin-Tabelle
  defp step(goal, _cutb, rest, st) do
    key = Compiler.key(goal)
    args = Compiler.args_of(goal)

    case Map.fetch(st.db, key) do
      {:ok, pred} ->
        try_clauses(goal, args, candidates(pred, args, st.subst), rest, st)

      :error ->
        case PrologEx.Builtins.lookup(key) do
          {:det, fun, _} ->
            apply_result(fun.(args, ctx(st)), rest, st)

          {:nondet, fun, _} ->
            start_solutions(fun.(args, ctx(st)), rest, st)

          {:prolog, pred, _} ->
            try_clauses(goal, args, candidates(pred, args, st.subst), rest, st)

          nil ->
            {name, arity} = key
            raise "existence_error(procedure, #{name}/#{arity}) – unbekanntes Prädikat"
        end
    end
  end

  defp ctx(st), do: %{subst: st.subst, db: st.db}

  # Ergebnis eines Builtins (siehe PrologEx.Builtin) umsetzen
  defp apply_result(result, rest, st) do
    case result do
      r when r in [:ok, true] ->
        run(%{st | goals: rest})

      r when r in [:fail, false] ->
        backtrack(st)

      {:unify, pairs} ->
        case unify_pairs(pairs, st.subst) do
          {:ok, s} -> run(%{st | goals: rest, subst: s})
          :error -> backtrack(st)
        end

      {:call, goal} ->
        run(%{st | goals: [{goal, st.height} | rest]})

      other ->
        raise "Builtin lieferte ungültiges Ergebnis: #{inspect(other)}"
    end
  end

  defp unify_pairs([], s), do: {:ok, s}

  defp unify_pairs([{x, y} | more], s) do
    case unify(x, y, s) do
      {:ok, s} -> unify_pairs(more, s)
      :error -> :error
    end
  end

  # Nichtdeterministische Builtins:
  #   * Liste: direkt, kein Choice Point für das letzte Element
  #   * lazy Liste [r | fn -> rest end]: der Rest wird erst beim
  #     Backtracking berechnet; das Builtin entscheidet selbst, wann [r]
  #     (letzte Lösung, kein Choice Point) kommt
  #   * sonstige Aufzählung (Stream, Range): lazy über :suspend
  defp start_solutions(thunk, rest, st) when is_function(thunk, 0),
    do: start_solutions(thunk.(), rest, st)

  defp start_solutions([], _rest, st), do: backtrack(st)
  defp start_solutions([r], rest, st), do: apply_result(r, rest, st)

  defp start_solutions([r | more], rest, st) do
    st = push(st, {:solutions_list, more, rest, st.subst, st.answer})
    apply_result(r, rest, st)
  end

  defp start_solutions(enum, rest, st) do
    enum
    |> Enumerable.reduce({:cont, nil}, fn x, _ -> {:suspend, x} end)
    |> next_solution(rest, st)
  end

  defp next_solution({:suspended, r, cont}, rest, st) do
    st = push(st, {:solutions, cont, rest, st.subst, st.answer})
    apply_result(r, rest, st)
  end

  defp next_solution(_done_or_halted, _rest, st), do: backtrack(st)

  defp report_time(us0) do
    secs = (System.monotonic_time(:microsecond) - us0) / 1_000_000
    IO.puts(:stderr, "% #{:erlang.float_to_binary(secs, decimals: 3)} seconds")
  end

  # (C -> T ; E): Choice Point für E, dann C mit eigener Cut-Barriere (Cut
  # in der Bedingung ist lokal). Hat C Erfolg, schneidet $cut_to alles ab
  # der Höhe vor E weg – also E und alle Alternativen von C. T und E sind
  # für den Cut transparent (Barriere des umgebenden Prädikats).
  defp if_then_else(c, t, e, cutb, rest, st) do
    h = st.height
    st = push(st, {:alt, {e, cutb}, rest, st.subst, st.answer})
    run(%{st | goals: [{c, h + 1}, {{:"$cut_to", h}, 0}, {t, cutb} | rest]})
  end

  defp add_args(g, []), do: g
  defp add_args({:atom, f}, extra), do: mk(f, extra)
  defp add_args({:struct, f, args}, extra), do: mk(f, args ++ extra)
  defp add_args({:var, _}, _), do: raise("instantiation_error")
  defp add_args(g, _), do: raise("type_error(callable, #{format(g)})")

  # Die Cut-Barriere für den Rumpf ist die Stack-Höhe VOR dem eigenen
  # Choice Point – ein Cut entfernt also auch die restlichen Klauseln.
  defp try_clauses(_goal, _args, [], _rest, st), do: backtrack(st)

  defp try_clauses(goal, args, [cl | more], rest, st) do
    {:clause, _key, nslots, pats, nfresh, body} = cl
    env = :erlang.make_tuple(nslots, nil)

    case match_args(pats, args, env, st.subst, st.next_var) do
      :error ->
        try_clauses(goal, args, more, rest, st)

      {:ok, env, s1, nv} ->
        barrier = st.height

        # Letzte passende Klausel: kein Choice Point
        st =
          if more == [],
            do: st,
            else: push(st, {:clauses, goal, args, more, rest, st.subst, st.answer})

        goals = inst_goals(body, env, nv, barrier, rest)
        run(%{st | goals: goals, subst: s1, next_var: nv + nfresh})
    end
  end

  defp push(st, cp), do: %{st | cps: [cp | st.cps], height: st.height + 1}

  defp backtrack(%{cps: []}), do: :done

  defp backtrack(%{cps: [cp | cps]} = st) do
    st = %{st | cps: cps, height: st.height - 1}

    case cp do
      {:alt, goal, rest, subst, answer} ->
        run(%{st | goals: [goal | rest], subst: subst, answer: answer})

      {:clauses, goal, args, more, rest, subst, answer} ->
        try_clauses(goal, args, more, rest, %{st | subst: subst, answer: answer})

      {:solutions_list, more, rest, subst, answer} ->
        start_solutions(more, rest, %{st | subst: subst, answer: answer})

      {:solutions, cont, rest, subst, answer} ->
        cont.({:cont, nil}) |> next_solution(rest, %{st | subst: subst, answer: answer})

      {:time_fail, t0, subst, answer} ->
        report_time(t0)
        backtrack(%{st | subst: subst, answer: answer})
    end
  end

  # ---------------------------------------------------------------------
  # Kompaktierung der Substitution
  #
  # Lebendig sind nur Variablen, die im Ziel-Stack oder in den
  # Anfragevariablen vorkommen (Choice Points haben eigene Schnappschüsse).
  # Wir setzen die Bindungen dort ein und starten mit leerer Map.
  # Das Memo pro Variable erhält geteilte Teilterme (sonst droht
  # exponentielles Aufblähen bei DAG-artigen Termen).
  # Dabei werden Terme, die durch das Einsetzen ground geworden sind, als
  # gstruct/glist markiert; markierte Terme werden nie wieder durchlaufen.
  # Die nächste Schwelle ist 2 × Anzahl der NICHT-ground Knoten in den
  # lebenden Termen -> amortisiert O(1), unabhängig von großen ground Daten.
  # ---------------------------------------------------------------------

  defp maybe_compact(%{subst: s, threshold: t} = st) when map_size(s) < t, do: st

  defp maybe_compact(st) do
    {goals, {memo, size}} =
      Enum.map_reduce(st.goals, {%{}, 0}, fn {g, cutb}, acc ->
        {g, acc} = compact(g, st.subst, acc)
        {{g, cutb}, acc}
      end)

    {answer, {_memo, size}} =
      Enum.map_reduce(st.answer, {memo, size}, fn {n, t}, acc ->
        {t, acc} = compact(t, st.subst, acc)
        {{n, t}, acc}
      end)

    %{st | goals: goals, answer: answer, subst: %{}, threshold: max(st.min_threshold, 2 * size)}
  end

  defp compact(t, subst, acc) do
    {t2, acc, _changed, _ground} = compact3(t, subst, acc)
    {t2, acc}
  end

  # Ergebnis: {Term, {memo, nicht_ground_größe}, verändert?, ground?}
  # Unveränderte Teilterme werden nicht kopiert, sondern geteilt.
  defp compact3(t, _subst, acc) when is_marked(t), do: {t, acc, false, true}

  defp compact3({:var, _} = var, subst, {memo, size} = acc) do
    case Map.fetch(memo, var) do
      {:ok, {t, g}} ->
        {t, acc, t != var, g}

      :error ->
        case walk(var, subst) do
          {:var, _} = free ->
            {free, {Map.put(memo, var, {free, false}), size}, free != var, false}

          bound ->
            {t, {memo, size}, _ch, g} = compact3(bound, subst, {memo, size})
            {t, {Map.put(memo, var, {t, g}), size}, true, g}
        end
    end
  end

  defp compact3({:struct, f, args} = t, subst, acc) do
    {args2, {acc, changed, ground}} =
      Enum.map_reduce(args, {acc, false, true}, fn arg, {acc, ch, gr} ->
        {a2, acc, c, g} = compact3(arg, subst, acc)
        {a2, {acc, ch or c, gr and g}}
      end)

    {memo, size} = acc

    cond do
      ground -> {{:gstruct, f, args2}, acc, true, true}
      changed -> {{:struct, f, args2}, {memo, size + 1}, true, false}
      true -> {t, {memo, size + 1}, false, false}
    end
  end

  defp compact3([h | t] = l, subst, acc) do
    {h2, acc, ch, gh} = compact3(h, subst, acc)
    {t2, {memo, size} = acc, ct, gt} = compact3(t, subst, acc)

    cond do
      gh and gt -> {cons(h2, t2), acc, true, true}
      ch or ct -> {[h2 | t2], {memo, size + 1}, true, false}
      true -> {l, {memo, size + 1}, false, false}
    end
  end

  defp compact3(t, _subst, acc), do: {t, acc, false, true}

  # ---------------------------------------------------------------------
  # Arithmetik
  # ---------------------------------------------------------------------

  defp eval(t, subst) do
    case unmark_top(walk(t, subst)) do
      n when is_number(n) -> n
      {:struct, op, [x, y]} -> arith(op, eval(x, subst), eval(y, subst))
      {:struct, op, [x]} -> arith(op, eval(x, subst))
      {:atom, "pi"} -> :math.pi()
      {:atom, "e"} -> :math.exp(1)
      {:atom, "max_tagged_integer"} -> 576_460_752_303_423_487
      {:var, _} -> raise "instantiation_error"
      other -> raise "type_error(evaluable, #{format(other)})"
    end
  end

  defp arith("+", x, y), do: x + y
  defp arith("-", x, y), do: x - y
  defp arith("*", x, y), do: x * y

  defp arith("/", x, y) when is_integer(x) and is_integer(y) do
    if y != 0 and rem(x, y) == 0, do: div(x, y), else: x / y
  end

  defp arith("/", x, y), do: x / y
  defp arith("//", x, y), do: div(x, y)
  defp arith("mod", x, y), do: Integer.mod(x, y)
  defp arith("rem", x, y), do: rem(x, y)
  defp arith("min", x, y), do: min(x, y)
  defp arith("max", x, y), do: max(x, y)
  defp arith("**", x, y) when is_integer(x) and is_integer(y) and y >= 0, do: Integer.pow(x, y)
  defp arith("**", x, y), do: :math.pow(x, y)
  defp arith("^", x, y) when is_integer(x) and is_integer(y) and y >= 0, do: Integer.pow(x, y)
  defp arith(">>", x, y), do: Bitwise.bsr(x, y)
  defp arith("<<", x, y), do: Bitwise.bsl(x, y)
  defp arith("/\\", x, y), do: Bitwise.band(x, y)
  defp arith("\\/", x, y), do: Bitwise.bor(x, y)
  defp arith("xor", x, y), do: Bitwise.bxor(x, y)
  defp arith(op, _, _), do: raise("type_error(evaluable, #{op}/2)")

  defp arith("-", x), do: -x
  defp arith("+", x), do: x
  defp arith("abs", x), do: abs(x)
  defp arith("sign", x) when is_integer(x), do: if(x > 0, do: 1, else: if(x < 0, do: -1, else: 0))
  defp arith("sqrt", x), do: :math.sqrt(x)
  defp arith("float", x), do: x * 1.0
  defp arith("integer", x), do: round(x)
  defp arith("truncate", x), do: trunc(x)
  defp arith("round", x), do: round(x)
  defp arith("floor", x), do: floor(x)
  defp arith("ceiling", x), do: ceil(x)
  defp arith("\\", x), do: Bitwise.bnot(x)
  defp arith(op, _), do: raise("type_error(evaluable, #{op}/1)")

  defp compare("<", x, y), do: x < y
  defp compare(">", x, y), do: x > y
  defp compare(">=", x, y), do: x >= y
  defp compare("=<", x, y), do: x <= y
  defp compare("=:=", x, y), do: x == y
  defp compare("=\\=", x, y), do: x != y

  # ---------------------------------------------------------------------
  # Top-Level: Lösungen als lazy Stream
  # ---------------------------------------------------------------------

  # Optionen:
  #   compact_threshold: Mindestschwelle für die Kompaktierung (Standard
  #   #{@min_threshold}); 1 = bei jedem Schritt kompaktieren (für Tests)
  def query(db, goal, opts \\ []) do
    db |> solutions(goal, opts) |> Stream.map(&elem(&1, 0))
  end

  @doc """
  Wie `query/3`, aber jede Lösung als `{antwort, weitere_möglich?}`.
  `weitere_möglich?` ist false, wenn keine Choice Points mehr existieren –
  dann gibt es sicher keine weitere Lösung (der Toplevel fragt nicht nach).
  """
  def solutions(db, goal, opts \\ []) do
    answer =
      goal
      |> query_vars()
      |> Enum.uniq()
      |> Enum.reject(fn {:var, n} -> is_binary(n) and String.starts_with?(n, "_") end)
      |> Enum.map(fn {:var, n} = var -> {n, var} end)

    start = new_state(db, [{goal, 0}], answer, opts)

    Stream.unfold({:start, start}, fn
      :halt ->
        nil

      {:start, st} ->
        emit(run(st))

      {:retry, st} ->
        emit(backtrack(st))
    end)
  end

  defp new_state(db, goals, answer, opts) do
    min = Keyword.get(opts, :compact_threshold, @min_threshold)
    %__MODULE__{goals: goals, db: db, answer: answer, threshold: min, min_threshold: min}
  end

  defp emit(:done), do: nil

  defp emit({:sol, st}) do
    ans = Map.new(st.answer, fn {n, t} -> {n, resolve(t, st.subst)} end)
    if st.height > 0, do: {{ans, true}, {:retry, st}}, else: {{ans, false}, :halt}
  end

  # Für Messungen: erste Lösung plus Zustandsgrößen
  def first_with_stats(db, goal, opts \\ []) do
    case run(new_state(db, [{goal, 0}], [], opts)) do
      {:sol, st} -> {:ok, %{bindings: map_size(st.subst), choicepoints: st.height}}
      :done -> false
    end
  end

  defp query_vars({:var, _} = var), do: [var]
  defp query_vars({:struct, _, args}), do: Enum.flat_map(args, &query_vars/1)
  defp query_vars([h | t]), do: query_vars(h) ++ query_vars(t)
  defp query_vars(_), do: []

  # ---------------------------------------------------------------------
  # Ausgabe
  # ---------------------------------------------------------------------

  # Baut iodata und wandelt erst am Ende in einen String: linear in der
  # Termgröße (verschachteltes <> wäre bei langen Listen quadratisch)
  def format(t), do: t |> fmt() |> IO.iodata_to_binary()

  defp fmt({:var, n}) when is_integer(n), do: ["_G", Integer.to_string(n)]
  defp fmt({:var, n}) when is_binary(n), do: n
  defp fmt({:var, n}), do: inspect(n)
  defp fmt({:atom, n}), do: n
  defp fmt(n) when is_integer(n), do: Integer.to_string(n)
  defp fmt(f) when is_float(f), do: Float.to_string(f)
  defp fmt([]), do: "[]"
  defp fmt([_ | _] = l), do: ["[", fmt_list(l, []), "]"]
  defp fmt({:glist, l}), do: ["[", fmt_list(l, []), "]"]

  defp fmt({tag, f, args}) when tag in [:struct, :gstruct],
    do: [f, "(", Enum.map_intersperse(args, ", ", &fmt/1), ")"]

  defp fmt(other), do: inspect(other)

  # endrekursiv entlang der Liste, Akkumulator in umgekehrter Reihenfolge
  defp fmt_list([h | t], acc) do
    case t do
      [] -> Enum.reverse(acc, [fmt(h)])
      [_ | _] -> fmt_list(t, [", ", fmt(h) | acc])
      {:glist, l} -> fmt_list(l, [", ", fmt(h) | acc])
      _ -> Enum.reverse(acc, [fmt(h), " | ", fmt(t)])
    end
  end

  # Wie SWI: ungebundene Anfragevariablen (X = X) werden nicht gezeigt
  def format_answer(ans) do
    case Enum.reject(ans, fn {k, t} -> t == {:var, k} end) do
      [] -> "true"
      shown -> Enum.map_join(shown, ", ", fn {k, t} -> "#{k} = #{format(t)}" end)
    end
  end
end
