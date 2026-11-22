defmodule PrologEx.TraceTest do
  # Der Tracer (PrologEx.Trace): Ports Call, Exit, Redo, Fail, Exception
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Stream.reset()
    PrologEx.Trace.reset()
    :ok
  end

  @src ~S"""
  :- use_module(library(lists)).
  :- use_module(library(iso_ext)).
  :- use_module(library(between)).
  app([], L, L).
  app([H|T], L, [H|R]) :- app(T, L, R).
  nrev([], []).
  nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R).
  p(X) :- q(X), X > 1.
  q(1). q(2). q(3).
  r(X) :- catch(s(X), E, X = caught(E)).
  s(_) :- throw(oops).
  c(X) :- q(X), !.
  fib(0, 0).
  fib(1, 1).
  fib(N, F) :- N > 1, A is N-1, B is N-2, fib(A, FA), fib(B, FB), F is FA+FB.
  w :- setup_call_cleanup(true, q(1), write(cleanup)), write(after).
  ws(X) :- setup_call_cleanup(true, q(X), write(c)), X > 1.
  qa(X) :- X = 'a b'.
  mk(L) :- length(L, 3000), maplist(=(a), L), mk2(L).
  mk2(L) :- length(L, N), N > 0.
  la(L) :- append([1], [2], L).
  """

  defp load do
    f = Path.join(System.tmp_dir!(), "px_trace_#{System.unique_integer([:positive])}.pl")
    File.write!(f, @src)
    PrologEx.put_db(%{})

    try do
      assert ExUnit.CaptureIO.capture_io(:stderr, fn ->
               {:ok, _} = PrologEx.Consult.load_file(f)
             end) == ""
    after
      File.rm(f)
    end
  end

  defp run(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(1)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  # die Ports (ohne Fragen: leash(none)) als Zeilen
  defp trace(c, q) do
    load()

    err =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        send(self(), {:answer, run(c, "leash(none), trace, (#{q}), notrace ; notrace, fail")})
      end)

    assert_received {:answer, _}

    err
    |> String.split("\n", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.replace(~r/_\d+/, "_")))
  end

  test "Call und Exit; Tiefe; Variablen beim Aufruf, Bindungen bei Exit", c do
    assert trace(c, "nrev([1,2], R)") == [
             "Call: (1) nrev([1,2],_)",
             "Call: (2) nrev([2],_)",
             "Call: (3) nrev([],_)",
             "Exit: (3) nrev([],[])",
             "Call: (3) app([],[2],_)",
             "Exit: (3) app([],[2],[2])",
             "Exit: (2) nrev([2],[2])",
             "Call: (2) app([2],[1],_)",
             "Call: (3) app([],[1],_)",
             "Exit: (3) app([],[1],[1])",
             "Exit: (2) app([2],[1],[2,1])",
             "Exit: (1) nrev([1,2],[2,1])"
           ]
  end

  test "Fail und Redo", c do
    assert trace(c, "p(X)") == [
             "Call: (1) p(_)",
             "Call: (2) q(_)",
             "Exit: (2) q(1)",
             "Call: (2) 1>1",
             "Fail: (2) 1>1",
             "Redo: (2) q(_)",
             "Exit: (2) q(2)",
             "Call: (2) 2>1",
             "Exit: (2) 2>1",
             "Exit: (1) p(2)"
           ]

    # \+: das Ziel scheitert, \+ gelingt
    assert trace(c, "\\+ q(4)") ==
             ["Call: (1) \\+q(4)", "Call: (2) q(4)", "Fail: (2) q(4)", "Exit: (1) \\+q(4)"]

    # die letzte Lösung deterministisch: kein Redo, kein Fail mehr
    assert trace(c, "findall(X, q(X), L)") == [
             "Call: (1) findall(_,q(_),_)",
             "Call: (2) q(_)",
             "Exit: (2) q(1)",
             "Redo: (2) q(_)",
             "Exit: (2) q(2)",
             "Redo: (2) q(_)",
             "Exit: (2) q(3)",
             "Exit: (1) findall(_,q(_),[1,2,3])"
           ]
  end

  test "Schnitt: was abgeschnitten ist, meldet kein Fail", c do
    assert trace(c, "c(X)") ==
             ["Call: (1) c(_)", "Call: (2) q(_)", "Exit: (2) q(1)", "Exit: (1) c(1)"]
  end

  test "Exception für jeden Aufruf, den die Ausnahme verlässt", c do
    assert trace(c, "r(X)") == [
             "Call: (1) r(_)",
             "Call: (2) catch(s(_),_,_=caught(_))",
             "Call: (3) s(_)",
             "Call: (4) throw(oops)",
             "Exception: (4) throw(oops) – oops",
             "Exception: (3) s(_) – oops",
             "Call: (3) _=caught(oops)",
             "Exit: (3) caught(oops)=caught(oops)",
             "Exit: (2) catch(s(caught(oops)),oops,caught(oops)=caught(oops))",
             "Exit: (1) r(caught(oops))"
           ]
  end

  test "übersetzte Prädikate (JIT) im Interpreter, Arithmetik wie im Quelltext", c do
    load()
    # aufwärmen: danach ist fib/2 übersetzt
    run(c, "between(1, 50, _), fib(12, _), fail ; true")

    assert trace(c, "fib(2, F)") == [
             "Call: (1) fib(2,_)",
             "Call: (2) 2>1",
             "Exit: (2) 2>1",
             "Call: (2) _ is 2-1",
             "Exit: (2) 1 is 2-1",
             "Call: (2) _ is 2-2",
             "Exit: (2) 0 is 2-2",
             "Call: (2) fib(1,_)",
             "Exit: (2) fib(1,1)",
             "Call: (2) fib(0,_)",
             "Exit: (2) fib(0,0)",
             "Call: (2) _ is 1+0",
             "Exit: (2) 1 is 1+0",
             "Exit: (1) fib(2,1)"
           ]
  end

  test "Bibliotheksprädikate als eine Box", c do
    assert trace(c, "la(L)") == [
             "Call: (1) la(_)",
             "Call: (2) append([1],[2],_)",
             "Exit: (2) append([1],[2],[1,2])",
             "Exit: (1) la([1,2])"
           ]
  end

  # deterministisch gelungen: der Fail-Punkt geht weg, setup_call_cleanup/3
  # räumt wie ohne Tracer sofort auf
  test "Cleanup zur selben Zeit wie ohne Tracer", c do
    load()
    out = ExUnit.CaptureIO.capture_io(fn -> run(c, "w") end)

    traced =
      ExUnit.CaptureIO.capture_io(fn ->
        ExUnit.CaptureIO.capture_io(:stderr, fn -> run(c, "leash(none), trace, w, notrace") end)
      end)

    assert out == "cleanupafter"
    assert traced == out
  end

  test "ohne trace keine Ausgabe; tracing/0; leash/1", c do
    load()

    assert ExUnit.CaptureIO.capture_io(:stderr, fn ->
             assert run(c, "nrev([1], _)") == ["true"]
           end) ==
             ""

    assert run(c, "tracing") == []

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert run(c, "leash(none), trace, tracing, notrace") == ["true"]
    end)

    assert run(c, "leash(all), leash(L)") == ["L = [call,exit,redo,fail,exception]"]
    assert run(c, "leash(half), leash(L)") == ["L = [call,redo]"]
    assert run(c, "leash(half), leash(+exit), leash(-call), leash(L)") == ["L = [exit,redo]"]
    assert run(c, "leash(none), leash(L)") == ["L = []"]
    assert run(c, "catch(leash(foo), error(E, _), true)") == ["E = domain_error(leash_port,foo)"]
  end

  # mit Fragen: die Antworten (Zeilen) aus einem Stream; die Ports je Zeile
  defp itrace(c, q, answers) do
    load()
    PrologEx.Trace.reset()
    # (danach Enter: ohne Eingabe liefe er ohne Fragen weiter)
    text = Enum.join(answers ++ List.duplicate("", 40), "\n") <> "\n"
    PrologEx.Trace.put_input(PrologEx.Stream.open_memory(text))

    err =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        send(self(), {:answer, run(c, "trace, (#{q}), notrace ; notrace, fail")})
      end)

    assert_received {:answer, a}

    lines =
      err
      |> String.replace(" ? ", "\n")
      |> String.split("\n", trim: true)
      |> Enum.map(&(&1 |> String.trim() |> String.replace(~r/_\d+/, "_")))

    {a, lines}
  end

  test "retry an Fail, Exit, Redo, Exception", c do
    # an Fail von 1>1: noch einmal 1>1
    assert {["X = 2"], lines} = itrace(c, "p(X)", ["", "", "", "", "r"])

    assert Enum.take(lines, 7) == [
             "Call: (1) p(_)",
             "Call: (2) q(_)",
             "Exit: (2) q(1)",
             "Call: (2) 1>1",
             "Fail: (2) 1>1",
             "Call: (2) 1>1",
             "Fail: (2) 1>1"
           ]

    # an Exit von q(1): q von vorn, die Bindung X = 1 ist weg
    assert {["X = 2"], lines} = itrace(c, "p(X)", ["", "", "r"])
    assert Enum.slice(lines, 2..4) == ["Exit: (2) q(1)", "Call: (2) q(_)", "Exit: (2) q(1)"]

    # an Redo von q
    assert {["X = 2"], lines} = itrace(c, "p(X)", ["", "", "", "", "", "r"])
    assert Enum.slice(lines, 5..7) == ["Redo: (2) q(_)", "Call: (2) q(_)", "Exit: (2) q(1)"]

    # an Exception: throw/1 noch einmal, dann weiter wie zuvor
    assert {["X = caught(oops)"], lines} = itrace(c, "r(X)", ["", "", "", "", "r"])

    assert Enum.slice(lines, 3..7) == [
             "Call: (4) throw(oops)",
             "Exception: (4) throw(oops) – oops",
             "Call: (4) throw(oops)",
             "Exception: (4) throw(oops) – oops",
             "Exception: (3) s(_) – oops"
           ]
  end

  test "retry in findall/3 und nach vielen Bindungen (Kompaktierung)", c do
    assert {["L = [1,2,3]"], lines} = itrace(c, "findall(X, q(X), L)", ["", "", "r"])
    assert Enum.slice(lines, 2..4) == ["Exit: (2) q(1)", "Call: (2) q(_)", "Exit: (2) q(1)"]

    # retry an Exit von mk/1 (der zehnte Port; "<3" fragt denselben noch einmal)
    assert {["N = 3000"], lines} =
             itrace(c, "mk(_L), length(_L, N)", ["<3"] ++ List.duplicate("", 9) ++ ["r"])

    assert Enum.count(lines, &String.starts_with?(&1, "Exit: (1) mk(")) == 2
    assert Enum.count(lines, &String.starts_with?(&1, "Exit: (3) 3000>0")) == 2
  end

  test "retry und fail räumen ab wie ein Schnitt (setup_call_cleanup/3)", c do
    # an Exit des (nichtdeterministischen) setup_call_cleanup: der Rahmen
    # wird abgeschnitten – sein Cleanup läuft –, dann neu
    out =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {["X = 2"], lines} = itrace(c, "ws(X)", List.duplicate("", 6) ++ ["r"])

        # (der Cleanup läuft hier wie im Rumpf: (call(C) -> true ; true))
        assert Enum.slice(lines, 6..11) == [
                 "Exit: (2) setup_call_cleanup(true,q(1),write(c))",
                 "Call: (2) write(c)",
                 "Exit: (2) write(c)",
                 "Call: (2) true",
                 "Exit: (2) true",
                 "Call: (2) setup_call_cleanup(true,q(_),write(c))"
               ]
      end)

    assert out == "c"

    # fail an derselben Stelle: Cleanup, dann scheitert ws/1
    out =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], lines} = itrace(c, "ws(X)", List.duplicate("", 6) ++ ["f"])

        assert Enum.slice(lines, 6..12) == [
                 "Exit: (2) setup_call_cleanup(true,q(1),write(c))",
                 "Call: (2) write(c)",
                 "Exit: (2) write(c)",
                 "Call: (2) true",
                 "Exit: (2) true",
                 "Fail: (2) setup_call_cleanup(true,q(_),write(c))",
                 "Fail: (1) ws(_)"
               ]
      end)

    assert out == "c"
  end

  test "skip, Schreibweise (w, p, d, < N)", c do
    assert {["R = [2,1]"], lines} = itrace(c, "nrev([1,2], R)", ["", "s"])

    assert Enum.take(lines, 4) == [
             "Call: (1) nrev([1,2],_)",
             "Call: (2) nrev([2],_)",
             "Exit: (2) nrev([2],[2])",
             "Call: (2) app([2],[1],_)"
           ]

    assert {_, lines} = itrace(c, "qa(X)", ["", "w", "", "p"])
    assert lines == ["Call: (1) qa(_)", "Exit: (1) qa('a b')", "Exit: (1) qa(a b)"]
    assert {_, lines} = itrace(c, "nrev([1,2], R)", ["<1"])
    assert Enum.take(lines, 2) == ["Call: (1) nrev([1,2],_)", "Call: (1) nrev(...,...)"]
  end

  defp quiet(c, q) do
    out = ExUnit.CaptureIO.capture_io(:stderr, fn -> send(self(), {:a, run(c, q)}) end)
    assert_received {:a, a}
    {a, out |> String.replace(~r/_\d+/, "_") |> String.split("\n", trim: true)}
  end

  test "Spypunkte: still bis zum ersten, dann Trace-Modus", c do
    load()

    assert quiet(c, "leash(none), spy(app/3), nrev([1,2],R), nodebug") ==
             {["R = [2,1]"],
              [
                "% Spypunkt auf app/3",
                " * Call: (1) app([],[2],_)",
                " * Exit: (1) app([],[2],[2])",
                " * Call: (1) app([2],[1],_)",
                " * Call: (2) app([],[1],_)",
                " * Exit: (2) app([],[1],[1])",
                " * Exit: (1) app([2],[1],[2,1])"
              ]}

    # der Spypunkt schaltete den Trace-Modus ein – nur bis zum Ende der Anfrage
    PrologEx.Trace.reset()
    quiet(c, "leash(none), spy(app/3), nrev([1],_)")
    assert run(c, "tracing") == []
    assert PrologEx.Trace.mode() == :debug

    PrologEx.Trace.reset()
    # spy/1 schaltet den Debug-Modus ein, nicht den Trace-Modus
    assert quiet(c, "spy(app/3), tracing") == {[], ["% Spypunkt auf app/3"]}
    PrologEx.Trace.reset()

    assert {["true"], out} =
             quiet(
               c,
               "spy(app), debugging, nospy(app/3), nospy(app), debugging, nospyall, nodebug, debugging"
             )

    assert out == [
             "% Spypunkt auf app",
             "% Debug-Modus; Spypunkte: app",
             "% leash: [call,exit,redo,fail,exception], visible: [call,exit,redo,fail,exception]",
             "% Spypunkt auf app entfernt",
             "% Debug-Modus; keine Spypunkte",
             "% leash: [call,exit,redo,fail,exception], visible: [call,exit,redo,fail,exception]",
             "% Debugger aus; keine Spypunkte",
             "% leash: [call,exit,redo,fail,exception], visible: [call,exit,redo,fail,exception]"
           ]

    assert run(c, "catch(spy(foo/bar), error(E, _), true)") ==
             ["E = type_error(predicate_indicator,foo/bar)"]
  end

  # leap: im Debug-Modus still bis zum nächsten Port eines Prädikats mit
  # Spypunkt (hier jeder Port von app/3)
  test "leap: bis zum nächsten Spypunkt", c do
    PrologEx.Trace.reset()
    load()
    ExUnit.CaptureIO.capture_io(:stderr, fn -> run(c, "spy(app/3)") end)
    PrologEx.Trace.put_input(PrologEx.Stream.open_memory("l\nl\nl\nl\nl\nl\n"))

    out =
      ExUnit.CaptureIO.capture_io(:stderr, fn -> send(self(), {:a, run(c, "nrev([1,2], R)")}) end)

    assert_received {:a, ["R = [2,1]"]}

    assert out
           |> String.replace(~r/_\d+/, "_")
           |> String.replace(" ? ", "\n")
           |> String.split("\n", trim: true) == [
             " * Call: (1) app([],[2],_)",
             " * Exit: (1) app([],[2],[2])",
             " * Call: (1) app([2],[1],_)",
             " * Call: (2) app([],[1],_)",
             " * Exit: (2) app([],[1],[1])",
             " * Exit: (1) app([2],[1],[2,1])"
           ]
  end

  test "visible/1: nicht gezeigte Ports", c do
    load()

    assert {["X = 2"], out} = quiet(c, "leash(none), visible(-exit), trace, p(X), notrace")

    assert out ==
             [
               "Call: (1) p(_)",
               "Call: (2) q(_)",
               "Call: (2) 1>1",
               "Fail: (2) 1>1",
               "Redo: (2) q(_)",
               "Call: (2) 2>1"
             ]
             |> Enum.map(&("   " <> &1))
  end
end
