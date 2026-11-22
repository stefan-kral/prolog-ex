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
    PrologEx.Trace.put_leash(PrologEx.Trace.ports())
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
end
