defmodule PrologEx.StatisticsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  @moduletag :gprolog

  @program """
  app([], L, L).
  app([H|T], L, [H|R]) :- app(T, L, R).
  nrev([], []).
  nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = Enum.reduce(["lists", "apply"], %{}, &PrologEx.use_library(&2, &1, "user"))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)

    c.db
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, text), do: Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end))

  # D aus "... D = 123 ..."
  defp d(c, text) do
    [answer] = ask(c, text)
    [_, n] = Regex.run(~r/\bD = (\d+)/, answer)
    String.to_integer(n)
  end

  describe "Zeit" do
    test "runtime, walltime: [Gesamt, seit letztem Aufruf]", c do
      for k <- ~w(runtime total_runtime process_cputime walltime) do
        assert [answer] =
                 ask(c, "statistics(#{k}, [T, D]), integer(T), integer(D), T >= D, D >= 0.")

        assert answer =~ ~r/^D = \d+, T = \d+$/, k
      end

      # D zählt ab dem letzten Aufruf mit demselben Schlüssel
      assert ask(
               c,
               "statistics(walltime, [T0, _]), numlist(1, 30000, L), sum_list(L, _), " <>
                 "statistics(walltime, [T1, D]), D =:= T1 - T0, D >= 0, !."
             )
             |> length() == 1
    end

    test "Rechenzeit wächst bei Arbeit", c do
      assert ask(
               c,
               "statistics(runtime, _), numlist(1, 100000, L), msort(L, _), " <>
                 "statistics(runtime, [_, D]), D > 0, !."
             )
             |> length() == 1
    end

    test "real_time in Sekunden", c do
      [answer] = ask(c, "statistics(real_time, [S, _]).")
      [_, s] = Regex.run(~r/S = (\d+)/, answer)
      assert abs(String.to_integer(s) - System.os_time(:second)) < 5
    end
  end

  describe "inferences" do
    test "zählt Prädikataufrufe, auch eingebaute", c do
      # =/2, is/2 und das zweite statistics/2
      assert d(
               c,
               "statistics(inferences, I0), X = 1, _ is X + 1, statistics(inferences, I1), D is I1 - I0."
             ) ==
               3

      # naive reverse über 30 Elemente: die klassischen 496, + statistics/2
      assert d(
               c,
               "numlist(1, 30, L), statistics(inferences, I0), nrev(L, _), statistics(inferences, I1), D is I1 - I0."
             ) ==
               497
    end

    test "Steuerkonstrukte und call/N zählen nicht", c do
      # gezählt: \\+, fail, true (aus ;), true (aus call), statistics/2;
      # nicht: ;, !, call/1
      assert d(
               c,
               "statistics(inferences, I0), \\+ fail, (true ; true), !, call(true), statistics(inferences, I1), D is I1 - I0."
             ) ==
               5
    end

    test "auch in Unter-Maschinen (findall, \\+, countall)", c do
      # findall, member (einmal gerufen – Backtracking in seine Klauseln
      # ist kein neuer Aufruf), statistics/2
      assert d(
               c,
               "statistics(inferences, I0), findall(X, member(X, [a,b,c]), _), statistics(inferences, I1), D is I1 - I0."
             ) ==
               3

      assert d(
               c,
               "statistics(inferences, I0), countall(between(1, 5, _), _), statistics(inferences, I1), D is I1 - I0."
             ) ==
               3

      n =
        d(
          c,
          "numlist(1, 30, L), statistics(inferences, I0), \\+ \\+ nrev(L, _), statistics(inferences, I1), D is I1 - I0."
        )

      assert n == 497 + 2
    end

    test "Backtracking nimmt nichts zurück", c do
      assert d(
               c,
               "statistics(inferences, I0), (member(_, [a,b,c]), fail ; true), statistics(inferences, I1), D is I1 - I0."
             ) ==
               6
    end

    test "über Anfragen hinweg in der Sitzung", c do
      [a] = ask(c, "statistics(inferences, I).")
      [b] = ask(c, "statistics(inferences, I).")
      [_, i1] = Regex.run(~r/I = (\d+)/, a)
      [_, i2] = Regex.run(~r/I = (\d+)/, b)
      assert String.to_integer(i2) == String.to_integer(i1) + 1
    end
  end

  describe "BEAM" do
    test "reductions: [R, D], wächst", c do
      assert ask(
               c,
               "statistics(reductions, [R0, _]), numlist(1, 10000, L), sum_list(L, _), " <>
                 "statistics(reductions, [R1, D]), R1 > R0, D =:= R1 - R0, !."
             )
             |> length() == 1
    end

    test "Speicher, GC, System", c do
      assert ask(c, "statistics(memory, [M, 0]), integer(M), M > 1000, !.") |> length() == 1
      assert ask(c, "statistics(process_memory, M), integer(M), M > 1000, !.") |> length() == 1

      assert ask(c, "statistics(vm_memory, M), statistics(process_memory, P), M > P, !.")
             |> length() == 1

      assert ask(c, "statistics(garbage_collection, [N, B, 0]), integer(N), integer(B), !.")
             |> length() == 1

      assert ask(c, "statistics(schedulers, S), integer(S), S >= 1, !.") |> length() == 1
      assert ask(c, "statistics(process_count, P), integer(P), P > 1, !.") |> length() == 1
    end
  end

  test "statistics/0: Übersicht", c do
    out = capture_io(fn -> assert ask(c, "statistics.") == ["true"] end)

    for label <- [
          "CPU-Zeit",
          "Laufzeit",
          "Inferenzen",
          "Reduktionen",
          "Speicher Sitzung",
          "Speicher VM",
          "GC",
          "Scheduler",
          "System"
        ] do
      assert out =~ "% " <> label, label
    end

    assert out =~ "Erlang/OTP #{:erlang.system_info(:otp_release)}"
  end

  test "Fehler", c do
    assert err(c, "statistics(K, V).") =~ "instantiation_error"
    assert err(c, "statistics(foo, V).") =~ "domain_error(statistics_key, foo)"
    assert err(c, "statistics(1, V).") =~ "type_error(atom, 1)"
  end
end
