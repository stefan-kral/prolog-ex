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
  #   {:var, 42}                 frische Variable (umbenannte Klauselvariable)
  #   {:atom, "foo"}             Atom – bewusst KEIN Elixir-Atom!
  #   integer                    Zahl
  #   {:struct, "f", [args]}     Struktur f(args...), Stelligkeit >= 1
  #   []                         das Atom '[]'
  #   [h | t]                    die Struktur '.'(h, t)
  #
  # Kanonische Form: '.'/2 ist IMMER eine Cons-Zelle, '[]' IMMER [].
  # Deshalb werden Terme ausschließlich über a/1 und mk/2 gebaut.
  # Elixir-Listen kommen sonst nur als Argumentliste in {:struct, f, args}
  # vor – auf Term-Ebene ist eine Liste also immer eine Prolog-Liste.
  # ---------------------------------------------------------------------

  def v(name), do: {:var, name}

  def a("[]"), do: []
  def a(name), do: {:atom, name}

  def mk(".", [h, t]), do: [h | t]
  def mk(name, []), do: a(name)
  def mk(name, args), do: {:struct, name, args}

  def s(name, args), do: mk(name, args)

  # [x1, ..., xn | tail]; ++ akzeptiert auch einen Nicht-Listen-Rest
  def list(items, tail \\ []), do: items ++ tail

  # Einheitlicher Listenzugriff. Spätere alternative Darstellungen
  # (Text-Ansichten auf Binaries) kommen hier dazu, ohne dass sich
  # Aufrufer ändern müssen.
  def uncons([h | t]), do: {:cons, h, t}
  def uncons([]), do: :empty
  def uncons(_), do: :other

  def cons(h, t), do: [h | t]

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

  defp unify_struct({:struct, f, xs}, {:struct, f, ys}, subst)
       when length(xs) == length(ys),
       do: unify_args(xs, ys, subst)

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

  def resolve(t, subst) do
    case walk(t, subst) do
      {:struct, f, args} -> {:struct, f, Enum.map(args, &resolve(&1, subst))}
      [h | t] -> [resolve(h, subst) | resolve(t, subst)]
      other -> other
    end
  end

  # ---------------------------------------------------------------------
  # Datenbank
  #   %{{name, arity} => {:pred, alle, nach_schlüssel, nur_var_klauseln}}
  # nach_schlüssel: für jeden Erstargument-Schlüssel die passenden
  # Klauseln (inkl. derer mit Variable an erster Stelle) in Originalreihenfolge.
  # ---------------------------------------------------------------------

  alias PrologEx.Compiler

  def consult(clauses) do
    clauses
    |> Enum.map(fn {head, _} = cl -> {Compiler.key(head), Compiler.compile_clause(cl)} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {k, cls} -> {k, build_pred(cls)} end)
  end

  defp build_pred(cls) do
    keys = cls |> Enum.map(&elem(&1, 1)) |> Enum.reject(&(&1 == :any)) |> Enum.uniq()

    by_key = Map.new(keys, fn k -> {k, Enum.filter(cls, &(elem(&1, 1) in [k, :any]))} end)

    {:pred, cls, by_key, Enum.filter(cls, &(elem(&1, 1) == :any))}
  end

  # Hauptfunktor als Indexschlüssel; :any = Variable (passt auf alles)
  @doc false
  def index_key({:var, _}), do: :any
  def index_key({:struct, f, args}), do: {f, length(args)}
  def index_key([_ | _]), do: {".", 2}
  def index_key(t), do: t

  defp candidates(db, goal, args, subst) do
    case Map.fetch(db, Compiler.key(goal)) do
      {:ok, {:pred, all, by_key, var_only}} ->
        case args do
          [] ->
            all

          [x | _] ->
            case walk(x, subst) do
              {:var, _} -> all
              t -> Map.get(by_key, index_key(t), var_only)
            end
        end

      :error ->
        raise "existence_error: #{inspect(Compiler.key(goal))}"
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

      {:var, _} = v ->
        {term, env, nv} = build(p, env, nv)
        {:ok, env, bind(v, term, s), nv}

      _ ->
        :error
    end
  end

  defp m({:struct, f, n, ps} = p, t, env, s, nv) do
    case walk(t, s) do
      {:struct, ^f, args} when length(args) == n ->
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
    {[h | t], env, nv}
  end

  def build({:struct, f, _n, ps}, env, nv) do
    {args, env, nv} = build_args(ps, env, nv)
    {{:struct, f, args}, env, nv}
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
  defp inst({:t_list, h, t}, env, base), do: [inst(h, env, base) | inst(t, env, base)]
  defp inst({:t_struct, f, args}, env, base), do: {:struct, f, inst_args(args, env, base)}

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
            threshold: @min_threshold

  defp run(st) do
    st = maybe_compact(st)

    case st.goals do
      [] -> {:sol, st}
      [{goal, cutb} | rest] -> step(walk(goal, st.subst), cutb, rest, st)
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
    st = push(st, {:alt, {g2, cutb}, rest, st.subst, st.answer})
    run(%{st | goals: [{g1, cutb} | rest]})
  end

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

  defp step(goal, _cutb, rest, st) do
    args = Compiler.args_of(goal)
    try_clauses(goal, args, candidates(st.db, goal, args, st.subst), rest, st)
  end

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
  # Die nächste Schwelle ist 2 × Größe der lebenden Terme -> amortisiert O(1).
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

    %{st | goals: goals, answer: answer, subst: %{}, threshold: max(@min_threshold, 2 * size)}
  end

  # Unveränderte Teilterme werden nicht kopiert, sondern das Original wird
  # zurückgegeben – so bleibt z. B. eine große, variablenfreie Liste geteilt.
  defp compact(t, subst, acc) do
    {t2, acc, _changed} = compact3(t, subst, acc)
    {t2, acc}
  end

  defp compact3({:var, _} = var, subst, {memo, size} = acc) do
    case Map.fetch(memo, var) do
      {:ok, t} ->
        {t, acc, t != var}

      :error ->
        case walk(var, subst) do
          {:var, _} = free ->
            {free, {Map.put(memo, var, free), size}, free != var}

          bound ->
            {t, {memo, size}} = compact(bound, subst, {memo, size})
            {t, {Map.put(memo, var, t), size}, true}
        end
    end
  end

  defp compact3({:struct, f, args} = t, subst, acc) do
    {args2, {{memo, size}, changed}} =
      Enum.map_reduce(args, {acc, false}, fn arg, {acc, ch} ->
        {a2, acc, c} = compact3(arg, subst, acc)
        {a2, {acc, ch or c}}
      end)

    if changed,
      do: {{:struct, f, args2}, {memo, size + 1}, true},
      else: {t, {memo, size + 1}, false}
  end

  defp compact3([h | t] = l, subst, acc) do
    {h2, acc, ch} = compact3(h, subst, acc)
    {t2, {memo, size}, ct} = compact3(t, subst, acc)

    if ch or ct,
      do: {[h2 | t2], {memo, size + 1}, true},
      else: {l, {memo, size + 1}, false}
  end

  defp compact3(t, _subst, acc), do: {t, acc, false}

  # ---------------------------------------------------------------------
  # Arithmetik
  # ---------------------------------------------------------------------

  defp eval(t, subst) do
    case walk(t, subst) do
      n when is_integer(n) -> n
      {:struct, "+", [x, y]} -> eval(x, subst) + eval(y, subst)
      {:struct, "-", [x, y]} -> eval(x, subst) - eval(y, subst)
      {:struct, "*", [x, y]} -> eval(x, subst) * eval(y, subst)
      {:struct, "//", [x, y]} -> div(eval(x, subst), eval(y, subst))
      {:struct, "mod", [x, y]} -> Integer.mod(eval(x, subst), eval(y, subst))
      {:var, _} -> raise "instantiation_error"
      other -> raise "type_error(evaluable, #{format(other)})"
    end
  end

  defp compare("<", x, y), do: x < y
  defp compare(">", x, y), do: x > y
  defp compare(">=", x, y), do: x >= y
  defp compare("=<", x, y), do: x <= y
  defp compare("=:=", x, y), do: x == y
  defp compare("=\\=", x, y), do: x != y

  # ---------------------------------------------------------------------
  # Top-Level: Lösungen als lazy Stream
  # ---------------------------------------------------------------------

  def query(db, goal) do
    answer =
      goal
      |> query_vars()
      |> Enum.uniq()
      |> Enum.reject(&(&1 == {:var, "_"}))
      |> Enum.map(fn {:var, n} = var -> {n, var} end)

    start = %__MODULE__{goals: [{goal, 0}], db: db, answer: answer}

    Stream.unfold({:start, start}, fn
      :halt ->
        nil

      {:start, st} ->
        emit(run(st))

      {:retry, st} ->
        emit(backtrack(st))
    end)
  end

  defp emit(:done), do: nil

  defp emit({:sol, st}) do
    ans = Map.new(st.answer, fn {n, t} -> {n, resolve(t, st.subst)} end)
    {ans, {:retry, st}}
  end

  # Für Messungen: erste Lösung plus Zustandsgrößen
  def first_with_stats(db, goal) do
    case run(%__MODULE__{goals: [{goal, 0}], db: db}) do
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

  def format({:var, n}) when is_integer(n), do: "_G#{n}"
  def format({:var, n}), do: n
  def format({:atom, n}), do: n
  def format(n) when is_integer(n), do: Integer.to_string(n)
  def format([]), do: "[]"
  def format([_ | _] = l), do: "[" <> format_list(l) <> "]"
  def format({:struct, f, args}), do: f <> "(" <> Enum.map_join(args, ", ", &format/1) <> ")"

  defp format_list([h]), do: format(h)
  defp format_list([h | [_ | _] = t]), do: format(h) <> ", " <> format_list(t)
  defp format_list([h | t]), do: format(h) <> " | " <> format(t)

  def format_answer(ans) when map_size(ans) == 0, do: "true"
  def format_answer(ans), do: Enum.map_join(ans, ", ", fn {k, t} -> "#{k} = #{format(t)}" end)
end
