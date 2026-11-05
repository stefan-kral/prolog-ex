defmodule PrologEx.Builtins.Atts do
  @moduledoc """
  `library(atts)` wie SICStus: attributierte Variablen für eigene
  Constraint-Löser.

      :- module(domain, [domain/2]).
      :- use_module(library(atts)).
      :- attribute dom/1.

      verify_attributes(Var, Other, Goals) :- ...   % vor der Bindung
      attribute_goal(Var, domain(Var, Dom)) :- get_atts(Var, dom(Dom)).

    * `:- attribute Name/Arity, ...` (höchstens eine Deklaration je
      Modul) – die Attribute sind privat für das Modul.
    * `put_atts(Var, Spec)`: `+A` setzt (ersetzt) Attribut A, `-A` entfernt
      es; Spec auch als Liste. Backtracking nimmt das zurück.
    * `get_atts(Var, Spec)`: `+A` – vorhanden und mit A unifiziert, `-A` –
      nicht vorhanden; ungebundenes Spec: Liste aller vorhandenen.
    * Beide wirken im Kontextmodul, Var muss ungebunden sein (sonst
      scheitert get_atts, put_atts meldet uninstantiation_error).
    * Hooks: `Modul:verify_attributes(Var, Wert, Goals)` – siehe
      `PrologEx` (Wecken); `Modul:attribute_goal(Var, Goal)` – für
      Restziele, `frozen/2`, `copy_term/3`.

  Ein Attribut ohne `+`/`-` gilt als `+`. Gespeichert sind die Attribute je
  Modul als Prolog-Liste in Deklarationsreihenfolge.
  """
  use PrologEx.Builtin, module: "atts"
  alias PrologEx.Error

  defbuiltin "put_atts", [var, spec] do
    mod = context_module()
    s = subst()

    case PrologEx.Store.walk(var, s) do
      {:var, _} = v ->
        decl = declared!(mod)
        old = current(v, mod, s)

        new =
          Enum.reduce(specs(spec, s), old, fn
            {:+, att}, acc ->
              List.keystore(acc, key!(att, decl, mod), 0, {key!(att, decl, mod), att})

            {:-, att}, acc ->
              List.keydelete(acc, key!(att, decl, mod), 0)
          end)
          |> Enum.sort_by(fn {k, _} -> Enum.find_index(decl, &(&1 == k)) end)

        {:subst, PrologEx.put_attr(s, v, mod, list(Enum.map(new, &elem(&1, 1))))}

      other ->
        Error.uninstantiation!(PrologEx.resolve(other, s))
    end
  end

  defbuiltin "get_atts", [var, spec] do
    mod = context_module()
    s = subst()

    case PrologEx.Store.walk(var, s) do
      {:var, _} = v ->
        decl = declared!(mod)
        present = current(v, mod, s)

        case PrologEx.Store.walk(spec, s) do
          {:var, _} ->
            {:unify, [{spec, list(Enum.map(present, &elem(&1, 1)))}]}

          _ ->
            Enum.reduce_while(specs(spec, s), {:unify, []}, fn
              {:+, att}, {:unify, pairs} ->
                case List.keyfind(present, key!(att, decl, mod), 0) do
                  {_, value} -> {:cont, {:unify, [{att, value} | pairs]}}
                  nil -> {:halt, :fail}
                end

              {:-, att}, acc ->
                if List.keymember?(present, key!(att, decl, mod), 0),
                  do: {:halt, :fail},
                  else: {:cont, acc}
            end)
        end

      _bound ->
        :fail
    end
  end

  # ---------------------------------------------------------------------

  @doc "Deklarierte Attribute eines Moduls (Liste von {name, arity}) oder nil"
  def declared(db, mod), do: Map.get(db, {:attributes, mod})

  @doc """
  `:- attribute Spec` eintragen; das Modul kommt (einmal) in die Liste der
  Attributmodule, deren Hooks beim Binden laufen.
  """
  def declare(db, mod, spec) do
    keys = for {_m, n, ar} <- PrologEx.Builtins.Modules.indicators(spec, mod), do: {n, ar}

    mods = Map.get(db, :attr_modules, [])
    mods = if mod in mods, do: mods, else: mods ++ [mod]
    db |> Map.put({:attributes, mod}, keys) |> Map.put(:attr_modules, mods)
  end

  defp declared!(mod) do
    case declared(PrologEx.current_db(), mod) do
      nil -> Error.existence!("attribute_declaration", a(mod))
      decl -> decl
    end
  end

  @doc false
  # für Bibliotheken in Elixir (clpb): Argument des Attributs name/1 von v
  # im Modul mod, oder nil (ohne die Attributwerte zu kopieren)
  def get_one(v, mod, name, s) do
    v
    |> PrologEx.get_attrs(s)
    |> Map.get(mod, [])
    |> top_items()
    |> Enum.find_value(fn
      {:struct, ^name, [x]} -> x
      _ -> nil
    end)
  end

  @doc false
  # wie put_atts(V, +Att) im Modul mod; v ist eine (attributierte) Variable
  # Die Liste steht immer in Deklarationsreihenfolge (put_atts/2 und
  # put_one/4 sortieren, Entfernen behält die Reihenfolge): ein vorhandenes
  # Attribut wird an seiner Stelle ersetzt, nur ein neues einsortiert
  def put_one(s, v, mod, att) do
    decl = declared!(mod)
    k = PrologEx.Compiler.key(att)
    items = v |> PrologEx.get_attrs(s) |> Map.get(mod, []) |> top_items()

    case replace_key(items, k, att) do
      {:ok, items} ->
        PrologEx.put_attr(s, v, mod, list(items))

      :none ->
        items
        |> Enum.map(&{PrologEx.Compiler.key(&1), &1})
        |> List.keystore(k, 0, {k, att})
        |> Enum.sort_by(fn {k, _} -> Enum.find_index(decl, &(&1 == k)) end)
        |> Enum.map(&elem(&1, 1))
        |> then(&PrologEx.put_attr(s, v, mod, list(&1)))
    end
  end

  defp replace_key([], _k, _att), do: :none

  defp replace_key([h | t], k, att) do
    if PrologEx.Compiler.key(h) == k do
      {:ok, [att | t]}
    else
      case replace_key(t, k, att) do
        {:ok, t} -> {:ok, [h | t]}
        :none -> :none
      end
    end
  end

  @doc false
  # wie put_atts(V, -name(_)) im Modul mod
  def del_one(s, v, mod, name) do
    items = v |> PrologEx.get_attrs(s) |> Map.get(mod, []) |> top_items()
    kept = Enum.reject(items, &match?({:struct, ^name, [_]}, &1))

    if length(kept) == length(items),
      do: s,
      else: PrologEx.put_attr(s, v, mod, list(kept))
  end

  defp top_items(l) do
    case PrologEx.unmark_top(l) do
      [h | t] -> [PrologEx.unmark_top(h) | top_items(t)]
      _ -> []
    end
  end

  # vorhandene Attribute im Modul: [{key, term}]
  defp current(v, mod, s) do
    v
    |> PrologEx.get_attrs(s)
    |> Map.get(mod, [])
    |> top_items()
    |> Enum.map(fn att -> {PrologEx.Compiler.key(att), att} end)
  end

  defp specs(spec, s) do
    case PrologEx.unmark_top(PrologEx.Store.walk(spec, s)) do
      [] -> []
      [h | t] -> specs(h, s) ++ specs(t, s)
      {:struct, "+", [att]} -> [{:+, PrologEx.Store.walk(att, s)}]
      {:struct, "-", [att]} -> [{:-, PrologEx.Store.walk(att, s)}]
      {:var, _} -> Error.instantiation!()
      att -> [{:+, att}]
    end
  end

  defp key!(att, decl, mod) do
    k =
      case att do
        {:var, _} -> Error.instantiation!()
        n when is_number(n) -> Error.type!("callable", n)
        t -> PrologEx.Compiler.key(t)
      end

    if k in decl,
      do: k,
      else: Error.existence!("attribute", mk(":", [a(mod), PrologEx.Error.indicator(k)]))
  end
end
