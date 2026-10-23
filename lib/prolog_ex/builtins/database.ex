defmodule PrologEx.Builtins.Database do
  @moduledoc """
  Veränderliche Datenbank: assert/1, asserta/1, assertz/1, retract/1,
  retractall/1 (siehe auch `PrologEx` – Abschnitt Datenbank).

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
    add(c, :z, subst())
  end

  defbuiltin "assertz", [c] do
    add(c, :z, subst())
  end

  defbuiltin "asserta", [c] do
    add(c, :a, subst())
  end

  # retract(C): entfernt die erste passende Klausel; beim Backtracking die
  # nächste. Deterministisch, wenn keine weitere passt.
  defbuiltin "retract", [c], nondet: true do
    s = subst()
    {h, b} = split(c, s)

    key =
      case PrologEx.walk(h, s) do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> Compiler.key(hh)
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
  defbuiltin "retractall", [h] do
    s = subst()

    head =
      case PrologEx.walk(h, s) do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> hh
      end

    key = Compiler.key(head)
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

  # dynamic(Spec) als Ziel: name/arity, Folge (a/1, b/2) oder Liste
  defbuiltin "dynamic", [spec] do
    keys = specs(resolve(spec))
    Enum.each(keys, &check_modifiable!/1)
    db = PrologEx.current_db()

    Enum.each(keys, fn key ->
      if Map.has_key?(db, key) and not PrologEx.dynamic?(db, key), do: permission!(key)
    end)

    PrologEx.put_db(Enum.reduce(keys, db, &PrologEx.declare(&2, &1)))
    :ok
  end

  # ---------------------------------------------------------------------

  defp specs({:var, _}), do: PrologEx.Error.instantiation!()
  defp specs({tag, ",", [a, b]}) when tag in [:struct, :gstruct], do: specs(a) ++ specs(b)

  defp specs({tag, "/", [{:atom, n}, ar]}) when tag in [:struct, :gstruct] and is_integer(ar),
    do: [{n, ar}]

  defp specs([]), do: []
  defp specs([h | t]), do: specs(h) ++ specs(t)
  defp specs({:glist, _} = l), do: specs(PrologEx.unmark(l))
  defp specs(t), do: PrologEx.Error.type!("predicate_indicator", t)

  defp add(c, where, s) do
    {h, b} = split(c, s)

    key =
      case PrologEx.walk(h, s) do
        {:var, _} -> PrologEx.Error.instantiation!()
        hh -> Compiler.key(hh)
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

    db = db |> PrologEx.declare(key) |> Map.put(key, PrologEx.assert_entry(pred, entry, where))
    PrologEx.put_db(db)
    :ok
  end

  # (H :- B) oder H (Rumpf true)
  defp split(c, s) do
    case PrologEx.unmark_top(PrologEx.walk(c, s)) do
      {:var, _} -> PrologEx.Error.instantiation!()
      {:struct, ":-", [h, b]} -> {h, b}
      h -> {h, a("true")}
    end
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
  defp check_modifiable!(key) do
    if PrologEx.Builtins.protected?(key), do: permission!(key)
  end

  # bestehendes Prädikat: nur dynamische dürfen sich ändern
  defp check_dynamic!(key) do
    check_modifiable!(key)
    unless PrologEx.dynamic?(PrologEx.current_db(), key), do: permission!(key)
  end

  defp permission!({name, arity}),
    do:
      PrologEx.Error.permission!(
        "modify",
        "static_procedure",
        PrologEx.Error.indicator(name, arity)
      )

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
