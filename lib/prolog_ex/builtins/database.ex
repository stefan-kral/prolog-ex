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
      case PrologEx.walk(h, s) do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> mkey(m, hh)
      end

    case Map.fetch(PrologEx.current_db(), key) do
      :error ->
        []

      {:ok, pred} ->
        check_dynamic!(key)
        entries = PrologEx.pred_entries(pred)
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

        keep =
          Enum.reject(PrologEx.pred_entries(pred), fn {_, {ch, _}, _} ->
            matches?(h, ch, s)
          end)

        PrologEx.put_db(Map.put(db, key, {:stale, keep, []}))
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
        n = PrologEx.walk(n, s)
        ar = PrologEx.walk(ar, s)

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
      case PrologEx.walk(h, s) do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> mkey(m, hh)
      end

    # Rumpf muss aufrufbar sein (Variablen werden zu call/1)
    case PrologEx.walk(b, s) do
      {:var, _} -> :ok
      bb -> Compiler.key(bb)
    end

    check_modifiable!(key)

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

  defp unify_all([], _s), do: true

  defp unify_all([{x, y} | more], s) do
    case PrologEx.unify(x, y, s) do
      {:ok, s} -> unify_all(more, s)
      :error -> false
    end
  end

  # Steuerkonstrukte und geschützte Builtins sind tabu; nicht geschützte
  # Builtins (append/3, ...) darf man wie beim consult durch eigene
  # Klauseln ersetzen
  defp check_modifiable!({_m, n, ar} = key) do
    if PrologEx.Builtins.protected?({n, ar}), do: permission!(key)
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
