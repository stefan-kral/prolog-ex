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

  # Einzige Stelle, an der Variablen gebunden werden. Eine attributierte
  # Variable ({:var, {:attv, id}}) wird zusätzlich unter :wake vermerkt; die
  # Maschine weckt danach ihre Ziele (siehe after_unify/2). Für normale
  # Variablen kostet das nichts (Mustervergleich auf den Namen).
  def bind({:var, {:attv, _}} = var, t, subst),
    do: subst |> Map.put(var, t) |> Map.update(:wake, [var], &[var | &1])

  def bind({:var, _} = var, t, subst), do: Map.put(subst, var, t)

  # ---------------------------------------------------------------------
  # Attributierte Variablen
  #
  # Eine Variable bekommt Attribute, indem sie an eine frische attributierte
  # Variable {:var, {:attv, id}} gebunden wird. Die Attribute stehen in der
  # Substitution unter {:attrs, id} als %{modul => Prolog-Term}; damit
  # überstehen sie Backtracking wie jede Bindung. Für alle anderen Teile
  # des Systems ist eine attributierte Variable eine normale ungebundene
  # Variable.
  #
  # Coroutining (freeze, dif, when) nutzt das Attribut "$susp": eine
  # Prolog-Liste von '$s'(Done, Weckziel, Restziel). Wird die Variable
  # gebunden, laufen die Weckziele aller Einträge mit ungebundenem Done.
  # ---------------------------------------------------------------------

  @doc "Ist die (dereferenzierte) Variable attributiert?"
  def attv?({:var, {:attv, _}}), do: true
  def attv?(_), do: false

  @doc "Attribute einer Variablen (dereferenziert): Map modul => Term"
  def get_attrs(var, subst) do
    case walk(var, subst) do
      {:var, {:attv, id}} -> Map.get(subst, {:attrs, id}, %{})
      _ -> %{}
    end
  end

  @doc """
  Attribut `module` der ungebundenen Variable `var` setzen. Eine normale
  Variable wird dazu an eine neue attributierte gebunden (ohne Wecken).
  Ergebnis: neue Substitution.
  """
  def put_attr(subst, var, module, value) do
    case walk(var, subst) do
      {:var, {:attv, id}} ->
        Map.update(subst, {:attrs, id}, %{module => value}, &Map.put(&1, module, value))

      {:var, _} = v ->
        id = System.unique_integer([:positive])
        subst |> Map.put(v, {:var, {:attv, id}}) |> Map.put({:attrs, id}, %{module => value})
    end
  end

  @doc "Suspension '$s'(Done, Weckziel, Restziel) an alle Variablen hängen"
  def suspend(subst, vars, susp) do
    Enum.reduce(vars, subst, fn v, s ->
      old = get_attrs(v, s) |> Map.get("$susp", [])
      put_attr(s, v, "$susp", append_term(old, susp))
    end)
  end

  defp append_term([], x), do: [x]
  defp append_term([h | t], x), do: [h | append_term(t, x)]
  defp append_term({:glist, _} = l, x), do: append_term(unmark(l), x)

  @doc """
  Attributierte Variablen in t, in Reihenfolge des Auftretens, auch die nur
  über Attribute erreichbaren (wie SWI term_attvars/2).
  """
  def term_attvars(t, subst) do
    {acc, _} = attvars(t, subst, {[], MapSet.new()})
    Enum.reverse(acc)
  end

  defp attvars(t, subst, {acc, seen} = st) do
    case walk(t, subst) do
      {:var, {:attv, id}} = v ->
        if MapSet.member?(seen, v) do
          st
        else
          st = {[v | acc], MapSet.put(seen, v)}

          subst
          |> Map.get({:attrs, id}, %{})
          |> Enum.reduce(st, fn {_m, a}, st -> attvars(a, subst, st) end)
        end

      {:struct, _, args} ->
        Enum.reduce(args, st, &attvars(&1, subst, &2))

      [h | tl] ->
        attvars(tl, subst, attvars(h, subst, st))

      _ ->
        st
    end
  end

  @doc "Aktive Suspensionen ('$s'-Terme mit ungebundenem Done) einer Variablen"
  def suspensions(var, subst) do
    var
    |> get_attrs(subst)
    |> Map.get("$susp", [])
    |> prolog_items()
    |> Enum.filter(fn s ->
      {_, "$s", [done, _, _]} = unmark_top(s)
      match?({:var, _}, walk(done, subst))
    end)
  end

  defp prolog_items([]), do: []
  defp prolog_items([h | t]), do: [h | prolog_items(t)]
  defp prolog_items({:glist, l}), do: prolog_items(unmark({:glist, l}))

  # ---------------------------------------------------------------------
  # Occurs-Check (Flag occurs_check = false | true | error)
  #
  # bind_checked/3 ist die Bindung für alle Stellen, an denen die Variable
  # im gebundenen Term vorkommen KÖNNTE: allgemeine Unifikation und Write-
  # Modus im Klauselkopf. (Bindung an Konstanten oder markierte ground
  # Terme im Kopf braucht keinen Check und nimmt bind/3.)
  # Der Modus liegt unter einem eigenen Schlüssel im Prozess: bei false
  # kostet das ein Process.get je Bindung.
  # ---------------------------------------------------------------------

  @occurs_key :prolog_ex_occurs_check

  @doc false
  def occurs_key, do: @occurs_key

  def bind_checked(var, t, subst) do
    case Process.get(@occurs_key) do
      nil ->
        {:ok, bind(var, t, subst)}

      mode ->
        if occurs?(var, t, subst) do
          if mode == :error,
            do: PrologEx.Error.error!(mk("occurs_check", [var, t])),
            else: :error
        else
          {:ok, bind(var, t, subst)}
        end
    end
  end

  @doc "Kommt die (ungebundene) Variable var in t vor?"
  def occurs?(var, t, subst) do
    case walk(t, subst) do
      ^var -> true
      m when is_marked(m) -> false
      {:struct, _, args} -> Enum.any?(args, &occurs?(var, &1, subst))
      # Listenrest per Tail Call: keine Rekursionstiefe entlang der Liste
      [h | tl] -> occurs?(var, h, subst) or occurs?(var, tl, subst)
      _ -> false
    end
  end

  def unify(x, y, subst) do
    x = walk(x, subst)
    y = walk(y, subst)

    cond do
      # strikt: 1 und 1.0 sind verschiedene Terme (Elixirs == hält sie für gleich)
      x === y ->
        {:ok, subst}

      # normale Variable an attributierte binden, nicht umgekehrt (kein Wecken)
      match?({:var, {:attv, _}}, x) and match?({:var, _}, y) and not attv?(y) ->
        bind_checked(y, x, subst)

      match?({:var, _}, x) ->
        bind_checked(x, y, subst)

      match?({:var, _}, y) ->
        bind_checked(y, x, subst)

      true ->
        unify_struct(x, y, subst)
    end
  end

  @doc "Unifikation immer mit Occurs-Check (unabhängig vom Flag)"
  def unify_with_occurs_check(x, y, subst) do
    old = Process.put(@occurs_key, true)

    try do
      unify(x, y, subst)
    after
      if old, do: Process.put(@occurs_key, old), else: Process.delete(@occurs_key)
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

  @doc """
  Kopie eines Terms mit frischen Variablen (gleiche Variablen bleiben
  gleich). Markierte ground Teilterme werden geteilt, nicht kopiert; ground
  gewordene Teile werden markiert.
  """
  def copy_fresh(t, subst) do
    {c, _map} = copy(t, subst, %{})
    c
  end

  defp copy(t, subst, map) do
    case walk(t, subst) do
      {:var, _} = var ->
        case Map.fetch(map, var) do
          {:ok, fresh} ->
            {fresh, map}

          :error ->
            fresh = {:var, "_B#{System.unique_integer([:positive])}"}
            {fresh, Map.put(map, var, fresh)}
        end

      m when is_marked(m) ->
        {m, map}

      {:struct, f, args} ->
        {args, map} = Enum.map_reduce(args, map, &copy(&1, subst, &2))
        {mk_struct(f, args), map}

      [h | tl] ->
        {h, map} = copy(h, subst, map)
        {tl, map} = copy(tl, subst, map)
        {cons(h, tl), map}

      atomic ->
        {atomic, map}
    end
  end

  # ---------------------------------------------------------------------
  # Datenbank
  #
  #   {modul, name, arity}         => prädikat
  #   :dynamic                     => MapSet der dynamischen {modul, name, arity}
  #   {:import, modul, name, arity} => Quellmodul (use_module)
  #   {:module, modul}             => %{exports: MapSet, file: pfad | nil}
  #   {:meta, modul, name, arity}  => meta_predicate-Angaben
  #   {:file, pfad}                => Modul der geladenen Datei
  #
  # Module sind Strings ("user", "lists", ...). Wie ein Aufruf aufgelöst
  # wird, steht bei locate/4.
  #
  # prädikat ist eines von
  #   {:pred, alle, nach_schlüssel, nur_var_klauseln, einträge}   kompiliert
  #   {:stale, vorne, hinten_umgekehrt}                           nach assert
  # einträge: [{kennung, {kopf, rumpf}, kompilierte_klausel}] in Reihenfolge;
  # die Kennung (eindeutige Ganzzahl) identifiziert eine Klausel für retract.
  # nach_schlüssel: für jeden Erstargument-Schlüssel die passenden Klauseln
  # (inkl. derer mit Variable an erster Stelle) in Originalreihenfolge.
  #
  # assertz/asserta hängen nur an ({:stale, ...}, O(1)); kompiliert und
  # indexiert wird beim nächsten Aufruf, einmal für alle neuen Klauseln.
  #
  # Die Datenbank einer laufenden Sitzung liegt im Prozess (wie die Flags):
  # Änderungen überstehen Backtracking und gelten auch aus findall/\+ heraus.
  # query/3 setzt sie beim Start, current_db/0 liest sie zurück.
  # ---------------------------------------------------------------------

  alias PrologEx.Compiler

  @db_key :prolog_ex_db

  @doc "Datenbank der laufenden Sitzung (nach assert/retract)"
  def current_db, do: Process.get(@db_key, %{})

  @doc false
  def put_db(db), do: Process.put(@db_key, db)

  @doc false
  def update_db(fun), do: put_db(fun.(current_db()))

  def consult(clauses), do: consult(%{}, clauses)

  @doc """
  Fügt Klauseln (in Modul `module`, Standard `"user"`) hinzu. Jedes
  Prädikat, das in `clauses` vorkommt, ERSETZT eine bestehende Definition
  (Reconsult-Semantik); andere bleiben erhalten.
  """
  def consult(db, clauses, module \\ "user") do
    new = Map.new(build_preds(clauses), fn {{n, a}, p} -> {{module, n, a}, p} end)
    Map.merge(db, new)
  end

  @doc "Klauseln zu Prädikaten: %{{name, arity} => prädikat}"
  def build_preds(clauses) do
    clauses
    |> Enum.group_by(fn {head, _} -> Compiler.key(head) end)
    |> Map.new(fn {k, cls} -> {k, build_pred(cls)} end)
  end

  @doc """
  Deklariert ein dynamisches Prädikat (ohne Klauseln: Aufrufe scheitern).
  `key`: `{modul, name, arity}` oder `{name, arity}` (Modul user).
  """
  def declare(db, key) do
    key = pkey(key)

    db
    |> Map.put_new(key, build_pred([]))
    |> Map.update(:dynamic, MapSet.new([key]), &MapSet.put(&1, key))
  end

  @doc false
  def dynamic?(db, key), do: MapSet.member?(Map.get(db, :dynamic, MapSet.new()), pkey(key))

  defp pkey({n, a}), do: {"user", n, a}
  defp pkey({_m, _n, _a} = k), do: k

  @doc """
  Wo ist name/arity, aufgerufen in Modul `mod`, definiert? (wie SICStus)

    1. in `mod` selbst (Datenbank oder Bibliotheks-Builtin von `mod`)
    2. von `mod` importiert (use_module)
    3. in `system`

  Sonst nirgends: kein Rückgriff auf `user` und kein Autoload. Was ein
  Modul aus `user` oder einer Bibliothek braucht, muss es importieren oder
  qualifiziert aufrufen (`user:foo`). Das Ergebnis hängt so nur vom
  aktuellen Inhalt der Datenbank ab, nicht von der Aufrufgeschichte.

  Ergebnis: `{:db, modul, prädikat}`, `{:builtin, modul, eintrag}`
  (siehe `PrologEx.Builtins.lookup/3`) oder `:none`.
  """
  def locate(db, mod, name, arity) do
    with :none <- visible(db, mod, name, arity) do
      local(db, "system", name, arity)
    end
  end

  @doc """
  Alle Exporte des Bibliotheksmoduls `lib` in Modul `into` importieren
  (wie `use_module(library(lib))`; für Elixir-Aufrufer und Tests).
  """
  def use_library(db, lib, into \\ "user") do
    exports = PrologEx.Builtins.exports(lib) || raise ArgumentError, "keine Bibliothek: #{lib}"

    Enum.reduce(exports, db, fn {n, a}, db ->
      if Map.has_key?(db, {into, n, a}), do: db, else: Map.put(db, {:import, into, n, a}, lib)
    end)
  end

  # lokal oder importiert
  defp visible(db, mod, name, arity) do
    case local(db, mod, name, arity) do
      :none ->
        case Map.fetch(db, {:import, mod, name, arity}) do
          {:ok, src} -> local(db, src, name, arity)
          :error -> :none
        end

      found ->
        found
    end
  end

  defp local(db, mod, name, arity) do
    case Map.fetch(db, {mod, name, arity}) do
      {:ok, pred} ->
        {:db, mod, pred}

      :error ->
        case PrologEx.Builtins.lookup(mod, name, arity) do
          nil -> :none
          entry -> {:builtin, mod, entry}
        end
    end
  end

  @doc false
  def entry({head, body} = src),
    do: {System.unique_integer([:positive]), src, Compiler.compile_clause({head, body})}

  defp build_pred(source), do: pred_from_entries(Enum.map(source, &entry/1))

  @doc false
  # Index in einem Durchgang: Klauseln je Schlüssel, Klauseln mit Variable
  # an erster Stelle werden in jede Schlüsselliste an ihrer Position
  # eingemischt (O(n + Schlüssel × Var-Klauseln) statt O(n × Schlüssel))
  def pred_from_entries(entries) do
    cls = Enum.map(entries, &elem(&1, 2))
    indexed = Enum.with_index(cls)
    var_only = for {c, _} <- indexed, elem(c, 1) == :any, do: c
    any_idx = for {c, i} <- indexed, elem(c, 1) == :any, do: {i, c}

    by_key =
      indexed
      |> Enum.reject(fn {c, _} -> elem(c, 1) == :any end)
      |> Enum.group_by(fn {c, _} -> elem(c, 1) end, fn {c, i} -> {i, c} end)
      |> Map.new(fn {k, own} -> {k, merge_by_index(own, any_idx)} end)

    {:pred, cls, by_key, var_only, entries}
  end

  defp merge_by_index([], b), do: Enum.map(b, &elem(&1, 1))
  defp merge_by_index(a, []), do: Enum.map(a, &elem(&1, 1))

  defp merge_by_index([{i, x} | a], [{j, _} | _] = b) when i < j,
    do: [x | merge_by_index(a, b)]

  defp merge_by_index(a, [{_, y} | b]), do: [y | merge_by_index(a, b)]

  @doc false
  def pred_entries({:pred, _, _, _, entries}), do: entries
  def pred_entries({:pending, p, [], []}), do: pred_entries(p)
  def pred_entries({:pending, p, fr, bk}), do: fr ++ pred_entries(p) ++ Enum.reverse(bk)
  def pred_entries({:stale, front, []}), do: front
  def pred_entries({:stale, front, back}), do: front ++ Enum.reverse(back)

  @doc false
  # Klausel mit Kennung `ref` entfernen. Kosten O(Position der Klausel):
  # das häufige "erste Klausel zurückziehen" ist O(1).
  def remove_entry(pred, ref) do
    # hinten angehängte Klauseln einmal nach vorn holen, damit folgende
    # retracts (und ihre Schnappschüsse) wieder O(1) beginnen
    entries = pred_entries(pred)

    case drop_ref(entries, ref, []) do
      {:ok, rest} -> {:stale, rest, []}
      :error -> {:stale, entries, []}
    end
  end

  defp drop_ref([], _ref, _acc), do: :error
  defp drop_ref([{ref, _, _} | rest], ref, acc), do: {:ok, :lists.reverse(acc, rest)}
  defp drop_ref([e | rest], ref, acc), do: drop_ref(rest, ref, [e | acc])

  @doc "Quelltext eines Prädikats: [{kopf, rumpf}]"
  def pred_source(pred), do: pred |> pred_entries() |> Enum.map(&elem(&1, 1))

  @doc false
  def materialize({:pred, _, _, _, _} = p), do: p

  def materialize({:pending, {:pred, cls, _, _, _} = p, fr, bk} = pending) do
    # viele neue Klauseln: Neubau ist dann billiger als Erweitern
    if length(fr) + length(bk) > length(cls),
      do: pred_from_entries(pred_entries(pending)),
      else: extend(p, fr, Enum.reverse(bk))
  end

  def materialize(p), do: pred_from_entries(pred_entries(p))

  # Index um vorn (asserta) und hinten (assertz) angefügte Klauseln
  # erweitern, statt ihn neu aufzubauen (~75× billiger; übrig bleibt das
  # Kopieren der Klausellisten)
  defp extend({:pred, cls, by_key, var_only, entries}, fr, bk) do
    # vorn: von hinten nach vorn voranstellen
    {by_key, var_only} =
      fr
      |> Enum.reverse()
      |> Enum.reduce({by_key, var_only}, fn {_, _, c}, {bk_, vo} ->
        case elem(c, 1) do
          :any -> {Map.new(bk_, fn {k, l} -> {k, [c | l]} end), [c | vo]}
          k -> {Map.update(bk_, k, [c | vo], &[c | &1]), vo}
        end
      end)

    # hinten: anhängen (neue Schlüssel beginnen mit allen Var-Klauseln)
    {by_key, var_only_rev} =
      Enum.reduce(bk, {by_key, Enum.reverse(var_only)}, fn {_, _, c}, {bk_, vr} ->
        case elem(c, 1) do
          :any -> {Map.new(bk_, fn {k, l} -> {k, l ++ [c]} end), [c | vr]}
          k -> {Map.update(bk_, k, Enum.reverse([c | vr]), &(&1 ++ [c])), vr}
        end
      end)

    cl = &elem(&1, 2)

    {:pred, Enum.map(fr, cl) ++ cls ++ Enum.map(bk, cl), by_key, Enum.reverse(var_only_rev),
     fr ++ entries ++ bk}
  end

  @doc false
  # Zustände eines Prädikats in der Datenbank:
  #   {:pred, ...}                 übersetzt und indiziert
  #   {:pending, pred, vorn, hinten_rev}  pred plus angefügte Klauseln;
  #                                der Index wird beim nächsten Aufruf
  #                                ERWEITERT (materialize/1)
  #   {:stale, vorn, hinten_rev}   nach retract: Index wird neu gebaut
  # Ein assert ist so immer O(1).
  def assert_entry(pred, entry, :z) do
    case pred do
      {:pred, _, _, _, _} -> {:pending, pred, [], [entry]}
      {:pending, p, fr, bk} -> {:pending, p, fr, [entry | bk]}
      {:stale, front, back} -> {:stale, front, [entry | back]}
    end
  end

  def assert_entry(pred, entry, :a) do
    case pred do
      {:pred, _, _, _, _} -> {:pending, pred, [entry], []}
      {:pending, p, fr, bk} -> {:pending, p, [entry | fr], bk}
      {:stale, front, back} -> {:stale, [entry | front], back}
    end
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
        # Write-Modus: der gebaute Term kann Slot-Inhalte enthalten, also
        # ggf. mit Occurs-Check binden
        {term, env, nv} = build(p, env, nv)

        case bind_checked(v, term, s) do
          {:ok, s} -> {:ok, env, s, nv}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp m({:struct, f, n, ps} = p, t, env, s, nv) do
    case walk(t, s) do
      {tag, ^f, args} when tag in [:struct, :gstruct] and length(args) == n ->
        match_args(ps, args, env, s, nv)

      {:var, _} = v ->
        # Write-Modus: der gebaute Term kann Slot-Inhalte enthalten, also
        # ggf. mit Occurs-Check binden
        {term, env, nv} = build(p, env, nv)

        case bind_checked(v, term, s) do
          {:ok, s} -> {:ok, env, s, nv}
          :error -> :error
        end

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

  defp inst_goals([], _env, _base, _barrier, _mod, rest), do: rest

  defp inst_goals([g | gs], env, base, barrier, mod, rest),
    do: [{inst(g, env, base), barrier, mod} | inst_goals(gs, env, base, barrier, mod, rest)]

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
            min_threshold: @min_threshold,
            # Zähler für call_nth/2: überstehen Backtracking (nicht in subst)
            counters: %{},
            # catch/3-Rahmen, deren Ziel gerade verlassen ist (siehe catch/3)
            catch_off: MapSet.new()

  # (vor dem Wecken nicht kompaktieren: $wake braucht die Attribute der
  # eben gebundenen Variablen)
  defp run(%{goals: [{{:"$wake", _}, _, _} | _]} = st), do: run_step(st)
  defp run(st), do: run_step(maybe_compact(st))

  defp run_step(st) do
    case st.goals do
      [] -> {:sol, st}
      [{goal, cutb, mod} | rest] -> step(unmark_top(walk(goal, st.subst)), cutb, mod, rest, st)
    end
  end

  defp step({:atom, "true"}, _cutb, _mod, rest, st), do: run(%{st | goals: rest})
  defp step({:atom, "fail"}, _cutb, _mod, _rest, st), do: backtrack(st)

  defp step({:atom, "!"}, cutb, _mod, rest, st) do
    cps = Enum.drop(st.cps, st.height - cutb)
    run(%{st | goals: rest, cps: cps, height: cutb})
  end

  defp step({:struct, ",", [g1, g2]}, cutb, mod, rest, st),
    do: run(%{st | goals: [{g1, cutb, mod}, {g2, cutb, mod} | rest]})

  defp step({:struct, ";", [g1, g2]}, cutb, mod, rest, st) do
    case unmark_top(walk(g1, st.subst)) do
      {:struct, "->", [c, t]} ->
        if_then_else(c, t, g2, cutb, mod, rest, st)

      _ ->
        st = push(st, {:alt, {g2, cutb, mod}, rest, st.subst, st.answer})
        run(%{st | goals: [{g1, cutb, mod} | rest]})
    end
  end

  defp step({:struct, "->", [c, t]}, cutb, mod, rest, st),
    do: if_then_else(c, t, {:atom, "fail"}, cutb, mod, rest, st)

  # Interne Markierung: Choice Points bis zur Höhe h abschneiden
  defp step({:"$cut_to", h}, _cutb, _mod, rest, st) do
    cps = Enum.drop(st.cps, st.height - h)
    run(%{st | goals: rest, cps: cps, height: h})
  end

  # call/1: Cut darin ist lokal (Barriere = aktuelle Höhe)
  defp step({:struct, "call", [g | extra]}, _cutb, mod, rest, st) do
    goal = add_args(unmark_top(walk(g, st.subst)), extra)
    run(%{st | goals: [{goal, st.height, mod} | rest]})
  end

  defp step({:struct, "not", [g]}, cutb, mod, rest, st),
    do: step({:struct, "\\+", [g]}, cutb, mod, rest, st)

  defp step({:struct, "=", [x, y]}, _cutb, _mod, rest, st) do
    case guarded(fn -> unify(x, y, st.subst) end) do
      {:ok, {:ok, s1}} -> cont(st, s1, rest)
      {:ok, :error} -> backtrack(st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  # Negation: eigener Lauf mit leerem Choice-Point-Stack (Cut darin ist lokal)
  defp step({:struct, "\\+", [g]}, _cutb, mod, rest, st) do
    case guarded(fn -> run(%{st | goals: [{g, 0, mod}], cps: [], height: 0, answer: []}) end) do
      {:ok, {:sol, _}} -> backtrack(st)
      {:ok, :done} -> run(%{st | goals: rest})
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  # findall(T, G, L) / findall(T, G, L, Rest): alle Lösungen in einer
  # Unter-Maschine, als Kopien mit frischen Variablen
  defp step({:struct, "findall", [t, g, l]}, cutb, mod, rest, st),
    do: step({:struct, "findall", [t, g, l, []]}, cutb, mod, rest, st)

  defp step({:struct, "findall", [t, g, l, tail]}, _cutb, mod, rest, st) do
    case guarded(fn -> collect(run(sub_machine(t, g, mod, st)), :infinity, []) end) do
      {:ok, {items, :done}} ->
        case unify(l, list(items, tail), st.subst) do
          {:ok, s} -> cont(st, s, rest)
          :error -> backtrack(st)
        end

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  # countall(G, N): Anzahl der Lösungen von G, ohne sie zu sammeln
  # (konstanter Speicher, anders als findall + length)
  defp step({:struct, "countall", [g, n]}, _cutb, mod, rest, st) do
    counted =
      guarded(fn ->
        case walk(n, st.subst) do
          x when is_integer(x) or (is_tuple(x) and elem(x, 0) == :var) -> :ok
          x -> PrologEx.Error.type!("integer", x)
        end

        count(run(sub_machine([], g, mod, st)), 0)
      end)

    case counted do
      {:ok, k} ->
        case unify(n, k, st.subst) do
          {:ok, s} -> cont(st, s, rest)
          :error -> backtrack(st)
        end

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  # findnsols(N, T, G, L) / findnsols(N, T, G, L, Rest) (wie SWI): jeweils
  # höchstens N Lösungen; beim Backtracking die nächsten N. Die Unter-
  # Maschine wird dazu im Choice Point aufbewahrt und fortgesetzt. Ist ein
  # Teil kürzer als N, ist es der letzte (deterministisch); ging es genau
  # auf, folgt wie bei SWI noch ein leerer Teil.
  defp step({:struct, "findnsols", [n, t, g, l]}, cutb, mod, rest, st),
    do: step({:struct, "findnsols", [n, t, g, l, []]}, cutb, mod, rest, st)

  defp step({:struct, "findnsols", [n, t, g, l, tail]}, _cutb, mod, rest, st) do
    chunk =
      guarded(fn ->
        k =
          case walk(n, st.subst) do
            k when is_integer(k) and k >= 1 -> k
            k when is_integer(k) -> PrologEx.Error.domain!("not_less_than_one", k)
            {:var, _} -> PrologEx.Error.instantiation!()
            other -> PrologEx.Error.type!("integer", other)
          end

        {k, collect(run(sub_machine(t, g, mod, st)), k, [])}
      end)

    case chunk do
      {:ok, {k, collected}} -> findnsols_chunk(collected, k, l, tail, rest, st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp step({:struct, "is", [x, expr]}, _cutb, _mod, rest, st) do
    case guarded(fn -> unify(x, eval(expr, st.subst), st.subst) end) do
      {:ok, {:ok, s1}} -> cont(st, s1, rest)
      {:ok, :error} -> backtrack(st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp step({:struct, op, [x, y]}, _cutb, _mod, rest, st)
       when op in ["<", ">", ">=", "=<", "=:=", "=\\="] do
    case guarded(fn -> compare(op, eval(x, st.subst), eval(y, st.subst)) end) do
      {:ok, true} -> run(%{st | goals: rest})
      {:ok, false} -> backtrack(st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp step({:var, _}, _cutb, _mod, _rest, st),
    do: throw_error(st, &PrologEx.Error.instantiation!/0)

  defp step(n, _cutb, _mod, _rest, st) when is_number(n),
    do: throw_error(st, fn -> PrologEx.Error.type!("callable", n) end)

  # Gebundene attributierte Variablen (siehe after_unify/2). Ohne Module
  # mit verify_attributes/3 laufen nur die eingebauten Weckziele (freeze,
  # dif, when). Sonst wie SICStus (library(atts)):
  #   1. die Bindungen dieser Variablen zurücknehmen,
  #   2. für jede Variable und jedes Attributmodul M (in Deklarations-
  #      reihenfolge) M:verify_attributes(Var, Wert, Goals) aufrufen –
  #      alle sehen alle beteiligten Variablen ungebunden,
  #   3. die Bindungen wiederherstellen ($attv_redo),
  #   4. alle Goals aufrufen (jeweils im Modul M),
  #   5. die eingebauten Weckziele.
  # Alles sind gewöhnliche Ziele: Scheitern, Alternativen und Ausnahmen
  # der Hooks wirken wie bei jedem Aufruf.
  defp step({:"$wake", attvs}, _cutb, _mod, rest, st) do
    case verify_modules(current_db()) do
      [] ->
        run(%{st | goals: wake_goals(attvs, st) ++ rest})

      mods ->
        pairs = for v <- attvs, do: {v, Map.fetch!(st.subst, v)}
        subst = Enum.reduce(attvs, st.subst, &Map.delete(&2, &1))

        hooks =
          for {v, val} <- pairs, m <- mods do
            g = {:var, "_H#{System.unique_integer([:positive])}"}
            {mk(":", [a(m), mk("verify_attributes", [v, val, g])]), mk("$g", [a(m), g])}
          end

        redo =
          mk("$attv_redo", [
            list(for({v, val} <- pairs, do: mk("$p", [v, val]))),
            list(Enum.map(hooks, &elem(&1, 1)))
          ])

        goals = for {h, _} <- hooks, do: {h, st.height, "system"}
        run(%{st | subst: subst, goals: goals ++ [{redo, st.height, "system"} | rest]})
    end
  end

  # Bindungen wiederherstellen, dann die Goals der Hooks, dann die
  # eingebauten Weckziele (siehe $wake)
  defp step({:struct, "$attv_redo", [ps, gs]}, _cutb, _mod, rest, st) do
    {subst, attvs, again} =
      ps
      |> prolog_items()
      |> Enum.reduce({st.subst, [], []}, fn p, {s, attvs, again} ->
        {_, "$p", [v, val]} = unmark_top(p)

        case walk(v, s) do
          {:var, {:attv, _}} = av -> {Map.put(s, av, val), [av | attvs], again}
          # vom Hook gebunden (laut SICStus undefiniert): normal unifizieren
          _ -> {s, attvs, [mk("=", [v, val]) | again]}
        end
      end)

    st = %{st | subst: subst}

    collected =
      guarded(fn ->
        for g <- prolog_items(gs),
            {_, "$g", [{:atom, m}, list]} = unmark_top(g),
            goal <- goal_list(list, subst),
            do: {goal, st.height, m}
      end)

    case collected do
      {:ok, hook_goals} ->
        again = for g <- Enum.reverse(again), do: {g, st.height, "system"}
        run(%{st | goals: again ++ hook_goals ++ wake_goals(Enum.reverse(attvs), st) ++ rest})

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  # M:G – G im Modul M ausführen (transparent für den Cut)
  defp step({:struct, ":", [m, g]}, cutb, _mod, rest, st) do
    case walk(m, st.subst) do
      {:atom, name} -> run(%{st | goals: [{g, cutb, name} | rest]})
      {:var, _} -> throw_error(st, &PrologEx.Error.instantiation!/0)
      other -> throw_error(st, fn -> PrologEx.Error.type!("module", other) end)
    end
  end

  # catch(G, C, R): Rahmen als Choice Point unter G. Verlässt G ohne eigene
  # Choice Points, wird der Rahmen entfernt; sonst bleibt er liegen, ist
  # aber inaktiv (catch_off), bis Backtracking wieder in G hineinführt –
  # eine Ausnahme NACH catch/3 wird so nicht von ihm gefangen.
  defp step({:struct, "catch", [g, c, r]}, _cutb, mod, rest, st) do
    id = make_ref()
    h = st.height
    st = push(st, {:catch, id, c, r, rest, mod, st.subst, st.answer})
    run(%{st | goals: [{g, h + 1, mod}, {{:"$catch_exit", id, h}, 0, mod} | rest]})
  end

  defp step({:"$catch_exit", id, h}, _cutb, _mod, rest, st) do
    if st.height == h + 1,
      do: run(%{st | goals: rest, cps: tl(st.cps), height: h}),
      else:
        run(
          push(%{st | goals: rest, catch_off: MapSet.put(st.catch_off, id)}, {:catch_reenter, id})
        )
  end

  defp step({:struct, "throw", [b]}, _cutb, _mod, _rest, st) do
    case walk(b, st.subst) do
      {:var, _} -> throw_error(st, &PrologEx.Error.instantiation!/0)
      _ -> throw_ball(b, st)
    end
  end

  # time(G): wie call/1, meldet danach die verstrichene Zeit. Ein Choice
  # Point direkt unter G meldet auch einen Fehlschlag. Hat G bei Erfolg
  # keine eigenen Choice Points hinterlassen, wird dieser Melde-Choice-Point
  # sofort entfernt – time(G) ist dann so deterministisch wie G.
  defp step({:struct, "time", [g]}, _cutb, mod, rest, st) do
    t0 = System.monotonic_time(:microsecond)
    h = st.height
    st = push(st, {:time_fail, t0, st.subst, st.answer})
    goal = unmark_top(walk(g, st.subst))
    run(%{st | goals: [{goal, h + 1, mod}, {{:"$time_exit", t0, h}, 0, mod} | rest]})
  end

  defp step({:"$time_exit", t0, h}, _cutb, _mod, rest, st) do
    report_time(t0)

    if st.height == h + 1,
      do: run(%{st | goals: rest, cps: tl(st.cps), height: h}),
      else: run(%{st | goals: rest})
  end

  # call_nth(G, N): zählt die Lösungen von G mit einem Zähler, den
  # Backtracking NICHT zurücksetzt (st.counters). Ist N eine Zahl, wird bei
  # der N-ten Lösung abgeschnitten (deterministisch). Ein Choice Point unter G
  # räumt den Zähler auf, wenn G erschöpft ist; hinterlässt G bei Erfolg
  # keine Choice Points, wird er gleich entfernt (wie bei time/1).
  defp step({:struct, "call_nth", [g, n]}, cutb, mod, rest, st) do
    case walk(n, st.subst) do
      {:var, _} ->
        call_nth(g, n, cutb, mod, rest, st)

      k when is_integer(k) and k >= 1 ->
        call_nth(g, n, cutb, mod, rest, st)

      k when is_integer(k) ->
        throw_error(st, fn -> PrologEx.Error.domain!("not_less_than_one", k) end)

      other ->
        throw_error(st, fn -> PrologEx.Error.type!("integer", other) end)
    end
  end

  defp step({:"$nth", ref, n, h}, _cutb, _mod, rest, st), do: nth_exit(ref, n, h, rest, st)

  # Benutzerprädikate zuerst; nur bei Fehltreffer die Builtin-Tabelle
  defp step(goal, _cutb, mod, rest, st), do: call_pred(goal, mod, rest, st)

  defp call_nth(g, n, _cutb, mod, rest, st) do
    ref = make_ref()
    h = st.height
    st = %{st | counters: Map.put(st.counters, ref, 0)}
    st = push(st, {:nth_cleanup, ref, st.subst, st.answer})
    goal = unmark_top(walk(g, st.subst))
    run(%{st | goals: [{goal, h + 1, mod}, {{:"$nth", ref, n, h}, 0, mod} | rest]})
  end

  defp nth_exit(ref, n, h, rest, st) do
    c = Map.fetch!(st.counters, ref) + 1
    st = %{st | counters: Map.put(st.counters, ref, c)}

    case walk(n, st.subst) do
      k when is_integer(k) and c < k ->
        backtrack(st)

      k when is_integer(k) ->
        # N-te Lösung: alles ab G abschneiden, Zähler entfernen
        cps = Enum.drop(st.cps, st.height - h)
        run(%{st | goals: rest, cps: cps, height: h, counters: Map.delete(st.counters, ref)})

      _ ->
        case unify(n, c, st.subst) do
          :error ->
            backtrack(st)

          {:ok, s} ->
            {s, rest} = after_unify(s, rest)
            st = %{st | subst: s}

            if st.height == h + 1,
              do:
                run(%{
                  st
                  | goals: rest,
                    cps: tl(st.cps),
                    height: h,
                    counters: Map.delete(st.counters, ref)
                }),
              else: run(%{st | goals: rest})
        end
    end
  end

  # Aufruf eines Prädikats im Kontextmodul mod. Schnellweg: in mod selbst
  # definiert (ein Map-Zugriff); sonst Auflösung über locate/4.
  defp call_pred(goal, mod, rest, st) do
    {name, args} = name_args(goal)
    arity = length(args)
    db = current_db()

    case Map.fetch(db, {mod, name, arity}) do
      {:ok, {:pred, _, _, _, _} = pred} ->
        try_clauses(goal, args, candidates(pred, args, st.subst), rest, mod, st)

      {:ok, _stale} ->
        call_located(
          {:db, mod, Map.fetch!(db, {mod, name, arity})},
          goal,
          name,
          args,
          mod,
          rest,
          st
        )

      :error ->
        found =
          case PrologEx.Builtins.protected_entry(name, arity) do
            nil -> locate(db, mod, name, arity)
            entry -> {:builtin, "system", entry}
          end

        call_located(found, goal, name, args, mod, rest, st)
    end
  end

  defp call_located(found, goal, name, args, mod, rest, st) do
    arity = length(args)

    case found do
      {:db, m, pred} ->
        pred =
          case pred do
            {:pred, _, _, _, _} ->
              pred

            stale ->
              # nach assert: einmal kompilieren/indexieren und zurückschreiben
              p = materialize(stale)
              update_db(&Map.put(&1, {m, name, arity}, p))
              p
          end

        args = qualify(args, Map.get(current_db(), {:meta, m, name, arity}), m, mod, st.subst)
        try_clauses(goal, args, candidates(pred, args, st.subst), rest, m, st)

      {:builtin, m, {:prolog, pred, _}} ->
        args = qualify(args, PrologEx.Builtins.meta(m, name, arity), m, mod, st.subst)
        try_clauses(goal, args, candidates(pred, args, st.subst), rest, m, st)

      {:builtin, m, {kind, fun, _}} ->
        args = qualify(args, PrologEx.Builtins.meta(m, name, arity), m, mod, st.subst)
        # {:call, ziel} aus system läuft im Kontext des Aufrufers
        call_mod = if m == "system", do: mod, else: m

        case guarded(fn -> fun.(args, ctx(st, mod)) end) do
          {:ok, r} when kind == :det -> apply_result(r, call_mod, rest, st)
          {:ok, r} -> start_solutions(r, call_mod, rest, st)
          {:thrown, ball} -> throw_ball(ball, st)
        end

      :none ->
        case PrologEx.Flags.get("unknown") do
          {:atom, "fail"} ->
            backtrack(st)

          {:atom, "warning"} ->
            IO.puts(:stderr, "Warnung: unbekanntes Prädikat #{qualified_name(mod, name, arity)}")
            backtrack(st)

          _error ->
            pi = PrologEx.Error.indicator(name, arity)
            pi = if mod == "user", do: pi, else: mk(":", [a(mod), pi])
            throw_error(st, fn -> PrologEx.Error.existence!("procedure", pi) end)
        end
    end
  end

  defp qualified_name("user", name, arity), do: "#{name}/#{arity}"
  defp qualified_name(mod, name, arity), do: "#{mod}:#{name}/#{arity}"

  defp name_args({:struct, f, args}), do: {f, args}
  defp name_args({:atom, f}), do: {f, []}
  defp name_args([]), do: {"[]", []}
  defp name_args([h | t]), do: {".", [h, t]}
  defp name_args(other), do: {Compiler.key(other), []}

  # meta_predicate: Meta-Argumente (0..9, ^, //, :) mit dem Kontextmodul
  # des Aufrufers qualifizieren, wenn das Prädikat in einem anderen Modul
  # liegt (wie SWI). Schon qualifizierte bleiben, wie sie sind.
  defp qualify(args, nil, _m, _mod, _subst), do: args
  defp qualify(args, _specs, m, m, _subst), do: args

  defp qualify(args, specs, _m, mod, subst) do
    Enum.zip_with(args, specs, fn arg, spec ->
      if meta_spec?(spec) and not qualified?(arg, subst),
        do: mk(":", [a(mod), arg]),
        else: arg
    end)
  end

  @doc false
  def meta_spec?(spec), do: is_integer(spec) or spec in ["^", "//", ":"]

  defp qualified?(t, subst) do
    case walk(t, subst) do
      {tag, ":", [_, _]} when tag in [:struct, :gstruct] -> true
      _ -> false
    end
  end

  defp ctx(st, mod), do: %{subst: st.subst, db: current_db(), module: mod}

  # Nach einer erfolgreichen Unifikation weitermachen. Wurden dabei
  # attributierte Variablen gebunden (:wake), laufen deren Weckziele vor
  # dem Rest (wie SICStus: am nächsten Aufruf-Port).
  defp cont(st, s, goals) do
    {s, goals} = after_unify(s, goals)
    run(%{st | goals: goals, subst: s})
  end

  defp after_unify(%{wake: ws} = s, goals),
    do: {Map.delete(s, :wake), [{{:"$wake", Enum.reverse(ws)}, 0, "system"} | goals]}

  defp after_unify(s, goals), do: {s, goals}

  # Goals-Liste eines Hooks (Restlisten können gebundene Variablen sein)
  defp goal_list(l, subst) do
    case uncons(walk(l, subst)) do
      :empty -> []
      {:cons, h, t} -> [h | goal_list(t, subst)]
      :other -> PrologEx.Error.type!("list", resolve(l, subst))
    end
  end

  # Attributmodule mit verify_attributes/3, in Deklarationsreihenfolge
  defp verify_modules(db) do
    for m <- Map.get(db, :attr_modules, []),
        Map.has_key?(db, {m, "verify_attributes", 3}),
        do: m
  end

  # Weckziele der gebundenen attributierten Variablen, in der Reihenfolge,
  # in der sie angehängt wurden; jedes wie call/1 (Cut lokal)
  defp wake_goals(attvs, st) do
    for {:var, {:attv, id}} <- attvs,
        susp <- prolog_items(Map.get(Map.get(st.subst, {:attrs, id}, %{}), "$susp", [])),
        {_, "$s", [done, wake, _residual]} = unmark_top(susp),
        match?({:var, _}, walk(done, st.subst)),
        do: {wake, st.height, "system"}
  end

  # Ergebnis eines Builtins (siehe PrologEx.Builtin) umsetzen
  defp apply_result(result, mod, rest, st) do
    case result do
      r when r in [:ok, true] ->
        run(%{st | goals: rest})

      r when r in [:fail, false] ->
        backtrack(st)

      {:unify, pairs} ->
        case guarded(fn -> unify_pairs(pairs, st.subst) end) do
          {:ok, {:ok, s}} -> cont(st, s, rest)
          {:ok, :error} -> backtrack(st)
          {:thrown, ball} -> throw_ball(ball, st)
        end

      {:call, goal} ->
        run(%{st | goals: [{goal, st.height, mod} | rest]})

      # neue Substitution (z. B. Attribute gesetzt: freeze, dif, when)
      {:subst, s} ->
        cont(st, s, rest)

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
  defp start_solutions(thunk, mod, rest, st) when is_function(thunk, 0) do
    case guarded(thunk) do
      {:ok, r} -> start_solutions(r, mod, rest, st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp start_solutions([], _mod, _rest, st), do: backtrack(st)
  defp start_solutions([r], mod, rest, st), do: apply_result(r, mod, rest, st)

  defp start_solutions([r | more], mod, rest, st) do
    st = push(st, {:solutions_list, more, mod, rest, st.subst, st.answer})
    apply_result(r, mod, rest, st)
  end

  defp start_solutions(enum, mod, rest, st) do
    case guarded(fn -> Enumerable.reduce(enum, {:cont, nil}, fn x, _ -> {:suspend, x} end) end) do
      {:ok, r} -> next_solution(r, mod, rest, st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp next_solution({:suspended, r, cont}, mod, rest, st) do
    st = push(st, {:solutions, cont, mod, rest, st.subst, st.answer})
    apply_result(r, mod, rest, st)
  end

  defp next_solution(_done_or_halted, _mod, _rest, st), do: backtrack(st)

  defp report_time(us0) do
    secs = (System.monotonic_time(:microsecond) - us0) / 1_000_000
    IO.puts(:stderr, "% #{:erlang.float_to_binary(secs, decimals: 3)} seconds")
  end

  # Unter-Maschine für findall & Co.: eigener Ziel- und Choice-Point-Stack;
  # das Template steht in der Antwortliste, damit die Kompaktierung seine
  # Bindungen mitführt. Cut im Ziel ist lokal (Barriere 0).
  defp sub_machine(t, g, mod, st) do
    %{st | goals: [{g, 0, mod}], cps: [], height: 0, answer: [{"$template", t}]}
  end

  # Lösungen einsammeln: höchstens n (oder :infinity). Ergebnis
  # {kopien, :done} oder {kopien, {:more, zustand}} zum Fortsetzen.
  defp collect(result, n, acc), do: collect(result, n, acc, 0)

  defp collect(:done, _n, acc, _k), do: {Enum.reverse(acc), :done}

  defp collect({:sol, s}, n, acc, k) do
    [{_, t}] = s.answer
    acc = [copy_fresh(t, s.subst) | acc]
    k = k + 1

    if n != :infinity and k >= n,
      do: {Enum.reverse(acc), {:more, s}},
      else: collect(backtrack(s), n, acc, k)
  end

  defp count(:done, k), do: k
  defp count({:sol, s}, k), do: count(backtrack(s), k + 1)

  # collected: {kopien, :done | {:more, unter_maschine}} (siehe collect/3)
  defp findnsols_chunk({items, cont}, k, l, tail, rest, st) do
    st =
      case cont do
        {:more, sub} -> push(st, {:findnsols, sub, k, l, tail, rest, st.subst, st.answer})
        :done -> st
      end

    case unify(l, list(items, tail), st.subst) do
      {:ok, s} -> cont(st, s, rest)
      :error -> backtrack(st)
    end
  end

  # (C -> T ; E): Choice Point für E, dann C mit eigener Cut-Barriere (Cut
  # in der Bedingung ist lokal). Hat C Erfolg, schneidet $cut_to alles ab
  # der Höhe vor E weg – also E und alle Alternativen von C. T und E sind
  # für den Cut transparent (Barriere des umgebenden Prädikats).
  defp if_then_else(c, t, e, cutb, mod, rest, st) do
    h = st.height
    st = push(st, {:alt, {e, cutb, mod}, rest, st.subst, st.answer})
    run(%{st | goals: [{c, h + 1, mod}, {{:"$cut_to", h}, 0, mod}, {t, cutb, mod} | rest]})
  end

  defp add_args(g, []), do: g
  defp add_args({:struct, ":", [m, g]}, extra), do: mk(":", [m, add_args(unmark_top(g), extra)])
  defp add_args({:atom, f}, extra), do: mk(f, extra)
  defp add_args({:struct, f, args}, extra), do: mk(f, args ++ extra)
  defp add_args({:var, _}, _), do: PrologEx.Error.instantiation!()
  defp add_args(g, _), do: PrologEx.Error.type!("callable", g)

  # Die Cut-Barriere für den Rumpf ist die Stack-Höhe VOR dem eigenen
  # Choice Point – ein Cut entfernt also auch die restlichen Klauseln.
  defp try_clauses(_goal, _args, [], _rest, _mod, st), do: backtrack(st)

  # mod: Modul, in dem das Prädikat definiert ist (Kontext für den Rumpf)
  defp try_clauses(goal, args, [cl | more], rest, mod, st) do
    {:clause, _key, nslots, pats, nfresh, body} = cl
    env = :erlang.make_tuple(nslots, nil)

    # guarded: mit occurs_check=error kann die Kopfunifikation werfen
    case guarded(fn -> match_args(pats, args, env, st.subst, st.next_var) end) do
      {:ok, matched} -> clause_matched(matched, goal, args, more, rest, nfresh, body, mod, st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp clause_matched(matched, goal, args, more, rest, nfresh, body, mod, st) do
    case matched do
      :error ->
        try_clauses(goal, args, more, rest, mod, st)

      {:ok, env, s1, nv} ->
        barrier = st.height

        # Letzte passende Klausel: kein Choice Point
        st =
          if more == [],
            do: st,
            else: push(st, {:clauses, goal, args, more, rest, mod, st.subst, st.answer})

        goals = inst_goals(body, env, nv, barrier, mod, rest)
        cont(%{st | next_var: nv + nfresh}, s1, goals)
    end
  end

  defp push(st, cp), do: %{st | cps: [cp | st.cps], height: st.height + 1}

  defp backtrack(%{cps: []}), do: :done

  defp backtrack(%{cps: [cp | cps]} = st) do
    st = %{st | cps: cps, height: st.height - 1}

    case cp do
      {:alt, goal, rest, subst, answer} ->
        run(%{st | goals: [goal | rest], subst: subst, answer: answer})

      {:clauses, goal, args, more, rest, mod, subst, answer} ->
        try_clauses(goal, args, more, rest, mod, %{st | subst: subst, answer: answer})

      {:solutions_list, more, mod, rest, subst, answer} ->
        start_solutions(more, mod, rest, %{st | subst: subst, answer: answer})

      {:solutions, cont, mod, rest, subst, answer} ->
        st = %{st | subst: subst, answer: answer}

        case guarded(fn -> cont.({:cont, nil}) end) do
          {:ok, r} -> next_solution(r, mod, rest, st)
          {:thrown, ball} -> throw_ball(ball, st)
        end

      {:findnsols, sub, k, l, tail, rest, subst, answer} ->
        st = %{st | subst: subst, answer: answer}

        case guarded(fn -> collect(backtrack(sub), k, []) end) do
          {:ok, collected} -> findnsols_chunk(collected, k, l, tail, rest, st)
          {:thrown, ball} -> throw_ball(ball, st)
        end

      {:nth_cleanup, ref, subst, answer} ->
        backtrack(%{st | subst: subst, answer: answer, counters: Map.delete(st.counters, ref)})

      {:time_fail, t0, subst, answer} ->
        report_time(t0)
        backtrack(%{st | subst: subst, answer: answer})

      # G von catch/3 erschöpft
      {:catch, _id, _c, _r, _rest, _mod, _subst, _answer} ->
        backtrack(st)

      # zurück in G: der Rahmen fängt wieder
      {:catch_reenter, id} ->
        backtrack(%{st | catch_off: MapSet.delete(st.catch_off, id)})
    end
  end

  # ---------------------------------------------------------------------
  # Ausnahmen
  #
  # Fehler entstehen in Builtins und in der Arithmetik als Elixir-Ausnahme
  # PrologEx.Error. Die Maschine fängt sie an jeder Stelle, an der sie
  # entstehen können (guarded/1, nicht um run/1 herum – das bleibt
  # endrekursiv), und wirft sie als Prolog-Ball weiter (throw_ball/2).
  # ---------------------------------------------------------------------

  defp guarded(fun) do
    {:ok, fun.()}
  rescue
    e in PrologEx.Error -> {:thrown, e.term}
  end

  # Fehler aus einer Funktion, die immer wirft (z. B. Error.type!/2)
  defp throw_error(st, raiser) do
    {:thrown, ball} = guarded(raiser)
    throw_ball(ball, st)
  end

  # Ball auflösen und kopieren (ISO), dann den innersten aktiven
  # catch/3-Rahmen suchen, dessen Catcher passt. Alles darüber wird
  # verworfen; der Rahmen selbst auch. Ohne passenden Rahmen geht die
  # Ausnahme an den Aufrufer (Toplevel, umgebende Unter-Maschine).
  defp throw_ball(ball, st) do
    ball = copy_fresh(ball, st.subst)
    unwind(ball, st.cps, st.height, st)
  end

  defp unwind(ball, [], _h, _st), do: PrologEx.Error.throw!(ball)

  defp unwind(ball, [{:catch, id, c, r, rest, mod, subst, answer} | below], h, st) do
    if MapSet.member?(st.catch_off, id) do
      unwind(ball, below, h - 1, st)
    else
      case unify(c, ball, subst) do
        {:ok, s} ->
          st = %{st | cps: below, height: h - 1, answer: answer}
          cont(st, s, [{r, h - 1, mod} | rest])

        :error ->
          unwind(ball, below, h - 1, st)
      end
    end
  end

  defp unwind(ball, [_ | below], h, st), do: unwind(ball, below, h - 1, st)

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
      Enum.map_reduce(st.goals, {%{}, 0}, fn {g, cutb, mod}, acc ->
        {g, acc} = compact(g, st.subst, acc)
        {{g, cutb, mod}, acc}
      end)

    {answer, {memo, size}} =
      Enum.map_reduce(st.answer, {memo, size}, fn {n, t}, acc ->
        {t, acc} = compact(t, st.subst, acc)
        {{n, t}, acc}
      end)

    # Attribute der noch lebenden attributierten Variablen mitnehmen (sie
    # können selbst wieder solche enthalten)
    {attrs, size} = compact_attrs(attvs_in(memo), MapSet.new(), %{}, {memo, size}, st.subst)

    # Zähler von call_nth/2, deren Aufräum-Choice-Point (z. B. durch einen
    # Cut) verschwunden ist, werden nie mehr gebraucht
    live = for {:nth_cleanup, ref, _, _} <- st.cps, do: ref
    counters = Map.take(st.counters, live)

    %{
      st
      | goals: goals,
        answer: answer,
        subst: attrs,
        counters: counters,
        threshold: max(st.min_threshold, 2 * size)
    }
  end

  defp term_attvs({:var, {:attv, id}}, acc), do: [id | acc]
  defp term_attvs({:struct, _, args}, acc), do: Enum.reduce(args, acc, &term_attvs/2)
  defp term_attvs([h | t], acc), do: term_attvs(t, term_attvs(h, acc))
  defp term_attvs(_, acc), do: acc

  defp attvs_in(memo) do
    for {_var, {{:var, {:attv, id}}, _}} <- memo, uniq: true, do: id
  end

  defp compact_attrs([], _done, out, {_memo, size}, _subst), do: {out, size}

  defp compact_attrs([id | ids], done, out, acc, subst) do
    if MapSet.member?(done, id) or not Map.has_key?(subst, {:attrs, id}) do
      compact_attrs(ids, MapSet.put(done, id), out, acc, subst)
    else
      {attrs, {memo, _} = acc} =
        Enum.reduce(Map.fetch!(subst, {:attrs, id}), {%{}, acc}, fn {m, t}, {as, acc} ->
          {t, acc} = compact(t, subst, acc)
          {Map.put(as, m, t), acc}
        end)

      _ = memo
      # attributierte Variablen in den (kompaktierten) Attributen selbst
      new = Enum.flat_map(attrs, fn {_m, t} -> term_attvs(t, []) end)

      compact_attrs(
        new ++ ids,
        MapSet.put(done, id),
        Map.put(out, {:attrs, id}, attrs),
        acc,
        subst
      )
    end
  end

  defp compact(t, subst, acc) do
    {t2, acc, _changed, _ground} = compact3(t, subst, acc)
    {t2, acc}
  end

  # Ergebnis: {Term, {memo, nicht_ground_größe}, verändert?, ground?}
  # Unveränderte Teilterme werden nicht kopiert, sondern geteilt.
  defp compact3(t, _subst, acc) when is_marked(t), do: {t, acc, false, true}

  # Markierung von call_nth/2: das Argument N kann eine Variable sein
  defp compact3({:"$nth", ref, n, h}, subst, acc) do
    {n2, acc, changed, _} = compact3(n, subst, acc)
    {{:"$nth", ref, n2, h}, acc, changed, false}
  end

  defp compact3({:var, _} = var, subst, {memo, size} = acc) do
    case Map.fetch(memo, var) do
      {:ok, {t, g}} ->
        {t, acc, t != var, g}

      :error ->
        case walk(var, subst) do
          # freie, nicht attributierte Variable: kein Memo nötig (attvs_in
          # sucht im Memo nur nach attributierten)
          {:var, n} = free when not is_tuple(n) ->
            {free, acc, free != var, false}

          {:var, _} = free ->
            {free, {Map.put(memo, var, {free, false}), size}, free != var, false}

          # atomar: nichts zu teilen, kein Memo
          atomic when not is_tuple(atomic) and not is_list(atomic) ->
            {atomic, acc, true, true}

          {:atom, _} = atomic ->
            {atomic, acc, true, true}

          [] ->
            {[], acc, true, true}

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

  # Listen: den Rücken iterativ ablaufen (auch über gebundene
  # Rest-Variablen), dann von hinten neu aufbauen. Rekursion über den Rest
  # hieße einen Stack so tief wie die Liste – und jede GC durchsucht den
  # ganzen Stack (bei 400 000 Zellen ein Mehrfaches der eigentlichen Arbeit).
  defp compact3([_ | _] = l, subst, acc) do
    {spine, tail, acc} = compact_spine(l, subst, acc, [])
    {t2, acc, ct, gt} = compact3(tail, subst, acc)
    compact_rebuild(spine, t2, acc, ct, gt)
  end

  defp compact3(t, _subst, acc), do: {t, acc, false, true}

  # Köpfe der Reihe nach kompaktieren; Einträge {:cell, zelle, h2, ch, gh}
  # oder {:link, var} (gebundene Rest-Variable, wird beim Aufbau memoisiert)
  defp compact_spine([h | t] = l, subst, acc, spine) do
    {h2, acc, ch, gh} = compact3(h, subst, acc)
    spine = [{:cell, l, h2, ch, gh} | spine]

    case t do
      [_ | _] ->
        compact_spine(t, subst, acc, spine)

      {:var, _} = var ->
        {memo, _} = acc

        with :error <- Map.fetch(memo, var),
             [_ | _] = next <- walk(var, subst) do
          compact_spine(next, subst, acc, [{:link, var} | spine])
        else
          _ -> {spine, t, acc}
        end

      _ ->
        {spine, t, acc}
    end
  end

  defp compact_rebuild([], t, acc, ch, g), do: {t, acc, ch, g}

  defp compact_rebuild([{:link, var} | rest], t, {memo, size}, _ch, g),
    do: compact_rebuild(rest, t, {Map.put(memo, var, {t, g}), size}, true, g)

  defp compact_rebuild([{:cell, l, h2, ch, gh} | rest], t2, {memo, size} = acc, ct, gt) do
    cond do
      gh and gt -> compact_rebuild(rest, cons(h2, t2), acc, true, true)
      ch or ct -> compact_rebuild(rest, [h2 | t2], {memo, size + 1}, true, false)
      true -> compact_rebuild(rest, l, {memo, size + 1}, false, false)
    end
  end

  # ---------------------------------------------------------------------
  # Arithmetik
  # ---------------------------------------------------------------------

  defp eval(t, subst) do
    case unmark_top(walk(t, subst)) do
      n when is_number(n) ->
        n

      {:struct, op, [x, y]} ->
        arith(op, eval(x, subst), eval(y, subst))

      {:struct, op, [x]} ->
        arith(op, eval(x, subst))

      {:atom, "pi"} ->
        :math.pi()

      {:atom, "e"} ->
        :math.exp(1)

      {:atom, "max_tagged_integer"} ->
        576_460_752_303_423_487

      {:var, _} ->
        PrologEx.Error.instantiation!()

      {:atom, n} ->
        PrologEx.Error.type!("evaluable", PrologEx.Error.indicator(n, 0))

      {:struct, f, args} ->
        PrologEx.Error.type!("evaluable", PrologEx.Error.indicator(f, length(args)))

      other ->
        PrologEx.Error.type!("evaluable", other)
    end
  rescue
    # Division durch 0 u. ä. aus der BEAM (vollständig in Punkt "Evaluables")
    ArithmeticError -> PrologEx.Error.evaluation!("undefined")
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
  defp arith(op, _, _), do: PrologEx.Error.type!("evaluable", PrologEx.Error.indicator(op, 2))

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
  defp arith(op, _), do: PrologEx.Error.type!("evaluable", PrologEx.Error.indicator(op, 1))

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

    start = new_state(db, [{goal, 0, Keyword.get(opts, :module, "user")}], answer, opts)

    Stream.unfold({:start, start}, fn
      :halt ->
        nil

      {:start, st} ->
        put_db(st.db)
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
    ans =
      Map.new(st.answer, fn {n, t} ->
        {n, t |> resolve(st.subst) |> PrologEx.Builtins.Mutables.show(st.subst)}
      end)

    # Restziele (freeze, dif, when) der in der Antwort vorkommenden
    # attributierten Variablen, wie im SWI/SICStus-Toplevel
    ans =
      case residual_goals(Map.values(ans), st) do
        [] -> ans
        goals -> Map.put(ans, "$residual", goals)
      end

    if st.height > 0, do: {{ans, true}, {:retry, st}}, else: {{ans, false}, :halt}
  end

  # Restziele über '$residuals'/2 (eingebaute Bedingungen und
  # attribute_goal/2 aller Attributmodule), in einer Unter-Maschine im
  # aktuellen Zustand. M:G wird ohne Modul gezeigt, wenn G in user dasselbe
  # Prädikat meint (oder M = user).
  defp residual_goals(terms, st) do
    case Enum.flat_map(terms, &term_attvars(&1, st.subst)) |> Enum.uniq() do
      [] ->
        []

      vars ->
        r = {:var, "_R#{System.unique_integer([:positive])}"}
        goal = mk("$residuals", [list(vars), r])
        sub = %{st | goals: [{goal, 0, "system"}], cps: [], height: 0, answer: [{"$r", r}]}

        case guarded(fn -> run(sub) end) do
          {:ok, {:sol, s2}} ->
            [{_, l}] = s2.answer
            db = current_db()

            l
            |> resolve(s2.subst)
            |> prolog_items()
            |> Enum.uniq()
            |> Enum.map(&unqualify(&1, db))

          _ ->
            []
        end
    end
  end

  defp unqualify({:struct, ":", [{:atom, m}, g]} = q, db) do
    case g do
      {:struct, f, args} ->
        case locate(db, "user", f, length(args)) do
          {:db, ^m, _} -> g
          {:builtin, ^m, _} -> g
          _ -> if m == "user", do: g, else: q
        end

      _ ->
        q
    end
  end

  defp unqualify(t, _db), do: t

  # Ungebundene Variablen in Antworten benennen wie SWI: Anfragevariablen,
  # die auf dieselbe ungebundene Variable zeigen, bilden eine Kette
  # "X = Y, Y = Z" (in Anfragereihenfolge), und die Variable selbst heißt
  # wie die letzte (Z). Aus "R = [2, _G2], Y = _G2" wird so "R = [2, Y]".
  # Die Richtung von Var-Var-Bindungen spielt für die Ausgabe keine Rolle.
  defp name_fresh_r(ans) do
    # ans: [{name, term}] in Anfragereihenfolge
    groups =
      ans
      |> Enum.filter(&match?({_, {:var, _}}, &1))
      |> Enum.group_by(fn {_, {:var, v}} -> v end, &elem(&1, 0))

    if Enum.all?(groups, fn {v, ns} -> ns == [v] end) do
      {ans, %{}}
    else
      renames = Map.new(groups, fn {v, ns} -> {v, List.last(ns)} end)

      chain =
        for {_, ns} <- groups,
            {n, next} <- Enum.zip(ns, tl(ns) ++ [List.last(ns)]),
            into: %{},
            do: {n, {:var, next}}

      {Enum.map(ans, fn {n, t} -> {n, Map.get(chain, n) || rename_free(t, renames)} end), renames}
    end
  end

  defp rename_free({:var, v} = x, m) do
    case Map.fetch(m, v) do
      {:ok, n} -> {:var, n}
      :error -> x
    end
  end

  defp rename_free({:struct, f, args}, m), do: {:struct, f, Enum.map(args, &rename_free(&1, m))}
  defp rename_free([h | t], m), do: [rename_free(h, m) | rename_free(t, m)]
  defp rename_free(t, _m), do: t

  # Für Messungen: erste Lösung plus Zustandsgrößen
  def first_with_stats(db, goal, opts \\ []) do
    put_db(db)

    case run(new_state(db, [{goal, 0, "user"}], [], opts)) do
      {:sol, st} -> {:ok, %{bindings: map_size(st.subst), choicepoints: st.height}}
      :done -> false
    end
  end

  @doc "Namen der Anfragevariablen in Reihenfolge ihres Auftretens"
  def query_var_names(goal) do
    for {:var, n} <- goal |> query_vars() |> Enum.uniq(), is_binary(n), do: n
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
  def format(t), do: PrologEx.Writer.format(t)

  @doc "Wie format/1, aber wie writeq (siehe PrologEx.Writer)"
  def format(t, opts), do: PrologEx.Writer.format(t, opts)

  @doc """
  Kürzeste Darstellung eines Floats, die beim Lesen denselben Wert ergibt –
  wie SWI dezimal für 1.0e-4 =< |f| < 1.0e15 (`1500.0`, `0.001`), sonst mit
  Exponent (`1.0e15`, `1.0e-5`).
  """
  def format_float(f) do
    s = Float.to_string(f)

    case String.split(s, "e") do
      [_plain] ->
        s

      [mant, exp] ->
        e = String.to_integer(exp)
        a = abs(f)

        if a >= 1.0e-4 and a < 1.0e15,
          do: plain_float(mant, e),
          else: s
    end
  end

  # "-1.25", 3 -> "-1250.0"; "1.5", -3 -> "0.0015"
  defp plain_float(mant, e) do
    {sign, mant} =
      if String.starts_with?(mant, "-"), do: {"-", String.slice(mant, 1..-1//1)}, else: {"", mant}

    [int, frac] = String.split(mant, ".")
    digits = String.trim_trailing(int <> frac, "0")
    digits = if digits == "", do: "0", else: digits
    point = String.length(int) + e

    body =
      cond do
        point <= 0 ->
          "0." <> String.duplicate("0", -point) <> digits

        point >= String.length(digits) ->
          digits <> String.duplicate("0", point - String.length(digits)) <> ".0"

        true ->
          {i, f} = String.split_at(digits, point)
          i <> "." <> f
      end

    sign <> body
  end

  # Wie SWI: ungebundene Anfragevariablen (X = X) werden nicht gezeigt
  # `order`: Namen in Anfragereihenfolge (für Variablenketten wie SWI);
  # ohne Angabe alphabetisch. Die Ausgabe ist alphabetisch sortiert.
  def format_answer(ans, order \\ nil) do
    # wie writeq; Zeichenlisten als "..." bei double_quotes=chars (wie Scryer)
    opts = PrologEx.Writer.answer_opts()
    {residual, ans} = Map.pop(ans, "$residual", [])
    order = order || Map.keys(ans) |> Enum.sort()

    {named, renames} =
      order
      |> Enum.filter(&Map.has_key?(ans, &1))
      |> Enum.map(&{&1, Map.fetch!(ans, &1)})
      |> name_fresh_r()

    bindings =
      named
      |> Enum.sort()
      |> Enum.reject(fn {k, t} -> t == {:var, k} end)
      |> Enum.map(fn {k, t} -> "#{k} = #{format(t, opts)}" end)

    goals = Enum.map(residual, &(&1 |> rename_free(renames) |> strip_user() |> format(opts)))

    case bindings ++ goals do
      [] -> "true"
      shown -> Enum.join(shown, ", ")
    end
  end

  # user:G in Restzielen wie SWI ohne Modul zeigen
  defp strip_user({:struct, ":", [{:atom, "user"}, g]}), do: strip_user(g)
  defp strip_user({:struct, f, args}), do: {:struct, f, Enum.map(args, &strip_user/1)}
  defp strip_user(t), do: t
end
