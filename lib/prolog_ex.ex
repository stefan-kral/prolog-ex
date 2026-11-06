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
  alias PrologEx.Store

  # ---------------------------------------------------------------------
  # Terme
  #   {:var, {"X", 17}}          Variable aus dem Quelltext (Name, Kennung)
  #   {:var, 42}                 frische Variable; Kennungen VM-weit
  #                              eindeutig, siehe PrologEx.Vars
  #   {:var, {:attv, 7}}         attributierte Variable
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
  def mark({:struct, f, args}), do: mk_struct(f, mark_args(args))
  def mark([h | t]), do: cons(mark(h), mark(t))
  def mark(t), do: t

  defp mark_args([]), do: []
  defp mark_args([a | as]), do: [mark(a) | mark_args(as)]

  # Entfernt alle Markierungen
  def unmark({:gstruct, f, args}), do: {:struct, f, unmark_args(args)}
  def unmark({:glist, l}), do: unmark(l)
  def unmark({:struct, f, args}), do: {:struct, f, unmark_args(args)}
  def unmark([h | t]), do: [unmark(h) | unmark(t)]
  def unmark(t), do: t

  defp unmark_args([]), do: []
  defp unmark_args([a | as]), do: [unmark(a) | unmark_args(as)]

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

  # Alle Zugriffe auf die Substitution laufen über PrologEx.Store; walk/2
  # und bind/3 bleiben hier als die bekannten Namen.
  def walk({:var, _} = var, subst), do: Store.walk(var, subst)
  def walk(t, _subst), do: t

  # Einzige Stelle, an der Variablen gebunden werden. Eine attributierte
  # Variable ({:var, {:attv, id}}) wird zusätzlich unter :wake vermerkt; die
  # Maschine weckt danach ihre Ziele (siehe after_unify/2). Für normale
  # Variablen kostet das nichts (Mustervergleich auf den Namen).
  def bind({:var, _} = var, t, subst), do: Store.bind(var, t, subst)

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
  # Coroutining (freeze, dif, when) nutzt das Attribut "$susp": eine Liste
  # von Suspensionen (Formen siehe PrologEx.Builtins.Coroutining), neuester
  # Eintrag vorn. Wird die Variable gebunden, verarbeitet die Maschine die
  # aktiven Einträge in der Reihenfolge des Anhängens (wake_builtin/4).
  # ---------------------------------------------------------------------

  @doc "Ist die (dereferenzierte) Variable attributiert?"
  def attv?({:var, {:attv, _}}), do: true
  def attv?(_), do: false

  @doc "Attribute einer Variablen (dereferenziert): Map modul => Term"
  def get_attrs(var, subst) do
    case Store.walk(var, subst) do
      {:var, {:attv, id}} -> Store.attrs(subst, id)
      _ -> %{}
    end
  end

  @doc """
  Attribut `module` der ungebundenen Variable `var` setzen. Eine normale
  Variable wird dazu an eine neue attributierte gebunden (ohne Wecken).
  Ergebnis: neue Substitution.
  """
  def put_attr(subst, var, module, value) do
    case Store.walk(var, subst) do
      {:var, {:attv, id}} ->
        Store.update_attrs(subst, id, %{module => value}, &Map.put(&1, module, value))

      {:var, _} = v ->
        Store.attach(subst, v, attv_id(), %{module => value})
    end
  end

  @doc """
  Attribut `module` von `var` mit `fun` (alter Wert oder nil → neuer Wert)
  ändern: ein walk, ein Schreibzugriff.
  """
  def update_attr(subst, var, module, fun) do
    case Store.walk(var, subst) do
      {:var, {:attv, id}} ->
        # fun genau einmal (ein Default %{module => fun.(nil)} würde vorab
        # ausgewertet, auch wenn es schon Attribute gibt)
        attrs = Store.attrs(subst, id)
        Store.put_attrs(subst, id, Map.put(attrs, module, fun.(Map.get(attrs, module))))

      {:var, _} = v ->
        Store.attach(subst, v, attv_id(), %{module => fun.(nil)})
    end
  end

  # Kennung einer neuen attributierten Variablen: aus dem gemeinsamen Zähler
  # (steigend, damit call_residue_vars/2 die während eines Ziels
  # entstandenen erkennt)
  @doc false
  def attv_id, do: PrologEx.Vars.next()

  @doc "Suspension an alle Variablen hängen"
  # Die Liste steht mit dem neuesten Eintrag vorn (Anhängen in O(1));
  # gelesen wird sie mit susp_items/1 in Reihenfolge des Anhängens.
  def suspend(subst, vars, susp) do
    Enum.reduce(vars, subst, fn v, s ->
      # ein walk statt dreien (get_attrs, put_attr)
      case Store.walk(v, s) do
        {:var, {:attv, id}} ->
          Store.update_attrs(s, id, %{"$susp" => [susp]}, fn attrs ->
            Map.put(attrs, "$susp", cons(susp, Map.get(attrs, "$susp", [])))
          end)

        {:var, _} = v ->
          Store.attach(s, v, attv_id(), %{"$susp" => [susp]})
      end
    end)
  end

  # Suspensionen aus den Attributen einer Variablen, älteste zuerst
  defp susp_items(attrs), do: attrs |> Map.get("$susp", []) |> prolog_items() |> Enum.reverse()

  @doc """
  Attributierte Variablen in t, in Reihenfolge des Auftretens, auch die nur
  über Attribute erreichbaren (wie SWI term_attvars/2).
  """
  def term_attvars(t, subst) do
    {acc, _} = attvars(t, subst, {[], %{}})
    Enum.reverse(acc)
  end

  # seen: gesehene Variablen und (PrologEx.Share) schon abgelaufene Teilterme
  defp attvars(t, subst, {acc, seen} = st) do
    case Store.walk(t, subst) do
      {:var, {:attv, id}} = v ->
        if Map.has_key?(seen, v) do
          st
        else
          st = {[v | acc], Map.put(seen, v, true)}

          subst
          |> Store.attrs(id)
          |> Enum.reduce(st, fn {_m, a}, st -> attvars(a, subst, st) end)
        end

      {:struct, _, args} = t ->
        case PrologEx.Share.get(seen, t) do
          {:ok, _} ->
            st

          :error ->
            {acc, seen} = attvars_args(args, subst, st)
            {acc, PrologEx.Share.put(seen, t, true)}
        end

      [h | tl] = l when is_tuple(h) or is_list(h) ->
        case PrologEx.Share.get(seen, l) do
          {:ok, _} ->
            st

          :error ->
            {acc, seen} = attvars(tl, subst, attvars(h, subst, st))
            {acc, PrologEx.Share.put(seen, l, true)}
        end

      [h | tl] ->
        attvars(tl, subst, attvars(h, subst, st))

      _ ->
        st
    end
  end

  defp attvars_args([], _subst, st), do: st
  defp attvars_args([a | as], subst, st), do: attvars_args(as, subst, attvars(a, subst, st))

  @doc "Aktive Suspensionen einer Variablen (Done ungebunden oder ohne Done)"
  def suspensions(var, subst) do
    var
    |> get_attrs(subst)
    |> susp_items()
    |> Enum.filter(&PrologEx.Builtins.Coroutining.active?(&1, subst))
  end

  @doc false
  def prolog_items([]), do: []
  def prolog_items([h | t]), do: [h | prolog_items(t)]
  def prolog_items({:glist, l}), do: prolog_items(unmark({:glist, l}))

  # ---------------------------------------------------------------------
  # Occurs-Check (Flag occurs_check = false | true | error)
  #
  # bind_checked/3 ist die Bindung für alle Stellen, an denen die Variable
  # im gebundenen Term vorkommen KÖNNTE: allgemeine Unifikation und Write-
  # Modus im Klauselkopf. (Bindung an Konstanten oder markierte ground
  # Terme im Kopf braucht keinen Check und nimmt bind/3.)
  # Der Modus liegt unter einem eigenen Schlüssel im Prozess. Gelesen wird
  # er einmal je Unifikation (unify/3), Klauselversuch (try_clauses) bzw.
  # Builtin-Ergebnis und dann als Argument durchgereicht (unify/4,
  # bind_checked/4, match_args/6) – nicht bei jeder Bindung.
  # ---------------------------------------------------------------------

  # Steuerkonstrukte, in die to_body/3 hineinsteigt (dazu M:G): ein call/N
  # mit ihnen geht den allgemeinen Weg
  @body_ops [",", ";", "->", "*->", ":"]

  @occurs_key :prolog_ex_occurs_check

  @doc false
  def occurs_key, do: @occurs_key

  def bind_checked(var, t, subst), do: bind_checked(var, t, subst, occurs_mode())

  # Wert des Flags occurs_check: nil (false), true oder :error
  @compile {:inline, occurs_mode: 0}
  defp occurs_mode do
    case :erlang.get(@occurs_key) do
      :undefined -> nil
      mode -> mode
    end
  end

  @doc false
  # mode: Wert des Flags occurs_check (nil = false, true, :error)
  def bind_checked(var, t, subst, mode) do
    case mode do
      nil ->
        {:ok, Store.bind(var, t, subst)}

      mode ->
        if occurs_checked?(var, t, subst) do
          if mode == :error,
            do: PrologEx.Error.error!(mk("occurs_check", [var, t])),
            else: :error
        else
          {:ok, Store.bind(var, t, subst)}
        end
    end
  end

  # Occurs-Check einer Bindung. Was schon oben entschieden ist (atomar,
  # Variable, als ground markiert), zählt nicht; sonst ein tatsächlicher
  # Check: statistics-Schlüssel occurs_checks (+1) und occurs_check_steps
  # (+ besuchte Teilterme) – lokal mitgezählt, einmal je Check gebucht
  defp occurs_checked?(var, t, subst) do
    case Store.walk(t, subst) do
      {:struct, _, _} = c -> count_occurs(occurs_steps(var, c, subst, 0, %{}))
      [_ | _] = c -> count_occurs(occurs_steps(var, c, subst, 0, %{}))
      ^var -> true
      _ -> false
    end
  end

  defp count_occurs({found, steps, _m}) do
    ref = occurs_counter()
    :counters.add(ref, 1, 1)
    :counters.add(ref, 2, steps)
    found
  end

  @doc "Kommt die (ungebundene) Variable var in t vor?"
  def occurs?(var, t, subst), do: elem(occurs_steps(var, t, subst, 0, %{}), 0)

  # {gefunden?, n + besuchte Teilterme, Memo}; bricht beim ersten Fund ab.
  # Eigene Rekursion über die Argumente (statt Enum.any? mit Closure):
  # trägt den Zähler und ist schneller. Memo (PrologEx.Share): geteilte
  # Teilterme ohne var nur einmal ablaufen.
  defp occurs_steps(var, t, subst, n, m) do
    n = n + 1

    case Store.walk(t, subst) do
      ^var ->
        {true, n, m}

      {:struct, _, args} = st ->
        case PrologEx.Share.get(m, st) do
          {:ok, _} ->
            {false, n, m}

          :error ->
            case occurs_args(var, args, subst, n, m) do
              {false, n, m} -> {false, n, PrologEx.Share.put(m, st, true)}
              found -> found
            end
        end

      # Listenrest per Tail Call: keine Rekursionstiefe entlang der Liste
      [h | tl] ->
        case occurs_steps(var, h, subst, n, m) do
          {false, n, m} -> occurs_steps(var, tl, subst, n, m)
          found -> found
        end

      # atomar, andere Variable, markiert (ground: :gstruct/:glist)
      _ ->
        {false, n, m}
    end
  end

  defp occurs_args(_var, [], _subst, n, m), do: {false, n, m}

  defp occurs_args(var, [a | as], subst, n, m) do
    case occurs_steps(var, a, subst, n, m) do
      {false, n, m} -> occurs_args(var, as, subst, n, m)
      found -> found
    end
  end

  @occurs_count_key :prolog_ex_occurs_counts

  @doc "Occurs-Checks dieser Sitzung: {tatsächliche Checks, besuchte Teilterme}"
  def occurs_counts do
    case Process.get(@occurs_count_key) do
      nil -> {0, 0}
      ref -> {:counters.get(ref, 1), :counters.get(ref, 2)}
    end
  end

  defp occurs_counter do
    case Process.get(@occurs_count_key) do
      nil ->
        ref = :counters.new(2, [])
        Process.put(@occurs_count_key, ref)
        ref

      ref ->
        ref
    end
  end

  def unify(x, y, subst), do: unify(x, y, subst, occurs_mode())

  @doc false
  # mode: siehe bind_checked/4
  def unify(x, y, subst, mode) do
    case u(x, y, subst, mode, %{}) do
      {:ok, s, _m} -> {:ok, s}
      :error -> :error
    end
  end

  @doc """
  Probe: sind x und y unifizierbar? Die Bindungen der Probe werden
  zurückgenommen – die Substitution bleibt, wie sie war.
  """
  def unifiable?(x, y, subst) do
    case unify(x, y, subst) do
      {:ok, _} ->
        Store.restore(subst)
        true

      :error ->
        false
    end
  end

  @doc "Probe für mehrere Paare (siehe unifiable?/3)"
  def unifiable_all?(pairs, subst) do
    case unify_pairs(pairs, subst, occurs_mode()) do
      {:ok, _} ->
        Store.restore(subst)
        true

      :error ->
        Store.restore(subst)
        false
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

  # m: Memo (PrologEx.Share) schon unifizierter Paare zusammengesetzter
  # Teilterme – bei zwei DAGs wird jedes Paar geteilter Teilterme nur
  # einmal unifiziert (Unifikation ist idempotent). Kein === auf
  # zusammengesetzten Termen: auf zwei verschiedenen DAGs liefe es (in C)
  # Pfad für Pfad; physisch derselbe Term genügt (same?/2, O(1)).
  defp u(x, y, subst, mode, m) do
    x = Store.walk(x, subst)
    y = Store.walk(y, subst)

    cond do
      # strikt: 1 und 1.0 sind verschiedene Terme (Elixirs == hält sie für gleich)
      not is_tuple(x) and not is_list(x) and x === y ->
        {:ok, subst, m}

      match?({:var, _}, x) and x === y ->
        {:ok, subst, m}

      match?({:atom, _}, x) and x === y ->
        {:ok, subst, m}

      # zwei Variablen: normale an attributierte (kein Wecken), sonst die
      # jüngere an die ältere wie die WAM (Scryer)
      match?({:var, _}, x) and match?({:var, _}, y) ->
        {v, t} = if younger?(x, y), do: {x, y}, else: {y, x}
        with {:ok, s} <- bind_checked(v, t, subst, mode), do: {:ok, s, m}

      match?({:var, _}, x) ->
        with {:ok, s} <- bind_checked(x, y, subst, mode), do: {:ok, s, m}

      match?({:var, _}, y) ->
        with {:ok, s} <- bind_checked(y, x, subst, mode), do: {:ok, s, m}

      PrologEx.Share.same?(x, y) ->
        {:ok, subst, m}

      true ->
        case PrologEx.Share.get2(m, x, y) do
          {:ok, _} ->
            {:ok, subst, m}

          :error ->
            case unify_struct(x, y, subst, mode, m) do
              {:ok, s, m} -> {:ok, s, PrologEx.Share.put2(m, x, y, true)}
              :error -> :error
            end
        end
    end
  end

  # Welche von zwei Variablen wird gebunden? Eine normale vor einer
  # attributierten, sonst die jüngere (größere Kennung; PrologEx.Vars
  # vergibt sie aufsteigend). Eine attributierte Variable ist so alt wie
  # ihr erstes Attribut.
  defp younger?({:var, {:attv, a}}, {:var, {:attv, b}}), do: a > b
  defp younger?({:var, {:attv, _}}, _), do: false
  defp younger?(_, {:var, {:attv, _}}), do: true
  defp younger?({:var, x}, {:var, y}), do: var_age(x) >= var_age(y)

  defp var_age(n) when is_integer(n), do: n
  defp var_age({_, n}) when is_integer(n), do: n
  # nur in Ausgaben (Namen ohne Kennung): wie bisher die linke binden
  defp var_age(_), do: :infinity

  # Zwei markierte (ground) Terme: gleich in der Standardordnung oder nicht
  defp unify_struct(x, y, subst, _mode, m) when is_marked(x) and is_marked(y) do
    if PrologEx.Order.equal?(x, y, subst), do: {:ok, subst, m}, else: :error
  end

  defp unify_struct({t1, f, xs}, {t2, f, ys}, subst, mode, m)
       when t1 in [:struct, :gstruct] and t2 in [:struct, :gstruct] and
              length(xs) == length(ys),
       do: unify_args(xs, ys, subst, mode, m)

  defp unify_struct({:glist, [x | xs]}, [y | ys], subst, mode, m) do
    case u(x, y, subst, mode, m) do
      {:ok, s, m} -> u(glist_tail(xs), ys, s, mode, m)
      :error -> :error
    end
  end

  defp unify_struct([x | xs], {:glist, [y | ys]}, subst, mode, m) do
    case u(x, y, subst, mode, m) do
      {:ok, s, m} -> u(xs, glist_tail(ys), s, mode, m)
      :error -> :error
    end
  end

  # Listen: Kopf unifizieren, dann per Tail Call mit dem Rest weiter –
  # keine Rekursionstiefe entlang der Liste.
  defp unify_struct([x | xs], [y | ys], subst, mode, m) do
    case u(x, y, subst, mode, m) do
      {:ok, s, m} -> u(xs, ys, s, mode, m)
      :error -> :error
    end
  end

  defp unify_struct(_, _, _, _, _), do: :error

  defp unify_args([], [], subst, _mode, m), do: {:ok, subst, m}

  defp unify_args([x | xs], [y | ys], subst, mode, m) do
    case u(x, y, subst, mode, m) do
      {:ok, s, m} -> unify_args(xs, ys, s, mode, m)
      :error -> :error
    end
  end

  # Vollständig auflösen, ohne Markierungen (für Antworten / Interop).
  # Geteilte Teilterme werden nur einmal aufgelöst (PrologEx.Share) und
  # bleiben im Ergebnis geteilt.
  def resolve(t, subst) do
    {r, _memo} = resolve(t, subst, %{})
    r
  end

  defp resolve(t, subst, memo) do
    case Store.walk(t, subst) do
      {:struct, f, args} = st ->
        case PrologEx.Share.get(memo, st) do
          {:ok, r} ->
            {r, memo}

          :error ->
            {args2, memo} = resolve_args(args, subst, memo)
            r = {:struct, f, args2}
            {r, PrologEx.Share.put(memo, st, r)}
        end

      [h | tl] = l when is_tuple(h) or is_list(h) ->
        # Zelle mit zusammengesetztem Kopf (etwa [X|X]): merken
        case PrologEx.Share.get(memo, l) do
          {:ok, r} ->
            {r, memo}

          :error ->
            {h2, memo} = resolve(h, subst, memo)
            {t2, memo} = resolve(tl, subst, memo)
            r = [h2 | t2]
            {r, PrologEx.Share.put(memo, l, r)}
        end

      [h | tl] ->
        {t2, memo} = resolve(tl, subst, memo)
        {[h | t2], memo}

      t when is_marked(t) ->
        {unmark(t), memo}

      other ->
        {other, memo}
    end
  end

  defp resolve_args([], _subst, memo), do: {[], memo}

  defp resolve_args([a | as], subst, memo) do
    {a, memo} = resolve(a, subst, memo)
    {as, memo} = resolve_args(as, subst, memo)
    {[a | as], memo}
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

  @doc """
  Wie `copy_fresh/2`, aber die Variablen von `keep` bleiben dieselben
  (für `Free+\\Lambda`: globale Variablen werden nicht umbenannt).
  """
  def copy_fresh(t, subst, keep) do
    map = keep |> PrologEx.Builtins.Order.variables(subst) |> Map.new(&{&1, &1})
    {c, _map} = copy(t, subst, map)
    c
  end

  defp copy(t, subst, map) do
    case Store.walk(t, subst) do
      {:var, _} = var ->
        case Map.fetch(map, var) do
          {:ok, fresh} ->
            {fresh, map}

          :error ->
            fresh = {:var, PrologEx.Vars.next()}
            {fresh, Map.put(map, var, fresh)}
        end

      m when is_marked(m) ->
        {m, map}

      {:struct, f, args} = st ->
        # geteilte Teilterme nur einmal kopieren; die Kopie bleibt geteilt
        case PrologEx.Share.get(map, st) do
          {:ok, c} ->
            {c, map}

          :error ->
            {args, map} = copy_args(args, subst, map)
            c = mk_struct(f, args)
            {c, PrologEx.Share.put(map, st, c)}
        end

      [h | tl] = l when is_tuple(h) or is_list(h) ->
        case PrologEx.Share.get(map, l) do
          {:ok, c} ->
            {c, map}

          :error ->
            {h, map} = copy(h, subst, map)
            {tl, map} = copy(tl, subst, map)
            c = cons(h, tl)
            {c, PrologEx.Share.put(map, l, c)}
        end

      [h | tl] ->
        {h, map} = copy(h, subst, map)
        {tl, map} = copy(tl, subst, map)
        {cons(h, tl), map}

      atomic ->
        {atomic, map}
    end
  end

  # Argumente kopieren (eigene Rekursion statt Enum.map_reduce mit Closure)
  defp copy_args([], _subst, map), do: {[], map}

  defp copy_args([a | as], subst, map) do
    {a, map} = copy(a, subst, map)
    {as, map} = copy_args(as, subst, map)
    {[a | as], map}
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
  # (:erlang.get/1 direkt: Process.get/2 wäre zwei Aufrufe mehr, und das
  # hier läuft bei jeder Inferenz)
  def current_db do
    case :erlang.get(@db_key) do
      :undefined -> %{}
      db -> db
    end
  end

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

  @doc """
  multifile/1, discontiguous/1: das Prädikat existiert danach (ohne
  Klauseln scheitert ein Aufruf nur, statt existence_error), und die
  Eigenschaft wird gemerkt (`kind`: :multifile | :discontiguous).
  """
  def declare_property(db, key, kind) do
    key = pkey(key)

    db
    |> Map.put_new(key, build_pred([]))
    |> Map.update(kind, MapSet.new([key]), &MapSet.put(&1, key))
  end

  @doc false
  def has_property?(db, key, kind), do: MapSet.member?(Map.get(db, kind, MapSet.new()), pkey(key))

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
      # Prädikate mit Heimat-Bibliothek (iso_ext, swi, ...): nur nach dem
      # Import, in den Modulen des Systems oder mit swi_compat
      if PrologEx.Builtins.home(name, arity) == nil or home_visible?(mod),
        do: local(db, "system", name, arity),
        else: :none
    end
  end

  @doc """
  Alle Exporte des Bibliotheksmoduls `lib` in Modul `into` importieren
  (wie `use_module(library(lib))`; für Elixir-Aufrufer und Tests).
  """
  def use_library(db, lib, into \\ "user") do
    exports = PrologEx.Builtins.exports(lib) || raise ArgumentError, "keine Bibliothek: #{lib}"

    Enum.reduce(exports, db, fn {n, a}, db ->
      if Map.has_key?(db, {into, n, a}),
        do: db,
        else: Map.put(db, {:import, into, n, a}, PrologEx.Builtins.source(lib, n, a))
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
          nil ->
            # Re-Export (lists:maplist(...)): im Quellmodul
            case PrologEx.Builtins.source(mod, name, arity) do
              ^mod -> :none
              src -> local(db, src, name, arity)
            end

          entry ->
            {:builtin, mod, entry}
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
  def pred_entries({:pred, _, _, _, entries}), do: flat(entries)
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
  # clause/2: Quelltext der Klauseln, die der Aufruf mit diesen Argumenten
  # versuchen würde (Index aufs erste Argument: gleicher Schlüssel oder
  # Variable an erster Stelle), in Reihenfolge
  def pred_source(pred, args, subst),
    do: for({_, src, _} <- candidate_entries(pred, args, subst), do: src)

  @doc false
  # Einträge {ref, quelltext, übersetzt} wie pred_source/3 (für retract/1,
  # retractall/1: nur diese können passen)
  def candidate_entries(pred, args, subst) do
    entries = pred_entries(pred)

    case args do
      [x | _] ->
        case Store.walk(x, subst) do
          {:var, _} ->
            entries

          t ->
            k = index_key(t)
            for {_, _, c} = e <- entries, (ck = elem(c, 1)) == :any or ck == k, do: e
        end

      [] ->
        entries
    end
  end

  @doc false
  def materialize({:pred, _, _, _, _} = p), do: p

  def materialize({:pending, {:pred, cls, _, _, _} = p, fr, bk} = pending) do
    # viele neue Klauseln: Neubau ist dann billiger als Erweitern (die
    # Länge von cls nur zählen, wenn es viele sind: sonst O(n) je assert)
    n = length(fr) + length(bk)

    if n > 16 and n > count(cls),
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

    # vorn voranstellen ist billig (O(neu)); hinten anhängen nur vormerken
    # ({:cat, liste, hinten_umgekehrt}), sonst kostete jedes assertz mit
    # folgendem Aufruf O(n) – flach wird erst, wer die ganze Liste braucht
    {:pred, cat(Enum.map(fr, cl), cls, Enum.map(bk, cl)), by_key, Enum.reverse(var_only_rev),
     cat(fr, entries, bk)}
  end

  # front ++ l ++ back, das Anhängen hinten aufgeschoben
  defp cat(front, {:cat, l, r}, back), do: {:cat, front ++ l, :lists.reverse(back, r)}
  defp cat(front, l, []), do: front ++ l
  defp cat(front, l, back), do: {:cat, front ++ l, :lists.reverse(back)}

  @doc false
  # Prädikat mit flachen Listen (Vergleich in Tests: erweitert == Neubau)
  def flat_pred({:pred, all, by_key, var_only, entries}),
    do: {:pred, flat(all), by_key, var_only, flat(entries)}

  defp flat({:cat, l, r}), do: l ++ :lists.reverse(r)
  defp flat(l), do: l

  defp count({:cat, l, r}), do: length(l) + length(r)
  defp count(l), do: length(l)

  # Aufruf, der alle Klauseln braucht (erstes Argument offen, nullstellig),
  # bei aufgeschobenem Anhängen: einmal flach machen und zurückschreiben
  defp flat_for_call({:pred, {:cat, _, _}, _, _, _} = p, key, args, subst) do
    open =
      case args do
        [] -> true
        [x | _] -> match?({:var, _}, Store.walk(x, subst))
      end

    if open do
      {:pred, all, by_key, var_only, entries} = p
      p = {:pred, flat(all), by_key, var_only, flat(entries)}
      update_db(&Map.put(&1, key, p))
      p
    else
      p
    end
  end

  defp flat_for_call(p, _key, _args, _subst), do: p

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
        flat(all)

      [x | _] ->
        case Store.walk(x, subst) do
          {:var, _} -> flat(all)
          t -> Map.get(by_key, index_key(t), var_only)
        end
    end
  end

  # --- Kopf matchen (Read-Modus) ---------------------------------------

  # mode: Wert des Flags occurs_check (einmal je Klauselversuch gelesen)
  defp match_args([], [], env, s, nv, _mode), do: {:ok, env, s, nv}

  defp match_args([p | ps], [t | ts], env, s, nv, mode) do
    case m(p, t, env, s, nv, mode) do
      {:ok, env, s, nv} -> match_args(ps, ts, env, s, nv, mode)
      :error -> :error
    end
  end

  defp m(:void, _t, env, s, nv, _mode), do: {:ok, env, s, nv}
  defp m({:first, i}, t, env, s, nv, _mode), do: {:ok, put_elem(env, i, t), s, nv}

  defp m({:val, i}, t, env, s, nv, mode) do
    case unify(elem(env, i), t, s, mode) do
      {:ok, s} -> {:ok, env, s, nv}
      :error -> :error
    end
  end

  defp m({:const, c}, t, env, s, nv, _mode) do
    case Store.walk(t, s) do
      ^c -> {:ok, env, s, nv}
      {:var, _} = v -> {:ok, env, Store.bind(v, c, s), nv}
      _ -> :error
    end
  end

  defp m({:ground, c}, t, env, s, nv, mode) do
    case Store.walk(t, s) do
      {:var, _} = v ->
        {:ok, env, Store.bind(v, c, s), nv}

      t ->
        case unify(t, c, s, mode) do
          {:ok, s} -> {:ok, env, s, nv}
          :error -> :error
        end
    end
  end

  defp m({:list, ph, pt} = p, t, env, s, nv, mode) do
    case Store.walk(t, s) do
      [h | tl] ->
        case m(ph, h, env, s, nv, mode) do
          {:ok, env, s, nv} -> m(pt, tl, env, s, nv, mode)
          :error -> :error
        end

      {:glist, [h | tl]} ->
        case m(ph, h, env, s, nv, mode) do
          {:ok, env, s, nv} -> m(pt, glist_tail(tl), env, s, nv, mode)
          :error -> :error
        end

      {:var, _} = v ->
        # Write-Modus: der gebaute Term kann Slot-Inhalte enthalten, also
        # ggf. mit Occurs-Check binden
        {term, env, nv} = build(p, env, nv)

        case bind_checked(v, term, s, mode) do
          {:ok, s} -> {:ok, env, s, nv}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp m({:struct, f, n, ps} = p, t, env, s, nv, mode) do
    case Store.walk(t, s) do
      {tag, ^f, args} when tag in [:struct, :gstruct] and length(args) == n ->
        match_args(ps, args, env, s, nv, mode)

      {:var, _} = v ->
        # Write-Modus: der gebaute Term kann Slot-Inhalte enthalten, also
        # ggf. mit Occurs-Check binden
        {term, env, nv} = build(p, env, nv)

        case bind_checked(v, term, s, mode) do
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

  # übersetzte Arithmetik (siehe PrologEx.Compiler): nur das Ziel, nicht
  # den Ausdruck bauen
  defp inst({:t_arith, :is, out, code, leaves}, env, base),
    do: {:struct, "$is", [inst(out, env, base), {:arith, code} | inst_args(leaves, env, base)]}

  defp inst({:t_arith, :cmp, nil, code, leaves}, env, base),
    do: {:struct, "$cmp", [{:arith, code} | inst_args(leaves, env, base)]}

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

  # aktuelle Ebene für call_with_depth_limit/3 (ein Eintrag der Substitution)
  @depth_key :"$depth"

  # Zeitgrenzen (siehe rearm/1): Prüfpunkt alle @tcheck Inferenzen, Timer
  # von set_timer/1 im Prozess-Dictionary (je Anfrage), die Ausnahme
  @tcheck 1000
  @timers_key :prolog_ex_timers
  @time_ball {:atom, "time_limit_exceeded"}

  defstruct goals: [],
            subst: Store.new(),
            cps: [],
            height: 0,
            db: %{},
            # Kennungen frischer Variablen: der nächste und das Ende des
            # Blocks aus PrologEx.Vars (exklusiv)
            next_var: 0,
            var_end: 0,
            answer: [],
            threshold: @min_threshold,
            min_threshold: @min_threshold,
            # Zähler für call_nth/2: überstehen Backtracking (nicht in subst)
            counters: %{},
            # catch/3-Rahmen, deren Ziel gerade verlassen ist (siehe catch/3)
            catch_off: MapSet.new(),
            # Inferenzzähler der Sitzung (:counters, je Prozess einer);
            # Unter-Maschinen (findall, \\+, ...) teilen ihn
            icount: nil,
            # aktive Inferenzgrenzen (call_with_inference_limit/3):
            # [{id, Grenze}] und die kleinste davon (nil: keine aktiv)
            ilimits: [],
            ilimit: nil,
            # aktive Zeitgrenzen (call_with_timeout): [{id, Deadline in µs
            # (monotone Uhr)}]; sie und set_timer/1 setzen ilimit als
            # Prüfpunkt (siehe rearm/1)
            tlimits: [],
            # Kennung der Anfrage (für set_timer/1; Unter-Maschinen teilen sie)
            qref: nil,
            # aktive Tiefengrenzen (call_with_depth_limit/3):
            # [{atomics, Basisebene, höchste erlaubte Ebene}] und das Minimum
            # der höchsten erlaubten Ebenen (nil: keine aktiv)
            dlimits: [],
            dlimit: nil,
            # gab es in diesem Lauf schon setup_call_cleanup/3? Nur dann
            # müssen Cuts die abgeschnittenen Choice Points ansehen
            scc: false

  # (vor dem Wecken nicht kompaktieren: $wake braucht die Attribute der
  # eben gebundenen Variablen)
  defp run(%{goals: [{{:"$wake", _}, _, _} | _]} = st), do: run_step(st)
  defp run(st), do: run_step(maybe_compact(st))

  defp run_step(st) do
    case st.goals do
      [] ->
        {:sol, st}

      [{goal, cutb, mod} | rest] ->
        goal = unmark_top(Store.walk(goal, st.subst))
        count_inference(goal, st.icount)

        # ohne aktive Inferenz- oder Zeitgrenze nur dieser eine Vergleich
        if st.ilimit != nil and :counters.get(st.icount, 1) > st.ilimit,
          do: limit_hit(goal, cutb, mod, rest, st),
          else: step(goal, cutb, mod, rest, st)
    end
  end

  # Inferenz = Aufruf eines Prädikats (wie SWI), auch eingebauter wie =/2
  # und is/2; nicht: Steuerkonstrukte und call/N (das gerufene Ziel zählt
  # selbst), interne Ziele der Maschine
  defp count_inference({:struct, f, _}, _ref) when f in [",", ";", "->", ":", "call"], do: :ok
  defp count_inference({:struct, _, _}, ref), do: :counters.add(ref, 1, 1)
  defp count_inference({:atom, "!"}, _ref), do: :ok
  defp count_inference({:atom, _}, ref), do: :counters.add(ref, 1, 1)
  defp count_inference(_, _ref), do: :ok

  @icount_key :prolog_ex_inferences

  @doc "Inferenzen dieser Sitzung (Prozess) bisher"
  def inferences do
    case Process.get(@icount_key) do
      nil -> 0
      ref -> :counters.get(ref, 1)
    end
  end

  defp inference_counter do
    case Process.get(@icount_key) do
      nil ->
        ref = :counters.new(1, [])
        Process.put(@icount_key, ref)
        ref

      ref ->
        ref
    end
  end

  defp step({:atom, "true"}, _cutb, _mod, rest, st), do: run(%{st | goals: rest})
  defp step({:atom, "fail"}, _cutb, _mod, _rest, st), do: backtrack(st)

  defp step({:atom, "!"}, cutb, _mod, rest, st) do
    {st, rest} = cut_to(st, cutb, rest)
    run(%{st | goals: rest})
  end

  defp step({:struct, ",", [g1, g2]}, cutb, mod, rest, st),
    do: run(%{st | goals: [{g1, cutb, mod}, {g2, cutb, mod} | rest]})

  defp step({:struct, ";", [g1, g2]}, cutb, mod, rest, st) do
    case unmark_top(Store.walk(g1, st.subst)) do
      {:struct, "->", [c, t]} ->
        if_then_else(c, t, g2, cutb, mod, rest, st)

      # Soft-Cut (library(swi)): unsichtbar wie eine gewöhnliche
      # Disjunktion, deren linker Zweig dann existence_error gibt
      {:struct, "*->", [c, t]} = sc ->
        if engine_visible?("*->", 2, mod),
          do: soft_if(c, t, g2, cutb, mod, rest, st),
          else: disjunction(sc, g2, cutb, mod, rest, st)

      _ ->
        disjunction(g1, g2, cutb, mod, rest, st)
    end
  end

  defp step({:struct, "->", [c, t]}, cutb, mod, rest, st),
    do: if_then_else(c, t, {:atom, "fail"}, cutb, mod, rest, st)

  # C *-> T ohne Else: wie (C, T), Cut in C lokal (wie SWI)
  defp step({:struct, "*->", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  # if(C, T, E) (SICStus): wie (C *-> T ; E)
  defp step({:struct, "if", [c, t, e]}, cutb, mod, rest, st),
    do: soft_if(c, t, e, cutb, mod, rest, st)

  # Interne Markierung (soft cut): C hat eine Lösung – den Choice Point für
  # Else an Höhe h + 1 unwirksam machen, die Alternativen von C bleiben.
  # Liegt er ganz oben (C ohne Alternativen), fällt er einfach weg.
  defp step({:"$soft_cut", h}, _cutb, _mod, rest, st) do
    case st.height - h - 1 do
      0 ->
        run(%{st | goals: rest, cps: tl(st.cps), height: h})

      i when i > 0 ->
        run(%{st | goals: rest, cps: List.replace_at(st.cps, i, :dead)})

      # schon abgeschnitten (oder schon unwirksam gemacht und weg)
      _ ->
        run(%{st | goals: rest})
    end
  end

  # Interne Markierung: Choice Points bis zur Höhe h abschneiden
  defp step({:"$cut_to", h}, _cutb, _mod, rest, st) do
    {st, rest} = cut_to(st, h, rest)
    run(%{st | goals: rest})
  end

  # call/1: Cut darin ist lokal (Barriere = aktuelle Höhe)
  # call/N: Ziel wie ISO 7.6.2 in einen Rumpf umwandeln – Variablen an
  # Zielstellen werden call(V) (ein später gebundener Cut ist dann lokal),
  # Nicht-Aufrufbares irgendwo im Gerüst aus , ; -> gibt sofort
  # type_error(callable, Ziel), bevor etwas ausgeführt wird
  # call/1..8, Schnellweg: ein Atom oder eine Struktur, die weder
  # Steuerkonstrukt noch M:G ist – das Ziel ist dann schon ein Rumpf (to_body
  # gäbe es unverändert zurück), Fehler sind ausgeschlossen: ohne Closure,
  # ohne zweites walk
  defp step({:struct, "call", [g | extra]}, _cutb, mod, rest, st) do
    case call_target(g, extra, mod, st.subst) do
      {:general, t} -> call_general(t, extra, mod, rest, st)
      {goal, m} -> run(%{st | goals: [{goal, st.height, m} | rest]})
    end
  end

  # foldl/4..6 (library(apply)): '$foldl'(Ls..., G, V0, V) führt die
  # Maschine selbst aus, solange alle Listen vorn eine Zelle haben bzw.
  # alle leer sind – statt Klauselauswahl, Kopfunifikation und Rumpf je
  # Element: call(G, X..., V0, V1) über den Schnellweg von call/N und
  # dahinter wieder '$foldl'. Dieselben Inferenzen ('$foldl' und G je
  # Element). Offene oder ungleich lange Listen gehen über die Klauseln
  # (Aufzählen, Scheitern wie bisher). Nur die Aufrufe der Bibliothek
  # selbst (Modul apply).
  # Je Stelligkeit ein eigener Fall (kein Zerlegen der Argumentliste); das
  # Folgeziel und call(G, X..., V0, V1) werden ohne Ground-Prüfung gebaut –
  # sie enthalten die frische Variable V1, sind also nie ground.
  defp step({:struct, "$foldl", [l, g, v0, v]} = goal, cutb, "apply" = mod, rest, st) do
    case uncons(Store.walk(l, st.subst)) do
      {:cons, x, t} ->
        {v1, st} = foldl_var(st)
        foldl_call(g, [x, v0, v1], {:struct, "$foldl", [t, g, v1, v]}, cutb, mod, rest, st)

      :empty ->
        foldl_done(v0, v, rest, st)

      :other ->
        call_pred(goal, mod, rest, st)
    end
  end

  defp step({:struct, "$foldl", [l1, l2, g, v0, v]} = goal, cutb, "apply" = mod, rest, st) do
    case {uncons(Store.walk(l1, st.subst)), uncons(Store.walk(l2, st.subst))} do
      {{:cons, x, t1}, {:cons, y, t2}} ->
        {v1, st} = foldl_var(st)
        next = {:struct, "$foldl", [t1, t2, g, v1, v]}
        foldl_call(g, [x, y, v0, v1], next, cutb, mod, rest, st)

      {:empty, :empty} ->
        foldl_done(v0, v, rest, st)

      _ ->
        call_pred(goal, mod, rest, st)
    end
  end

  defp step({:struct, "$foldl", [l1, l2, l3, g, v0, v]} = goal, cutb, "apply" = mod, rest, st) do
    case {uncons(Store.walk(l1, st.subst)), uncons(Store.walk(l2, st.subst)),
          uncons(Store.walk(l3, st.subst))} do
      {{:cons, x, t1}, {:cons, y, t2}, {:cons, z, t3}} ->
        {v1, st} = foldl_var(st)
        next = {:struct, "$foldl", [t1, t2, t3, g, v1, v]}
        foldl_call(g, [x, y, z, v0, v1], next, cutb, mod, rest, st)

      {:empty, :empty, :empty} ->
        foldl_done(v0, v, rest, st)

      _ ->
        call_pred(goal, mod, rest, st)
    end
  end

  # functor/3, arg/3, =../2, copy_term/2 (ISO, geschützt: kein Modul
  # definiert sie um) ohne
  # den allgemeinen Aufrufweg eines Builtins; das Ergebnis außerhalb des
  # geschützten Bereichs (Endrekursion, Fehler der Fortsetzung bleiben ihre)
  defp step({:struct, "functor", [t, n, a]}, _cutb, mod, rest, st) do
    try do
      PrologEx.Builtins.Terms.functor(t, n, a, st.subst)
    rescue
      e in PrologEx.Error -> throw_ball(e.term, st)
    else
      r -> apply_result(r, mod, rest, st)
    end
  end

  # ==/2 und \\==/2 (ISO, geschützt): können nicht werfen, direkt
  defp step({:struct, "==", [x, y]}, _cutb, _mod, rest, st) do
    if PrologEx.Order.equal?(x, y, st.subst), do: run(%{st | goals: rest}), else: backtrack(st)
  end

  defp step({:struct, "\\==", [x, y]}, _cutb, _mod, rest, st) do
    if PrologEx.Order.equal?(x, y, st.subst), do: backtrack(st), else: run(%{st | goals: rest})
  end

  # compare/3, @</2, @>/2, @=</2, @>=/2 (ISO, geschützt) direkt. compare/3:
  # ungebundenes Order (gewöhnliche Variable) direkt binden, gebundenes
  # gültiges nur vergleichen; sonst (attributiert, Fehler) das Builtin
  defp step({:struct, "compare", [o, x, y]} = goal, _cutb, mod, rest, st) do
    case Store.walk(o, st.subst) do
      {:var, n} = v when not (is_tuple(n) and elem(n, 0) == :attv) ->
        sym = order_atom(PrologEx.Order.compare(x, y, st.subst))
        run(%{st | goals: rest, subst: Store.bind(v, sym, st.subst)})

      {:atom, s} when s in ["<", "=", ">"] ->
        if order_atom(PrologEx.Order.compare(x, y, st.subst)) == {:atom, s},
          do: run(%{st | goals: rest}),
          else: backtrack(st)

      _ ->
        call_pred(goal, mod, rest, st)
    end
  end

  defp step({:struct, "@<", [x, y]}, _cutb, _mod, rest, st),
    do: order_step(PrologEx.Order.compare(x, y, st.subst) == :lt, rest, st)

  defp step({:struct, "@>", [x, y]}, _cutb, _mod, rest, st),
    do: order_step(PrologEx.Order.compare(x, y, st.subst) == :gt, rest, st)

  defp step({:struct, "@=<", [x, y]}, _cutb, _mod, rest, st),
    do: order_step(PrologEx.Order.compare(x, y, st.subst) != :gt, rest, st)

  defp step({:struct, "@>=", [x, y]}, _cutb, _mod, rest, st),
    do: order_step(PrologEx.Order.compare(x, y, st.subst) != :lt, rest, st)

  # bb_get/2, bb_put/2 (library(blackboard)) direkt, wenn der Aufruf sie
  # meint: aus blackboard importiert und nicht selbst definiert (oder im
  # Modul blackboard); sonst der allgemeine Weg (eigene Definition,
  # Re-Export über ein anderes Modul, nicht importiert → Fehler)
  defp step({:struct, "bb_get", [k, t]} = goal, _cutb, mod, rest, st) do
    if bb_visible?(mod, "bb_get") do
      try do
        PrologEx.Builtins.Blackboard.get(k, t, mod, st.subst)
      rescue
        e in PrologEx.Error -> throw_ball(e.term, st)
      else
        r -> apply_result(r, mod, rest, st)
      end
    else
      call_pred(goal, mod, rest, st)
    end
  end

  defp step({:struct, "bb_put", [k, t]} = goal, _cutb, mod, rest, st) do
    if bb_visible?(mod, "bb_put") do
      try do
        PrologEx.Builtins.Blackboard.put(k, t, mod, st.subst)
      rescue
        e in PrologEx.Error -> throw_ball(e.term, st)
      else
        r -> apply_result(r, mod, rest, st)
      end
    else
      call_pred(goal, mod, rest, st)
    end
  end

  # current_prolog_flag/2 (ISO, geschützt) mit gebundenem Namen: das Flag
  # direkt lesen, deterministisch; sonst (Aufzählen, Fehler) das Builtin
  defp step({:struct, "current_prolog_flag", [f, v]} = goal, _cutb, mod, rest, st) do
    with {:atom, name} <- unmark_top(Store.walk(f, st.subst)),
         val when val != nil <- PrologEx.Flags.get(name) do
      apply_result({:unify, [{v, val}]}, mod, rest, st)
    else
      _ -> call_pred(goal, mod, rest, st)
    end
  end

  defp step({:struct, "copy_term", [t, c]}, _cutb, mod, rest, st),
    do: apply_result(PrologEx.Builtins.Terms.copy_term(t, c, st.subst), mod, rest, st)

  defp step({:struct, "=..", [t, l]}, _cutb, mod, rest, st) do
    try do
      PrologEx.Builtins.Terms.univ(t, l, st.subst)
    rescue
      e in PrologEx.Error -> throw_ball(e.term, st)
    else
      r -> apply_result(r, mod, rest, st)
    end
  end

  defp step({:struct, "arg", [n, t, x]}, _cutb, mod, rest, st) do
    try do
      PrologEx.Builtins.Terms.arg(n, t, x, st.subst)
    rescue
      e in PrologEx.Error -> throw_ball(e.term, st)
    else
      r -> apply_result(r, mod, rest, st)
    end
  end

  defp step({:struct, "plus", [_, _, _]} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  defp step({:struct, "not", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  # once/1 (ISO, nicht geschützt) und ignore/1 (library(swi)): sonst
  # Prolog-Klauseln (call(G), !) bzw. (call(G) -> true ; true) – gleich
  # direkt als Bedingung; call/1 behält Fehler (type_error(callable)), den
  # lokalen Cut und das Modul des Aufrufers
  defp step({:struct, "once", [_]} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  defp step({:struct, "ignore", [_]} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  defp step({:struct, "=", [x, y]}, _cutb, _mod, rest, st) do
    case guarded(fn -> unify(x, y, st.subst) end) do
      {:ok, {:ok, s1}} -> cont(st, s1, rest)
      {:ok, :error} -> backtrack(st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  # Negation: eigener Lauf mit leerem Choice-Point-Stack (Cut darin ist lokal)
  defp step({:struct, "\\+", [g]}, _cutb, mod, rest, st) do
    case guarded(fn ->
           run(%{st | goals: [{body!(g, st.subst), 0, mod}], cps: [], height: 0, answer: []})
         end) do
      {:ok, {:sol, sub}} -> discard(sub, resync(st), &backtrack/1)
      {:ok, :done} -> run(%{resync(st) | goals: rest})
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  # findall(T, G, L) / findall(T, G, L, Rest): alle Lösungen in einer
  # Unter-Maschine, als Kopien mit frischen Variablen
  defp step({:struct, "findall", [t, g, l]}, cutb, mod, rest, st),
    do: step({:struct, "findall", [t, g, l, []]}, cutb, mod, rest, st)

  defp step({:struct, "findall", [t, g, l, tail]}, _cutb, mod, rest, st) do
    # ISO 8.10.1.3: die Ergebnisliste muss eine (Teil-)Liste sein – vorab
    case guarded(fn ->
           partial_list!(l, st.subst)
           collect(run(sub_machine(t, body!(g, st.subst), mod, st)), :infinity, [])
         end) do
      {:ok, {items, :done}} ->
        case unify(l, list(items, tail), st.subst) do
          {:ok, s} -> cont(resync(st), s, rest)
          :error -> backtrack(st)
        end

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  # '$aggregate_all'(T, G, R) (library(aggregate)): die Lösungen von G
  # in das Template T falten (PrologEx.Aggregate), ohne sie zu sammeln –
  # count, sum, min, max mit konstantem Speicher; Template vorab geprüft
  defp step({:struct, "$aggregate_all", [t, g, r]}, _cutb, mod, rest, st) do
    folded =
      guarded(fn ->
        spec = PrologEx.Aggregate.spec!(t, st.subst)

        acc =
          fold(
            run(sub_machine(t, body!(g, st.subst), mod, st)),
            spec,
            PrologEx.Aggregate.init(spec)
          )

        PrologEx.Aggregate.result(spec, acc)
      end)

    case folded do
      {:ok, {:ok, v}} ->
        case unify(r, v, st.subst) do
          {:ok, s} -> cont(resync(st), s, rest)
          :error -> backtrack(st)
        end

      {:ok, :fail} ->
        backtrack(st)

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  # countall(G, N): Anzahl der Lösungen von G, ohne sie zu sammeln
  # (konstanter Speicher, anders als findall + length)
  defp step({:struct, "countall", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  # findnsols(N, T, G, L) / findnsols(N, T, G, L, Rest) (wie SWI): jeweils
  # höchstens N Lösungen; beim Backtracking die nächsten N. Die Unter-
  # Maschine wird dazu im Choice Point aufbewahrt und fortgesetzt. Ist ein
  # Teil kürzer als N, ist es der letzte (deterministisch); ging es genau
  # auf, folgt wie bei SWI noch ein leerer Teil.
  defp step({:struct, "findnsols", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  defp step({:struct, "is", [x, expr]}, _cutb, _mod, rest, st) do
    case guarded(fn -> unify(x, eval(expr, st.subst), st.subst) end) do
      {:ok, {:ok, s1}} -> cont(st, s1, rest)
      {:ok, :error} -> backtrack(st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  # übersetztes is/2 bzw. übersetzter Vergleich (siehe inst/3)
  defp step({:struct, "$is", [x, {:arith, code} | leaves]}, _cutb, _mod, rest, st) do
    case guarded(fn ->
           unify(x, PrologEx.Arith.run(code, List.to_tuple(leaves), st.subst), st.subst)
         end) do
      {:ok, {:ok, s1}} -> cont(st, s1, rest)
      {:ok, :error} -> backtrack(st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp step({:struct, "$cmp", [{:arith, {:cmp, op, a, b}} | leaves]}, _cutb, _mod, rest, st) do
    l = List.to_tuple(leaves)

    case guarded(fn ->
           compare(op, PrologEx.Arith.run(a, l, st.subst), PrologEx.Arith.run(b, l, st.subst))
         end) do
      {:ok, true} -> run(%{st | goals: rest})
      {:ok, false} -> backtrack(st)
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
        wake_and_run(attvs, st.subst, st, rest)

      mods ->
        pairs = for v <- attvs, {:ok, val} = Store.binding(st.subst, v), do: {v, val}
        subst = Enum.reduce(attvs, st.subst, &Store.unbind(&2, &1))

        hooks =
          for {v, val} <- pairs, m <- mods do
            g = {:var, PrologEx.Vars.next()}
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

  # geweckte freeze-Suspension, die hinter einem anderen Weckziel ansteht
  # (siehe wake_builtin/4): jetzt neu stellen – das Ziel läuft (wie call/1,
  # Cut lokal) oder wartet an der Variablen, an die V gebunden wurde
  defp step({:struct, "$wake_fz", [v, g]}, _cutb, _mod, rest, st) do
    case PrologEx.Builtins.Coroutining.freeze(v, g, st.subst) do
      {:call, goal} -> run(%{st | goals: [{goal, st.height, "system"} | rest]})
      {:ok, s} -> run(%{st | subst: s, goals: rest})
    end
  end

  # geweckte when-Suspension hinter einem anderen Weckziel: Done prüfen und
  # binden, Bedingung neu stellen
  defp step({:struct, "$wake_wh", [susp]}, _cutb, _mod, rest, st) do
    case wake_when(susp, st.subst) do
      :done -> run(%{st | goals: rest})
      {:call, goal, s} -> run(%{st | subst: s, goals: [{goal, st.height, "system"} | rest]})
      {:ok, s} -> run(%{st | subst: s, goals: rest})
    end
  end

  # Ausschlussmenge einer gebundenen Variablen prüfen (siehe wake_builtin/4)
  defp step({:struct, "$difset_check", [x, data]}, _cutb, _mod, rest, st) do
    case PrologEx.Builtins.Coroutining.check_excluded(x, data, st.subst) do
      {:ok, s} -> run(%{st | subst: s, goals: rest})
      :fail -> backtrack(st)
    end
  end

  # geweckte dif-Suspensionen hinter einem anderen Weckziel (siehe
  # wake_builtin/4): je aktivem Eintrag Done binden und dif neu stellen
  defp step({:struct, "$difs", [difs]}, _cutb, _mod, rest, st) do
    result =
      difs
      |> prolog_items()
      |> Enum.reduce_while({:ok, st.subst}, fn susp, {:ok, s} ->
        case wake_dif(susp, s) do
          :fail -> {:halt, :fail}
          ok -> {:cont, ok}
        end
      end)

    case result do
      {:ok, s} -> run(%{st | subst: s, goals: rest})
      :fail -> backtrack(st)
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

        case Store.walk(v, s) do
          {:var, {:attv, _}} = av -> {Store.put_binding(s, av, val), [av | attvs], again}
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
        # eingebaute Suspensionen erst nach den Goals der Hooks, alle als Ziele
        {_s, wake} = wake_builtin(Enum.reverse(attvs), st.subst, st, :deferred)
        run(%{st | goals: again ++ hook_goals ++ wake ++ rest})

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  # M:G – G im Modul M ausführen (transparent für den Cut)
  defp step({:struct, ":", [m, g]}, cutb, _mod, rest, st) do
    case Store.walk(m, st.subst) do
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
    st = push(st, {:catch, id, c, r, rest, mod, Store.snapshot(st.subst), st.answer})
    run_body(g, h + 1, mod, [{{:"$catch_exit", id, h}, 0, mod} | rest], st)
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
    case Store.walk(b, st.subst) do
      {:var, _} -> throw_error(st, &PrologEx.Error.instantiation!/0)
      _ -> throw_ball(b, st)
    end
  end

  # time(G): wie call/1, meldet nach jeder Lösung und beim Fehlschlag die
  # Zeit, die G bisher tatsächlich gelaufen ist – summiert über alle
  # Abschnitte: die Uhr steht, solange G eine Lösung geliefert hat (etwa
  # während man im Toplevel überlegt, ob man ";" drückt), und läuft weiter,
  # wenn Backtracking wieder in G hineingeht. Die Summe liegt in
  # st.counters (Backtracking setzt sie nicht zurück): {Summe, Start | nil}.
  # Ein Choice Point direkt unter G meldet auch einen Fehlschlag. Hat G bei
  # Erfolg keine eigenen Choice Points hinterlassen, wird dieser
  # Melde-Choice-Point sofort entfernt – time(G) ist dann so
  # deterministisch wie G; sonst kommt über die Lösung ein Choice Point,
  # der die Uhr beim Wiedereintritt neu startet.
  # time/1: eingebaut, außer im Modul gibt es ein eigenes oder ein
  # importiertes (library(time) wie Scryer)
  defp step({:struct, "time", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  defp step({:"$time_exit", ref, h}, _cutb, _mod, rest, st) do
    time_exit(ref, h, rest, st)
  end

  # call_with_inference_limit(G, L, R) wie SWI und Scryer: höchstens L
  # Inferenzen je Lösung von G. R = ! (G deterministisch gelungen), true
  # (Choice Points offen) oder inference_limit_exceeded – dann wird G mit der
  # Ausnahme inference_limit_exceeded abgebrochen und hier gefangen.
  #
  # Der Rahmen ist ein Choice Point unter G (wie bei catch/3): Eintritt
  # aktiviert die Grenze (aktueller Zählerstand + L), der Ausgang setzt sie
  # aus; bleiben Choice Points, kommt darüber ein Wiedereintritts-Choice-
  # Point, der beim Backtracking in G eine frische Grenze setzt. Scheitert G
  # endgültig, nimmt der Rahmen-Choice-Point die Grenze weg.
  #
  # Verschachtelt gilt jede aktive Grenze: geprüft wird gegen die kleinste
  # (die strengere gewinnt). Fängt G die Ausnahme selbst (catch-all), wird
  # sie beim nächsten Schritt erneut geworfen – die Grenze bleibt in Kraft.
  defp step({:struct, "call_with_inference_limit", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  # '$call_with_timeout'(G, Us, Mode, OnTimeout) aus library(time):
  # Rahmen wie bei call_with_inference_limit/3, mit einer Deadline statt
  # einer Inferenzzahl. Mode: cumulative (Budget für alle Lösungen; die
  # Zeit außerhalb von G zählt nicht) oder per_answer (je Lösung neu).
  # OnTimeout: throw, fail oder ein Ziel.
  defp step({:struct, "$call_with_timeout", [g, us, mode, on]}, _cutb, mod, rest, st) do
    us = Store.walk(us, st.subst)
    {:atom, mode} = Store.walk(mode, st.subst)

    on =
      case Store.walk(on, st.subst) do
        {:atom, "throw"} -> :throw
        {:atom, "fail"} -> :fail
        {:struct, "call", [goal]} -> goal
      end

    id = make_ref()
    h = st.height
    st = add_tlimit(st, id, now_us() + us)
    st = push(st, {:tlimit, id, on, rest, mod, Store.snapshot(st.subst), st.answer})
    run_body(g, h + 1, mod, [{{:"$tlimit_exit", id, mode, us, h}, 0, mod} | rest], st)
  end

  # Ausgang: auch hier die Uhr – eine Lösung nach Ablauf der Frist zählt
  # nicht (sonst entkäme G, das die Ausnahme selbst fängt und ohne
  # gezählten Schritt endet)
  defp step({:"$tlimit_exit", id, mode, us, h}, _cutb, _mod, rest, st) do
    now = now_us()

    case List.keyfind(st.tlimits, id, 0) do
      {_, d} when d <= now -> throw_ball(@time_ball, check_soon(st))
      found -> tlimit_exit(found, now, id, mode, us, h, rest, st)
    end
  end

  # set_timer/1: ein Timer je Anfrage (ein neuer ersetzt ihn), bis zum Ende
  # der Anfrage oder cancel_timer/0; Backtracking nimmt ihn nicht zurück
  defp step({:struct, "$set_timer", [us]}, _cutb, _mod, rest, st) do
    Process.put(@timers_key, Map.put(timers(), st.qref, now_us() + Store.walk(us, st.subst)))
    run(%{check_soon(rearm(st)) | goals: rest})
  end

  defp step({:atom, "$cancel_timer"}, _cutb, _mod, rest, st) do
    drop_timer(st.qref)
    run(%{rearm(st) | goals: rest})
  end

  # '$sleep'(Ms): schlafen, aber höchstens bis zur nächsten Deadline –
  # dann time_limit_exceeded
  defp step({:struct, "$sleep", [ms]}, _cutb, _mod, rest, st) do
    sleep_step(now_us() + Store.walk(ms, st.subst) * 1000, rest, st)
  end

  defp step({:"$ilimit_exit", id, n, h, r}, _cutb, _mod, rest, st) do
    st = remove_ilimit(st, id)

    {st, res} =
      if st.height == h + 1,
        do: {%{st | cps: tl(st.cps), height: h}, "!"},
        else: {push(st, {:ilimit_reenter, id, n}), "true"}

    case unify(r, {:atom, res}, st.subst) do
      {:ok, s} -> cont(st, s, rest)
      :error -> backtrack(st)
    end
  end

  # call_with_depth_limit(G, L, R) wie SWI, mit unserer Zählung der Tiefe:
  # Nur Prädikate mit Klauseln aus Benutzermodulen bilden Ebenen; eingebaute
  # Prädikate und die Interna der Bibliotheken (auch in Prolog geschriebener)
  # sind durchsichtig, ebenso Steuerkonstrukte und call/N. Ein Ziel, das eine
  # Bibliothek zurückruft (maplist, findall, ...), liegt auf der Ebene ihres
  # Aufrufs. G selbst ist Ebene 1.
  #
  # Gelingt G, ist R die größte erreichte Ebene (mindestens 1). Aufrufe
  # jenseits von L scheitern (für Iterative Deepening); scheitert G am Ende
  # und wurde dabei irgendwo die Grenze überschritten, gelingt der Aufruf
  # einmal mit R = depth_limit_exceeded, sonst scheitert er.
  #
  # Die aktuelle Ebene steht in der Substitution (@depth_key): Choice
  # Points und catch/3 stellen sie so von selbst wieder her. Beim Betreten
  # einer Benutzerklausel (depth_enter/3) wird sie erhöht; nach dem Rumpf
  # setzt ein Ziel {:"$depth", Ebene} sie zurück – außer es folgt ohnehin
  # schon eines (Endrekursion: konstanter Speicher). Ohne aktive Grenze
  # wird nichts mitgeführt. Größte Ebene und "überschritten" stehen in
  # :atomics je Rahmen – sie überstehen Backtracking und Unter-Maschinen.
  defp step({:struct, "call_with_depth_limit", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  defp step({:"$dlimit_exit", {ref, _, _} = frame, h, r}, _cutb, _mod, rest, st) do
    st = remove_dlimit(st, frame)

    st =
      if st.height == h + 1,
        do: %{st | cps: tl(st.cps), height: h},
        else: push(st, {:dlimit_reenter, frame})

    case unify(r, :atomics.get(ref, 1), st.subst) do
      {:ok, s} -> cont(st, s, rest)
      :error -> backtrack(st)
    end
  end

  # Rumpf zu Ende: Ebene des Aufrufers wiederherstellen
  defp step({:"$depth", level}, _cutb, _mod, rest, st),
    do: run(%{st | goals: rest, subst: Store.put(st.subst, @depth_key, level)})

  # setup_call_cleanup(S, G, C) wie SWI und der WG17-Vorschlag (N215):
  #
  #   * S läuft wie once/1; scheitert oder wirft S, gibt es kein Cleanup.
  #   * Danach müssen G und C aufrufbar sein (sonst Fehler, bevor G läuft).
  #   * Ein Rahmen-Choice-Point {:scc, ...} unter G merkt sich C und die
  #     Bindungen nach S, dazu C für die jeweils aktuellen Bindungen (das
  #     letzte Feld; die Kompaktierung schreibt es mit um, siehe
  #     maybe_compact/1).
  #   * G deterministisch gelungen: C sofort, mit den aktuellen Bindungen,
  #     die bleiben; Scheitern von C zählt nicht, Ausnahmen gehen weiter.
  #   * G scheitert endgültig (Backtracking erreicht den Rahmen) oder wirft
  #     (die Ausnahme passiert den Rahmen): C mit den Bindungen nach S; beim
  #     Werfen gewinnt die ursprüngliche Ausnahme.
  #   * G hat Choice Points hinterlassen: C läuft, sobald ein Cut den Rahmen
  #     abschneidet (cut_to/3, auch once/1, ->, call_nth/2) oder eine
  #     Unter-Maschine mit ihm verworfen wird (\\+, discard/3) – mit den
  #     aktuellen Bindungen, innen vor außen.
  defp step({:struct, "setup_call_cleanup", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  defp step({:"$scc_setup", h, g, c}, _cutb, mod, rest, st) do
    # once(S): Alternativen von S abschneiden (Cleanups darin laufen zuerst)
    {st, pre} = cut_to(st, h, [])

    checked =
      guarded(fn ->
        gb = callable_goal!(g, st.subst)
        _ = callable_goal!(c, st.subst)
        gb
      end)

    case checked do
      {:ok, gb} ->
        st = push(%{st | scc: true}, {:scc, make_ref(), c, mod, st.subst, st.answer, c})
        goals = [{gb, h + 1, mod}, {{:"$scc_exit", h}, 0, mod} | rest]
        run(%{st | goals: pre ++ goals})

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  defp step({:"$scc_exit", h}, _cutb, _mod, rest, st) do
    if st.height == h + 1 do
      # G deterministisch: Rahmen weg, C jetzt
      [{:scc, _id, _c, cmod, _s, _a, c} | cps] = st.cps
      run(%{st | goals: [cleanup_goal(c, cmod, h) | rest], cps: cps, height: h})
    else
      run(%{st | goals: rest})
    end
  end

  # call_nth(G, N): zählt die Lösungen von G mit einem Zähler, den
  # Backtracking NICHT zurücksetzt (st.counters). Ist N eine Zahl, wird bei
  # der N-ten Lösung abgeschnitten (deterministisch). Ein Choice Point unter G
  # räumt den Zähler auf, wenn G erschöpft ist; hinterlässt G bei Erfolg
  # keine Choice Points, wird er gleich entfernt (wie bei time/1).
  defp step({:struct, "call_nth", _} = goal, cutb, mod, rest, st),
    do: homed_step(goal, cutb, mod, rest, st)

  defp step({:"$nth", ref, n, h}, _cutb, _mod, rest, st), do: nth_exit(ref, n, h, rest, st)

  # Benutzerprädikate zuerst; nur bei Fehltreffer die Builtin-Tabelle
  defp step(goal, _cutb, mod, rest, st), do: call_pred(goal, mod, rest, st)

  # Steuerkonstrukte, die nur nach dem Import ihrer Bibliothek sichtbar sind
  # (PrologEx.Builtins.home/2: iso_ext, swi, ...): die Klausel von step/5
  # fragt die Sichtbarkeit, die Ausführung steht hier. Ein eigenes oder
  # anders importiertes Prädikat gleichen Namens geht vor; unsichtbar:
  # gewöhnlicher Aufruf (also existence_error).
  defp disjunction(g1, g2, cutb, mod, rest, st) do
    st = push(st, {:alt, {g2, cutb, mod}, rest, Store.snapshot(st.subst), st.answer})
    run(%{st | goals: [{g1, cutb, mod} | rest]})
  end

  # Builtins mit Heimat-Bibliothek (between/3 usw.): aus system importiert
  # oder ohne Import sichtbar, sonst wie üblich locate/4 (mod definiert es
  # hier nicht selbst: das prüft call_pred/4 vorher)
  defp homed_located(entry, db, mod, name, arity) do
    if engine_visible?(db, name, arity, mod),
      do: {:builtin, "system", entry},
      else: locate(db, mod, name, arity)
  end

  defp homed_step({:struct, name, args} = goal, cutb, mod, rest, st) do
    if engine_visible?(name, length(args), mod),
      do: engine_step(goal, cutb, mod, rest, st),
      else: call_pred(goal, mod, rest, st)
  end

  defp engine_visible?(name, arity, mod), do: engine_visible?(current_db(), name, arity, mod)

  # Nicht geschütztes system-Builtin, das die Maschine selbst ausführt:
  # sichtbar, wenn mod es aus system importiert hat, oder wenn mod es weder
  # selbst definiert (in der Datenbank oder als Bibliotheks-Builtin, etwa
  # files:delete_file/1) noch – bei einem mit Heimat-Bibliothek – die
  # Heimat verbirgt (ein Import schließt eine eigene Definition aus: Laden
  # und assert entfernen ihn). Ohne Heimat (once/1): sonst immer sichtbar
  defp engine_visible?(db, name, arity, mod) do
    case Map.fetch(db, {:import, mod, name, arity}) do
      {:ok, src} ->
        src == "system"

      :error ->
        not Map.has_key?(db, {mod, name, arity}) and
          (PrologEx.Builtins.home(name, arity) == nil or home_visible?(mod)) and
          PrologEx.Builtins.lookup(mod, name, arity) == nil
    end
  end

  def home_visible?(mod),
    do: PrologEx.Builtins.system_module?(mod) or PrologEx.Flags.get("swi_compat") == a("true")

  defp engine_step({:struct, "call_nth", [g, n]}, cutb, mod, rest, st) do
    case Store.walk(n, st.subst) do
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

  defp engine_step({:struct, "findnsols", [n, t, g, l]}, cutb, mod, rest, st),
    do: step({:struct, "findnsols", [n, t, g, l, []]}, cutb, mod, rest, st)

  defp engine_step({:struct, "findnsols", [n, t, g, l, tail]}, _cutb, mod, rest, st) do
    chunk =
      guarded(fn ->
        k =
          case Store.walk(n, st.subst) do
            k when is_integer(k) and k >= 1 -> k
            k when is_integer(k) -> PrologEx.Error.domain!("not_less_than_one", k)
            {:var, _} -> PrologEx.Error.instantiation!()
            other -> PrologEx.Error.type!("integer", other)
          end

        {k, collect(run(sub_machine(t, body!(g, st.subst), mod, st)), k, [])}
      end)

    case chunk do
      {:ok, {k, collected}} -> findnsols_chunk(collected, k, l, tail, rest, resync(st))
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp engine_step({:struct, "countall", [g, n]}, _cutb, mod, rest, st) do
    counted =
      guarded(fn ->
        case Store.walk(n, st.subst) do
          x when is_integer(x) or (is_tuple(x) and elem(x, 0) == :var) -> :ok
          x -> PrologEx.Error.type!("integer", x)
        end

        count(run(sub_machine([], body!(g, st.subst), mod, st)), 0)
      end)

    case counted do
      {:ok, k} ->
        case unify(n, k, st.subst) do
          {:ok, s} -> cont(resync(st), s, rest)
          :error -> backtrack(st)
        end

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  # plus/3 (library(swi)) ohne den allgemeinen Aufrufpfad eines Builtins
  defp engine_step({:struct, "plus", [x, y, z]}, _cutb, mod, rest, st) do
    try do
      PrologEx.Builtins.Terms.plus(x, y, z, st.subst)
    rescue
      e in PrologEx.Error -> throw_ball(e.term, st)
    else
      r -> apply_result(r, mod, rest, st)
    end
  end

  defp engine_step({:struct, "not", [g]}, cutb, mod, rest, st),
    do: step({:struct, "\\+", [g]}, cutb, mod, rest, st)

  # once(G): call(G), dann alles ab der jetzigen Höhe abschneiden – kein
  # Choice Point für ein Sonst, kein Dann-Ziel (zählt wie die alte Klausel:
  # once und G)
  defp engine_step({:struct, "once", [g]}, _cutb, mod, rest, st) do
    h = st.height
    run(%{st | goals: [{{:struct, "call", [g]}, h, mod}, {{:"$cut_to", h}, 0, mod} | rest]})
  end

  defp engine_step({:struct, "ignore", [g]}, cutb, mod, rest, st),
    do:
      if_then_else({:struct, "call", [g]}, {:atom, "true"}, {:atom, "true"}, cutb, mod, rest, st)

  defp engine_step({:struct, "time", [g]}, _cutb, mod, rest, st),
    do: builtin_time(g, mod, rest, st)

  defp engine_step({:struct, "*->", [c, t]}, cutb, mod, rest, st),
    do: run(%{st | goals: [{c, st.height, mod}, {t, cutb, mod} | rest]})

  defp engine_step({:struct, "call_with_inference_limit", [g, l, r]}, _cutb, mod, rest, st) do
    case Store.walk(l, st.subst) do
      {:var, _} ->
        throw_error(st, &PrologEx.Error.instantiation!/0)

      n when is_integer(n) and n >= 0 ->
        id = make_ref()
        h = st.height
        st = add_ilimit(st, id, :counters.get(st.icount, 1) + n)
        st = push(st, {:ilimit, id, r, rest, mod, Store.snapshot(st.subst), st.answer})
        run_body(g, h + 1, mod, [{{:"$ilimit_exit", id, n, h, r}, 0, mod} | rest], st)

      n when is_integer(n) ->
        throw_error(st, fn -> PrologEx.Error.domain!("not_less_than_zero", n) end)

      other ->
        throw_error(st, fn -> PrologEx.Error.type!("integer", other) end)
    end
  end

  defp engine_step({:struct, "call_with_depth_limit", [g, l, r]}, _cutb, mod, rest, st) do
    case Store.walk(l, st.subst) do
      {:var, _} ->
        throw_error(st, &PrologEx.Error.instantiation!/0)

      n when is_integer(n) and n >= 0 ->
        ref = :atomics.new(2, signed: true)
        if n >= 1, do: :atomics.put(ref, 1, 1)
        base = Store.get(st.subst, @depth_key, 0)
        frame = {ref, base, base + n - 1}
        h = st.height
        st = add_dlimit(%{st | subst: Store.put(st.subst, @depth_key, base)}, frame)
        st = push(st, {:dlimit, frame, r, rest, mod, Store.snapshot(st.subst), st.answer})
        run_body(g, h + 1, mod, [{{:"$dlimit_exit", frame, h, r}, 0, mod} | rest], st)

      n when is_integer(n) ->
        throw_error(st, fn -> PrologEx.Error.domain!("not_less_than_zero", n) end)

      other ->
        throw_error(st, fn -> PrologEx.Error.type!("integer", other) end)
    end
  end

  defp engine_step({:struct, "setup_call_cleanup", [s, g, c]}, _cutb, mod, rest, st) do
    case guarded(fn -> callable_goal!(s, st.subst) end) do
      {:ok, sb} ->
        h = st.height
        run(%{st | goals: [{sb, h, mod}, {{:"$scc_setup", h, g, c}, 0, mod} | rest]})

      {:thrown, ball} ->
        throw_ball(ball, st)
    end
  end

  defp engine_step(goal, _cutb, mod, rest, st), do: call_pred(goal, mod, rest, st)

  # das eingebaute time/1 (step/5 für time/1 entscheidet, ob es gilt)
  defp builtin_time(g, mod, rest, st) do
    ref = make_ref()
    h = st.height
    st = %{st | counters: Map.put(st.counters, ref, {0, now_us()})}
    st = push(st, {:time_fail, ref, Store.snapshot(st.subst), st.answer})
    run_body(g, h + 1, mod, [{{:"$time_exit", ref, h}, 0, mod} | rest], st)
  end

  defp time_exit(ref, h, rest, st) do
    total = time_stop(st, ref)
    report_time(total)

    if st.height == h + 1,
      do:
        run(%{
          st
          | goals: rest,
            cps: tl(st.cps),
            height: h,
            counters: Map.delete(st.counters, ref)
        }),
      else:
        run(
          push(
            %{st | goals: rest, counters: Map.put(st.counters, ref, {total, nil})},
            {:time_reenter, ref}
          )
        )
  end

  defp call_nth(g, n, _cutb, mod, rest, st) do
    ref = make_ref()
    h = st.height
    st = %{st | counters: Map.put(st.counters, ref, 0)}
    st = push(st, {:nth_cleanup, ref, Store.snapshot(st.subst), st.answer})
    run_body(g, h + 1, mod, [{{:"$nth", ref, n, h}, 0, mod} | rest], st)
  end

  defp nth_exit(ref, n, h, rest, st) do
    c = Map.fetch!(st.counters, ref) + 1
    st = %{st | counters: Map.put(st.counters, ref, c)}

    case Store.walk(n, st.subst) do
      k when is_integer(k) and c < k ->
        backtrack(st)

      k when is_integer(k) ->
        # N-te Lösung: alles ab G abschneiden, Zähler entfernen
        {st, rest} = cut_to(st, h, rest)
        run(%{st | goals: rest, counters: Map.delete(st.counters, ref)})

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
        pred = flat_for_call(pred, {mod, name, arity}, args, st.subst)

        case depth_enter(st, rest, mod) do
          {st, rest} -> try_clauses(goal, args, candidates(pred, args, st.subst), rest, mod, st)
          :fail -> backtrack(st)
        end

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
          case PrologEx.Builtins.fast_entry(name, arity) do
            {:protected, entry} -> {:builtin, "system", entry}
            {:homed, entry} -> homed_located(entry, db, mod, name, arity)
            nil -> locate(db, mod, name, arity)
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

        pred = flat_for_call(pred, {m, name, arity}, args, st.subst)

        args = qualify(args, Map.get(current_db(), {:meta, m, name, arity}), m, mod, st.subst)

        case depth_enter(st, rest, m) do
          {st, rest} -> try_clauses(goal, args, candidates(pred, args, st.subst), rest, m, st)
          :fail -> backtrack(st)
        end

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
    case Store.walk(t, subst) do
      {tag, ":", [_, _]} when tag in [:struct, :gstruct] -> true
      _ -> false
    end
  end

  defp ctx(st, mod), do: %{subst: st.subst, db: current_db(), module: mod}

  # Nach einer erfolgreichen Unifikation weitermachen. Wurden dabei
  # attributierte Variablen gebunden (:wake), laufen deren Weckziele vor
  # dem Rest (wie SICStus: am nächsten Aufruf-Port). Ohne Module mit
  # verify_attributes/3 verarbeitet die Maschine die eingebauten
  # Suspensionen gleich hier; sonst über das Ziel $wake (Hooks, $attv_redo).
  defp cont(st, s, goals) do
    case Store.take_wake(s) do
      {ws, s} -> woken(ws, s, goals, st)
      :none -> run(%{st | goals: goals, subst: s})
    end
  end

  # ws: die gebundenen attributierten Variablen (neueste vorn), s ohne Vermerk
  defp woken(ws, s, goals, st) do
    attvs = Enum.reverse(ws)

    case verify_modules(current_db()) do
      [] -> wake_and_run(attvs, s, st, goals)
      _ -> run(%{st | subst: s, goals: [{{:"$wake", attvs}, 0, "system"} | goals]})
    end
  end

  # (für Stellen, die das Wecken als Ziel brauchen, siehe call_nth/2)
  defp after_unify(s, goals) do
    case Store.take_wake(s) do
      {ws, s} -> {s, [{{:"$wake", Enum.reverse(ws)}, 0, "system"} | goals]}
      :none -> {s, goals}
    end
  end

  defp wake_and_run(attvs, s, st, rest) do
    case wake_builtin(attvs, s, st, :immediate) do
      :fail -> backtrack(st)
      {s, goals} -> run(%{st | subst: s, goals: goals ++ rest})
    end
  end

  # Goals-Liste eines Hooks (Restlisten können gebundene Variablen sein)
  defp goal_list(l, subst) do
    case uncons(Store.walk(l, subst)) do
      :empty -> []
      {:cons, h, t} -> [h | goal_list(t, subst)]
      :other -> PrologEx.Error.type!("list", resolve(l, subst))
    end
  end

  # Attributmodule mit verify_attributes/3, in Deklarationsreihenfolge
  @doc false
  def verify_modules(db) do
    for m <- Map.get(db, :attr_modules, []),
        Map.has_key?(db, {m, "verify_attributes", 3}),
        do: m
  end

  # Eingebaute Suspensionen (freeze, dif, when, Ausschlussmengen) der eben
  # gebundenen attributierten Variablen attvs (in Bindereihenfolge)
  # verarbeiten; je Variable zuerst die Ausschlussmenge, dann die
  # Suspensionen in der Reihenfolge des Anhängens. Solange noch kein Ziel
  # ansteht, wird direkt geprüft und neu aufgehängt (ein Scheitern bricht
  # sofort ab). Ab dem ersten Ziel, das laufen muss, wird alles Weitere zu
  # Zielen hinter ihm – so bleibt die Reihenfolge gegenüber diesem Ziel
  # erhalten (aufeinanderfolgende dif-Prüfungen als ein Ziel $difs). Im
  # Modus :deferred (nach den Hooks von verify_attributes/3) von Anfang an
  # nur Ziele. Ergebnis: :fail oder {Substitution, Ziele}.
  defp wake_builtin(attvs, s, st, mode) do
    acc = {s, [], mode == :deferred}

    case Enum.reduce_while(attvs, acc, &wake_var(&1, &2, st)) do
      :fail -> :fail
      {s, items, _} -> {s, wake_items(Enum.reverse(items), [], st.height)}
    end
  end

  # acc = {Substitution, Einträge (umgekehrt), schon ein Ziel?}; Einträge
  # {:goal, ziel, cutb, modul} oder {:dif, suspension}
  defp wake_var({:var, {:attv, id}} = v, {s, _, _} = acc, st) do
    attrs = Store.attrs(s, id)

    acc =
      case attrs do
        %{"$difset" => data} -> wake_difset(v, data, acc)
        _ -> acc
      end

    case acc do
      :fail -> {:halt, :fail}
      acc -> wake_susps(susp_items(attrs), v, acc, st)
    end
  end

  defp wake_difset(v, data, {s, items, false}) do
    case PrologEx.Builtins.Coroutining.check_excluded(v, data, s) do
      {:ok, s} -> {s, items, false}
      :fail -> :fail
    end
  end

  defp wake_difset(v, data, {s, items, true}),
    do: {s, [{:goal, mk("$difset_check", [v, data]), 0, "system"} | items], true}

  defp wake_susps([], _v, acc, _st), do: {:cont, acc}

  defp wake_susps([susp | more], v, acc, st) do
    case wake_susp(unmark_top(susp), susp, v, acc, st) do
      :fail -> {:halt, :fail}
      acc -> wake_susps(more, v, acc, st)
    end
  end

  # freeze: V an eine Variable gebunden – der Eintrag wandert mit; sonst
  # läuft das Ziel
  defp wake_susp({:struct, "$fz", [g]}, susp, v, {s, items, false}, st) do
    case Store.walk(v, s) do
      {:var, _} = w -> {suspend(s, [w], susp), items, false}
      _ -> {s, [goal_item(g, s, st.height) | items], true}
    end
  end

  defp wake_susp({:struct, "$fz", [g]}, _susp, v, {s, items, true}, st),
    do: {s, [{:goal, mk("$wake_fz", [v, g]), st.height, "system"} | items], true}

  defp wake_susp({:struct, "$wh", _}, susp, _v, {s, items, false}, st) do
    case wake_when(susp, s) do
      :done -> {s, items, false}
      {:ok, s} -> {s, items, false}
      {:call, g, s} -> {s, [goal_item(g, s, st.height) | items], true}
    end
  end

  defp wake_susp({:struct, "$wh", _}, susp, _v, {s, items, true}, st) do
    if PrologEx.Builtins.Coroutining.active?(susp, s),
      do: {s, [{:goal, mk("$wake_wh", [susp]), st.height, "system"} | items], true},
      else: {s, items, true}
  end

  defp wake_susp({:struct, "$df", _}, susp, _v, {s, items, false}, _st) do
    case wake_dif(susp, s) do
      {:ok, s} -> {s, items, false}
      :fail -> :fail
    end
  end

  defp wake_susp({:struct, "$df", _}, susp, _v, {s, items, true}, _st) do
    if PrologEx.Builtins.Coroutining.active?(susp, s),
      do: {s, [{:dif, susp} | items], true},
      else: {s, items, true}
  end

  # Weckziel M:G direkt als Ziel in M (wie der Schritt für ':'), Cut lokal
  defp goal_item(g, s, height) do
    with {tag, ":", [m, inner]} when tag in [:struct, :gstruct] <- Store.walk(g, s),
         {:atom, name} <- Store.walk(m, s) do
      {:goal, inner, height, name}
    else
      _ -> {:goal, g, height, "system"}
    end
  end

  # Einträge zu Zielen; aufeinanderfolgende dif-Einträge als ein $difs
  defp wake_items([], acc, _height), do: Enum.reverse(acc)

  defp wake_items([{:dif, _} | _] = items, acc, height) do
    {difs, rest} = Enum.split_while(items, &match?({:dif, _}, &1))
    goal = {mk("$difs", [list(Enum.map(difs, &elem(&1, 1)))]), 0, "system"}
    wake_items(rest, [goal | acc], height)
  end

  defp wake_items([{:goal, g, cutb, mod} | rest], acc, height),
    do: wake_items(rest, [{g, cutb, mod} | acc], height)

  # when-Suspension neu stellen: :done (Done schon gebunden), {:ok, s}
  # (wartet weiter) oder {:call, Ziel, s}
  defp wake_when(susp, s) do
    case unmark_top(Store.walk(susp, s)) do
      {:struct, "$wh", [c, g]} ->
        wake_when_(c, g, s)

      {:struct, "$wh", [d, c, g]} ->
        case Store.walk(d, s) do
          {:var, _} = dv -> wake_when_(c, g, Store.put_binding(s, dv, {:atom, "true"}))
          _ -> :done
        end
    end
  end

  defp wake_when_(c, g, s) do
    case PrologEx.Builtins.Coroutining.when_(c, g, s) do
      {:call, goal} -> {:call, goal, s}
      {:ok, s} -> {:ok, s}
    end
  end

  # dif-Suspension neu stellen (Done binden): {:ok, s} oder :fail
  defp wake_dif(susp, s) do
    case unmark_top(Store.walk(susp, s)) do
      {:struct, "$df", [l, r]} ->
        PrologEx.Builtins.Coroutining.dif(l, r, s)

      {:struct, "$df", [d, l, r]} ->
        case Store.walk(d, s) do
          {:var, _} = dv ->
            PrologEx.Builtins.Coroutining.dif(l, r, Store.put_binding(s, dv, {:atom, "true"}))

          _ ->
            {:ok, s}
        end
    end
  end

  # Ergebnis eines Builtins (siehe PrologEx.Builtin) umsetzen
  defp apply_result(result, mod, rest, st) do
    case result do
      r when r in [:ok, true] ->
        run(%{st | goals: rest})

      r when r in [:fail, false] ->
        backtrack(st)

      # (werfen kann die Unifikation nur mit occurs_check=error)
      {:unify, pairs} ->
        mode = occurs_mode()

        if mode == :error do
          case guarded(fn -> unify_pairs(pairs, st.subst, mode) end) do
            {:ok, {:ok, s}} -> cont(st, s, rest)
            {:ok, :error} -> backtrack(st)
            {:thrown, ball} -> throw_ball(ball, st)
          end
        else
          case unify_pairs(pairs, st.subst, mode) do
            {:ok, s} -> cont(st, s, rest)
            :error -> backtrack(st)
          end
        end

      {:call, goal} ->
        run(%{st | goals: [{goal, st.height, mod} | rest]})

      # neue Substitution, dann weiter mit einem Ziel (z. B. Lambda:
      # Parameter gebunden, jetzt der Rumpf)
      {:call, goal, s} ->
        cont(st, s, [{goal, st.height, mod} | rest])

      # neue Substitution (z. B. Attribute gesetzt: freeze, dif, when)
      {:subst, s} ->
        cont(st, s, rest)

      other ->
        raise "Builtin lieferte ungültiges Ergebnis: #{inspect(other)}"
    end
  end

  defp unify_pairs([], s, _mode), do: {:ok, s}

  defp unify_pairs([{x, y} | more], s, mode) do
    case unify(x, y, s, mode) do
      {:ok, s} -> unify_pairs(more, s, mode)
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
    st = push(st, {:solutions_list, more, mod, rest, Store.snapshot(st.subst), st.answer})
    apply_result(r, mod, rest, st)
  end

  defp start_solutions(enum, mod, rest, st) do
    case guarded(fn -> Enumerable.reduce(enum, {:cont, nil}, fn x, _ -> {:suspend, x} end) end) do
      {:ok, r} -> next_solution(r, mod, rest, st)
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  defp next_solution({:suspended, r, cont}, mod, rest, st) do
    st = push(st, {:solutions, cont, mod, rest, Store.snapshot(st.subst), st.answer})
    apply_result(r, mod, rest, st)
  end

  defp next_solution(_done_or_halted, _mod, _rest, st), do: backtrack(st)

  # Choice Points bis zur Höhe h abschneiden. Waren darunter Rahmen von
  # setup_call_cleanup/3, kommen ihre Cleanups vor die übrigen Ziele
  # (innen vor außen), als (call(C) -> true ; true).
  defp cut_to(%{scc: false} = st, h, rest),
    do: {%{st | cps: Enum.drop(st.cps, st.height - h), height: h}, rest}

  defp cut_to(st, h, rest) do
    {dropped, cps} = Enum.split(st.cps, st.height - h)
    {%{st | cps: cps, height: h}, cleanups(dropped, h) ++ rest}
  end

  defp cleanups(cps, h) do
    Enum.flat_map(cps, fn
      {:scc, _id, _c, mod, _s, _a, c} -> [cleanup_goal(c, mod, h)]
      # eine aufbewahrte Unter-Maschine (findnsols) mit eigenen Rahmen
      {:findnsols, %{scc: true, cps: sub}, _, _, _, _, _, _} -> cleanups(sub, h)
      _ -> []
    end)
  end

  defp cleanup_goal(c, mod, h),
    do: {mk(";", [mk("->", [mk("call", [c]), a("true")]), a("true")]), h, mod}

  # eine Unter-Maschine wird mit offenen Choice Points verworfen (\\+ nach
  # einer Lösung): ihre Cleanups laufen dort (Bindungen zählen nicht mehr),
  # Ausnahmen daraus gehen weiter; dann k.(st)
  defp discard(%{scc: false}, st, k), do: k.(st)

  defp discard(sub, st, k) do
    case cleanups(sub.cps, 0) do
      [] ->
        k.(st)

      goals ->
        case guarded(fn -> run(%{sub | goals: goals, cps: [], height: 0, answer: []}) end) do
          {:thrown, ball} -> throw_ball(ball, st)
          _ -> k.(st)
        end
    end
  end

  # Cleanup eines verlassenen Rahmens in einer Unter-Maschine mit den
  # Bindungen nach dem Setup: {:ok, _} | {:thrown, ball}
  # Ohne Inferenzgrenzen: beim Abwickeln einer Überschreitung wäre die
  # Grenze sonst schon überschritten und bräche auch das Cleanup ab.
  defp run_cleanup({:scc, _id, c, mod, subst, _answer, _cur}, st) do
    sub = %{
      st
      | goals: [cleanup_goal(c, mod, 0)],
        cps: [],
        height: 0,
        answer: [],
        subst: Store.restore(subst),
        ilimits: [],
        ilimit: nil
    }

    guarded(fn -> run(sub) end)
  end

  # Ziel prüfen wie call/1 (Variable: instantiation_error, sonst
  # Rumpfumwandlung mit type_error(callable, _))
  defp callable_goal!(t, subst) do
    case Store.walk(t, subst) do
      {:var, _} -> PrologEx.Error.instantiation!()
      g -> to_body(unmark_top(g), g, subst)
    end
  end

  defp add_dlimit(st, frame) do
    ls = [frame | st.dlimits]
    %{st | dlimits: ls, dlimit: min_dlimit(ls)}
  end

  defp remove_dlimit(%{dlimits: []} = st, _frame), do: st

  defp remove_dlimit(st, frame) do
    ls = List.delete(st.dlimits, frame)
    %{st | dlimits: ls, dlimit: min_dlimit(ls)}
  end

  defp min_dlimit([]), do: nil
  defp min_dlimit(ls), do: ls |> Enum.map(&elem(&1, 2)) |> Enum.min()

  # Aufruf eines Prädikats mit Klauseln aus Modul m: bei aktiver
  # Tiefengrenze Ebene prüfen und für den Rumpf erhöhen
  defp depth_enter(%{dlimit: nil} = st, rest, _m), do: {st, rest}

  defp depth_enter(st, rest, m) do
    if PrologEx.Builtins.system_module?(m) do
      {st, rest}
    else
      level = Store.get(st.subst, @depth_key, 0)

      if level > st.dlimit do
        for {ref, _base, max} <- st.dlimits, level > max, do: :atomics.put(ref, 2, 1)
        :fail
      else
        for {ref, base, _max} <- st.dlimits do
          rel = level - base + 1
          if rel > :atomics.get(ref, 1), do: :atomics.put(ref, 1, rel)
        end

        rest =
          case rest do
            [{{:"$depth", _}, _, _} | _] -> rest
            _ -> [{{:"$depth", level}, 0, "system"} | rest]
          end

        {%{st | subst: Store.put(st.subst, @depth_key, level + 1)}, rest}
      end
    end
  end

  # Variable oder (Teil-)Liste, sonst type_error(list, L)
  defp partial_list!(l, subst) do
    case PrologEx.Builtins.Lists.skip_list(l, subst) do
      {_, []} -> :ok
      {_, {:var, _}} -> :ok
      _ -> PrologEx.Error.type!("list", resolve(l, subst))
    end
  end

  # Rumpfumwandlung für call/N (ISO 7.6.2); whole: das ganze Ziel (für
  # den Fehlerterm)
  @doc """
  Prüft einen Klauselrumpf (assert/1, ISO 8.9.1.3): lässt er sich nicht in
  ein Ziel umwandeln, type_error(callable, Rumpf).
  """
  def check_body!(b, subst) do
    _ = to_body(b, b, subst)
    :ok
  end

  defp to_body(g, whole, subst) do
    case unmark_top(Store.walk(g, subst)) do
      {:var, _} = v ->
        {:struct, "call", [v]}

      {:struct, op, [a, b]} when op in [",", ";", "->", "*->"] ->
        {:struct, op, [to_body(a, whole, subst), to_body(b, whole, subst)]}

      # M:Rumpf: der Rumpf ebenso (mit offenem M entscheidet der Aufruf)
      {:struct, ":", [m, inner]} = t ->
        case Store.walk(m, subst) do
          {:atom, _} = ma -> {:struct, ":", [ma, to_body(inner, whole, subst)]}
          _ -> t
        end

      {:atom, _} = t ->
        t

      {:struct, _, _} = t ->
        t

      # [] ist in ISO ein Atom, Listen sind Strukturen: wie bisher weiter
      t when is_list(t) ->
        t

      {:glist, _} = t ->
        t

      _ ->
        PrologEx.Error.type!("callable", resolve(whole, subst))
    end
  end

  # call/N, allgemeiner Weg: Steuerkonstrukte, M:G, Variable, Fehler
  # Ziel von call(G, Extra...) für den Schnellweg: {Ziel, Modul} für ein
  # Atom oder eine Struktur ohne Steuer-Funktor, auch als M:G mit Atom M;
  # sonst {:general, G} (Steuerkonstrukte, Variablen, Fehler)
  defp call_target(g, extra, mod, subst) do
    case unmark_top(Store.walk(g, subst)) do
      {:atom, f} = a when f not in @body_ops ->
        {if(extra == [], do: a, else: mk(f, extra)), mod}

      {:struct, f, args} = t when f not in @body_ops ->
        {if(extra == [], do: t, else: mk(f, args ++ extra)), mod}

      # M:G mit Atom M (so kommen Meta-Argumente an: maplist, foldl, ...):
      # G direkt in M
      {:struct, ":", [m, inner]} = t ->
        with {:atom, mn} <- Store.walk(m, subst),
             goal when goal != nil <- plain_goal(unmark_top(Store.walk(inner, subst)), extra) do
          {goal, mn}
        else
          _ -> {:general, t}
        end

      t ->
        {:general, t}
    end
  end

  defp foldl_var(st) do
    st = if st.next_var + 1 > st.var_end, do: new_block(st, 1), else: st
    {{:var, st.next_var}, %{st | next_var: st.next_var + 1}}
  end

  # call(G, Extra...) über den Schnellweg von call/N, dahinter das Folgeziel
  defp foldl_call(g, extra, next, cutb, mod, rest, st) do
    next = {next, cutb, mod}

    case call_target_open(g, extra, mod, st.subst) do
      {call, m} -> run(%{st | goals: [{call, st.height, m}, next | rest]})
      :general -> run(%{st | goals: [{mk("call", [g | extra]), cutb, mod}, next | rest]})
    end
  end

  defp foldl_done(v0, v, rest, st) do
    case unify(v0, v, st.subst) do
      {:ok, s} -> cont(st, s, rest)
      :error -> backtrack(st)
    end
  end

  # wie call_target/4, aber extra enthält eine frische Variable: das Ziel
  # ist nie ground, also ohne Ground-Prüfung gebaut
  defp call_target_open(g, extra, mod, subst) do
    case unmark_top(Store.walk(g, subst)) do
      {:atom, f} when f not in @body_ops ->
        {{:struct, f, extra}, mod}

      {:struct, f, args} when f not in @body_ops ->
        {{:struct, f, args ++ extra}, mod}

      {:struct, ":", [m, inner]} ->
        with {:atom, mn} <- Store.walk(m, subst),
             goal when goal != nil <- open_goal(unmark_top(Store.walk(inner, subst)), extra) do
          {goal, mn}
        else
          _ -> :general
        end

      _ ->
        :general
    end
  end

  defp open_goal({:atom, f}, extra) when f not in @body_ops, do: {:struct, f, extra}

  defp open_goal({:struct, f, args}, extra) when f not in @body_ops,
    do: {:struct, f, args ++ extra}

  defp open_goal(_, _), do: nil

  defp plain_goal({:atom, f} = a, extra) when f not in @body_ops,
    do: if(extra == [], do: a, else: mk(f, extra))

  defp plain_goal({:struct, f, args} = t, extra) when f not in @body_ops,
    do: if(extra == [], do: t, else: mk(f, args ++ extra))

  defp plain_goal(_, _), do: nil

  defp bb_visible?("blackboard", _name), do: true

  defp bb_visible?(mod, name) do
    db = current_db()
    Map.get(db, {:import, mod, name, 2}) == "blackboard" and not Map.has_key?(db, {mod, name, 2})
  end

  defp order_step(true, rest, st), do: run(%{st | goals: rest})
  defp order_step(false, _rest, st), do: backtrack(st)

  defp order_atom(:lt), do: {:atom, "<"}
  defp order_atom(:eq), do: {:atom, "="}
  defp order_atom(:gt), do: {:atom, ">"}

  defp call_general(g, extra, mod, rest, st) do
    case guarded(fn ->
           # g ist schon dereferenziert: oben eine Variable → instantiation_error
           # (nur innen wird sie call(V))
           case add_args(g, extra, st.subst) do
             {:var, _} -> PrologEx.Error.instantiation!()
             goal -> to_body(goal, goal, st.subst)
           end
         end) do
      {:ok, goal} -> run(%{st | goals: [{goal, st.height, mod} | rest]})
      {:thrown, ball} -> throw_ball(ball, st)
    end
  end

  # Ziel aus Daten als Rumpf (wie call/1, ISO 7.6.2): oben eine Variable →
  # instantiation_error; beim Aufruf ungebundene Variablen innen → call(V)
  # (Cut darin lokal); nicht aufrufbar → type_error(callable). Für \+,
  # findall/3 & Co., catch/3, ... – ohne eigenen call-Schritt
  defp body!(g, subst) do
    case unmark_top(Store.walk(g, subst)) do
      {:var, _} -> PrologEx.Error.instantiation!()
      goal -> to_body(goal, goal, subst)
    end
  end

  # body!/2 und dann ausführen; ein Fehler der Umwandlung entsteht im schon
  # angelegten Rahmen (catch/3 fängt ihn selbst, wie einen beim Ausführen)
  defp run_body(g, barrier, mod, tail, st) do
    try do
      body!(g, st.subst)
    rescue
      e in PrologEx.Error -> throw_ball(e.term, st)
    else
      goal -> run(%{st | goals: [{goal, barrier, mod} | tail]})
    end
  end

  defp add_ilimit(st, id, limit), do: rearm(%{st | ilimits: [{id, limit} | st.ilimits]})

  defp remove_ilimit(%{ilimits: []} = st, _id), do: st
  defp remove_ilimit(st, id), do: rearm(%{st | ilimits: List.keydelete(st.ilimits, id, 0)})

  defp min_ilimit([]), do: nil
  defp min_ilimit(ls), do: ls |> Enum.map(&elem(&1, 1)) |> Enum.min()

  # ---------------------------------------------------------------------
  # Zeitgrenzen (library(time): call_with_timeout/2,3, set_timer/1)
  #
  # Die Maschine liest die Uhr nicht bei jedem Schritt: st.ilimit ist der
  # Zählerstand, ab dem run_step/1 in limit_hit/5 schaut – das Minimum der
  # echten Inferenzgrenzen und, solange eine Zeitgrenze aktiv ist, des
  # nächsten Prüfpunkts (alle @tcheck Inferenzen). Ohne Grenzen bleibt
  # st.ilimit nil, der Schritt kostet also nichts zusätzlich. Der
  # Prüfpunkt ist nur ein Hinweis: Entscheidend ist immer die Uhr, ein zu
  # früher Prüfpunkt kostet nur einen Blick auf sie.

  defp rearm(st) do
    timed = if st.tlimits != [] or timer_set?(st), do: :counters.get(st.icount, 1) + @tcheck

    %{st | ilimit: min_limit(min_ilimit(st.ilimits), timed)}
  end

  # beim nächsten gezählten Schritt prüfen
  defp check_soon(st), do: %{st | ilimit: min_limit(st.ilimit, :counters.get(st.icount, 1))}

  defp min_limit(nil, b), do: b
  defp min_limit(a, nil), do: a
  defp min_limit(a, b), do: min(a, b)

  defp timers, do: Process.get(@timers_key, %{})
  defp timer_set?(st), do: Map.has_key?(timers(), st.qref)

  # nach einer Unter-Maschine (findall, \+, ...): hat sie set_timer/1
  # gerufen, muss auch diese Maschine wieder prüfen
  defp resync(st) do
    case Process.get(@timers_key) do
      nil -> st
      m when map_size(m) == 0 -> st
      _ -> rearm(st)
    end
  end

  # Prüfpunkt erreicht: echte Inferenzgrenze überschritten, abgelaufene
  # Zeitgrenze oder weiter (mit neuem Prüfpunkt)
  defp limit_hit(goal, cutb, mod, rest, st) do
    n = :counters.get(st.icount, 1)

    if Enum.any?(st.ilimits, fn {_, l} -> n > l end) do
      throw_ball({:atom, "inference_limit_exceeded"}, st)
    else
      case timer_expired(st) do
        nil -> step(goal, cutb, mod, rest, rearm(st))
        st -> throw_ball(@time_ball, st)
      end
    end
  end

  # nil oder der Zustand, mit dem time_limit_exceeded geworfen wird. Eine
  # abgelaufene Zeitgrenze bleibt in Kraft, bis ihr Rahmen die Ausnahme
  # fängt: Der Prüfpunkt bleibt gerissen, fängt G sie selbst (catch-all),
  # kommt sie beim nächsten gezählten Schritt wieder. Der Timer von
  # set_timer/1 läuft dagegen einmal ab und ist dann weg.
  defp timer_expired(st) do
    now = now_us()

    cond do
      # der Prüfpunkt ist schon gerissen (st.ilimit < Zählerstand) und
      # bleibt es, bis der Rahmen die Grenze entfernt
      Enum.any?(st.tlimits, fn {_, d} -> d <= now end) ->
        st

      (d = Map.get(timers(), st.qref)) != nil and d <= now ->
        drop_timer(st.qref)
        rearm(st)

      true ->
        nil
    end
  end

  defp drop_timer(qref) do
    case Process.get(@timers_key) do
      nil -> :ok
      m -> Process.put(@timers_key, Map.delete(m, qref))
    end
  end

  defp add_tlimit(st, id, deadline),
    do: check_soon(rearm(%{st | tlimits: [{id, deadline} | st.tlimits]}))

  defp remove_tlimit(%{tlimits: []} = st, _id), do: st
  defp remove_tlimit(st, id), do: rearm(%{st | tlimits: List.keydelete(st.tlimits, id, 0)})

  # gehört time_limit_exceeded diesem Rahmen? Seine Grenze ist aktiv,
  # abgelaufen und die früheste (verschachtelt gewinnt, wer zuerst abläuft)
  defp tlimit_owner?(st, id) do
    case List.keyfind(st.tlimits, id, 0) do
      {_, d} -> d <= now_us() and Enum.all?(st.tlimits, fn {_, d2} -> d2 >= d end)
      nil -> false
    end
  end

  # früheste Deadline (Rahmen und set_timer/1) oder nil
  defp earliest_deadline(st) do
    ds = for({_, d} <- st.tlimits, do: d) ++ List.wrap(Map.get(timers(), st.qref))
    if ds == [], do: nil, else: Enum.min(ds)
  end

  # in Stücken: receive after nimmt höchstens 2^32 - 1 ms
  defp sleep_until(t) do
    left = t - now_us()

    if left > 0 do
      Process.sleep(min(div(left + 999, 1000), 4_000_000_000))
      sleep_until(t)
    end
  end

  # ist die Grenze dieses Rahmens aktiv und überschritten?
  defp ilimit_exceeded?(st, id) do
    case List.keyfind(st.ilimits, id, 0) do
      {_, limit} -> :counters.get(st.icount, 1) > limit
      nil -> false
    end
  end

  defp now_us, do: System.monotonic_time(:microsecond)

  defp tlimit_exit(found, now, id, mode, us, h, rest, st) do
    budget =
      case {mode, found} do
        {"cumulative", {_, d}} -> d - now
        _ -> us
      end

    st = remove_tlimit(st, id)

    st =
      if st.height == h + 1,
        do: %{st | cps: tl(st.cps), height: h},
        else: push(st, {:tlimit_reenter, id, budget})

    run(%{st | goals: rest})
  end

  defp sleep_step(target, rest, st) do
    case earliest_deadline(st) do
      d when is_integer(d) and d < target ->
        sleep_until(d)

        case timer_expired(st) do
          nil -> sleep_step(target, rest, st)
          st -> throw_ball(@time_ball, st)
        end

      _ ->
        sleep_until(target)
        run(%{st | goals: rest})
    end
  end

  # bisher gelaufene Zeit von time/1 (µs), einschließlich des laufenden Abschnitts
  defp time_stop(st, ref) do
    case Map.get(st.counters, ref) do
      {total, nil} -> total
      {total, t0} -> total + now_us() - t0
      nil -> 0
    end
  end

  defp report_time(us) do
    secs = us / 1_000_000
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

  defp fold(:done, _spec, acc), do: acc

  defp fold({:sol, s}, spec, acc) do
    [{_, t}] = s.answer
    acc = PrologEx.Aggregate.step(spec, t, s.subst, acc, &copy_fresh/2)
    fold(backtrack(s), spec, acc)
  end

  defp count(:done, k), do: k
  defp count({:sol, s}, k), do: count(backtrack(s), k + 1)

  # collected: {kopien, :done | {:more, unter_maschine}} (siehe collect/3)
  defp findnsols_chunk({items, cont}, k, l, tail, rest, st) do
    st =
      case cont do
        # Rahmen von setup_call_cleanup/3 in der aufbewahrten Teilberechnung:
        # dann müssen auch Cuts hier hinsehen (cut_to/3)
        {:more, sub} ->
          st = if sub.scc, do: %{st | scc: true}, else: st
          push(st, {:findnsols, sub, k, l, tail, rest, Store.snapshot(st.subst), st.answer})

        :done ->
          st
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
    st = push(st, {:alt, {e, cutb, mod}, rest, Store.snapshot(st.subst), st.answer})
    run(%{st | goals: [{c, h + 1, mod}, {{:"$cut_to", h}, 0, mod}, {t, cutb, mod} | rest]})
  end

  # (C *-> T ; E), if(C, T, E): wie if_then_else, aber $soft_cut nimmt nur
  # E weg – für jede Lösung von C läuft T; E nur, wenn C keine hat
  defp soft_if(c, t, e, cutb, mod, rest, st) do
    h = st.height
    st = push(st, {:alt, {e, cutb, mod}, rest, Store.snapshot(st.subst), st.answer})
    run(%{st | goals: [{c, h + 1, mod}, {{:"$soft_cut", h}, 0, mod}, {t, cutb, mod} | rest]})
  end

  @doc """
  Ziel um Argumente erweitern wie call/N (auch M:Ziel); Ziel dereferenziert,
  das innere von M:Ziel wird hier dereferenziert
  """
  def add_args(g, [], _subst), do: g

  def add_args({:struct, ":", [m, g]}, extra, subst),
    do: mk(":", [m, add_args(unmark_top(Store.walk(g, subst)), extra, subst)])

  def add_args({:atom, f}, extra, _subst), do: mk(f, extra)
  # [] ist in ISO ein Atom: call([], A) ruft '[]'(A)
  def add_args([], extra, _subst), do: mk("[]", extra)
  def add_args({:struct, f, args}, extra, _subst), do: mk(f, args ++ extra)
  def add_args({:var, _}, _, _subst), do: PrologEx.Error.instantiation!()
  def add_args(g, _, _subst), do: PrologEx.Error.type!("callable", g)

  # Die Cut-Barriere für den Rumpf ist die Stack-Höhe VOR dem eigenen
  # Choice Point – ein Cut entfernt also auch die restlichen Klauseln.
  defp try_clauses(_goal, _args, [], _rest, _mod, st), do: backtrack(st)

  # mod: Modul, in dem das Prädikat definiert ist (Kontext für den Rumpf)
  defp try_clauses(goal, args, [cl | more], rest, mod, st) do
    {:clause, _key, nslots, pats, nfresh, body, nvars} = cl
    env = :erlang.make_tuple(nslots, nil)
    # reicht der Block von Kennungen für die frischen Variablen?
    st = if st.next_var + nvars > st.var_end, do: new_block(st, nvars), else: st

    # werfen kann die Kopfunifikation nur mit occurs_check=error: nur dann
    # der try-Block (samt Closure), sonst direkt
    mode = occurs_mode()

    if mode == :error do
      case guarded(fn -> match_args(pats, args, env, st.subst, st.next_var, mode) end) do
        {:ok, matched} -> clause_matched(matched, goal, args, more, rest, nfresh, body, mod, st)
        {:thrown, ball} -> throw_ball(ball, st)
      end
    else
      matched = match_args(pats, args, env, st.subst, st.next_var, mode)
      clause_matched(matched, goal, args, more, rest, nfresh, body, mod, st)
    end
  end

  defp clause_matched(matched, goal, args, more, rest, nfresh, body, mod, st) do
    case matched do
      :error ->
        try_clauses(goal, args, more, rest, mod, st)

      {:ok, env, s1, nv} ->
        barrier = st.height

        # Letzte passende Klausel: kein Choice Point
        {cps, height} =
          if more == [],
            do: {st.cps, barrier},
            else:
              {[
                 {:clauses, goal, args, more, rest, mod, Store.snapshot(st.subst), st.answer}
                 | st.cps
               ], barrier + 1}

        goals = inst_goals(body, env, nv, barrier, mod, rest)

        # ein einziges Update des Zustands je Inferenz (statt push, next_var
        # und cont nacheinander: jedes kopiert den ganzen Struct)
        case Store.take_wake(s1) do
          :none ->
            run(%{
              st
              | cps: cps,
                height: height,
                next_var: nv + nfresh,
                goals: goals,
                subst: s1
            })

          {ws, s1} ->
            woken(ws, s1, goals, %{st | cps: cps, height: height, next_var: nv + nfresh})
        end
    end
  end

  @var_block 4096

  # neuer Block von Kennungen (mindestens n)
  defp new_block(st, n) do
    size = max(@var_block, n)
    start = PrologEx.Vars.block(size)
    %{st | next_var: start, var_end: start + size}
  end

  defp push(st, cp), do: %{st | cps: [cp | st.cps], height: st.height + 1}

  defp backtrack(%{cps: []}), do: :done

  defp backtrack(%{cps: [cp | cps]} = st) do
    st = %{st | cps: cps, height: st.height - 1}

    case cp do
      # Else eines soft cut, dessen Bedingung schon eine Lösung hatte
      :dead ->
        backtrack(st)

      {:alt, goal, rest, subst, answer} ->
        run(%{st | goals: [goal | rest], subst: Store.restore(subst), answer: answer})

      {:clauses, goal, args, more, rest, mod, subst, answer} ->
        try_clauses(goal, args, more, rest, mod, %{
          st
          | subst: Store.restore(subst),
            answer: answer
        })

      {:solutions_list, more, mod, rest, subst, answer} ->
        start_solutions(more, mod, rest, %{st | subst: Store.restore(subst), answer: answer})

      {:solutions, cont, mod, rest, subst, answer} ->
        st = %{st | subst: Store.restore(subst), answer: answer}

        case guarded(fn -> cont.({:cont, nil}) end) do
          {:ok, r} -> next_solution(r, mod, rest, st)
          {:thrown, ball} -> throw_ball(ball, st)
        end

      {:findnsols, sub, k, l, tail, rest, subst, answer} ->
        st = %{st | subst: Store.restore(subst), answer: answer}

        case guarded(fn -> collect(backtrack(sub), k, []) end) do
          {:ok, collected} -> findnsols_chunk(collected, k, l, tail, rest, resync(st))
          {:thrown, ball} -> throw_ball(ball, st)
        end

      {:nth_cleanup, ref, subst, answer} ->
        backtrack(%{
          st
          | subst: Store.restore(subst),
            answer: answer,
            counters: Map.delete(st.counters, ref)
        })

      {:time_fail, ref, subst, answer} ->
        report_time(time_stop(st, ref))

        backtrack(%{
          st
          | subst: Store.restore(subst),
            answer: answer,
            counters: Map.delete(st.counters, ref)
        })

      # G von setup_call_cleanup/3 endgültig gescheitert: Cleanup, dann weiter
      {:scc, _, _, _, _, _, _} = frame ->
        case run_cleanup(frame, st) do
          {:thrown, ball} -> throw_ball(ball, st)
          _ -> backtrack(st)
        end

      # G von call_with_depth_limit/3 erschöpft: einmal depth_limit_exceeded,
      # falls die Grenze irgendwo überschritten wurde, sonst scheitern
      {:dlimit, {ref, _, _} = frame, r, rest, _mod, subst, answer} ->
        st = remove_dlimit(st, frame)

        with 1 <- :atomics.get(ref, 2),
             {:ok, s} <- unify(r, {:atom, "depth_limit_exceeded"}, Store.restore(subst)) do
          cont(%{st | answer: answer}, s, rest)
        else
          _ -> backtrack(st)
        end

      {:dlimit_reenter, frame} ->
        backtrack(add_dlimit(st, frame))

      # G von call_with_inference_limit/3 erschöpft: Grenze weg
      {:ilimit, id, _r, _rest, _mod, _subst, _answer} ->
        backtrack(remove_ilimit(st, id))

      # zurück in G: frische Grenze für die nächste Lösung
      {:ilimit_reenter, id, n} ->
        backtrack(add_ilimit(st, id, :counters.get(st.icount, 1) + n))

      # G von call_with_timeout erschöpft: Zeitgrenze weg
      {:tlimit, id, _on, _rest, _mod, _subst, _answer} ->
        backtrack(remove_tlimit(st, id))

      # zurück in G: neue Deadline aus dem verbleibenden Budget
      {:tlimit_reenter, id, budget} ->
        backtrack(add_tlimit(st, id, now_us() + budget))

      # zurück in G (time/1): die Uhr läuft weiter
      {:time_reenter, ref} ->
        {total, _} = Map.get(st.counters, ref, {0, nil})
        backtrack(%{st | counters: Map.put(st.counters, ref, {total, now_us()})})

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
      case unify(c, ball, Store.restore(subst)) do
        {:ok, s} ->
          st = %{st | cps: below, height: h - 1, answer: answer}
          cont(st, s, [{r, h - 1, mod} | rest])

        :error ->
          unwind(ball, below, h - 1, st)
      end
    end
  end

  # Rahmen von setup_call_cleanup/3: Cleanup, dessen Ausnahmen zählen nicht
  defp unwind(ball, [{:scc, _, _, _, _, _, _} = frame | below], h, st) do
    _ = run_cleanup(frame, st)
    unwind(ball, below, h - 1, st)
  end

  # Rahmen von call_with_depth_limit/3: G wird verlassen, Grenze weg
  defp unwind(ball, [{:dlimit, frame, _, _, _, _, _} | below], h, st),
    do: unwind(ball, below, h - 1, remove_dlimit(st, frame))

  # Rahmen von call_with_inference_limit/3: fängt nur die eigene
  # Überschreitung; sonst Grenze weg (G wird verlassen) und weiter
  defp unwind(ball, [{:ilimit, id, r, rest, _mod, subst, answer} | below], h, st) do
    if ball == {:atom, "inference_limit_exceeded"} and ilimit_exceeded?(st, id) do
      st = remove_ilimit(%{st | cps: below, height: h - 1, answer: answer}, id)

      case unify(r, ball, Store.restore(subst)) do
        {:ok, s} -> cont(st, s, rest)
        :error -> backtrack(st)
      end
    else
      unwind(ball, below, h - 1, remove_ilimit(st, id))
    end
  end

  # Rahmen von call_with_timeout: fängt nur die eigene abgelaufene
  # Zeitgrenze (außer bei on_timeout(throw)); sonst Grenze weg und weiter
  defp unwind(ball, [{:tlimit, id, on, rest, mod, subst, answer} | below], h, st) do
    if ball == @time_ball and on != :throw and tlimit_owner?(st, id) do
      st = remove_tlimit(%{st | cps: below, height: h - 1, answer: answer}, id)

      case on do
        :fail ->
          backtrack(st)

        goal ->
          run(%{
            st
            | goals: [{mk("call", [goal]), h - 1, mod} | rest],
              subst: Store.restore(subst)
          })
      end
    else
      unwind(ball, below, h - 1, remove_tlimit(st, id))
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
  # Die nächste Schwelle ist das Doppelte des Größeren von: Anzahl der
  # NICHT-ground Knoten in den lebenden Termen (die Kosten der
  # Kompaktierung) und Einträge der kompaktierten Substitution (etwa
  # Attribute vieler lebender attributierter Variablen mit kleinen
  # Suspensionen). So kommen bis zur nächsten Kompaktierung mindestens so
  # viele Einträge dazu, wie sie kostet -> amortisiert O(1), unabhängig von
  # großen ground Daten.
  # ---------------------------------------------------------------------

  defp maybe_compact(st) do
    if Store.size(st.subst) < st.threshold, do: st, else: compact_all(st)
  end

  defp compact_all(st) do
    # acc = {Memo, Größe, erreichte attributierte Variablen (Kennungen)}
    {goals, acc} =
      Enum.map_reduce(st.goals, {%{}, 0, []}, fn {g, cutb, mod}, acc ->
        {g, acc} = compact(g, st.subst, acc)
        {{g, cutb, mod}, acc}
      end)

    {answer, acc} =
      Enum.map_reduce(st.answer, acc, fn {n, t}, acc ->
        {t, acc} = compact(t, st.subst, acc)
        {{n, t}, acc}
      end)

    # Cleanups von setup_call_cleanup/3, die mit den aktuellen Bindungen
    # laufen werden (G gelungen, Cut): ihr C gehört zu den Wurzeln
    {cps, acc} =
      if st.scc do
        Enum.map_reduce(st.cps, acc, fn
          {:scc, id, c, mod, s, a, cur}, acc ->
            {cur, acc} = compact(cur, st.subst, acc)
            {{:scc, id, c, mod, s, a, cur}, acc}

          cp, acc ->
            {cp, acc}
        end)
      else
        {st.cps, acc}
      end

    # Werte von bb_b_put/2 (backtrackbar, in der Substitution): Wurzeln
    bb_key = PrologEx.Builtins.Blackboard.b_key()

    {bb_b, acc} =
      case Store.fetch(st.subst, bb_key) do
        {:ok, m} ->
          {kvs, acc} =
            Enum.map_reduce(m, acc, fn {k, v}, acc ->
              {v, acc} = compact(v, st.subst, acc)
              {{k, v}, acc}
            end)

          {Map.new(kvs), acc}

        _ ->
          {nil, acc}
      end

    {_memo, _size, root_attvs} = acc

    # Attribute der noch lebenden attributierten Variablen mitnehmen (sie
    # können selbst wieder solche enthalten)
    # während call_residue_vars/2: auch unerreichbare attributierte
    # Variablen behalten, die seit der ältesten offenen Marke entstanden
    # sind (sie sind genau das, was es finden soll)
    keep =
      case Process.get(:prolog_ex_crv_marks) do
        [_ | _] = marks ->
          m = Enum.min(marks)
          for id <- Store.attv_ids(st.subst), id > m, do: id

        _ ->
          []
      end

    {attrs, size} = compact_attrs(root_attvs ++ keep, Store.new(), acc, st.subst)

    # Ebene von call_with_depth_limit/3 mitnehmen
    attrs =
      case Store.fetch(st.subst, @depth_key) do
        {:ok, level} -> Store.put(attrs, @depth_key, level)
        :error -> attrs
      end

    attrs = if bb_b, do: Store.put(attrs, bb_key, bb_b), else: attrs

    # Zähler von call_nth/2 und Uhren von time/1, deren Choice Point (z. B.
    # durch einen Cut) verschwunden ist, werden nie mehr gebraucht
    live = for cp <- st.cps, ref = counter_ref(cp), ref != nil, do: ref
    counters = Map.take(st.counters, live)

    %{
      st
      | goals: goals,
        answer: answer,
        cps: cps,
        subst: attrs,
        counters: counters,
        threshold: max(st.min_threshold, 2 * max(size, Store.size(attrs)))
    }
  end

  defp counter_ref({:nth_cleanup, ref, _, _}), do: ref
  defp counter_ref({:time_fail, ref, _, _}), do: ref
  defp counter_ref(_), do: nil

  # Attribute der Variablen ids (und der in ihren Attributen erreichten)
  # kompaktieren; schon behandelte stehen in out
  defp compact_attrs([], out, {_memo, size, _}, _subst), do: {out, size}

  defp compact_attrs([id | ids], out, acc, subst) do
    case not Store.has_attrs?(out, id) and Store.fetch_attrs(subst, id) do
      {:ok, old} ->
        # die beim Kompaktieren erreichten attributierten Variablen sammelt
        # compact3/3 im Akkumulator (je Teilterm einmal, auch bei geteilten
        # Teiltermen); sie sind die nächsten Kandidaten
        {memo, size, _} = acc

        {attrs, {memo, size, new}} =
          Enum.reduce(old, {%{}, {memo, size, []}}, fn {m, t}, {as, acc} ->
            # tote Suspensionen (Done gebunden) fallen weg
            t = if m == "$susp", do: live_susps(t, subst), else: t
            {t, acc} = compact(t, subst, acc)
            {Map.put(as, m, t), acc}
          end)

        # attributierte Variablen in den (kompaktierten) Attributen selbst
        compact_attrs(new ++ ids, Store.put_attrs(out, id, attrs), {memo, size, []}, subst)

      _ ->
        compact_attrs(ids, out, acc, subst)
    end
  end

  defp compact(t, subst, acc) do
    {t2, acc, _changed, _ground} = compact3(t, subst, acc)
    {t2, acc}
  end

  # Eine als ground markierte Liste (oder ein markierter Rest) enthält keine
  # Done-Variablen: alles aktiv, nichts zu tun (und nicht zu durchlaufen)
  defp live_susps({:glist, _} = l, _subst), do: l

  defp live_susps([susp | more], subst) do
    rest = live_susps(more, subst)

    if PrologEx.Builtins.Coroutining.active?(susp, subst),
      do: cons(susp, rest),
      else: rest
  end

  defp live_susps(l, _subst), do: l

  # Ergebnis: {Term, {memo, nicht_ground_größe}, verändert?, ground?}
  # Unveränderte Teilterme werden nicht kopiert, sondern geteilt.
  defp compact3(t, _subst, acc) when is_marked(t), do: {t, acc, false, true}

  # Markierung von call_nth/2: das Argument N kann eine Variable sein
  defp compact3({:"$nth", ref, n, h}, subst, acc) do
    {n2, acc, changed, _} = compact3(n, subst, acc)
    {{:"$nth", ref, n2, h}, acc, changed, false}
  end

  defp compact3({:var, _} = var, subst, {memo, size, attvs} = acc) do
    case Map.fetch(memo, var) do
      {:ok, {t, g}} ->
        {t, acc, t != var, g}

      :error ->
        case Store.walk(var, subst) do
          # freie attributierte Variable: merken, dass sie erreichbar ist
          # (kein Memo – ein Blatt)
          {:var, {:attv, id}} = free ->
            {free, {memo, size, [id | attvs]}, free != var, false}

          {:var, _} = free ->
            {free, acc, free != var, false}

          # atomar: nichts zu teilen, kein Memo
          atomic when not is_tuple(atomic) and not is_list(atomic) ->
            {atomic, acc, true, true}

          {:atom, _} = atomic ->
            {atomic, acc, true, true}

          [] ->
            {[], acc, true, true}

          # zusammengesetzt: merken, damit geteilte Teilterme geteilt bleiben
          # (atomare Werte und Variablen sind oben abgehandelt – die Memo-Map
          # bleibt klein, ihre Zugriffe billig)
          bound ->
            {t, {memo, size, attvs}, _ch, g} = compact3(bound, subst, acc)
            {t, {Map.put(memo, var, {t, g}), size, attvs}, true, g}
        end
    end
  end

  # Geteilte Teilterme (ein DAG, etwa die Knoten eines BDDs) nur einmal
  # ablaufen (PrologEx.Share): ein Treffer liefert, was die Rechnung ergäbe.
  defp compact3({:struct, f, args} = t, subst, {memo, _, _} = acc) do
    case PrologEx.Share.get(memo, t) do
      {:ok, {t2, changed, ground}} ->
        {t2, acc, changed, ground}

      :error ->
        {t2, {memo, size, attvs}, changed, ground} = compact_struct(t, f, args, subst, acc)
        {t2, {PrologEx.Share.put(memo, t, {t2, changed, ground}), size, attvs}, changed, ground}
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

  defp compact_struct(t, f, args, subst, acc) do
    {args2, {acc, changed, ground}} =
      Enum.map_reduce(args, {acc, false, true}, fn arg, {acc, ch, gr} ->
        {a2, acc, c, g} = compact3(arg, subst, acc)
        {a2, {acc, ch or c, gr and g}}
      end)

    {memo, size, attvs} = acc

    cond do
      ground -> {{:gstruct, f, args2}, acc, true, true}
      changed -> {{:struct, f, args2}, {memo, size + 1, attvs}, true, false}
      true -> {t, {memo, size + 1, attvs}, false, false}
    end
  end

  # Köpfe der Reihe nach kompaktieren; Einträge {:cell, zelle, h2, ch, gh}
  # oder {:link, var} (gebundene Rest-Variable, wird beim Aufbau memoisiert)
  defp compact_spine([h | t] = l, subst, acc, spine) do
    {h2, acc, ch, gh} = compact3(h, subst, acc)
    spine = [{:cell, l, h2, ch, gh} | spine]

    case t do
      [_ | _] ->
        compact_spine(t, subst, acc, spine)

      {:var, _} = var ->
        {memo, _, _} = acc

        with :error <- Map.fetch(memo, var),
             [_ | _] = next <- Store.walk(var, subst) do
          compact_spine(next, subst, acc, [{:link, var} | spine])
        else
          _ -> {spine, t, acc}
        end

      _ ->
        {spine, t, acc}
    end
  end

  defp compact_rebuild([], t, acc, ch, g), do: {t, acc, ch, g}

  defp compact_rebuild([{:link, var} | rest], t, {memo, size, attvs}, _ch, g),
    do: compact_rebuild(rest, t, {Map.put(memo, var, {t, g}), size, attvs}, true, g)

  defp compact_rebuild([{:cell, l, h2, ch, gh} | rest], t2, {memo, size, attvs} = acc, ct, gt) do
    cond do
      gh and gt -> compact_rebuild(rest, cons(h2, t2), acc, true, true)
      ch or ct -> compact_rebuild(rest, [h2 | t2], {memo, size + 1, attvs}, true, false)
      true -> compact_rebuild(rest, l, {memo, size + 1, attvs}, false, false)
    end
  end

  # ---------------------------------------------------------------------
  # Arithmetik
  # ---------------------------------------------------------------------

  defp eval(t, subst), do: PrologEx.Arith.eval(t, subst)

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
    # benannte Variablen der Anfrage; gezeigt werden die ohne führendes _
    named =
      for {:var, id} = var <- goal |> query_vars() |> Enum.uniq(), n = var_name(id), do: {n, var}

    answer = Enum.reject(named, fn {n, _} -> String.starts_with?(n, "_") end)

    start = new_state(db, [{goal, 0, Keyword.get(opts, :module, "user")}], answer, opts)

    # set_timer/1: der Timer gilt bis zum Ende der Anfrage
    qref = start.qref

    Stream.unfold({:start, start}, fn
      :halt ->
        drop_timer(qref)
        nil

      {:start, st} ->
        put_db(st.db)
        st |> run() |> emit() |> query_done(qref)

      {:retry, st} ->
        st |> backtrack() |> emit() |> query_done(qref)
    end)
  end

  defp new_state(db, goals, answer, opts) do
    min = Keyword.get(opts, :compact_threshold, @min_threshold)

    %__MODULE__{
      goals: goals,
      db: db,
      answer: answer,
      threshold: min,
      min_threshold: min,
      icount: inference_counter(),
      qref: make_ref()
    }
  end

  defp query_done(nil, qref) do
    drop_timer(qref)
    nil
  end

  defp query_done(next, _qref), do: next

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

  # Restziele über '$residuals'/2 (eingebaute Bedingungen,
  # attribute_goal/2 und attribute_goals//1 der Attributmodule, vorher
  # deren project_attributes/2), in einer Unter-Maschine im
  # aktuellen Zustand. M:G wird ohne Modul gezeigt, wenn G in user dasselbe
  # Prädikat meint (oder M = user).
  defp residual_goals(terms, st) do
    case Enum.flat_map(terms, &term_attvars(&1, st.subst)) |> Enum.uniq() do
      [] ->
        []

      vars ->
        r = {:var, PrologEx.Vars.next()}
        # zuerst project_attributes/2 (Anfragevariablen, attributierte)
        qvars =
          terms |> Enum.flat_map(&PrologEx.Builtins.Order.variables(&1, st.subst)) |> Enum.uniq()

        goal =
          mk(",", [
            mk("$res_project", [list(qvars), list(vars)]),
            mk("$residuals", [list(vars), r])
          ])

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
  # wie die letzte (Z). Aus "R = [2, _2], Y = _2" wird so "R = [2, Y]".
  # Die Richtung von Var-Var-Bindungen spielt für die Ausgabe keine Rolle.
  defp name_fresh_r(ans) do
    # ans: [{name, term}] in Anfragereihenfolge
    groups =
      ans
      |> Enum.filter(&match?({_, {:var, _}}, &1))
      |> Enum.group_by(fn {_, v} -> v end, &elem(&1, 0))

    if Enum.all?(groups, fn {v, ns} -> ns == [var_name(v)] end) do
      {ans, %{}}
    else
      renames = Map.new(groups, fn {v, ns} -> {v, named_as(v, List.last(ns))} end)

      chain =
        for {v, ns} <- groups,
            {n, next} <- Enum.zip(ns, tl(ns) ++ [List.last(ns)]),
            into: %{},
            do: {n, named_as(v, next)}

      {Enum.map(ans, fn {n, t} -> {n, Map.get(chain, n) || rename_free(t, renames)} end), renames}
    end
  end

  # dieselbe Variable unter dem Namen einer Anfragevariablen (nur für die
  # Ausgabe: der Name steckt in der Kennung)
  defp named_as({:var, {_, id}}, name), do: {:var, {name, id}}
  defp named_as({:var, id}, name) when is_integer(id), do: {:var, {name, id}}
  defp named_as(_, name), do: {:var, name}

  # renames: Variable → Variable
  defp rename_free({:var, _} = x, m), do: Map.get(m, x, x)
  defp rename_free({:struct, f, args}, m), do: {:struct, f, Enum.map(args, &rename_free(&1, m))}
  defp rename_free([h | t], m), do: [rename_free(h, m) | rename_free(t, m)]
  defp rename_free(t, _m), do: t

  # Für Messungen: erste Lösung plus Zustandsgrößen
  def first_with_stats(db, goal, opts \\ []) do
    put_db(db)

    case run(new_state(db, [{goal, 0, "user"}], [], opts)) do
      {:sol, st} ->
        {:ok,
         %{
           bindings: Store.size(st.subst),
           choicepoints: st.height,
           # Kennungen nie über den Block hinaus vergeben
           vars_in_block: st.next_var <= st.var_end
         }}

      :done ->
        false
    end
  end

  @doc "Namen der benannten Anfragevariablen in Reihenfolge ihres Auftretens"
  def query_var_names(goal) do
    for {:var, id} <- goal |> query_vars() |> Enum.uniq(), n = var_name(id), do: n
  end

  # Name einer Variablen aus dem Quelltext ({name, n} vom Reader; eine
  # Binary ist ein von Hand gebauter Name), sonst nil (anonyme _ auch)
  defp var_name({:var, id}), do: var_name(id)
  defp var_name({"_", _}), do: nil
  defp var_name({n, _}) when is_binary(n), do: n
  defp var_name(n) when is_binary(n), do: n
  defp var_name(_), do: nil

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

    # ungebundene Anfragevariablen (X = X) werden nicht gezeigt
    shown = named |> Enum.sort() |> Enum.reject(fn {k, t} -> var_name(t) == k end)
    goal_terms = Enum.map(residual, &(&1 |> rename_free(renames) |> strip_user()))
    terms = Enum.map(shown, &elem(&1, 1)) ++ goal_terms

    # Variablen der Anfrage (Name in der Kennung) behalten ihren Namen –
    # auch _X, die (wie bei SWI) nicht angezeigt werden; anonyme _ und
    # frische heißen _A, _B, ... in Reihenfolge des Auftretens, wie SICStus
    opts = opts ++ [variable_names: fresh_names(terms, named_vars(terms))]

    bindings =
      Enum.map(shown, fn {k, t} ->
        # rechts von =/2 (700, xfx): höchstens 699, Operator-Atome in Klammern
        "#{k} = #{format(t, opts ++ [priority: 699, operand: true])}"
      end)

    goals = Enum.map(goal_terms, &format(&1, opts ++ [priority: 999]))

    case bindings ++ goals do
      [] -> "true"
      shown -> Enum.join(shown, ", ")
    end
  end

  # Variable → Name für alle benannten Variablen der Terme
  defp named_vars(terms) do
    for t <- terms, {:var, id} = v <- query_vars(t), n = var_name(id), into: %{}, do: {v, n}
  end

  # Namen für Variablen, die nicht aus der Anfrage stammen: _A, ..., _Z,
  # _AA, _AB, ... in Reihenfolge des ersten Auftretens; die Namen der
  # Anfrage (named: Variable → Name) bleiben und werden nicht vergeben
  defp fresh_names(terms, named) do
    taken = named |> Map.values() |> MapSet.new()

    {vars, _} =
      Enum.reduce(terms, {[], MapSet.new()}, fn t, acc -> answer_vars(t, named, acc) end)

    {names, _} =
      vars
      |> Enum.reverse()
      |> Enum.map_reduce(0, fn v, i ->
        {name, i} = next_fresh_name(i, taken)
        {{v, name}, i + 1}
      end)

    Map.merge(named, Map.new(names))
  end

  defp answer_vars({:var, _} = v, named, {acc, seen} = all) do
    cond do
      Map.has_key?(named, v) -> all
      MapSet.member?(seen, v) -> all
      true -> {[v | acc], MapSet.put(seen, v)}
    end
  end

  defp answer_vars({tag, _, args}, named, acc) when tag in [:struct, :gstruct],
    do: Enum.reduce(args, acc, &answer_vars(&1, named, &2))

  defp answer_vars([h | t], named, acc), do: answer_vars(t, named, answer_vars(h, named, acc))
  defp answer_vars(_, _named, acc), do: acc

  defp next_fresh_name(i, taken) do
    name = "_" <> letters(i)
    if MapSet.member?(taken, name), do: next_fresh_name(i + 1, taken), else: {name, i}
  end

  # 0 -> A, 25 -> Z, 26 -> AA, 27 -> AB, ... (bijektiv zur Basis 26)
  defp letters(i) when i < 26, do: <<?A + i>>
  defp letters(i), do: letters(div(i, 26) - 1) <> <<?A + rem(i, 26)>>

  # user:G in Restzielen wie SWI ohne Modul zeigen
  defp strip_user({:struct, ":", [{:atom, "user"}, g]}), do: strip_user(g)
  defp strip_user({:struct, f, args}), do: {:struct, f, Enum.map(args, &strip_user/1)}
  defp strip_user(t), do: t
end
