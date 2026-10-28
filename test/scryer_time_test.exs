defmodule PrologEx.ScryerTimeTest do
  # library(time) aus Scryer Prolog
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(r, ":- use_module(library(time)).\n:- use_module(library(lists)).\n")
      )

    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp ask(c, q, db \\ nil) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    (db || c.db)
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch(#{goal}, error(E, _), true)")

  # Ausgabe von time/1 ohne die (schwankende) Zeit
  defp timed(c, q) do
    capture_io(fn -> send(self(), {:answers, ask(c, q)}) end)
    |> String.replace(~r/CPU time: \d+\.\d{3}s/, "CPU time: T")
  end

  test "format_time//2 (Beispiel aus Scryers Doku)", c do
    [utc] = :calendar.local_time_to_universal_time_dst({{2020, 6, 11}, {0, 24, 32}})

    t =
      PrologEx.Builtins.Files.timestamp(
        :calendar.datetime_to_gregorian_seconds(utc) - 62_167_219_200
      )

    stamp = PrologEx.format(t, quoted: true)

    assert ask(c, ~s|phrase(format_time("%d.%m.%Y (%H:%M:%S)", #{stamp}), Cs)|) ==
             [~s|Cs = "11.06.2020 (00:24:32)"|]

    assert ask(c, ~s|phrase(format_time("%a %A %b %j %% %y", #{stamp}), Cs)|) ==
             [~s|Cs = "Thu Thursday Jun 163 % 20"|]

    assert err(c, ~s|phrase(format_time("%Q", #{stamp}), _)|) ==
             ["E = domain_error(time_specifier, 'Q')"]
  end

  test "current_time/1: Zeitstempel jetzt", c do
    {{y, _, _}, _} = :calendar.local_time()

    assert ask(c, ~s|current_time(T), phrase(format_time("%Y", T), Cs), atom_chars(A, Cs)|)
           |> hd() =~ "A = '#{y}'"

    assert ask(c, "current_time(A), current_time(B), A @=< B") |> length() == 1
  end

  test "sleep/1, max_sleep_time/1", c do
    {us, ans} = :timer.tc(fn -> ask(c, "sleep(0.05)") end)
    assert ans == ["true"]
    assert us >= 50_000
    assert ask(c, "sleep(0)") == ["true"]
    assert ask(c, "max_sleep_time(T)") == ["T = 18446744073709550591"]
    assert err(c, "sleep(_)") == ["E = instantiation_error"]
    assert err(c, "sleep(a)") == ["E = type_error(number, a)"]
    assert err(c, "sleep(-1)") == ["E = domain_error(not_less_than_zero, -1)"]
    assert err(c, "sleep(18446744073709550592)") == ["E = representation_error(max_sleep_time)"]
  end

  test "time/1: Ausgabe wie Scryer, gezählt wird nur das Ziel", c do
    assert timed(c, "time(true)") == "% CPU time: T, 1 inference\n"
    assert_received {:answers, ["true"]}

    assert timed(c, "time((true, true, true))") == "% CPU time: T, 3 inferences\n"
    assert timed(c, "time(numlist(1, 5, _))") == "% CPU time: T, 1 inference\n"

    # je Lösung; nach der letzten noch einmal beim Scheitern
    assert timed(c, "time((X = 1 ; X = 2 ; X = 3))") ==
             String.duplicate("% CPU time: T, 1 inference\n", 3)

    assert_received {:answers, ["X = 1", "X = 2", "X = 3"]}

    assert timed(c, "time((true ; fail))") ==
             "% CPU time: T, 1 inference\n% CPU time: T, 1 inference\n"

    assert timed(c, "time(fail)") == "% CPU time: T, 1 inference\n"
    assert_received {:answers, []}

    # Ausnahmen: berichtet, dann weiter geworfen
    assert timed(c, "catch(time(throw(x)), x, true)") == "% CPU time: T, 1 inference\n"
    assert_received {:answers, ["true"]}

    # keine Inferenz: Scryers Hinweis
    assert timed(c, "time(member(X, [a, b])), X == b") ==
             "% CPU time: T, 1 inference\n% CPU time: T, 0 inference (exception?)\n"

    # Tausendertrennung wie Scryer (~U)
    assert timed(c, "time((between(1, 1500, _), fail ; true))") ==
             "% CPU time: T, 1_502 inferences\n"
  end

  test "ohne library(time): das eingebaute time/1", c do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, "p.\n"))
    assert capture_io(:stderr, fn -> assert ask(c, "time(true)", db) == ["true"] end) =~ "seconds"
  end

  test "statistics/2 ist das eingebaute", c do
    assert ask(c, "statistics(runtime, [T, D]), integer(T), integer(D)") |> length() == 1
    assert ask(c, "statistics(inferences, I), integer(I)") |> length() == 1
  end
end
