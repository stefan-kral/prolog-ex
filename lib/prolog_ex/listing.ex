defmodule PrologEx.Listing do
  @moduledoc """
  `listing/0,1`: gibt Prädikate aus ihrem gespeicherten Quelltext aus.

  Vorläufig ohne Operator-Schreibweise in den Teilzielen (die kommt mit dem
  Writer); Klauselstruktur und Konjunktionen werden aber lesbar gesetzt:

      app([], L, L).
      app([H|T], L, [H|R]) :-
          app(T, L, R).
  """

  import PrologEx, only: [format: 1, unmark: 1]

  @doc "spec: `:all`, ein Atom (alle Stelligkeiten) oder `Name/Stelligkeit`"
  def listing(db, spec) do
    db
    |> Enum.filter(fn {key, _} -> matches?(key, spec) end)
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.map_join("\n", fn {key, pred} -> pred_text(key, pred) end)
  end

  defp matches?({_name, _arity}, :all), do: true
  defp matches?({name, _}, {:atom, name}), do: true
  defp matches?({name, arity}, {:struct, "/", [{:atom, name}, arity]}), do: true
  defp matches?(_, _), do: false

  defp pred_text({name, arity}, {:pred, _, _, _, []}),
    do: ":- dynamic #{name}/#{arity}.\n"

  defp pred_text(_key, {:pred, _, _, _, source}),
    do: Enum.map_join(source, "", &clause_text/1)

  @doc false
  def clause_text({head, body}) do
    case goals(unmark(body)) do
      [] -> format(head) <> ".\n"
      gs -> format(head) <> " :-\n" <> Enum.map_join(gs, ",\n", &("    " <> format(&1))) <> ".\n"
    end
  end

  defp goals({:atom, "true"}), do: []
  defp goals({:struct, ",", [a, b]}), do: goals(a) ++ goals(b)
  defp goals(g), do: [g]
end
