defmodule PrologEx.Builtins.Filesex do
  @moduledoc """
  `library(filesex)` wie in SWI-Prolog, der Teil, der nur liest: Pfade
  zusammensetzen und zerlegen, Verzeichnisbäume durchlaufen. Pfade als Atome
  (Zeichen- und Codelisten werden angenommen), Ergebnisse als Atome.

    * `directory_file_path(?Dir, ?File, ?Path)` – zusammensetzen
      (`Dir` `.` und absolute `File`: `Path = File`) oder zerlegen.
    * `directory_member(+Dir, -Member, +Optionen)` – die Einträge von `Dir`
      (ohne `.`, `..`), als Pfad (`directory_file_path/3`), der Reihe nach
      (sortiert; SWI: wie das Betriebssystem sie liefert), lazy. Optionen
      wie SWI:
        * `recursive(B)` (false) – auch die Unterverzeichnisse, Tiefe
          zuerst: erst das Verzeichnis selbst, dann sein Inhalt;
        * `follow_links(B)` (true) – symbolischen Verzeichnissen folgen
          (jedes Verzeichnis nur einmal: keine Schleifen);
        * `file_type(T)` – nur `directory`, `regular`, `prolog` (`.pl`,
          `.prolog`) oder `txt` (gewöhnliche Dateien);
        * `extensions(L)` – nur gewöhnliche Dateien mit einer dieser
          Endungen (ohne Punkt; `''` keine);
        * `matches(Glob)`, `exclude(Glob)` – Name (ohne Verzeichnis) passt
          bzw. passt nicht (`*`, `?`, `[...]`);
        * `exclude_directory(Glob)` – solche Verzeichnisse weder liefern
          noch betreten;
        * `hidden(B)` (true) – auch Namen mit `.` am Anfang (`false`:
          solche Verzeichnisse auch nicht betreten);
        * `file_errors(E)` (`error`) – ein Verzeichnis, das sich nicht
          lesen lässt: `existence_error(directory, D)` bzw.
          `permission_error(...)`, mit `fail` stillschweigend übergangen.
      Unbekannte Optionen werden übergangen (wie SWI).
    * `relative_file_name(?Path, +RelTo, ?RelPath)` – `Path` relativ zum
      Verzeichnis der Datei `RelTo` und umgekehrt.

  Dazu, eingebaut mit Heimat `library(swi)` (in SWI eingebaut):
  `file_base_name/2`, `file_directory_name/2` (wie POSIX `basename` und
  `dirname`), `file_name_extension/3`, `is_absolute_file_name/1` – siehe
  `PrologEx.Builtins.Swi`.

  Nur Abfragen: in den Arbeitern von `library(concurrent)` erlaubt.
  """
  use PrologEx.Builtin, module: "filesex"
  alias PrologEx.{Error, Store}

  # --- Pfade -----------------------------------------------------------------

  defbuiltin "directory_file_path", [dir, file, path] do
    s = subst()

    case {opt_text(dir, s), opt_text(file, s), opt_text(path, s)} do
      {d, f, _} when is_binary(d) and is_binary(f) ->
        {:unify, [{path, a(join(d, f))}]}

      {d, nil, p} when is_binary(d) and is_binary(p) ->
        cond do
          d == "." and not absolute?(p) ->
            {:unify, [{file, a(p)}]}

          String.ends_with?(d, "/") and String.starts_with?(p, d) ->
            {:unify, [{file, a(String.replace_prefix(p, d, ""))}]}

          String.starts_with?(p, d <> "/") ->
            {:unify, [{file, a(String.replace_prefix(p, d <> "/", ""))}]}

          true ->
            :fail
        end

      {nil, f, p} when is_binary(f) and is_binary(p) ->
        if String.ends_with?(p, f) do
          d0 = String.replace_suffix(p, f, "")
          {:unify, [{dir, a(strip_slash(d0))}]}
        else
          :fail
        end

      {nil, nil, p} when is_binary(p) ->
        {:unify, [{dir, a(dirname(p))}, {file, a(basename(p))}]}

      _ ->
        Error.instantiation!()
    end
  end

  defbuiltin "relative_file_name", [path, relto, rel] do
    s = subst()
    base = relto |> text!(s) |> Path.expand() |> dirname()

    case opt_text(path, s) do
      p when is_binary(p) ->
        {:unify, [{rel, a(relative(Path.expand(p), base))}]}

      nil ->
        r = text!(rel, s)
        {:unify, [{path, a(if(absolute?(r), do: r, else: Path.expand(r, base)))}]}
    end
  end

  # --- directory_member/3 -------------------------------------------------------

  defbuiltin "directory_member", [dir, member, opts], nondet: true do
    s = subst()
    d = text!(dir, s)
    o = options(opts, s)

    case read_dir(d, o, s, dir) do
      nil -> []
      entries -> walk([{d, entries}], o, member, MapSet.new([dir_id(d)]))
    end
  end

  # lazy Liste der Lösungen: ein Stapel aus {Verzeichnis, übrige Namen}
  defp walk([], _o, _member, _seen), do: []
  defp walk([{_d, []} | rest], o, member, seen), do: walk(rest, o, member, seen)

  defp walk([{d, [name | names]} | rest], o, member, seen) do
    p = join(d, name)
    stack = [{d, names} | rest]
    dir? = File.dir?(p)

    # ausgeschlossene und (hidden(false)) versteckte Verzeichnisse: weder
    # liefern noch betreten
    if dir? and (glob_any?(o.exclude_dir, name) or (not o.hidden and hidden?(name))) do
      walk(stack, o, member, seen)
    else
      {stack, seen} =
        if dir? and o.recursive and (o.follow_links or not link?(p)) and
             not MapSet.member?(seen, dir_id(p)) do
          case read_dir(p, o, nil, nil) do
            nil -> {stack, seen}
            entries -> {[{p, entries} | stack], MapSet.put(seen, dir_id(p))}
          end
        else
          {stack, seen}
        end

      if wanted?(p, name, dir?, o) do
        [{:unify, [{member, a(p)}]} | fn -> walk(stack, o, member, seen) end]
      else
        walk(stack, o, member, seen)
      end
    end
  end

  defp wanted?(p, name, dir?, o) do
    (o.hidden or not hidden?(name)) and
      type_ok?(o.file_type, p, dir?) and
      (o.extensions == nil or (not dir? and File.regular?(p) and ext(name) in o.extensions)) and
      (o.matches == [] or glob_any?(o.matches, name)) and
      not glob_any?(o.exclude, name)
  end

  defp hidden?(name), do: String.starts_with?(name, ".")

  defp type_ok?(nil, _p, _dir?), do: true
  defp type_ok?("directory", _p, dir?), do: dir?
  defp type_ok?(t, p, dir?) when t in ["regular", "txt"], do: not dir? and File.regular?(p)

  defp type_ok?("prolog", p, dir?),
    do: not dir? and File.regular?(p) and ext(Path.basename(p)) in ["pl", "prolog"]

  # die Namen eines Verzeichnisses, sortiert; nicht lesbar: Fehler oder nil
  defp read_dir(d, o, s, term) do
    case File.ls(d) do
      {:ok, names} ->
        Enum.sort(names)

      {:error, reason} ->
        if o.file_errors == :error do
          t = if term, do: PrologEx.resolve(term, s), else: a(d)

          if reason in [:enoent, :enotdir],
            do: Error.existence!("directory", t),
            else: Error.permission!("open", "directory", t)
        end
    end
  end

  # ein Verzeichnis eindeutig (Gerät und Inode; folgt Links)
  defp dir_id(p) do
    case File.stat(p) do
      {:ok, %File.Stat{major_device: dev, inode: ino}} -> {dev, ino}
      _ -> {:path, Path.expand(p)}
    end
  end

  defp link?(p), do: match?({:ok, %File.Stat{type: :symlink}}, File.lstat(p))

  # --- Optionen ----------------------------------------------------------------

  defp options(opts, s) do
    init = %{
      recursive: false,
      follow_links: true,
      file_type: nil,
      extensions: nil,
      matches: [],
      exclude: [],
      exclude_dir: [],
      hidden: true,
      file_errors: :error
    }

    opts
    |> list!(s)
    |> Enum.reduce(init, fn o, acc -> option(PrologEx.unmark_top(Store.walk(o, s)), acc, s) end)
  end

  defp option({:var, _}, _acc, _s), do: Error.instantiation!()

  defp option({:struct, n, [v]}, acc, s) do
    v = PrologEx.unmark_top(Store.walk(v, s))

    case n do
      "recursive" -> %{acc | recursive: bool!(v, s)}
      "follow_links" -> %{acc | follow_links: bool!(v, s)}
      "hidden" -> %{acc | hidden: bool!(v, s)}
      "file_type" -> %{acc | file_type: file_type!(v, s)}
      "extensions" -> %{acc | extensions: Enum.map(list!(v, s), &ext_text(&1, s))}
      "matches" -> %{acc | matches: [glob(text!(v, s)) | acc.matches]}
      "exclude" -> %{acc | exclude: [glob(text!(v, s)) | acc.exclude]}
      "exclude_directory" -> %{acc | exclude_dir: [glob(text!(v, s)) | acc.exclude_dir]}
      "file_errors" -> %{acc | file_errors: file_errors!(v, s)}
      _ -> acc
    end
  end

  defp option(_other, acc, _s), do: acc

  defp bool!({:atom, "true"}, _s), do: true
  defp bool!({:atom, "false"}, _s), do: false
  defp bool!({:var, _}, _s), do: Error.instantiation!()
  defp bool!(v, s), do: Error.type!("bool", PrologEx.resolve(v, s))

  defp file_type!({:atom, t}, _s) when t in ~w(directory regular prolog txt), do: t
  defp file_type!({:var, _}, _s), do: Error.instantiation!()
  defp file_type!(v, s), do: Error.domain!("file_type", PrologEx.resolve(v, s))

  defp file_errors!({:atom, "error"}, _s), do: :error
  defp file_errors!({:atom, "fail"}, _s), do: :fail
  defp file_errors!({:var, _}, _s), do: Error.instantiation!()
  defp file_errors!(v, s), do: Error.domain!("file_errors", PrologEx.resolve(v, s))

  defp ext_text(e, s) do
    t = text!(e, s)
    String.replace_prefix(t, ".", "")
  end

  defp list!(l, s) do
    case PrologEx.Builtins.Lists.skip_list(l, s) do
      {_, []} -> collect(Store.walk(l, s), s)
      {_, {:var, _}} -> Error.instantiation!()
      _ -> Error.type!("list", PrologEx.resolve(l, s))
    end
  end

  defp collect(l, s) do
    case PrologEx.uncons(Store.walk(l, s)) do
      :empty -> []
      {:cons, h, t} -> [h | collect(t, s)]
    end
  end

  # --- Glob ----------------------------------------------------------------

  defp glob(pat) do
    re =
      pat
      |> String.graphemes()
      |> glob_re([])
      |> IO.iodata_to_binary()

    Regex.compile!("^" <> re <> "$", "u")
  end

  defp glob_re([], acc), do: Enum.reverse(acc)
  defp glob_re(["*" | t], acc), do: glob_re(t, [".*" | acc])
  defp glob_re(["?" | t], acc), do: glob_re(t, ["." | acc])

  defp glob_re(["[" | t], acc) do
    case Enum.split_while(t, &(&1 != "]")) do
      {cls, ["]" | rest]} -> glob_re(rest, ["[" <> Enum.join(cls) <> "]" | acc])
      _ -> glob_re(t, ["\\[" | acc])
    end
  end

  defp glob_re([c | t], acc), do: glob_re(t, [Regex.escape(c) | acc])

  defp glob_any?(globs, name), do: Enum.any?(globs, &Regex.match?(&1, name))

  # --- Hilfen (auch für PrologEx.Builtins.Swi) --------------------------------

  @doc "Pfad zusammensetzen wie directory_file_path/3"
  def join(d, f) do
    cond do
      absolute?(f) or d == "." -> f
      String.ends_with?(d, "/") -> d <> f
      true -> d <> "/" <> f
    end
  end

  @doc "absoluter Pfad (Unix: / oder ~ am Anfang)"
  def absolute?(p), do: String.starts_with?(p, "/") or String.starts_with?(p, "~")

  @doc "wie POSIX basename"
  def basename(p) do
    case strip_slash(p) do
      "/" -> "/"
      q -> q |> String.split("/") |> List.last()
    end
  end

  @doc "wie POSIX dirname"
  def dirname(p) do
    q = strip_slash(p)

    cond do
      q == "/" ->
        "/"

      not String.contains?(q, "/") ->
        "."

      true ->
        parts = String.split(q, "/")

        case parts |> Enum.drop(-1) |> Enum.join("/") |> strip_slash() do
          "" -> "/"
          d -> d
        end
    end
  end

  @doc "Endung eines Namens (ohne Punkt; der letzte Punkt nach dem letzten /), sonst \"\""
  def ext(name) do
    case split_ext(name) do
      {_, e} -> e
    end
  end

  @doc "{Basis, Endung} wie file_name_extension/3"
  def split_ext(name) do
    file = name |> String.split("/") |> List.last()

    case :binary.matches(file, ".") do
      [] ->
        {name, ""}

      ms ->
        {pos, _} = List.last(ms)
        cut = byte_size(name) - byte_size(file) + pos
        <<b::binary-size(^cut), ".", e::binary>> = name
        {b, e}
    end
  end

  defp strip_slash("/"), do: "/"
  defp strip_slash(""), do: ""

  defp strip_slash(p) do
    case String.trim_trailing(p, "/") do
      "" -> "/"
      q -> q
    end
  end

  defp relative(p, base) do
    ps = Path.split(p)
    bs = Path.split(base)
    {common, prest, brest} = common(ps, bs)
    _ = common

    case List.duplicate("..", length(brest)) ++ prest do
      [] -> "."
      parts -> Path.join(parts)
    end
  end

  defp common([x | xs], [x | ys]) do
    {c, a, b} = common(xs, ys)
    {[x | c], a, b}
  end

  defp common(xs, ys), do: {[], xs, ys}

  @doc "Text eines Pfads: Atom, Zeichen- oder Codeliste (ungebunden: Fehler)"
  def text!(t, s) do
    case opt_text(t, s) do
      nil -> Error.instantiation!()
      p -> p
    end
  end

  @doc "Text eines Pfads oder nil, wenn ungebunden"
  def opt_text(t, s) do
    case PrologEx.unmark_top(Store.walk(t, s)) do
      {:var, _} ->
        nil

      {:atom, p} ->
        p

      other ->
        l = PrologEx.resolve(other, s)

        try do
          PrologEx.Builtins.Modules.file_name(l)
        rescue
          _ -> Error.type!("atom", l)
        end
    end
  end
end
