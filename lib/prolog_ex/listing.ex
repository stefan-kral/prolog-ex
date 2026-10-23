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

  @doc """
  spec: `:all` (nur Benutzerprädikate), ein Atom (alle Stelligkeiten) oder
  `Name/Stelligkeit`. Bei einem Atom oder `Name/Stelligkeit` werden auch
  Bibliotheksprädikate gezeigt, die nicht vom Benutzer überdeckt sind: in
  Prolog geschriebene mit Quelltext, in Elixir geschriebene als Hinweis.
  """
  def listing(db, spec) do
    user = Enum.filter(db, fn {key, _} -> matches?(key, spec) end)

    library =
      if spec == :all,
        do: [],
        else: for(key <- PrologEx.Builtins.keys(), matches?(key, spec), do: key)

    library = library |> Enum.reject(&Map.has_key?(db, &1)) |> with_helpers()

    lib_entries = Enum.map(library, &{&1, {:builtin, PrologEx.Builtins.lookup(&1)}})

    Enum.sort_by(user, fn {key, _} -> key end)
    |> Kernel.++(lib_entries)
    |> Enum.map_join("\n", fn {key, pred} -> pred_text(key, pred) end)
  end

  # Gewünschte Bibliotheksprädikate (ohne $-Hilfsprädikate, außer explizit
  # verlangt), danach alle von ihnen – auch indirekt – aufgerufenen
  # Hilfsprädikate ($...), jeweils sortiert
  defp with_helpers(keys) do
    {named, helpers} = Enum.split_with(keys, &(not helper?(&1)))
    named = if named == [], do: helpers, else: named
    found = helper_closure(named, MapSet.new(named))
    Enum.sort(named) ++ (found |> MapSet.difference(MapSet.new(named)) |> Enum.sort())
  end

  defp helper_closure([], seen), do: seen

  defp helper_closure([key | rest], seen) do
    new =
      for k <- called_helpers(key), not MapSet.member?(seen, k), uniq: true, do: k

    helper_closure(new ++ rest, MapSet.union(seen, MapSet.new(new)))
  end

  defp called_helpers(key) do
    case PrologEx.Builtins.lookup(key) do
      {:prolog, {:pred, _, _, _, source}, _} ->
        for {_head, body} <- source,
            g <- called_goals(unmark(body)),
            k = goal_key(g),
            k != nil and helper?(k) and PrologEx.Builtins.lookup(k) != nil,
            do: k

      _ ->
        PrologEx.Builtins.helpers(key)
    end
  end

  # Ziele in Steuerkonstrukten aufsammeln
  defp called_goals({:struct, op, [a, b]}) when op in [",", ";", "->"],
    do: called_goals(a) ++ called_goals(b)

  defp called_goals({:struct, op, [g]}) when op in ["\\+", "not", "call", "time"],
    do: called_goals(g) ++ [{:struct, op, [g]}]

  defp called_goals(g), do: [g]

  defp goal_key({:atom, n}), do: {n, 0}
  defp goal_key({:struct, f, args}), do: {f, length(args)}
  defp goal_key(_), do: nil

  defp helper?({name, _}), do: String.starts_with?(name, "$")

  defp matches?({_name, _arity}, :all), do: true
  defp matches?({name, _}, {:atom, name}), do: true
  defp matches?({name, arity}, {:struct, "/", [{:atom, name}, arity]}), do: true
  defp matches?(_, _), do: false

  defp pred_text(_key, {:builtin, {:prolog, pred, _}}), do: pred_text(nil, pred)

  defp pred_text({name, arity}, {:builtin, {_kind, fun, _}}) do
    mod = fun |> Function.info() |> Keyword.fetch!(:module) |> inspect()
    "% #{name}/#{arity}: eingebaut, in Elixir realisiert (#{mod})\n"
  end

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
