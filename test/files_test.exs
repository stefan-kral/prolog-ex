defmodule PrologEx.FilesTest do
  # library(files) wie Scryer: Pfade als Zeichenlisten
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(r, ":- use_module(library(files)).\n:- use_module(library(lists)).\n")
      )

    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    File.write!(Path.join(c.tmp_dir, "a.txt"), "hallo\n")
    File.mkdir_p!(Path.join(c.tmp_dir, "sub"))
    File.ln_s!(Path.join(c.tmp_dir, "sub"), Path.join(c.tmp_dir, "link"))
    :ok
  end

  # DIR im Text steht für das Testverzeichnis (als Zeichen in "...")
  defp ask(c, q, db \\ nil) do
    q = String.replace(q, "DIR", c.tmp_dir)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    (db || c.db)
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    |> Enum.map(&String.replace(&1, c.tmp_dir, "DIR"))
  end

  defp err(c, goal), do: ask(c, "catch(#{goal}, error(E, _), true)")

  test "directory_files/2, file_exists/1, directory_exists/1, file_size/2", c do
    assert ask(c, ~s|directory_files("DIR", Fs)|) == [~s|Fs = ["a.txt","link","sub"]|]
    assert ask(c, ~s|directory_files("DIR/gibts", _)|) == []
    assert ask(c, ~s|file_exists("DIR/a.txt")|) == ["true"]
    assert ask(c, ~s|file_exists("DIR/sub")|) == []
    assert ask(c, ~s|file_exists("DIR/gibts")|) == []
    assert ask(c, ~s|directory_exists("DIR/sub")|) == ["true"]
    # symbolische Verweise werden verfolgt
    assert ask(c, ~s|directory_exists("DIR/link")|) == ["true"]
    assert ask(c, ~s|directory_exists("DIR/a.txt")|) == []
    assert ask(c, ~s|file_size("DIR/a.txt", S)|) == ["S = 6"]
    assert ask(c, ~s|file_size("DIR/a.txt", 7)|) == []
  end

  test "Verzeichnisse anlegen und löschen", c do
    assert ask(c, ~s|make_directory("DIR/neu"), directory_exists("DIR/neu")|) == ["true"]
    # gibt es schon / Elternverzeichnis fehlt: scheitert
    assert ask(c, ~s|make_directory("DIR/neu")|) == []
    assert ask(c, ~s|make_directory("DIR/x/y")|) == []
    assert ask(c, ~s|make_directory_path("DIR/x/y/z"), directory_exists("DIR/x/y/z")|) == ["true"]
    assert ask(c, ~s|make_directory_path("DIR/x/y/z")|) == ["true"]
    # nicht leer: scheitert
    assert ask(c, ~s|delete_directory("DIR/x")|) == []

    assert ask(c, ~s|delete_directory("DIR/x/y/z"), \\+ directory_exists("DIR/x/y/z")|) == [
             "true"
           ]

    assert err(c, ~s|delete_directory("DIR/gibts")|) == [
             ~s|E = existence_error(directory, "DIR/gibts")|
           ]

    assert err(c, ~s|delete_directory("DIR/a.txt")|) == [
             ~s|E = existence_error(directory, "DIR/a.txt")|
           ]
  end

  test "Dateien löschen, umbenennen, kopieren", c do
    assert ask(c, ~s|file_copy("DIR/a.txt", "DIR/b.txt"), file_size("DIR/b.txt", S)|) == ["S = 6"]

    assert ask(c, ~s|rename_file("DIR/b.txt", "DIR/c.txt"), \\+ file_exists("DIR/b.txt")|) == [
             "true"
           ]

    assert ask(c, ~s|delete_file("DIR/c.txt"), \\+ file_exists("DIR/c.txt")|) == ["true"]
    assert err(c, ~s|delete_file("DIR/c.txt")|) == [~s|E = existence_error(file, "DIR/c.txt")|]
    assert err(c, ~s|delete_file("DIR/sub")|) == [~s|E = existence_error(file, "DIR/sub")|]

    assert err(c, ~s|rename_file("DIR/gibts", "DIR/x")|) == [
             ~s|E = existence_error(file, "DIR/gibts")|
           ]

    assert err(c, ~s|file_copy("DIR/gibts", "DIR/x")|) == [
             ~s|E = existence_error(file, "DIR/gibts")|
           ]

    assert err(c, ~s|file_size("DIR/gibts", _)|) == [~s|E = existence_error(file, "DIR/gibts")|]
    # Ziel in einem Verzeichnis, das es nicht gibt: scheitert
    assert ask(c, ~s|file_copy("DIR/a.txt", "DIR/gibts/b.txt")|) == []
    assert ask(c, ~s|rename_file("DIR/a.txt", "DIR/gibts/b.txt")|) == []
  end

  test "delete_file/1: library(swi) hat eines, das auch Atome nimmt", c do
    File.write!(Path.join(c.tmp_dir, "d.txt"), "")
    assert ask(c, "delete_file('DIR/d.txt')", PrologEx.use_library(%{}, "swi")) == ["true"]

    assert ask(c, "catch(delete_file(x), error(E, _), true)", %{}) == [
             "E = existence_error(procedure, delete_file/1)"
           ]

    assert err(c, "delete_file('DIR/d.txt')") == ["E = type_error(list, 'DIR/d.txt')"]
  end

  test "Typprüfungen wie Scryers must_be/2, can_be/2", c do
    assert err(c, "file_exists(_)") == ["E = instantiation_error"]
    assert err(c, "file_exists(foo)") == ["E = type_error(list, foo)"]
    assert err(c, "file_exists([a|_])") == ["E = instantiation_error"]
    assert err(c, "file_exists([a|b])") == ["E = type_error(list, [a|b])"]
    assert err(c, "file_exists([a, _])") == ["E = instantiation_error"]
    # Typfehler vor Instanziierungsfehlern
    assert err(c, "file_exists([a, _, 1])") == ["E = type_error(character, 1)"]
    assert err(c, "file_exists([0'a])") == ["E = type_error(character, 97)"]
    assert err(c, "file_exists([ab])") == ["E = type_error(character, ab)"]
    assert err(c, ~s|file_size("DIR/a.txt", x)|) == ["E = type_error(integer, x)"]
    assert err(c, ~s|directory_files("DIR", x)|) == ["E = type_error(list, x)"]
    assert err(c, ~s{directory_files("DIR", [a|b])}) == ["E = type_error(list, [a|b])"]
    assert err(c, ~s|rename_file("DIR/a.txt", _)|) == ["E = instantiation_error"]
    assert err(c, ~s|file_copy("DIR/a.txt", x)|) == ["E = type_error(list, x)"]
    assert err(c, "make_directory(1)") == ["E = type_error(list, 1)"]
    assert err(c, "make_directory_path(_)") == ["E = instantiation_error"]
    assert err(c, "delete_directory(x)") == ["E = type_error(list, x)"]
    assert err(c, ~s|path_canonical("DIR", x)|) == ["E = type_error(list, x)"]
    assert err(c, "path_canonical(x, _)") == ["E = type_error(list, x)"]
    assert err(c, "working_directory(x, _)") == ["E = type_error(list, x)"]
    assert err(c, "working_directory(_, x)") == ["E = type_error(list, x)"]
  end

  test "path_canonical/2", c do
    assert ask(c, ~s|path_canonical("DIR/link/../a.txt", P)|) == [~s|P = "DIR/a.txt"|]
    assert ask(c, ~s|path_canonical("DIR/./sub//../a.txt", P)|) == [~s|P = "DIR/a.txt"|]
    assert ask(c, ~s|path_canonical("DIR/link", P)|) == [~s|P = "DIR/sub"|]
    # relativer Verweis
    File.ln_s!("sub", Path.join(c.tmp_dir, "rel"))
    assert ask(c, ~s|path_canonical("DIR/rel/", P)|) == [~s|P = "DIR/sub"|]
    # gibt es nicht / Zwischenkomponente kein Verzeichnis: scheitert
    assert ask(c, ~s|path_canonical("DIR/gibts", _)|) == []
    assert ask(c, ~s|path_canonical("DIR/a.txt/x", _)|) == []
    assert ask(c, ~s|path_canonical("DIR/a.txt/..", _)|) == []
    # Schleife
    File.ln_s!("schleife", Path.join(c.tmp_dir, "schleife"))
    assert ask(c, ~s|path_canonical("DIR/schleife", _)|) == []
    # relativ zum Arbeitsverzeichnis
    assert ask(c, ~s|working_directory(D, D), path_canonical(".", P), P == D|) |> length() == 1
  end

  test "path_segments/2 (Beispiele aus Scryers Doku)", c do
    assert ask(c, ~s|path_segments("/hello/there", S)|) == [~s|S = [[],"hello","there"]|]
    assert ask(c, ~s|path_segments(P, ["hello", "there"])|) == [~s|P = "hello/there"|]
    assert ask(c, ~s|path_segments(P, ["", ""])|) == [~s|P = "/"|]
    assert ask(c, ~s|path_segments("", S)|) == ["S = [[]]"]
    assert ask(c, ~s|path_segments(P, [])|) == ["P = []"]
    assert ask(c, ~s|path_segments("a/", S)|) == [~s|S = ["a",[]]|]
    assert err(c, "path_segments(_, _)") == ["E = instantiation_error"]
    assert err(c, "path_segments(_, [\"a\"|_])") == ["E = instantiation_error"]
    assert err(c, "path_segments(_, x)") == ["E = type_error(list, x)"]
    assert err(c, "path_segments(_, [x])") == ["E = type_error(list, x)"]
    assert err(c, "path_segments(x, _)") == ["E = type_error(list, x)"]
  end

  test "working_directory/2", c do
    {:ok, cwd} = File.cwd()

    try do
      assert ask(c, ~s|working_directory(D0, "DIR/sub"), working_directory(D, D)|) ==
               [~s|D = "DIR/sub", D0 = "#{cwd}"|]

      # D0 passt nicht oder Ziel fehlt: nichts geändert
      assert ask(c, ~s|working_directory("/gibts", "DIR")|) == []
      assert ask(c, ~s|working_directory(_, "DIR/gibts")|) == []
      assert ask(c, ~s|working_directory(_, _)|) == []
      assert File.cwd() == {:ok, Path.join(c.tmp_dir, "sub")}
      # relativ
      assert ask(c, ~s|working_directory(_, ".."), working_directory(D, D)|) == [~s|D = "DIR"|]
    after
      File.cd!(cwd)
    end
  end

  test "Zeitstempel wie Scryer (für format_time//2)", c do
    # 2026-01-04 09:05:07 Ortszeit (ein Sonntag, Woche 0 nach Montag)
    [utc] = :calendar.local_time_to_universal_time_dst({{2026, 1, 4}, {9, 5, 7}})
    posix = :calendar.datetime_to_gregorian_seconds(utc) - 62_167_219_200

    assert PrologEx.Builtins.Files.timestamp(posix)
           |> PrologEx.format(quoted: true, strings: true) ==
             ~s|['Y'="2026",m="01",d="04",'H'="09",'M'="05",'S'="07",y="26",b="Jan",| <>
               ~s|'B'="January",a="Sun",'A'="Sunday",w="0",u="7",'U'="01",'W'="00",| <>
               ~s|j="004",'D'="01/04/26",x="01/04/26",v=" 4-Jan-2026",finis]|

    # 2024-01-01 ist ein Montag: nach Montag Woche 1, nach Sonntag Woche 0
    [utc] = :calendar.local_time_to_universal_time_dst({{2024, 1, 1}, {0, 0, 0}})

    t =
      PrologEx.Builtins.Files.timestamp(
        :calendar.datetime_to_gregorian_seconds(utc) - 62_167_219_200
      )

    text = PrologEx.format(t, quoted: true, strings: true)
    assert text =~ ~s|'U'="00",'W'="01",j="001"|
    assert text =~ ~s|w="1",u="1"|

    assert ask(c, ~s{file_modification_time("DIR/a.txt", T), T = ['Y'=_|_], last(T, L)})
           |> hd() =~ "L = finis"

    assert ask(c, ~s{file_access_time("DIR/a.txt", ['Y'=Y|_])}) |> hd() =~ ~s|Y = "20|

    # früher heißt @<
    File.touch!(Path.join(c.tmp_dir, "a.txt"), 1_000_000_000)

    # nur Dateien
    assert err(c, ~s|file_modification_time("DIR/sub", _)|) ==
             [~s|E = existence_error(file, "DIR/sub")|]

    File.touch!(Path.join([c.tmp_dir, "sub", "b.txt"]), 1_500_000_000)

    assert ask(
             c,
             ~s|file_modification_time("DIR/a.txt", A), file_modification_time("DIR/sub/b.txt", B), A @< B|
           )
           |> length() == 1

    assert err(c, ~s|file_modification_time("DIR/gibts", _)|) ==
             [~s|E = existence_error(file, "DIR/gibts")|]

    # Erstellungszeit kennt Erlang unter Unix nicht
    assert ask(c, ~s|file_creation_time("DIR/a.txt", _)|) == []

    assert err(c, ~s|file_creation_time("DIR/gibts", _)|) ==
             [~s|E = existence_error(file, "DIR/gibts")|]
  end

  test "Pfade aus library(files) gehen direkt an open/3", c do
    assert ask(
             c,
             ~s{directory_files("DIR", Fs), member(F, Fs), F = [a|_], } <>
               ~s|path_segments(P, ["DIR", F]), open(P, read, S), get_char(S, C), close(S)|
           )
           |> hd() =~ ~s|C = h|
  end
end
