defmodule PrologEx.Listing do
  @moduledoc """
  `listing/0,1`: gibt Prädikate aus ihrem gespeicherten Quelltext aus.

  Wie `portray_clause/1`: gequotet, mit Operatoren, ein Teilziel je Zeile,
  Wenn-dann-sonst und Disjunktionen eingerückt:

      app([], L, L).
      app([H|T], L, [H|R]) :-
          app(T, L, R).
      max(X, Y, Z) :-
          (   X >= Y
          ->  Z = X
          ;   Z = Y
          ).
  """

  import PrologEx, only: [unmark: 1]

  @doc """
  spec: `:all` (Prädikate des Moduls), ein Atom (alle Stelligkeiten),
  `Name/Stelligkeit`, jeweils auch als `M:Spec`. Bei einem Atom oder
  `Name/Stelligkeit` werden auch sichtbare Bibliotheksprädikate gezeigt, die
  nicht im Modul überdeckt sind: in Prolog geschriebene mit Quelltext, in
  Elixir geschriebene als Hinweis. Prädikate anderer Module als user
  erscheinen qualifiziert (`m:foo(X) :- ...`).
  """
  def listing(db, spec, module \\ "user") do
    {module, spec} = strip(spec, module)

    own = for {{^module, n, ar} = key, pred} <- db, matches?({n, ar}, spec), do: {key, pred}

    library =
      if spec == :all do
        []
      else
        # sichtbare Bibliotheksprädikate (importiert, user, system)
        for lib <- ["system" | PrologEx.Builtins.library_modules()],
            {n, ar} <- PrologEx.Builtins.keys(lib),
            matches?({n, ar}, spec),
            not Map.has_key?(db, {module, n, ar}),
            visible_from?(db, module, lib, n, ar),
            do: {lib, n, ar}
      end

    library = with_helpers(library)

    lib_entries =
      Enum.map(library, fn {m, n, ar} = k ->
        {k, {:builtin, PrologEx.Builtins.lookup(m, n, ar)}}
      end)

    Enum.sort_by(own, fn {key, _} -> key end)
    |> Enum.map(fn {key, pred} ->
      if PrologEx.dynamic?(db, key), do: {key, {:dynamic, pred}}, else: {key, pred}
    end)
    |> Kernel.++(lib_entries)
    |> Enum.map_join("\n", fn {key, pred} -> pred_text(key, pred) end)
  end

  defp strip({:struct, ":", [{:atom, m}, spec]}, _module), do: strip(spec, m)
  defp strip(spec, module), do: {module, spec}

  defp visible_from?(db, module, lib, n, ar) do
    case PrologEx.locate(db, module, n, ar) do
      {:builtin, ^lib, _} -> true
      _ -> String.starts_with?(n, "$")
    end
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
    new = for k <- called_helpers(key), not MapSet.member?(seen, k), uniq: true, do: k

    helper_closure(new ++ rest, MapSet.union(seen, MapSet.new(new)))
  end

  defp called_helpers({m, n, ar}) do
    case PrologEx.Builtins.lookup(m, n, ar) do
      {:prolog, pred, _} ->
        for {_head, body} <- PrologEx.pred_source(pred),
            g <- called_goals(unmark(body)),
            {hn, har} <- [goal_key(g)],
            helper?({m, hn, har}) and PrologEx.Builtins.lookup(m, hn, har) != nil,
            do: {m, hn, har}

      _ ->
        for {hn, har} <- PrologEx.Builtins.helpers(m, n, ar), do: {m, hn, har}
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
  defp goal_key(_), do: {"", -1}

  defp helper?({_m, name, _}), do: String.starts_with?(name, "$")

  defp matches?({_name, _arity}, :all), do: true
  defp matches?({name, _}, {:atom, name}), do: true
  defp matches?({name, arity}, {:struct, "/", [{:atom, name}, arity]}), do: true
  defp matches?(_, _), do: false

  defp pred_text(key, {:builtin, {:prolog, pred, _}}), do: pred_text(key, pred)

  defp pred_text({m, name, arity}, {:builtin, {_kind, fun, _}}) do
    mod = fun |> Function.info() |> Keyword.fetch!(:module) |> inspect()
    "% #{prefix(m)}#{name}/#{arity}: eingebaut, in Elixir realisiert (#{mod})\n"
  end

  defp pred_text({m, name, arity} = key, {:dynamic, pred}) do
    case PrologEx.pred_source(pred) do
      [] -> ":- dynamic #{prefix(m)}#{name}/#{arity}.\n"
      _ -> ":- dynamic #{prefix(m)}#{name}/#{arity}.\n\n" <> pred_text(key, pred)
    end
  end

  defp pred_text({m, _, _}, pred),
    do: Enum.map_join(PrologEx.pred_source(pred), "", &(prefix(m) <> clause_text(&1)))

  defp prefix(m) when m in ["user", "system"], do: ""
  defp prefix(m), do: m <> ":"

  @doc false
  def clause_text({head, body}) do
    case unmark(body) do
      {:atom, "true"} -> q(head, 1199) <> ".\n"
      b -> q(head, 1199) <> " :-\n" <> body(b, "    ") <> ".\n"
    end
  end

  # Rumpf ab Einrückung ind; die erste Zeile beginnt mit ind
  defp body({:struct, ",", [a, b]}, ind), do: body(a, ind) <> ",\n" <> body(b, ind)

  defp body({:struct, op, [_, _]} = g, ind) when op in [";", "->", "*->"] do
    branches(g)
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {{prefix, goal}, i} ->
      lead = if i == 0, do: "(   ", else: prefix
      ind <> lead <> String.trim_leading(body(goal, ind <> "    "))
    end)
    |> Kernel.<>("\n" <> ind <> ")")
  end

  defp body(g, ind), do: ind <> q(g, 999)

  # (C1 -> T1 ; C2 -> T2 ; E) als [{"(   ", C1}, {"->  ", T1}, {";   ", C2}, ...]
  defp branches({:struct, ";", [a, b]}), do: branch(a) ++ alt(b)
  defp branches(g), do: branch(g)

  defp alt({:struct, ";", [a, b]}), do: mark(branch(a), ";   ") ++ alt(b)
  defp alt(g), do: mark(branch(g), ";   ")

  defp branch({:struct, op, [c, t]}) when op in ["->", "*->"],
    do: [{"(   ", c}, {String.pad_trailing(op, 4), t}]

  defp branch(g), do: [{"(   ", g}]

  defp mark([{_, g} | rest], prefix), do: [{prefix, g} | rest]

  # wie portray_clause: gequotet, Leerzeichen nach Kommas
  defp q(t, priority),
    do:
      PrologEx.Writer.format(
        t,
        PrologEx.Writer.answer_opts() ++ [priority: priority, numbervars: true]
      )
end
