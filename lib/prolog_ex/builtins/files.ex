defmodule PrologEx.Builtins.Files do
  @moduledoc """
  `library(files)` wie in Scryer Prolog (Markus Triska): Dateien und
  Verzeichnisse als *Zeichenlisten*.

  Typprüfungen und Fehler wie dort (`must_be/2`, `can_be/2` aus Scryers
  `library(error)`):

    * Pfad `must_be(chars)`: Variable oder Teilliste → `instantiation_error`,
      keine Liste → `type_error(list, P)`, ein Element kein Zeichen →
      `type_error(character, E)` (Typfehler vor Instanziierungsfehlern);
    * Ergebnisse `can_be(list)` bzw. `can_be(integer)`;
    * Datei muss existieren: `existence_error(file, F)` bzw.
      `existence_error(directory, D)`.

  Sonst scheitert ein Prädikat, wenn das Betriebssystem nicht mitspielt
  (Verzeichnis existiert schon, ist nicht leer, keine Rechte, ...).

  Zeitstempel (`file_modification_time/2` usw.) wie in Scryer:
  `['Y'="2026", 'm'="10", ..., finis]` in Ortszeit, für `format_time//2`
  aus `library(time)`; früher heißt `@<`.
  """
  use PrologEx.Builtin, module: "files"
  alias PrologEx.Error

  # --- Typprüfungen (Scryers library(error)) ------------------------------

  # must_be(chars, P): der Pfad als Elixir-String
  defp chars!(t, s) do
    can_chars!(t, s)

    t
    |> items(s)
    |> case do
      {:partial, _} -> Error.instantiation!()
      {:list, l} -> Enum.map_join(l, fn {:atom, c} -> c end)
    end
  end

  # can_be(chars, T): Liste oder Teilliste, nicht freie Elemente Zeichen
  defp can_chars!(t, s) do
    case items(t, s) do
      :other ->
        Error.type!("list", PrologEx.resolve(t, s))

      {_, l} ->
        for e <- l do
          case e do
            {:atom, <<_::utf8>>} -> :ok
            {:var, _} -> :ok
            other -> Error.type!("character", PrologEx.resolve(other, s))
          end
        end

        case items(t, s) do
          {:list, l} ->
            if Enum.any?(l, &match?({:var, _}, &1)), do: Error.instantiation!(), else: :ok

          _ ->
            :ok
        end
    end
  end

  # can_be(list, T)
  defp can_list!(t, s) do
    if items(t, s) == :other, do: Error.type!("list", PrologEx.resolve(t, s)), else: :ok
  end

  # {:list, elemente} | {:partial, elemente} | :other (Elemente dereferenziert)
  defp items(t, s, acc \\ []) do
    case PrologEx.walk(t, s) |> uncons() do
      :empty ->
        {:list, Enum.reverse(acc)}

      {:cons, h, tl} ->
        items(tl, s, [PrologEx.walk(h, s) | acc])

      :other ->
        case PrologEx.walk(t, s) do
          {:var, _} -> {:partial, Enum.reverse(acc)}
          _ -> :other
        end
    end
  end

  defp chars(str), do: list(for(<<c::utf8 <- str>>, do: a(<<c::utf8>>)))

  defp file_must_exist!(f, s) do
    p = chars!(f, s)
    if File.regular?(p), do: p, else: Error.existence!("file", PrologEx.resolve(f, s))
  end

  defp directory_must_exist!(d, s) do
    p = chars!(d, s)
    if File.dir?(p), do: p, else: Error.existence!("directory", PrologEx.resolve(d, s))
  end

  defp ok?(:ok), do: :ok
  defp ok?({:ok, _}), do: :ok
  defp ok?(_), do: :fail

  # --- Prädikate -----------------------------------------------------------

  # Einträge (Dateien und Verzeichnisse) ohne . und .., sortiert
  defbuiltin "directory_files", [d, fs] do
    p = chars!(d, subst())
    can_list!(fs, subst())

    case File.ls(p) do
      {:ok, names} -> {:unify, [{fs, list(names |> Enum.sort() |> Enum.map(&chars/1))}]}
      _ -> :fail
    end
  end

  defbuiltin "file_size", [f, size] do
    p = file_must_exist!(f, subst())

    case deref(size) do
      {:var, _} -> :ok
      n when is_integer(n) -> :ok
      other -> Error.type!("integer", resolve(other))
    end

    case File.stat(p) do
      {:ok, %{size: n}} -> {:unify, [{size, n}]}
      _ -> :fail
    end
  end

  defbuiltin "file_exists", [f] do
    if File.regular?(chars!(f, subst())), do: :ok, else: :fail
  end

  defbuiltin "directory_exists", [d] do
    if File.dir?(chars!(d, subst())), do: :ok, else: :fail
  end

  defbuiltin "make_directory", [d] do
    d |> chars!(subst()) |> File.mkdir() |> ok?()
  end

  # wie mkdir -p
  defbuiltin "make_directory_path", [d] do
    d |> chars!(subst()) |> File.mkdir_p() |> ok?()
  end

  defbuiltin "delete_file", [f] do
    f |> file_must_exist!(subst()) |> File.rm() |> ok?()
  end

  defbuiltin "rename_file", [f, r] do
    p = file_must_exist!(f, subst())
    File.rename(p, chars!(r, subst())) |> ok?()
  end

  defbuiltin "file_copy", [f, c] do
    p = file_must_exist!(f, subst())
    File.cp(p, chars!(c, subst())) |> ok?()
  end

  # muss leer sein
  defbuiltin "delete_directory", [d] do
    d |> directory_must_exist!(subst()) |> File.rmdir() |> ok?()
  end

  # working_directory(D0, D): D0 ist das aktuelle Verzeichnis, danach D
  # (working_directory(D, D) fragt nur ab)
  defbuiltin "working_directory", [d0, d] do
    can_list!(d0, subst())
    can_list!(d, subst())
    {:ok, cwd} = File.cwd()

    case PrologEx.unify(d0, chars(cwd), subst()) do
      {:ok, s} ->
        case items(d, s) do
          {:list, l} ->
            if Enum.all?(l, &match?({:atom, <<_::utf8>>}, &1)) and
                 File.cd(Enum.map_join(l, fn {:atom, c} -> c end)) == :ok,
               do: {:subst, s},
               else: :fail

          _ ->
            :fail
        end

      :error ->
        :fail
    end
  end

  # kanonischer, absoluter Pfad: Komponenten normalisiert, symbolische
  # Verweise aufgelöst; scheitert, wenn es den Pfad nicht gibt
  defbuiltin "path_canonical", [ps, cs] do
    p = chars!(ps, subst())
    can_list!(cs, subst())

    case canonical(p) do
      {:ok, c} -> {:unify, [{cs, chars(c)}]}
      :error -> :fail
    end
  end

  # path_segments(P, Segmente): an "/" getrennt; eines muss gebunden sein
  defbuiltin "path_segments", [p, segs] do
    s = subst()

    case PrologEx.walk(p, s) do
      {:var, _} ->
        segments =
          case items(segs, s) do
            {:list, l} -> l
            {:partial, _} -> Error.instantiation!()
            :other -> Error.type!("list", resolve(segs))
          end

        {:unify, [{p, chars(Enum.map_join(segments, "/", &chars!(&1, s)))}]}

      _ ->
        path = chars!(p, subst())
        {:unify, [{segs, list(path |> String.split("/") |> Enum.map(&chars/1))}]}
    end
  end

  defbuiltin "file_modification_time", [f, t] do
    file_time(f, t, :mtime, subst())
  end

  defbuiltin "file_access_time", [f, t] do
    file_time(f, t, :atime, subst())
  end

  # Erstellungszeit: unter Unix kennt Erlang sie nicht (ctime ist dort die
  # letzte Änderung des Inodes) – dann scheitert es, wie Scryer auf
  # Systemen ohne Erstellungszeit
  defbuiltin "file_creation_time", [f, t] do
    case :os.type() do
      {:win32, _} ->
        file_time(f, t, :ctime, subst())

      _ ->
        _ = file_must_exist!(f, subst())
        :fail
    end
  end

  defp file_time(f, t, which, s) do
    p = file_must_exist!(f, s)

    case File.stat(p, time: :posix) do
      {:ok, st} -> {:unify, [{t, timestamp(Map.fetch!(st, which))}]}
      _ -> :fail
    end
  end

  # --- Zeitstempel wie Scryer (chrono, Ortszeit) ---------------------------

  @months ~w(January February March April May June July August September October November December)
  @days ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  @doc false
  def timestamp(posix) do
    {{y, mo, d} = date, {h, mi, sec}} = :calendar.system_time_to_local_time(posix, :second)

    dow = :calendar.day_of_the_week(date)
    yday = :calendar.date_to_gregorian_days(date) - :calendar.date_to_gregorian_days(y, 1, 1)
    month = Enum.at(@months, mo - 1)
    day = Enum.at(@days, dow - 1)
    p2 = &String.pad_leading(Integer.to_string(&1), 2, "0")
    # Woche des Jahres, erster Sonntag bzw. Montag beginnt Woche 1
    week_sun = div(yday + 7 - rem(dow, 7), 7)
    week_mon = div(yday + 7 - (dow - 1), 7)
    y2 = p2.(rem(y, 100))

    fields = [
      {"Y", Integer.to_string(y)},
      {"m", p2.(mo)},
      {"d", p2.(d)},
      {"H", p2.(h)},
      {"M", p2.(mi)},
      {"S", p2.(sec)},
      {"y", y2},
      {"b", String.slice(month, 0, 3)},
      {"B", month},
      {"a", String.slice(day, 0, 3)},
      {"A", day},
      {"w", Integer.to_string(rem(dow, 7))},
      {"u", Integer.to_string(dow)},
      {"U", p2.(week_sun)},
      {"W", p2.(week_mon)},
      {"j", String.pad_leading(Integer.to_string(yday + 1), 3, "0")},
      {"D", "#{p2.(mo)}/#{p2.(d)}/#{y2}"},
      {"x", "#{p2.(mo)}/#{p2.(d)}/#{y2}"},
      {"v", "#{String.pad_leading(Integer.to_string(d), 2)}-#{String.slice(month, 0, 3)}-#{y}"}
    ]

    list(for({k, v} <- fields, do: mk("=", [a(k), chars(v)])) ++ [a("finis")])
  end

  # --- realpath ------------------------------------------------------------

  @doc false
  def canonical(p) do
    {:ok, cwd} = File.cwd()
    start = if String.starts_with?(p, "/"), do: [], else: Path.split(cwd) |> tl()
    resolve_parts(start, Path.split(p) |> Enum.reject(&(&1 == "/")), 0)
  end

  # done: aufgelöste Komponenten (ohne "/"), todo: offene
  defp resolve_parts(_done, _todo, 40), do: :error
  defp resolve_parts(done, [], _), do: {:ok, "/" <> Enum.join(done, "/")}
  defp resolve_parts(done, ["." | rest], n), do: resolve_parts(done, rest, n)

  defp resolve_parts(done, [".." | rest], n),
    do: resolve_parts(Enum.drop(done, -1), rest, n)

  defp resolve_parts(done, [c | rest], n) do
    path = "/" <> Enum.join(done ++ [c], "/")

    case :file.read_link_info(path) do
      {:ok, {:file_info, _, :symlink, _, _, _, _, _, _, _, _, _, _, _}} ->
        {:ok, target} = :file.read_link(path)
        target = to_string(target)
        parts = Path.split(target) |> Enum.reject(&(&1 == "/"))
        base = if String.starts_with?(target, "/"), do: [], else: done
        resolve_parts(base, parts ++ rest, n + 1)

      {:ok, {:file_info, _, type, _, _, _, _, _, _, _, _, _, _, _}} ->
        # nur die letzte Komponente darf kein Verzeichnis sein
        if rest == [] or type == :directory,
          do: resolve_parts(done ++ [c], rest, n),
          else: :error

      _ ->
        :error
    end
  end
end
