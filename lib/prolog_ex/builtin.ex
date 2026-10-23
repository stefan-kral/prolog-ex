defmodule PrologEx.Builtin do
  @moduledoc """
  Schnittstelle für Builtin-Prädikate in Elixir.

      defmodule PrologEx.Builtins.Atoms do
        use PrologEx.Builtin

        # deterministisch
        defbuiltin "atom_length", [x, len] do
          case deref(x) do
            {:atom, name} -> {:unify, [{len, String.length(name)}]}
            {:var, _} -> PrologEx.Error.instantiation!()
          end
        end

        # nichtdeterministisch: Liste oder Stream von Ergebnissen
        defbuiltin "between", [lo, hi, x], nondet: true do
          for i <- deref(lo)..deref(hi)//1, do: {:unify, [{x, i}]}
        end
      end

  Das Modul muss in `PrologEx.Builtins` (Liste `@modules`) eingetragen sein.

  ## Ergebnis eines Builtins

    * `:ok` / `true`              – Erfolg ohne Bindungen
    * `:fail` / `false`           – Fehlschlag
    * `{:unify, [{a, b}, ...]}`   – Erfolg, wenn alle Paare unifizieren
    * `{:call, ziel}`             – weiter mit einem Prolog-Ziel (Cut darin
                                    ist lokal, wie bei call/1)

  Mit `nondet: true` liefert der Rumpf eine Aufzählung solcher Ergebnisse.
  Jedes Element ist eine Lösung; beim Backtracking wird das nächste geholt.

    * Liste `[r1, r2, ...]` – für das letzte Element kein Choice Point
    * lazy Liste `[r | fn -> rest end]` – der Rest (wieder eine Liste oder
      lazy Liste) wird erst beim Backtracking berechnet. So entscheidet das
      Builtin selbst, wann die letzte Lösung `[r]` kommt: lazy UND ohne
      übrigen Choice Point. Das ist die schnellste Form.
    * Stream, Range, ... – lazy, auch unendlich; nach der letzten Lösung
      bleibt aber ein Choice Point, bis erneut gefragt wird

  Beispiel:

      defbuiltin "$repeat", [n], nondet: true do
        repeat_n(deref(n))
      end

      defp repeat_n(1), do: [:ok]
      defp repeat_n(n), do: [:ok | fn -> repeat_n(n - 1) end]

  ## Hilfen im Rumpf

    * `deref(t)`   – Variable bis zum Wert verfolgen (oberste Ebene)
    * `resolve(t)` – Term vollständig auflösen (ohne Ground-Markierungen)
    * `db()`       – die aktuelle Datenbank
    * `subst()`    – die aktuelle Substitution
    * `fresh_var()` – eine neue, unbenutzte Variable
    * importiert: `a/1`, `v/1`, `mk/2`, `list/1,2`, `cons/2`, `uncons/1`,
      `format/1` aus `PrologEx`

  Fehler: über `PrologEx.Error`, z. B. `PrologEx.Error.type!("list", t)`
  oder `PrologEx.Error.instantiation!()`. Das wirft den ISO-Fehlerterm
  `error(type_error(list, T), _)`, den `catch/3` fangen kann. Variablen im
  Kulprit dürfen gebunden sein, die Maschine löst ihn auf.

  ## Optionen

    * `nondet: true` – siehe oben
    * `helpers: [{"$name", stelligkeit}, ...]` – Hilfsprädikate, die das
      Builtin über `{:call, ...}` aufruft; `listing` zeigt sie mit an
    * `module: "lists"` – Prolog-Modul dieses Builtins (Standard: das bei
      `use PrologEx.Builtin, module: ...` angegebene, sonst `"system"`).
      Ein `{:call, ziel}` aus einem system-Builtin läuft im Kontextmodul
      des Aufrufers, aus einem Bibliotheks-Builtin in dessen Modul.
    * `protected: false` – das Prädikat darf vom Benutzer neu definiert
      werden (Bibliotheksprädikate wie append/3). Standard: geschützt, eine
      Klausel dafür in consult ergibt `permission_error`.
  """

  defmacro __using__(opts) do
    pmod = Keyword.get(opts, :module, "system")

    quote do
      import PrologEx.Builtin,
        only: [
          defbuiltin: 3,
          defbuiltin: 4,
          deref: 1,
          resolve: 1,
          db: 0,
          subst: 0,
          context_module: 0
        ]

      @prolog_module unquote(pmod)
      @doc false
      def __prolog_module__, do: @prolog_module

      import PrologEx,
        only: [a: 1, v: 1, mk: 2, list: 1, list: 2, cons: 2, uncons: 1, format: 1]

      import PrologEx.Builtin.Helpers

      Module.register_attribute(__MODULE__, :prolog_builtins, accumulate: true)
      @before_compile PrologEx.Builtin
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __builtins__, do: @prolog_builtins
    end
  end

  # defbuiltin "n", [a, b] do ... end                 (3 Argumente)
  # defbuiltin "n", [a, b], nondet: true do ... end   (4 Argumente)
  defmacro defbuiltin(name, args, do: body), do: define(name, args, [], body)
  defmacro defbuiltin(name, args, opts, do: body), do: define(name, args, opts, body)

  defp define(name, args, opts, body) do
    unless is_binary(name),
      do: raise(ArgumentError, "defbuiltin: Name muss ein String-Literal sein")

    arity = length(args)
    fun = :"bi #{name}/#{arity}"
    kind = if Keyword.get(opts, :nondet, false), do: :nondet, else: :det
    protected = Keyword.get(opts, :protected, true)
    helpers = Keyword.get(opts, :helpers, [])
    pmod = Keyword.get(opts, :module)
    ctx = Macro.var(:ctx, nil)

    quote do
      @prolog_builtins {{unquote(name), unquote(arity)}, unquote(kind),
                        &(__MODULE__.unquote(fun) / 2), unquote(protected), unquote(helpers),
                        unquote(pmod) || @prolog_module}

      @doc false
      def unquote(fun)(unquote(args), unquote(ctx)) do
        _ = unquote(ctx)
        unquote(body)
      end
    end
  end

  defmacro deref(t),
    do: quote(do: PrologEx.walk(unquote(t), var!(ctx).subst))

  defmacro resolve(t),
    do: quote(do: PrologEx.resolve(unquote(t), var!(ctx).subst))

  defmacro db, do: quote(do: var!(ctx).db)

  @doc "Kontextmodul des Aufrufers (für assert, clause, ... ohne M:)"
  defmacro context_module, do: quote(do: var!(ctx).module)
  defmacro subst, do: quote(do: var!(ctx).subst)

  defmodule Helpers do
    @moduledoc false
    def fresh_var, do: {:var, "_B#{System.unique_integer([:positive])}"}
  end
end
