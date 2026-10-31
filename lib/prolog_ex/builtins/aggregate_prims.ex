defmodule PrologEx.Builtins.AggregatePrims do
  @moduledoc """
  Interne Prädikate für `library(aggregate)` (priv/library/aggregate.pl),
  Kern in `PrologEx.Aggregate`:

    * `'$aggregate_check'(+Template)` – wirft bei ungültigem Template
    * `'$aggregate_list'(+Template, +Instanzen, -Ergebnis)` – faltet eine
      Liste von Template-Instanzen (aus bagof/setof/findall); scheitert
      bei min/max ohne Instanz

  `'$aggregate_all'(+Template, :Ziel, -Ergebnis)` führt die Maschine
  selbst aus (Faltung über die Lösungen, ohne sie zu sammeln).
  """
  use PrologEx.Builtin
  alias PrologEx.Aggregate

  defbuiltin "$aggregate_check", [t] do
    _ = Aggregate.spec!(t, subst())
    :ok
  end

  defbuiltin "$aggregate_list", [t, items, r] do
    s = subst()
    spec = Aggregate.spec!(t, s)

    # die Instanzen sind schon Kopien (bagof & Co.): nicht noch einmal
    acc =
      Enum.reduce(PrologEx.Builtins.Lists.items(items, s), Aggregate.init(spec), fn inst, acc ->
        Aggregate.step(spec, inst, s, acc, &PrologEx.resolve/2)
      end)

    case Aggregate.result(spec, acc) do
      {:ok, v} -> {:unify, [{r, v}]}
      :fail -> :fail
    end
  end
end
