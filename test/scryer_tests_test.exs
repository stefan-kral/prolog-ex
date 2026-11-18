defmodule PrologEx.ScryerTestsTest do
  # Scryers eigene Tests (test/fixtures/scryer_tests, aus src/tests, mit
  # ihrem Rahmen test_framework.pl): jeder Test test(Name, Ziel) muss
  # gelingen – bis auf die wenigen, die Scryer-Interna oder eine
  # darstellungsabhängige Reihenfolge prüfen (siehe README, „Scryers eigene
  # Tests“). Wie in Scryer mit double_quotes = chars.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @dir "test/fixtures/scryer_tests"

  # dif:attribute_goals//1 ist Scryers Schnittstelle (dif ist hier
  # eingebaut); die Variablenreihenfolge eines zyklischen Terms hängt an
  # seiner Darstellung
  @expected_fail %{
    "dif" => ["dif#18", "dif#o3"],
    "term_variables" => ["term_variables#2100"]
  }

  @files ~w(acyclic_term dif double_bar ground term_variables when)

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  for f <- @files do
    @tag :tmp_dir
    test f, c do
      Reader.put_current(c.reader)
      file = Path.join(c.tmp_dir, "load.pl")
      src = Path.expand(Path.join(@dir, unquote(f) <> ".pl"))

      File.write!(
        file,
        ":- set_prolog_flag(double_quotes, chars).\n:- ensure_loaded('#{src}').\n"
      )

      PrologEx.put_db(%{})

      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        {:ok, _} = PrologEx.Consult.load_file(file)
      end)

      db = PrologEx.current_db()

      m =
        case Regex.run(~r/^:- module\((\w+),/m, File.read!(src)) do
          [_, m] -> m
          nil -> "user"
        end

      # die nicht gelungenen Tests (Namen als Atome) und die Zahl aller
      q =
        "findall(A, (#{m}:test(N, G), \\+ catch(#{m}:G, _, fail), atom_chars(A, N)), Bad), " <>
          "findall(N, #{m}:test(N, _), All), length(All, Total)"

      assert {_, {:answers, [a]}} = TableCase.run(c.reader, db, q)
      expected = Map.get(@expected_fail, unquote(f), [])
      bad = "[" <> Enum.map_join(expected, ",", &"'#{&1}'") <> "]"
      assert a =~ "Bad = #{bad}" or (expected == [] and a =~ "Bad = []"), a
      total = length(Regex.scan(~r/^test\(/m, File.read!(src)))
      assert a =~ "Total = #{total}", a
    end
  end
end
