defmodule PrologEx.Builtins do
  @moduledoc """
  Registry aller Builtins. Neue Module mit `use PrologEx.Builtin` hier in
  `@modules` eintragen. Bibliotheksprädikate in Prolog liefert ein Modul
  über `library/0` (Liste von Klauseln); sie werden beim Übersetzen
  kompiliert.

  Die Maschine fragt die Tabelle nur, wenn ein Prädikat NICHT in der
  Benutzer-Datenbank steht – Benutzerprädikate kosten dadurch nichts
  extra, und nicht geschützte Builtins (append/3, ...) lassen sich durch
  eigene Definitionen ersetzen.
  """

  @modules [
    PrologEx.Builtins.Core,
    PrologEx.Builtins.Terms,
    PrologEx.Builtins.Lists,
    PrologEx.Builtins.Order,
    PrologEx.Builtins.System,
    PrologEx.Builtins.Database
  ]

  # Steuerkonstrukte und schnelle Builtins, die die Maschine selbst
  # ausführt (siehe PrologEx.step/4); hier nur für den Schutz in consult.
  @engine ~w(true/0 fail/0 !/0 ,/2 ;/2 ->/2 call/1 call/2 call/3 call/4 call/5 call/6
             call/7 call/8 call_nth/2 findall/3 findall/4
             findnsols/4 findnsols/5 not/1 \\+/1 =/2 is/2 </2 >/2 >=/2 =</2 =:=/2 =\\=/2 time/1)

  @table (for mod <- @modules,
              {key, kind, fun, protected, _helpers} <- mod.__builtins__(),
              into: %{} do
            {key, {kind, fun, protected}}
          end)

  @helpers (for mod <- @modules,
                {key, _, _, _, helpers} <- mod.__builtins__(),
                helpers != [],
                into: %{} do
              {key, helpers}
            end)

  @library (for mod <- @modules,
                function_exported?(mod, :library, 0),
                {key, pred} <- PrologEx.consult(mod.library()),
                into: %{} do
              # nur interne Hilfsprädikate ($...) sind geschützt
              {key, {:prolog, pred, String.starts_with?(elem(key, 0), "$")}}
            end)

  @all Map.merge(@table, @library)

  @protected for({key, {_, _, true}} <- @all, into: MapSet.new(), do: key)
             |> MapSet.union(
               MapSet.new(@engine, fn s ->
                 [n, a] = String.split(s, "/", parts: 2) |> then(fn [n, a] -> [n, a] end)
                 {n, String.to_integer(a)}
               end)
             )

  @doc "`{:det | :nondet, fun, protected?}`, `{:prolog, pred, true}` oder nil"
  def lookup(key), do: Map.get(@all, key)

  @doc "Von einem Elixir-Builtin angegebene Hilfsprädikate (Option helpers:)"
  def helpers(key), do: Map.get(@helpers, key, [])

  @doc "Darf der Benutzer dieses Prädikat nicht definieren?"
  def protected?(key), do: MapSet.member?(@protected, key)

  @doc "Alle Builtins als `{name, stelligkeit}`, sortiert"
  def keys, do: @all |> Map.keys() |> Enum.sort()
end
