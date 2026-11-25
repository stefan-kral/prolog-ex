defmodule PrologEx.LibraryIndex do
  @moduledoc """
  Verzeichnis der Bibliotheken: welche exportiert ein Prädikat
  (`libraries/2`), welche einen Operator (`op_libraries/1`), und welche
  nimmt der Toplevel, um es selbst zu importieren (`choice/2`).

  Aus den Exporten der Bibliotheken in Elixir (`PrologEx.Builtins`) und
  den Köpfen (`:- module(Name, Exporte)`) der Bibliotheken in Prolog
  (`priv/library/**/*.pl`; in Unterordnern heißt die Bibliothek nach dem
  Pfad: `dcg/basics`). Nichtterminale `Name//N` zählen als `Name/(N+2)`.
  Gebaut beim ersten Gebrauch (ein Fehler, ein Hinweis), dann in
  `:persistent_term` – auf dem Weg einer gewöhnlichen Anfrage kostet es
  nichts.

  `choice/2`: eine Bibliothek, wenn es genau eine gibt, nachdem
  Weitergaben (`lists` gibt `maplist/3` aus `apply` weiter, `swi` fast
  alles) auf ihre Quelle zurückgeführt und Alternativen beiseitegelassen
  sind, die man bewusst wählt (`reif_pl` neben `reif`, `wgraphs` neben
  `ugraphs`, ...); sonst `nil` – dann nennt der Hinweis alle.
  """

  alias PrologEx.Builtins

  @key {__MODULE__, :index}

  # Bibliotheken, die eine andere Fassung derselben Prädikate sind oder sie
  # nur weitergeben: nie von selbst gewählt (im Hinweis genannt)
  @alternatives ~w(swi reif_pl lambda_pl yall_pl memberd_pl linda/client linda/server)

  @doc "Bibliotheken, die name/arity exportieren (sortiert; [] wenn keine)"
  def libraries(name, arity), do: Map.get(index().preds, {name, arity}, [])

  @doc "Bibliotheken, die den Operator name exportieren"
  def op_libraries(name), do: Map.get(index().ops, name, [])

  @doc """
  Die Bibliothek, aus der name/arity von selbst importiert werden darf,
  oder nil (keine oder mehrere echte Kandidaten)
  """
  def choice(name, arity) do
    case libraries(name, arity) do
      [] ->
        nil

      [lib] ->
        lib

      libs ->
        # Weitergaben zurück auf die Quelle; Heimat-Bibliotheken eines
        # eingebauten Prädikats (die Quelle ist system) bleiben
        home = Builtins.home(name, arity)

        sources =
          libs
          |> Enum.map(fn lib ->
            case Builtins.source(lib, name, arity) do
              "system" -> home || lib
              src -> if src in libs, do: src, else: lib
            end
          end)
          |> Enum.uniq()

        case sources -- @alternatives do
          [lib] -> lib
          [] when length(sources) == 1 -> hd(sources)
          _ -> nil
        end
    end
  end

  @doc "Das ganze Verzeichnis (für Tests): %{preds: ..., ops: ...}"
  def index do
    case :persistent_term.get(@key, nil) do
      nil ->
        idx = build()
        :persistent_term.put(@key, idx)
        idx

      idx ->
        idx
    end
  end

  defp build do
    elixir = for m <- Builtins.library_names(), m != "system", do: {m, elixir_exports(m)}
    names = MapSet.new(elixir, &elem(&1, 0))

    prolog =
      for {spec, exports} <- prolog_libraries(),
          # eine Bibliothek in Elixir gleichen Namens gilt (use_module lädt sie)
          not MapSet.member?(names, spec),
          do: {spec, exports}

    Enum.reduce(elixir ++ prolog, %{preds: %{}, ops: %{}}, fn {lib, {preds, ops}}, acc ->
      acc
      |> add(:preds, preds, lib)
      |> add(:ops, ops, lib)
    end)
    |> Map.update!(:preds, &Map.new(&1, fn {k, v} -> {k, Enum.sort(Enum.uniq(v))} end))
    |> Map.update!(:ops, &Map.new(&1, fn {k, v} -> {k, Enum.sort(Enum.uniq(v))} end))
  end

  defp add(acc, kind, keys, lib) do
    Map.update!(acc, kind, fn m ->
      Enum.reduce(keys, m, fn k, m -> Map.update(m, k, [lib], &[lib | &1]) end)
    end)
  end

  defp elixir_exports(m) do
    preds = Builtins.exports(m) |> Enum.to_list()
    ops = for {_p, _t, name} <- Builtins.ops(m), do: name
    {preds, ops}
  end

  # {Bibliothek, {Prädikate, Operatoren}} je Datei mit :- module/2
  defp prolog_libraries do
    dir = Path.join(:code.priv_dir(:prolog_ex), "library")

    for f <- Path.wildcard(Path.join(dir, "**/*.pl")),
        {:ok, exports} <- [header(f)] do
      {f |> Path.relative_to(dir) |> Path.rootname(), exports}
    end
  end

  defp header(file) do
    with {:ok, text} <- File.read(file),
         {:term, t, _} <- safe_read(text),
         {:struct, ":-", [{:struct, "module", [_name, exports]}]} when is_list(exports) <-
           PrologEx.unmark(t) do
      {:ok, Enum.reduce(exports, {[], []}, &export/2)}
    else
      _ -> :none
    end
  end

  defp safe_read(text) do
    PrologEx.Parser.read_one(text)
  rescue
    _ -> :none
  end

  defp export({:struct, "/", [{:atom, n}, a]}, {ps, os}) when is_integer(a),
    do: {[{n, a} | ps], os}

  defp export({:struct, "//", [{:atom, n}, a]}, {ps, os}) when is_integer(a),
    do: {[{n, a + 2} | ps], os}

  defp export({:struct, "op", [_p, _t, {:atom, n}]}, {ps, os}), do: {ps, [n | os]}

  defp export({:struct, "op", [_p, _t, names]}, {ps, os}) when is_list(names),
    do: {ps, for({:atom, n} <- names, do: n) ++ os}

  defp export(_, acc), do: acc
end
