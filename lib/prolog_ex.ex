# PrologEx – Prolog-Kern in Elixir (Stand: Version 2)
#
# Gegenüber Version 1 (Closures als Continuations) ist die Maschine jetzt
# "defunktionalisiert": Ziel-Stack und Choice-Point-Stack sind gewöhnliche
# Daten. Dadurch:
#
#   * Last-Call-Optimierung: das letzte Ziel eines Rumpfs ersetzt den
#     Aufruf, der Ziel-Stack wächst bei Endrekursion nicht.
#   * Kein Choice Point für die letzte passende Klausel, und Indexierung
#     nach dem ersten Argument filtert unpassende Klauseln vorher weg.
#     Deterministische Schleifen hinterlassen so gar keine Choice Points.
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
  #   {:struct, "f", [args]}     Struktur f(args...)
  # Listen: '.'(H, T) und '[]', wie in klassischem Prolog.
  # ---------------------------------------------------------------------

  def v(name), do: {:var, name}
  def a(name), do: {:atom, name}
  def s(name, args), do: {:struct, name, args}

  def list(items, tail \\ {:atom, "[]"}),
    do: List.foldr(items, tail, fn x, acc -> {:struct, ".", [x, acc]} end)

  def fact(head), do: {head, a("true")}
  def rule(head, goals), do: {head, conj(goals)}

  def conj([g]), do: g
  def conj([g | rest]), do: s(",", [g, conj(rest)])

  # ---------------------------------------------------------------------
  # Unifikation (unverändert)
  # ---------------------------------------------------------------------

  def walk({:var, _} = var, subst) do
    case Map.fetch(subst, var) do
      {:ok, t} -> walk(t, subst)
      :error -> var
    end
  end

  def walk(t, _subst), do: t

  def unify(x, y, subst) do
    x = walk(x, subst)
    y = walk(y, subst)

    cond do
      x == y -> {:ok, subst}
      match?({:var, _}, x) -> {:ok, Map.put(subst, x, y)}
      match?({:var, _}, y) -> {:ok, Map.put(subst, y, x)}
      true -> unify_struct(x, y, subst)
    end
  end

  defp unify_struct({:struct, f, xs}, {:struct, f, ys}, subst)
       when length(xs) == length(ys),
       do: unify_args(xs, ys, subst)

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
      other -> other
    end
  end

  # ---------------------------------------------------------------------
  # Datenbank
  #   %{{name, arity} => [{index_key, nvars, head, body}]}
  # Klauselvariablen werden beim Laden auf {:local, i} nummeriert, damit
  # das Umbenennen später nur noch "i + offset" ist. Jedes "_" bekommt
  # eine eigene Nummer.
  # ---------------------------------------------------------------------

  def consult(clauses) do
    Enum.reduce(clauses, %{}, fn {head, body}, db ->
      {head, map} = number_vars(head, %{})
      {body, map} = number_vars(body, map)
      entry = {index_key(first_arg(head)), map_size(map), head, body}
      Map.update(db, key(head), [entry], &(&1 ++ [entry]))
    end)
  end

  defp number_vars({:var, "_"}, map) do
    i = map_size(map)
    {{:var, {:local, i}}, Map.put(map, {:anon, i}, i)}
  end

  defp number_vars({:var, n}, map) do
    case Map.fetch(map, n) do
      {:ok, i} ->
        {{:var, {:local, i}}, map}

      :error ->
        i = map_size(map)
        {{:var, {:local, i}}, Map.put(map, n, i)}
    end
  end

  defp number_vars({:struct, f, args}, map) do
    {args, map} = Enum.map_reduce(args, map, &number_vars/2)
    {{:struct, f, args}, map}
  end

  defp number_vars(t, map), do: {t, map}

  defp key({:struct, f, args}), do: {f, length(args)}
  defp key({:atom, f}), do: {f, 0}

  defp first_arg({:struct, _, [x | _]}), do: x
  defp first_arg(_), do: nil

  # Hauptfunktor des ersten Arguments; :any = Variable (passt auf alles)
  defp index_key(nil), do: :any
  defp index_key({:var, _}), do: :any
  defp index_key({:struct, f, args}), do: {f, length(args)}
  defp index_key(t), do: t

  defp candidates(db, goal, subst) do
    case Map.fetch(db, key(goal)) do
      {:ok, clauses} ->
        case index_key(walk(first_arg(goal), subst)) do
          :any -> clauses
          k -> Enum.filter(clauses, fn {ck, _, _, _} -> ck == :any or ck == k end)
        end

      :error ->
        raise "existence_error: #{inspect(key(goal))}"
    end
  end

  defp rename({:var, {:local, i}}, base), do: {:var, base + i}
  defp rename({:struct, f, args}, base), do: {:struct, f, Enum.map(args, &rename(&1, base))}
  defp rename(t, _base), do: t

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

  defp step(goal, _cutb, rest, st),
    do: try_clauses(goal, candidates(st.db, goal, st.subst), rest, st)

  # Die Cut-Barriere für den Rumpf ist die Stack-Höhe VOR dem eigenen
  # Choice Point – ein Cut entfernt also auch die restlichen Klauseln.
  defp try_clauses(_goal, [], _rest, st), do: backtrack(st)

  defp try_clauses(goal, [{_, nvars, head, body} | more], rest, st) do
    base = st.next_var
    st = %{st | next_var: base + nvars}

    case unify(goal, rename(head, base), st.subst) do
      :error ->
        try_clauses(goal, more, rest, st)

      {:ok, s1} ->
        barrier = st.height

        # Letzte passende Klausel: kein Choice Point
        st =
          if more == [],
            do: st,
            else: push(st, {:clauses, goal, more, rest, st.subst, st.answer})

        run(%{st | goals: [{rename(body, base), barrier} | rest], subst: s1})
    end
  end

  defp push(st, cp), do: %{st | cps: [cp | st.cps], height: st.height + 1}

  defp backtrack(%{cps: []}), do: :done

  defp backtrack(%{cps: [cp | cps]} = st) do
    st = %{st | cps: cps, height: st.height - 1}

    case cp do
      {:alt, goal, rest, subst, answer} ->
        run(%{st | goals: [goal | rest], subst: subst, answer: answer})

      {:clauses, goal, more, rest, subst, answer} ->
        try_clauses(goal, more, rest, %{st | subst: subst, answer: answer})
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
  defp query_vars(_), do: []

  # ---------------------------------------------------------------------
  # Ausgabe
  # ---------------------------------------------------------------------

  def format({:var, n}) when is_integer(n), do: "_G#{n}"
  def format({:var, n}), do: n
  def format({:atom, n}), do: n
  def format(n) when is_integer(n), do: Integer.to_string(n)
  def format({:struct, ".", _} = l), do: "[" <> format_list(l) <> "]"
  def format({:struct, f, args}), do: f <> "(" <> Enum.map_join(args, ", ", &format/1) <> ")"

  defp format_list({:struct, ".", [h, {:atom, "[]"}]}), do: format(h)

  defp format_list({:struct, ".", [h, {:struct, ".", _} = t]}),
    do: format(h) <> ", " <> format_list(t)

  defp format_list({:struct, ".", [h, t]}), do: format(h) <> " | " <> format(t)

  def format_answer(ans) when map_size(ans) == 0, do: "true"
  def format_answer(ans), do: Enum.map_join(ans, ", ", fn {k, t} -> "#{k} = #{format(t)}" end)
end
