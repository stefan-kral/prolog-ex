defmodule PrologEx.ClpzListing do
  @moduledoc """
  clpz_listing/0,1: welche Teile von library(clpz) in PrologEx in Elixir
  laufen und welche in Prolog – abgelesen aus den geladenen Klauseln, nicht
  aus einer Liste, die veralten könnte.

  Je Prädikat des Moduls clpz eine von fünf Stufen:

    * in Elixir: clpz.pl ersetzt Aufrufe beim Laden durch ein Builtin
      (`goal_expansion(fd_get(A,B,C), '$clpz_fd_get'(A,B,C))`), oder jede
      Klausel ruft nur ein `'$clpz_…'`-Builtin;
    * Abkürzer: die erste Klausel versucht ein Builtin und schneidet ab,
      sonst laufen die Klauseln des Originals (clpz_neq/2, parse_clpz/2);
    * Prüfungen in Prolog, der Rest in Elixir: das letzte Ziel ist ein
      Builtin mit Original (all_distinct/1 nach den Typprüfungen);
    * Prolog mit Elixir-Bausteinen: Prolog-Logik, die Builtins ruft
      (label/5 mit '$clpz_fd_get'/3);
    * Prolog.

  Ein Rückfall aufs Original: zum Prädikat steht `name_ref` daneben, oder
  zu einem gerufenen Builtin `'$clpz_X'` ein `X_ref` – das läuft, wenn das
  Builtin aufgibt.

  Propagatoren (die Fälle von `run_propagator//2`): in Elixir sind die,
  die `activate_propagator//1` dort rechnet (`ClpzPrims.ported/0`); fällt
  einer zurück, rechnet `run_propagator//2` des Originals.

  `clpz_listing/0`: Übersicht – die Prädikate in Elixir und mit Abkürzer,
  alle Propagatoren, dazu die Zahlen. `clpz_listing(Name)` bzw.
  `clpz_listing(Name/Arität)`: ein Prädikat (jede Arität) oder ein
  Propagator im Einzelnen, mit Bausteinen und Originalen.
  """

  @mod "clpz"

  @doc "Text (spec: :all, {:atom, name} oder Name/Arität)"
  def listing(db, spec) do
    if not Map.has_key?(db, {@mod, "run_propagator", 4}) do
      "% library(clpz) ist nicht geladen\n"
    else
      ge = expansions(db)
      infos = for {n, a} <- preds(db), pick?(spec, n, a), do: info(db, ge, n, a)
      props = propagators(db)

      case spec do
        :all -> overview(infos, props)
        _ -> detail(infos, for(p <- props, pick?(spec, p, nil), do: p))
      end
    end
  end

  defp overview(infos, props) do
    by = Enum.group_by(infos, & &1.kind)
    count = &length(Map.get(by, &1, []))
    ported = Enum.count(props, &(&1 in PrologEx.Builtins.ClpzPrims.ported()))

    "% library(clpz): #{length(infos)} Prädikate – #{count.(:elixir)} in Elixir, " <>
      "#{count.(:shortcut)} mit Abkürzer, #{count.(:tail)} mit dem Rest in Elixir, " <>
      "#{count.(:mixed)} Prolog mit " <>
      "Elixir-Bausteinen, #{count.(:prolog)} nur Prolog\n" <>
      "% (clpz_listing(Name) zeigt jedes Prädikat und jeden Propagator im Einzelnen)\n" <>
      "%\n% In Elixir (beim Laden ersetzt oder ganz an ein Builtin delegiert):\n" <>
      table(for i <- Map.get(by, :elixir, []), do: {i.pi, rueck(i), short(i)}) <>
      "%\n% Abkürzer in Elixir vor den Klauseln des Originals:\n" <>
      table(for i <- Map.get(by, :shortcut, []), do: {i.pi, rueck(i), short(i)}) <>
      "%\n% Prüfungen in Prolog, der Rest in Elixir:\n" <>
      table(for i <- Map.get(by, :tail, []), do: {i.pi, rueck(i), short(i)}) <>
      "%\n% Propagatoren (run_propagator//2): #{length(props)}, davon #{ported} in Elixir\n" <>
      table(Enum.map(props, &prop_row/1))
  end

  defp detail(infos, props) do
    case {infos, props} do
      {[], []} ->
        "% nichts dergleichen in library(clpz)\n"

      _ ->
        rows =
          for i <- infos do
            "% #{i.pi}: #{kind_text(i.kind)}\n" <>
              if(i.ge, do: "%     beim Laden ersetzt durch #{i.ge}\n", else: "") <>
              Enum.map_join(i.builtins, "", fn {b, orig} ->
                "%     ruft #{b}" <> if(orig, do: " (Original #{orig})", else: "") <> "\n"
              end) <>
              if(i.ref, do: "%     Original #{i.ref}\n", else: "")
          end

        prow =
          for p <- props do
            {_, st, d} = prop_row(p)
            "% Propagator #{p}: #{st} (#{d})\n"
          end

        Enum.join(rows ++ prow)
    end
  end

  defp kind_text(:elixir), do: "in Elixir"
  defp kind_text(:shortcut), do: "Abkürzer in Elixir, sonst die Klauseln des Originals"
  defp kind_text(:tail), do: "Prüfungen in Prolog, der Rest in Elixir"
  defp kind_text(:mixed), do: "Prolog mit Elixir-Bausteinen"
  defp kind_text(:prolog), do: "Prolog"

  defp rueck(i) do
    if i.ref || Enum.any?(i.builtins, &elem(&1, 1)), do: "mit Rückfall", else: ""
  end

  defp short(i) do
    origs = for {_, o} <- i.builtins, o, do: o
    origs = if i.ref, do: [i.ref | origs], else: origs

    via =
      cond do
        i.ge -> "→ " <> i.ge
        true -> i.builtins |> Enum.map(&elem(&1, 0)) |> Enum.join(", ")
      end

    via <> if(origs == [], do: "", else: "; Original " <> Enum.join(Enum.uniq(origs), ", "))
  end

  # die Prädikate von clpz ohne die Originale (name_ref) – die stehen bei
  # ihrem Prädikat
  defp preds(db) do
    for {{@mod, n, a}, _} <- db,
        is_binary(n),
        not String.ends_with?(n, "_ref"),
        do: {n, a},
        into: MapSet.new()
  end

  defp pick?(:all, _, _), do: true
  defp pick?({:atom, n}, n, _), do: true
  defp pick?({:struct, "/", [{:atom, n}, a]}, n, a), do: true
  defp pick?(_, _, _), do: false

  # %{pi, kind, ge, builtins: [{"'$clpz_x'/k", Original oder nil}], ref}
  defp info(db, ge, n, a) do
    bodies = Enum.map(entries(db, n, a), &elem(elem(&1, 1), 1))
    calls = Enum.map(bodies, &goals/1)

    builtins =
      calls
      |> List.flatten()
      |> Enum.filter(fn {gn, _} -> String.starts_with?(gn, "$clpz_") end)
      |> Enum.uniq()
      |> Enum.map(fn {"$clpz_" <> base = gn, ga} ->
        {"'#{gn}'/#{ga}", original(db, base, ga)}
      end)

    via_ge = Map.get(ge, {n, a})
    ref = if Map.has_key?(db, {@mod, n <> "_ref", a}), do: "#{n}_ref/#{a}"

    kind =
      cond do
        via_ge != nil -> :elixir
        bodies != [] and Enum.all?(calls, &delegation?/1) -> :elixir
        shortcut?(calls) -> :shortcut
        bodies != [] and Enum.all?(calls, &tail_post?(&1, db)) -> :tail
        builtins != [] -> :mixed
        true -> :prolog
      end

    %{pi: "#{n}/#{a}", kind: kind, ge: via_ge, builtins: builtins, ref: ref}
  end

  # das Original zum Builtin '$clpz_X'/k: X_ref/k, sonst X_ref anderer Arität
  defp original(db, base, k) do
    name = base <> "_ref"

    if Map.has_key?(db, {@mod, name, k}) do
      "#{name}/#{k}"
    else
      Enum.find_value(db, fn
        {{@mod, ^name, a}, _} -> "#{name}/#{a}"
        _ -> nil
      end)
    end
  end

  # davor nur Prüfungen und Vorbereitungen, dann genau ein Builtin mit
  # Original (all_distinct/1)
  @checks ~w(must_be can_be fd_must_be_list fd_variable maplist = is_list)

  defp tail_post?(goals, db) do
    case Enum.reverse(goals) do
      [{"$clpz_" <> base, k} | pre] ->
        original(db, base, k) != nil and Enum.all?(pre, fn {gn, _} -> gn in @checks end)

      _ ->
        false
    end
  end

  # Rumpf ein einziges Builtin (höchstens mit Cut)
  defp delegation?(goals) do
    case Enum.reject(goals, &(&1 == {"!", 0})) do
      [{"$clpz_" <> _, _}] -> true
      _ -> false
    end
  end

  # erste Klausel: Builtin(s), dann Cut – und weitere Klauseln
  defp shortcut?([first, _ | _]) do
    case Enum.split_while(first, &(&1 != {"!", 0})) do
      {[_ | _] = pre, [{"!", 0} | _]} ->
        Enum.any?(pre, fn {gn, _} -> String.starts_with?(gn, "$clpz_") end)

      _ ->
        false
    end
  end

  defp shortcut?(_), do: false

  defp prop_row(p) do
    if p in PrologEx.Builtins.ClpzPrims.ported(),
      do: {p, "Elixir", "fällt zurück auf run_propagator//2 des Originals"},
      else: {p, "Prolog", "run_propagator//2"}
  end

  # goal_expansion(Kopf, Ersatz) von clpz: %{{n, a} => "Ersatz/k"}
  defp expansions(db) do
    for e <- entries(db, "goal_expansion", 2),
        {head, _} = elem(e, 1),
        {_, "goal_expansion", [h, r]} <- [s(head)],
        {hn, ha} <- [functor(h)],
        is_binary(hn),
        into: %{} do
      {{hn, ha}, describe(r)}
    end
  end

  defp describe(r) do
    case functor(r) do
      {"$" <> _ = n, a} -> "'#{n}'/#{a}"
      {n, a} when is_binary(n) -> "#{n}/#{a} (umgeschrieben)"
      _ -> "(umgeschrieben)"
    end
  end

  defp entries(db, n, a) do
    case db[{@mod, n, a}] do
      nil ->
        []

      p ->
        p |> PrologEx.materialize() |> PrologEx.pred_entries()
    end
  end

  # Ziele eines Rumpfs (durch Kontrollkonstrukte und M:G hindurch)
  defp goals(t) do
    case s(t) do
      {_, op, [x, y]} when op in [",", ";", "->", "*->"] -> goals(x) ++ goals(y)
      {_, "\\+", [x]} -> goals(x)
      {_, ":", [_, g]} -> goals(g)
      _ -> List.wrap(goal(t))
    end
  end

  defp goal(t) do
    case functor(t) do
      {n, a} when is_binary(n) -> {n, a}
      _ -> nil
    end
  end

  defp functor(t) do
    case s(t) do
      {_, n, args} -> {n, length(args)}
      {:atom, n} -> {n, 0}
      _ -> nil
    end
  end

  defp s({tag, n, args}) when tag in [:struct, :gstruct], do: {:struct, n, args}
  defp s({:atom, _} = a), do: a
  defp s(_), do: nil

  # die Propagatoren: erste Argumentstelle der Klauseln von run_propagator//2
  defp propagators(db) do
    entries(db, "run_propagator", 4)
    |> Enum.flat_map(fn e ->
      case s(elem(elem(e, 1), 0)) do
        {_, "run_propagator", [p | _]} ->
          case functor(p) do
            {n, _} when is_binary(n) -> [n]
            _ -> []
          end

        _ ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp table(rows) do
    rows = Enum.sort(rows)
    w1 = rows |> Enum.map(&String.length(elem(&1, 0))) |> Enum.max(fn -> 0 end)
    w2 = rows |> Enum.map(&String.length(elem(&1, 1))) |> Enum.max(fn -> 0 end)

    for {a, b, c} <- rows, into: "" do
      String.trim_trailing("% #{String.pad_trailing(a, w1)}  #{String.pad_trailing(b, w2)}  #{c}") <>
        "\n"
    end
  end
end
