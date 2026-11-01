defmodule PrologEx.TimeLimitsTest do
  # library(time): sleep/1, sleep_ms/1, set_timer/1, cancel_timer/0,
  # call_with_timeout/2,3, call_with_time_limit/2
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @tle "time_limit_exceeded"
  @inst "instantiation_error"
  @loop "(repeat, fail)"

  @rows [
    # Fehler
    {"sleep(_)", {:error, @inst}},
    {"sleep(a)", {:error, "type_error(number,a)"}},
    {"sleep(-1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"sleep_ms(_)", {:error, @inst}},
    {"sleep_ms(-0.5)", {:error, "domain_error(not_less_than_zero,-0.5)"}},
    {"set_timer(x)", {:error, "type_error(number,x)"}},
    {"call_with_timeout(true, _)", {:error, @inst}},
    {"call_with_timeout(true, a)", {:error, "type_error(number,a)"}},
    {"call_with_timeout(true, -1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"call_with_timeout(true, 1, _)", {:error, @inst}},
    {"call_with_timeout(true, 1, [a|_])", {:error, @inst}},
    {"call_with_timeout(true, 1, foo)", {:error, "type_error(list,foo)"}},
    {"call_with_timeout(true, 1, [_])", {:error, @inst}},
    {"call_with_timeout(true, 1, [foo])", {:error, "domain_error(call_with_timeout_option,foo)"}},
    {"call_with_timeout(true, 1, [mode(x)])",
     {:error, "domain_error(call_with_timeout_option,mode(x))"}},
    {"call_with_timeout(true, 1, [mode(_)])", {:error, @inst}},
    {"call_with_timeout(true, 1, [on_timeout(_)])", {:error, @inst}},
    {"call_with_timeout(true, 1, [on_timeout(1)])", {:error, "type_error(callable,1)"}},
    {"call_with_time_limit(a, true)", {:error, "type_error(number,a)"}},
    # ohne Zeitüberschreitung: wie call/1 (Lösungen, Fehlschlag, Ausnahmen)
    {"call_with_timeout(true, 1)", true},
    {"call_with_timeout(member(X, [a,b,c]), 1)", ["X = a", "X = b", "X = c"]},
    {"call_with_timeout(fail, 1)", :fails},
    {"call_with_timeout(throw(x), 1)", {:error, "x"}},
    {"catch(call_with_timeout(throw(x), 1), x, true)", true},
    {"call_with_timeout(member(X, [a,b]), 1, [mode(per_answer)])", ["X = a", "X = b"]},
    {"call_with_time_limit(1, member(X, [a,b]))", ["X = a"]},
    {"sleep(0)", true},
    {"sleep_ms(1.5)", true},
    # Zeitüberschreitung
    {"call_with_timeout(#{@loop}, 0.02)", {:error, @tle}},
    {"call_with_timeout(true, 0)", {:error, @tle}},
    {"call_with_timeout(#{@loop}, 0.02, [on_timeout(fail)])", :fails},
    {"call_with_timeout(#{@loop}, 0.02, [on_timeout(X = t)])", ["X = t"]},
    {"call_with_timeout(#{@loop}, 0.02, [on_timeout(fail), on_timeout(X = t)])", ["X = t"]},
    {"call_with_timeout(#{@loop}, 0.02, [on_timeout(throw)])", {:error, @tle}},
    {"call_with_time_limit(0.02, #{@loop})", {:error, @tle}},
    # sleep schläft nur bis zur Deadline
    {"call_with_timeout(sleep(30), 0.02, [on_timeout(X = t)])", ["X = t"]},
    {"call_with_timeout(sleep_ms(30000), 0.02, [on_timeout(X = t)])", ["X = t"]},
    # G kann die Ausnahme nicht verschlucken: sie kommt wieder, auch wenn G
    # danach ohne gezählten Schritt endet
    {"call_with_timeout(catch(#{@loop}, _, true), 0.02, [on_timeout(X = t)])", ["X = t"]},
    {"call_with_timeout(catch(#{@loop}, _, !), 0.02, [on_timeout(X = t)])", ["X = t"]},
    # ... auch wenn G danach scheitert: der Prüfpunkt bleibt gerissen,
    # schon der nächste Schritt wirft wieder
    {"call_with_timeout((catch(#{@loop}, _, true), fail), 0.02, [on_timeout(X = t)])", ["X = t"]},
    # die erste Prüfung kommt sofort: bei abgelaufener Frist läuft G nicht
    {"call_with_timeout(fail, 0, [on_timeout(X = t)])", ["X = t"]},
    # verschachtelt: wer zuerst abläuft, fängt
    {"call_with_timeout(call_with_timeout(#{@loop}, 30, [on_timeout(X = innen)]), 0.02, " <>
       "[on_timeout(X = aussen)])", ["X = aussen"]},
    {"call_with_timeout(call_with_timeout(#{@loop}, 0.02, [on_timeout(X = innen)]), 30, " <>
       "[on_timeout(X = aussen)])", ["X = innen"]},
    {"call_with_timeout(call_with_timeout(#{@loop}, 0.02), 30, [on_timeout(X = aussen)])",
     {:error, @tle}},
    # zusammen mit Inferenzgrenzen
    {"call_with_timeout(call_with_inference_limit(#{@loop}, 1000, R), 30)",
     ["R = inference_limit_exceeded"]},
    {"call_with_inference_limit(call_with_timeout(#{@loop}, 0.02, [on_timeout(R = t)]), " <>
       "100000000, _)", ["R = t"]},
    # in Unter-Maschinen
    {"findall(X, call_with_timeout(#{@loop}, 0.02, [on_timeout(X = t)]), L)", ["L = [t]"]},
    {"call_with_timeout(findall(x, #{@loop}, _), 0.02, [on_timeout(X = t)])", ["X = t"]},
    {"call_with_timeout(\\+ #{@loop}, 0.02, [on_timeout(X = t)])", ["X = t"]},
    # Budget: kumulativ über alle Lösungen oder je Lösung
    {"call_with_timeout((member(X, [1,2,3,4]), sleep(0.05)), 0.125, [on_timeout(X = t)])",
     ["X = 1", "X = 2", "X = t"]},
    {"call_with_timeout((member(X, [1,2,3,4]), sleep(0.05)), 0.2, " <>
       "[mode(per_answer), on_timeout(X = t)])", ["X = 1", "X = 2", "X = 3", "X = 4"]},
    {"call_with_timeout((member(X, [1,2]), sleep(0.03)), 0.05, [mode(cumulative), " <>
       "mode(per_answer), on_timeout(X = t)])", ["X = 1", "X = 2"]},
    # nach Fehlschlag oder Ausgang von G ist die Grenze weg; die Zeit
    # außerhalb von G (zwischen den Lösungen) zählt nicht
    {"(call_with_timeout(fail, 0.02) ; sleep(0.05))", true},
    {"call_with_timeout(true, 0.02), sleep(0.05)", true},
    {"call_with_timeout(member(X, [a,b]), 0.05), sleep(0.08), X == b", ["X = b"]},
    # beim Wiedereintritt gilt die Grenze wieder
    {"call_with_timeout((member(X, [1,2]), (X == 2 -> #{@loop} ; true)), 0.05, " <>
       "[on_timeout(X = t)])", ["X = 1", "X = t"]},
    # eine Lösung nach Ablauf der Frist zählt nicht, auch ohne Prüfpunkt
    # dazwischen (ein langes eingebautes Ziel)
    {"call_with_timeout((numlist(1, 600000, _L), msort(_L, _)), 0.002, [on_timeout(X = t)])",
     ["X = t"]},
    # beide abgelaufen: die frühere Grenze fängt
    {"call_with_timeout(call_with_timeout((numlist(1, 600000, _L), msort(_L, _), " <>
       "#{@loop}), 0.06, [on_timeout(fail)]), 0.05, [on_timeout(X = aussen)])", ["X = aussen"]},
    # sehr lange Schlafzeiten (über 2^32 ms) werden unterbrochen
    {"max_sleep_time(N), M is N + 1, call_with_timeout(sleep_ms(M), 0.02, [on_timeout(true)])",
     :succeeds},
    {"max_sleep_time(N), M is N * 1000 + 1, sleep_ms(M)",
     {:error, "representation_error(max_sleep_time)"}},
    # set_timer/1
    {"catch((set_timer(0.02), #{@loop}), E, true)", ["E = #{@tle}"]},
    {"catch((set_timer(0.02), sleep(30)), E, true)", ["E = #{@tle}"]},
    {"catch((set_timer(30), set_timer(0.02), #{@loop}), E, true)", ["E = #{@tle}"]},
    {"set_timer(0.02), cancel_timer, sleep(0.05)", true},
    {"cancel_timer", true},
    # wirkt auf die laufende Anfrage: beim nächsten Schritt
    {"set_timer(0), true", {:error, @tle}},
    # gesetzt in einer Unter-Maschine, gilt danach auch außen
    {"catch((findall(x, set_timer(0.02), _), #{@loop}), E, true)", ["E = #{@tle}"]},
    {"catch((\\+ \\+ set_timer(0.02), #{@loop}), E, true)", ["E = #{@tle}"]},
    {"catch(((\\+ set_timer(0.02) ; true), #{@loop}), E, true)", ["E = #{@tle}"]},
    # Backtracking nimmt ihn nicht zurück
    {"catch(((set_timer(0.02), fail ; true), #{@loop}), E, true)", ["E = #{@tle}"]},
    # er läuft einmal ab
    {"catch((set_timer(0.02), #{@loop}), _, true), sleep(0.05)", true},
    # verschachtelt mit call_with_timeout
    {"catch(call_with_timeout((set_timer(0.02), #{@loop}), 30, [on_timeout(X = t)]), E, true)",
     ["E = #{@tle}"]}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(time lists iso_ext between))}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  for {q, expect} <- @rows do
    test q, c do
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  defp ms(c, q) do
    {us, actual} = :timer.tc(fn -> TableCase.run(c.reader, c.db, q) end)
    {div(us, 1000), actual}
  end

  test "Zeitüberschreitung kommt pünktlich (alle 1000 Inferenzen geprüft)", c do
    for q <- [
          "call_with_timeout(#{@loop}, 0.1, [on_timeout(true)])",
          "call_with_timeout((repeat, length(_, 50), fail), 0.1, [on_timeout(true)])",
          "call_with_timeout(sleep(5), 0.1, [on_timeout(true)])",
          "catch((set_timer(0.1), #{@loop}), _, true)"
        ] do
      {t, {_, {:answers, ["true"]}}} = ms(c, q)
      assert t in 100..1000, "#{q}: #{t} ms"
    end
  end

  test "sleep_ms/1 schläft ceiling(Ms), sleep/1 ceiling(S * 1000) Millisekunden", c do
    {t, _} = ms(c, "sleep_ms(30.2)")
    assert t >= 31
    {t, _} = ms(c, "sleep(0.05)")
    assert t >= 50
  end

  test "der Timer gilt nur in seiner Anfrage", c do
    assert {_, {:error, @tle}} = TableCase.run(c.reader, c.db, "set_timer(0.01), sleep(1)")
    assert {_, {:answers, ["true"]}} = TableCase.run(c.reader, c.db, "set_timer(0.01)")
    assert {_, {:answers, ["true"]}} = TableCase.run(c.reader, c.db, "sleep(0.05)")
    assert Process.get(:prolog_ex_timers, %{}) == %{}
    # auch wenn die Anfrage scheitert
    assert {_, {:answers, []}} = TableCase.run(c.reader, c.db, "(set_timer(10) ; true), fail")
    assert Process.get(:prolog_ex_timers, %{}) == %{}
  end

  test "Cleanups laufen beim Abbruch", c do
    {db, []} =
      PrologEx.Consult.load(
        c.db,
        Reader.read_terms(c.reader, ":- dynamic(aufgeraeumt/0).\n")
      )

    q =
      "call_with_timeout(setup_call_cleanup(true, #{@loop}, assertz(aufgeraeumt)), 0.02, " <>
        "[on_timeout(true)]), aufgeraeumt"

    assert {_, {:answers, ["true"]}} = TableCase.run(c.reader, db, q)
  end

  test "deterministisches G hinterlässt keinen Choice Point", c do
    [{:term, g, _}] = Reader.read_terms(c.reader, "call_with_timeout(X = 1, 1).")
    assert [{_, false}] = c.db |> PrologEx.solutions(g) |> Enum.to_list()
  end

  test "'$ceil_scaled'/3: Floats als die gezeigte Dezimalzahl" do
    f = &PrologEx.Builtins.ScryerPrims.ceil_scaled/2
    assert f.(1.1, 1000) == 1100
    assert f.(0.1, 1000) == 100
    assert f.(30.2, 1) == 31
    assert f.(30.0, 1) == 30
    assert f.(0.0001, 1) == 1
    assert f.(1.0e-4, 1_000_000) == 100
    assert f.(1.0e-7, 1_000_000) == 1
    assert f.(0.0, 1000) == 0
    assert f.(1.5e20, 1) == 150_000_000_000_000_000_000
    assert f.(7, 1000) == 7000
  end
end
