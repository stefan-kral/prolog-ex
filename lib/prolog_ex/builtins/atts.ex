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

    case PrologEx.walk(var, s) do
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

    case PrologEx.walk(var, s) do
      {:var, _} = v ->
        decl = declared!(mod)
        present = current(v, mod, s)

        case PrologEx.walk(spec, s) do
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

  # vorhandene Attribute im Modul: [{key, term}]
  defp current(v, mod, s) do
    v
    |> PrologEx.get_attrs(s)
    |> Map.get(mod, [])
    |> PrologEx.unmark()
    |> items()
    |> Enum.map(fn att -> {PrologEx.Compiler.key(att), att} end)
  end

  defp items([]), do: []
  defp items([h | t]), do: [h | items(t)]

  defp specs(spec, s) do
    case PrologEx.unmark_top(PrologEx.walk(spec, s)) do
      [] -> []
      [h | t] -> specs(h, s) ++ specs(t, s)
      {:struct, "+", [att]} -> [{:+, PrologEx.walk(att, s)}]
      {:struct, "-", [att]} -> [{:-, PrologEx.walk(att, s)}]
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
