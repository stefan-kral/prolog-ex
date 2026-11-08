defmodule PrologEx.Builtins.Database do
  @moduledoc """
  Veränderliche Datenbank: assert/1, asserta/1, assertz/1, retract/1,
  retractall/1, abolish/1 (siehe auch `PrologEx` – Abschnitt Datenbank).

    * Durch assert entstehende Prädikate sind dynamisch; geladene
      Prädikate sind statisch, außer mit `:- dynamic`. Änderungen an
      statischen Prädikaten und Builtins ergeben permission_error.
    * Logical update view (ISO): ein laufender Aufruf sieht die Klauseln
      vom Zeitpunkt des Aufrufs; retract entfernt genau die gefundene
      Klausel (über ihre Kennung).
    * Klauseln werden beim Eintragen kopiert; ihre Variablen heißen danach
      A, B, C, ... (für listing).
  """
  use PrologEx.Builtin
  alias PrologEx.Compiler

  defbuiltin "assert", [c] do
    add(c, :z, subst(), context_module())
  end

  defbuiltin "assertz", [c] do
    add(c, :z, subst(), context_module())
  end

  defbuiltin "asserta", [c] do
    add(c, :a, subst(), context_module())
  end

  # retract(C): entfernt die erste passende Klausel; beim Backtracking die
  # nächste. Deterministisch, wenn keine weitere passt.
  defbuiltin "retract", [c], nondet: true do
    s = subst()
    {m, h, b} = split(c, s, context_module())

    key =
      case PrologEx.Store.walk(h, s) do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> mkey(m, hh)
      end

    # eingebaute Prädikate (atom/1, ...): permission_error, auch ohne Eintrag
    check_modifiable!(key)

    case Map.fetch(PrologEx.current_db(), key) do
      :error ->
        []

      {:ok, pred} ->
        check_dynamic!(key)
        # nur Klauseln, die zum ersten Argument passen können
        entries = PrologEx.candidate_entries(pred, Compiler.args_of(PrologEx.Store.walk(h, s)), s)
        retract_from(next_match(entries, h, b, s), key, h, b, s)
    end
  end

  # retractall(H): entfernt alle Klauseln, deren Kopf zu H passt; legt ein
  # unbekanntes Prädikat als dynamisch an
  defbuiltin "retractall", [h0] do
    s = subst()
    {m, h} = PrologEx.Builtins.Modules.strip(h0, context_module(), s)

    head =
      case h do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> hh
      end

    key = mkey(m, head)
    db = PrologEx.current_db()

    case Map.fetch(db, key) do
      :error ->
        check_modifiable!(key)
        PrologEx.put_db(PrologEx.declare(db, key))

      {:ok, pred} ->
        check_dynamic!(key)

        # Kandidaten wie beim Aufruf; nur diese werden geprüft
        gone =
          for {ref, {ch, _}, _} <- PrologEx.candidate_entries(pred, Compiler.args_of(head), s),
              matches?(h, ch, s),
              into: MapSet.new(),
              do: ref

        # nichts gefunden: das Prädikat bleibt, wie es ist (samt Index)
        if MapSet.size(gone) > 0 do
          keep = Enum.reject(PrologEx.pred_entries(pred), fn {ref, _, _} -> ref in gone end)
          PrologEx.put_db(Map.put(db, key, {:stale, keep, []}))
        end
    end

    :ok
  end

  # abolish(Name/Arity), auch M:Name/Arity (ISO 8.9.4): entfernt ein
  # dynamisches Prädikat ganz – Klauseln und Eigenschaften (danach ist es
  # unbekannt, anders als nach retractall/1). Ein unbekanntes Prädikat ist
  # kein Fehler; statische (geladene, eingebaute, aus Bibliotheken
  # importierte) ergeben permission_error(modify, static_procedure, PI).
  # Laufende Aufrufe behalten ihren Schnappschuss (logical update view).
  defbuiltin "abolish", [pi] do
    s = subst()
    {m, spec} = PrologEx.Builtins.Modules.strip(pi, context_module(), s)
    {name, arity} = abolish_indicator!(spec, s)
    key = {m, name, arity}
    check_modifiable!(key)
    db = PrologEx.current_db()

    cond do
      Map.has_key?(db, key) ->
        check_dynamic!(key)

        db =
          db
          |> Map.delete(key)
          |> Map.delete({:meta, m, name, arity})
          |> Map.update(:dynamic, MapSet.new(), &MapSet.delete(&1, key))

        PrologEx.put_db(db)

      # eingebaut oder aus einer Bibliothek sichtbar: statisch. (Aus einem
      # anderen Benutzermodul importiert: hier unbekannt, wie bei retract/1.)
      match?({:builtin, _, _}, PrologEx.locate(db, m, name, arity)) ->
        permission!(key)

      true ->
        :ok
    end

    :ok
  end

  defp abolish_indicator!(spec, s) do
    case PrologEx.unmark_top(spec) do
      {:var, _} ->
        PrologEx.Error.instantiation!()

      {:struct, "/", [n, ar]} ->
        n = PrologEx.Store.walk(n, s)
        ar = PrologEx.Store.walk(ar, s)

        cond do
          match?({:var, _}, n) or match?({:var, _}, ar) -> PrologEx.Error.instantiation!()
          not (match?({:atom, _}, n) or n == []) -> PrologEx.Error.type!("atom", n)
          not is_integer(ar) -> PrologEx.Error.type!("integer", PrologEx.resolve(ar, s))
          ar < 0 -> PrologEx.Error.domain!("not_less_than_zero", ar)
          true -> {atom_name(n), ar}
        end

      other ->
        PrologEx.Error.type!("predicate_indicator", PrologEx.resolve(other, s))
    end
  end

  defp atom_name([]), do: "[]"
  defp atom_name({:atom, n}), do: n

  # dynamic(Spec) als Ziel: name/arity, Folge (a/1, b/2) oder Liste
  defbuiltin "dynamic", [spec] do
    keys = PrologEx.Builtins.Modules.indicators(resolve(spec), context_module())
    Enum.each(keys, &check_modifiable!/1)
    db = PrologEx.current_db()

    Enum.each(keys, fn key ->
      if Map.has_key?(db, key) and not PrologEx.dynamic?(db, key), do: permission!(key)
    end)

    PrologEx.put_db(Enum.reduce(keys, db, &PrologEx.declare(&2, &1)))
    :ok
  end

  # ---------------------------------------------------------------------

  defp add(c, where, s, ctx) do
    {m, h, b} = split(c, s, ctx)

    key =
      case PrologEx.Store.walk(h, s) do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> mkey(m, hh)
      end

    # Rumpf muss aufrufbar sein (Variablen werden zu call/1)
    PrologEx.check_body!(b, s)

    check_modifiable!(key)

    # Übersetzen schreibt geteilte Teilterme als Baum aus (X+X über 40
    # Stufen: 2^40 Knoten). Erst die Baumgröße zählen (mit Gedächtnis, so
    # teuer wie der geteilte Term) und vorab gegen eine Speichergrenze
    # prüfen; ohne Grenze ab 50 Mio. Knoten resource_error(memory) statt
    # minutenlang zu rechnen
    check_size!({:struct, ":-", [h, b]}, s)

    # Kopie mit frischen, lesbar benannten Variablen
    {_, "$clause", [head, body]} =
      PrologEx.copy_fresh({:struct, "$clause", [h, b]}, s) |> nice_vars()

    entry = PrologEx.entry({head, body})
    db = PrologEx.current_db()

    pred =
      case Map.fetch(db, key) do
        {:ok, p} ->
          check_dynamic!(key)
          p

        :error ->
          PrologEx.pred_from_entries([])
      end

    {m, n, ar} = key

    db =
      db
      |> PrologEx.declare(key)
      |> Map.put(key, PrologEx.assert_entry(pred, entry, where))
      |> Map.delete({:import, m, n, ar})

    PrologEx.put_db(db)
    :ok
  end

  @big_clause 10_000
  @max_clause 50_000_000

  defp check_size!(c, s) do
    # fast immer klein: ohne Gedächtnis zählen, Abbruch bei @big_clause
    if quick_size(c, s, @big_clause) < 0, do: check_big!(c, s), else: :ok
  end

  defp check_big!(c, s) do
    {n, _} = tsize(c, s, %{})

    if n > @big_clause do
      # übersetzte Klausel etwa 4 Wörter je Knoten
      PrologEx.reserve!(4 * n)

      if n > @max_clause and not PrologEx.mem_limited?(),
        do: PrologEx.Error.resource!("memory")
    end

    :ok
  end

  # Restbudget nach dem Zählen der Knoten (als Baum); negativ: zu groß
  defp quick_size(_t, _s, b) when b < 0, do: b

  defp quick_size({:var, _} = v, s, b) do
    case PrologEx.Store.walk(v, s) do
      {:var, _} -> b - 1
      t -> quick_size(t, s, b)
    end
  end

  defp quick_size({tag, _, args}, s, b) when tag in [:struct, :gstruct],
    do: quick_all(args, s, b - 1)

  defp quick_size([h | t], s, b), do: quick_size(t, s, quick_size(h, s, b - 1))
  defp quick_size({:glist, items}, s, b), do: quick_all(items, s, b - 1)
  defp quick_size(_, _s, b), do: b - 1

  defp quick_all(_, _s, b) when b < 0, do: b
  defp quick_all([], _s, b), do: b
  defp quick_all([a | as], s, b), do: quick_all(as, s, quick_size(a, s, b))

  # Zahl der Knoten als Baum; geteilte Teilterme (gebundene Variablen,
  # physisch gleiche Strukturen) zählen nur einmal Arbeit
  # (eine Variable auf ihrem eigenen Pfad: ein Zyklus – eine Klausel kann
  # ihn nicht darstellen)
  defp tsize({:var, _} = v, s, memo) do
    case memo do
      %{^v => :path} ->
        PrologEx.Cyclic.error!()

      %{^v => n} ->
        {n, memo}

      _ ->
        case PrologEx.Store.walk(v, s) do
          {:var, _} ->
            {1, memo}

          t ->
            {n, memo} = tsize(t, s, Map.put(memo, v, :path))
            {n, Map.put(memo, v, n)}
        end
    end
  end

  defp tsize({tag, _, args} = t, s, memo) when tag in [:struct, :gstruct] do
    case PrologEx.Share.get(memo, t) do
      {:ok, n} ->
        {n, memo}

      :error ->
        {n, memo} = tsize_all(args, s, {1, memo})
        {n, PrologEx.Share.put(memo, t, n)}
    end
  end

  defp tsize([_ | _] = l, s, memo), do: tsize_list(l, s, {0, memo})
  defp tsize({:glist, items}, s, memo), do: tsize_all(items, s, {length(items), memo})
  defp tsize(_, _s, memo), do: {1, memo}

  defp tsize_all([], _s, acc), do: acc

  defp tsize_all([a | as], s, {k, memo}) do
    {n, memo} = tsize(a, s, memo)
    tsize_all(as, s, {k + n, memo})
  end

  # Listenrücken ohne Rekursion (lange Listen)
  defp tsize_list([h | t], s, {k, memo}) do
    {n, memo} = tsize(h, s, memo)
    tsize_list(t, s, {k + n + 1, memo})
  end

  defp tsize_list(t, s, {k, memo}) do
    {n, memo} = tsize(t, s, memo)
    {k + n, memo}
  end

  # (H :- B) oder H (Rumpf true), jeweils mit Modul: M:(H :- B) gilt ganz
  # in M; bei (M:H :- B) läuft der Rumpf im Kontextmodul (wie SWI).
  # Ergebnis {modul, kopf, rumpf}
  defp split(c, s, ctx) do
    {m, c} = PrologEx.Builtins.Modules.strip(c, ctx, s)

    {h, b} =
      case PrologEx.unmark_top(c) do
        {:var, _} -> PrologEx.Error.instantiation!()
        {:struct, ":-", [h, b]} -> {h, b}
        h -> {h, a("true")}
      end

    case PrologEx.Builtins.Modules.strip(h, m, s) do
      {^m, h} -> {m, h, b}
      {hm, h} -> {hm, h, mk(":", [a(m), b])}
    end
  end

  defp mkey(m, head) do
    {n, ar} = Compiler.key(head)
    {m, n, ar}
  end

  defp retract_from(:none, _key, _h, _b, _s), do: []

  defp retract_from({ref, pairs, rest}, key, h, b, s) do
    # die gefundene Klausel entfernen (falls noch vorhanden)
    PrologEx.update_db(fn db ->
      case Map.fetch(db, key) do
        {:ok, pred} ->
          Map.put(db, key, PrologEx.remove_entry(pred, ref))

        :error ->
          db
      end
    end)

    res = {:unify, pairs}

    # nächste passende Klausel schon suchen: gibt es keine, ist dies die
    # letzte Lösung (deterministisch)
    case next_match(rest, h, b, s) do
      :none -> [res]
      found -> [res | fn -> retract_from(found, key, h, b, s) end]
    end
  end

  # erste Klausel im Schnappschuss, die zu (H :- B) passt
  defp next_match([], _h, _b, _s), do: :none

  defp next_match([{ref, {ch, cb}, _} | rest], h, b, s) do
    {_, "$clause", [ch2, cb2]} = PrologEx.copy_fresh({:struct, "$clause", [ch, cb]}, %{})
    pairs = [{h, ch2}, {b, cb2}]

    if unify_all(pairs, s), do: {ref, pairs, rest}, else: next_match(rest, h, b, s)
  end

  defp matches?(h, ch, s) do
    {_, "$h", [ch2]} = PrologEx.copy_fresh({:struct, "$h", [ch]}, %{})
    unify_all([{h, ch2}], s)
  end

  defp unify_all(pairs, s), do: PrologEx.unifiable_all?(pairs, s)

  # Steuerkonstrukte und geschützte Builtins sind tabu; nicht geschützte
  # Builtins (append/3, ...) darf man wie beim consult durch eigene
  # Klauseln ersetzen
  # (Klauseln als Kopf: (:-)/1,2 zählt wie ein Steuerkonstrukt, ISO 8.9.1.4)
  defp check_modifiable!({_m, n, ar} = key) do
    if PrologEx.Builtins.protected?({n, ar}) or {n, ar} in [{":-", 1}, {":-", 2}],
      do: permission!(key)
  end

  # bestehendes Prädikat: nur dynamische dürfen sich ändern
  defp check_dynamic!(key) do
    check_modifiable!(key)
    unless PrologEx.dynamic?(PrologEx.current_db(), key), do: permission!(key)
  end

  defp permission!({m, name, arity}) do
    pi = PrologEx.Error.indicator(name, arity)
    pi = if m == "user", do: pi, else: mk(":", [a(m), pi])
    PrologEx.Error.permission!("modify", "static_procedure", pi)
  end

  # Variablen in Reihenfolge des ersten Auftretens A, B, ..., Z, A1, ...
  defp nice_vars(t) do
    {t, _} = rename(t, %{})
    t
  end

  defp rename({:var, _} = x, m) do
    case Map.fetch(m, x) do
      {:ok, y} ->
        {y, m}

      :error ->
        y = {:var, var_name(map_size(m))}
        {y, Map.put(m, x, y)}
    end
  end

  defp rename({tag, f, args}, m) when tag in [:struct, :gstruct] do
    {args, m} = Enum.map_reduce(args, m, &rename/2)
    {mk(f, args), m}
  end

  defp rename([h | t], m) do
    {h, m} = rename(h, m)
    {t, m} = rename(t, m)
    {cons(h, t), m}
  end

  defp rename(t, m), do: {t, m}

  defp var_name(i) when i < 26, do: <<?A + i>>
  defp var_name(i), do: <<?A + rem(i, 26)>> <> Integer.to_string(div(i, 26))
end
