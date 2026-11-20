defmodule PrologEx.Shell.Complete do
  @moduledoc """
  TAB-Completion für den Zeileneditor des Toplevels (`PrologEx.Shell.Edit`):

    * ein Atom am Wortende: die in `user` sichtbaren Prädikate (eigene,
      importierte, eingebaute; ohne `$`-Hilfsprädikate). Eindeutig: der
      Name, mit `(`, wenn es ihn nur mit Argumenten gibt; mehrdeutig: das
      gemeinsame Stück, beim nächsten TAB die Liste `name/N`
    * nach `library(`: die Bibliotheken, eindeutig mit `)`
    * in einem gequoteten Atom (`['…`, `consult('…`): Dateinamen relativ
      zum aktuellen Verzeichnis, Verzeichnisse mit `/`, Dateien mit `'`

  Die Prädikate legt der Toplevel nach jeder Anfrage in eine ETS-Tabelle
  (`publish/1`), nur wenn sich die Datenbank geändert hat.
  """

  @table :prolog_ex_complete

  @doc false
  def init do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:named_table, :public, read_concurrency: true])

    :ok
  end

  @doc "Sichtbare Prädikate für die Completion ablegen (nach jeder Anfrage)"
  def publish(db) do
    with true <- :ets.whereis(@table) != :undefined,
         false <- same_db?(db) do
      Process.put(:prolog_complete_db, db)
      :ets.insert(@table, {:preds, visible_preds(db)})
    end

    :ok
  end

  defp same_db?(db) do
    case Process.get(:prolog_complete_db) do
      nil -> false
      old -> :erts_debug.same(old, db)
    end
  end

  @doc false
  def visible_preds(db) do
    keys = Map.keys(db)
    local = for {"user", n, ar} <- keys, do: {n, ar}
    imported = for {:import, "user", n, ar} <- keys, do: {n, ar}

    sys =
      for {n, ar} <- PrologEx.Builtins.system_keys(),
          PrologEx.locate(db, "user", n, ar) != :none,
          do: {n, ar}

    for {n, _} = k <- local ++ imported ++ sys, plain?(n), uniq: true, do: k
  end

  defp plain?(<<c, _::binary>>) when c in ?a..?z, do: true
  defp plain?(_), do: false

  @doc false
  # Text vor dem Cursor, umgekehrt: {:yes, Einfügen, []} oder
  # {:no, [], Treffer} (Rückgabe wie bei expand_fun der BEAM)
  def expand(before_rev) do
    before = before_rev |> Enum.reverse() |> List.to_string()

    cond do
      quoted?(before) ->
        [_, path] = Regex.run(~r/'([^']*)$/u, before)
        files(path)

      m = Regex.run(~r/library\(([a-z0-9_\/]*)$/, before) ->
        complete(Enum.at(m, 1), libraries(), ")", & &1)

      m = Regex.run(~r/(?:^|[^A-Za-z0-9_])([a-z][A-Za-z0-9_]*)$/u, before) ->
        predicates(Enum.at(m, 1))

      true ->
        {:no, ~c"", []}
    end
  rescue
    _ -> {:no, ~c"", []}
  end

  # in einem gequoteten Atom: ungerade Zahl von ' (verdoppelte zählen zwei)
  defp quoted?(before), do: rem(length(String.split(before, "'")) - 1, 2) == 1

  defp predicates(prefix) do
    preds =
      case :ets.whereis(@table) != :undefined and :ets.lookup(@table, :preds) do
        [{:preds, ps}] -> ps
        _ -> []
      end

    hits = for {n, _} = k <- preds, String.starts_with?(n, prefix), do: k

    case Enum.uniq(for {n, _} <- hits, do: n) do
      [] ->
        {:no, ~c"", []}

      [name] ->
        # nur mit Argumenten: gleich die Klammer
        paren = if Enum.all?(hits, fn {_, ar} -> ar > 0 end), do: "(", else: ""
        insert(prefix, name, paren, hits)

      names ->
        extend(prefix, names, show_preds(hits))
    end
  end

  defp insert(prefix, name, suffix, hits) do
    case String.replace_prefix(name, prefix, "") <> suffix do
      "" -> {:no, ~c"", show_preds(hits)}
      rest -> {:yes, String.to_charlist(rest), []}
    end
  end

  defp show_preds(hits) do
    for {n, ar} <- Enum.sort(hits), do: String.to_charlist("#{n}/#{ar}")
  end

  # mehrere Treffer: das gemeinsame Stück ergänzen, sonst die Liste zeigen
  defp extend(prefix, names, shown) do
    case String.replace_prefix(common(names), prefix, "") do
      "" -> {:no, ~c"", shown}
      rest -> {:yes, String.to_charlist(rest), []}
    end
  end

  defp complete(prefix, candidates, suffix, show) do
    case Enum.filter(candidates, &String.starts_with?(&1, prefix)) do
      [] ->
        {:no, ~c"", []}

      [one] ->
        {:yes, String.to_charlist(String.replace_prefix(one, prefix, "") <> suffix), []}

      many ->
        extend(prefix, many, for(c <- Enum.sort(many), do: String.to_charlist(show.(c))))
    end
  end

  defp common([first | rest]) do
    Enum.reduce(rest, first, fn s, acc ->
      n = :binary.longest_common_prefix([acc, s])
      binary_part(acc, 0, n)
    end)
  end

  @doc false
  # Für die TAB-Ergänzung unter rlwrap (.rlwrap_filter.py): je Name die
  # Stelligkeiten der Prädikate, die man im Toplevel rufen kann – System
  # und die Exporte aller Bibliotheken (eingebaute über use_library/3,
  # Prolog-Dateien über ihr :- module/2). Text: "name a1 a2 ..." je Zeile,
  # sortiert; steht in .rlwrap_predicates (test/rlwrap_test.exs prüft das)
  def rlwrap_predicates_text do
    sys = PrologEx.Builtins.system_keys()

    home =
      for l <- PrologEx.Builtins.library_names(),
          {:import, "user", n, ar} <- Map.keys(PrologEx.use_library(%{}, l, "user")),
          do: {n, ar}

    files =
      for f <- Path.wildcard(Path.join([:code.priv_dir(:prolog_ex), "library", "**", "*.pl"])),
          e <- file_exports(f),
          do: e

    (sys ++ home ++ files)
    |> Enum.filter(fn {n, _} -> plain?(n) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map_join(fn {n, ars} ->
      Enum.join([n | ars |> Enum.uniq() |> Enum.sort()], " ") <> "\n"
    end)
  end

  # Exporte aus :- module(Name, Liste) am Anfang einer Bibliotheksdatei
  defp file_exports(path) do
    text = File.read!(path)

    case Regex.run(~r/:-\s*module\(.*?\]\s*\)\s*\./s, text) do
      [decl] ->
        case PrologEx.Parser.read_terms(decl) do
          [{:term, {_, ":-", [{_, "module", [_, list]}]}, _} | _] -> export_items(list)
          _ -> []
        end

      _ ->
        []
    end
  end

  defp export_items([{t, "/", [{:atom, n}, ar]} | rest])
       when t in [:struct, :gstruct] and is_integer(ar),
       do: [{n, ar} | export_items(rest)]

  defp export_items([{t, "//", [{:atom, n}, ar]} | rest])
       when t in [:struct, :gstruct] and is_integer(ar),
       do: [{n, ar + 2} | export_items(rest)]

  defp export_items([_ | rest]), do: export_items(rest)
  defp export_items({:glist, l}), do: export_items(l)
  defp export_items(_), do: []

  @doc false
  def libraries do
    dir = Path.join(:code.priv_dir(:prolog_ex), "library")

    files =
      for f <- Path.wildcard(Path.join(dir, "**/*.pl")),
          do: f |> Path.relative_to(dir) |> Path.rootname()

    Enum.uniq(PrologEx.Builtins.library_names() ++ files)
  end

  defp files(path) do
    {dir, base} =
      if path == "" or String.ends_with?(path, "/"),
        do: {path, ""},
        else: {Path.dirname(path), Path.basename(path)}

    lsdir = if dir in ["", "."], do: ".", else: dir

    case File.ls(lsdir) do
      {:ok, entries} ->
        entries =
          for e <- entries,
              not String.starts_with?(e, ".") or String.starts_with?(base, "."),
              do: e

        names = for e <- entries, do: if(File.dir?(Path.join(lsdir, e)), do: e <> "/", else: e)
        complete_file(base, names)

      _ ->
        {:no, ~c"", []}
    end
  end

  defp complete_file(base, names) do
    case Enum.filter(names, &String.starts_with?(&1, base)) do
      [] ->
        {:no, ~c"", []}

      [one] ->
        close = if String.ends_with?(one, "/"), do: "", else: "'"
        {:yes, String.to_charlist(String.replace_prefix(one, base, "") <> close), []}

      many ->
        extend(base, many, for(n <- Enum.sort(many), do: String.to_charlist(n)))
    end
  end
end
