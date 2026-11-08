defmodule PrologEx.ConcurrentTest do
  # library(concurrent): Ziele parallel in BEAM-Prozessen, super-strikt ohne
  # Seiteneffekte
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  @src ~S"""
  :- use_module(library(concurrent)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(lambda)).
  :- use_module(library(time)).
  :- use_module(library(iso_ext)).
  :- dynamic(f/1).
  sq(X, Y) :- Y is X * X.
  fib(0, 0).
  fib(1, 1).
  fib(N, F) :- N > 1, N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.
  loop :- loop.
  slow(X) :- fib(20, _), X = slow.
  big(L) :- numlist(1, 2000000, L).
  """

  defp ask(c, q, src \\ @src) do
    f = Path.join(System.tmp_dir!(), "px_conc_#{System.unique_integer([:positive])}.pl")
    File.write!(f, src)
    PrologEx.put_db(%{})

    try do
      err =
        ExUnit.CaptureIO.capture_io(:stderr, fn -> {:ok, _} = PrologEx.Consult.load_file(f) end)

      assert err == ""
    after
      File.rm(f)
    end

    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "concurrent_maplist/2,3,4: Ergebnisse in der Reihenfolge der Elemente", c do
    assert ask(c, "concurrent_maplist(sq, [1, 2, 3, 4], Ys)") == ["Ys = [1,4,9,16]"]
    assert ask(c, ~S"concurrent_maplist(\X^(X > 0), [1, 2, 3])") == ["true"]
    assert ask(c, ~S"concurrent_maplist(\X^(X < 3), [1, 2, 3])") == []

    assert ask(c, ~S"concurrent_maplist(\X^Y^Z^(Z is X + Y), [1, 2], [10, 20], Zs)") ==
             ["Zs = [11,22]"]

    assert ask(c, "concurrent_maplist(sq, [], Ys)") == ["Ys = []"]
    # deterministisch
    assert ask(c, "call_cleanup(concurrent_maplist(sq, [1, 2], Ys), Det = true)") ==
             ["Det = true, Ys = [1,4]"]

    # mehr Elemente als Scheduler
    assert ask(c, "numlist(1, 40, L), concurrent_maplist(sq, L, Ys), sum_list(Ys, S)") |> hd() =~
             "S = 22140"
  end

  test "ein Seiteneffekt beendet alles; die Ausnahme kommt beim Aufrufer an", c do
    [a] =
      ask(
        c,
        ~S"catch(concurrent_maplist(\X^(X > 2 -> assertz(f(X)) ; true), [1, 2, 3, 4]), error(E, _), true)"
      )

    assert a =~ ~r/E = permission_error\(perform,side_effect,assertz\(f\([34]\)\)\)/

    assert ask(c, "catch(concurrent_maplist(sq, [1, a], _), error(E, _), true)") ==
             ["E = type_error(evaluable,a/0)"]

    # nichts ist geschehen
    assert ask(c, ~S"catch(concurrent_maplist(\X^assertz(f(X)), [1, 2]), _, true), \+ f(_)") ==
             ["true"]
  end

  test "concurrent/3, concurrent_forall/2,3, concurrent_findall/3", c do
    assert ask(c, "concurrent(2, [A = 1, B is 1 + 1, C = c], [])") == ["A = 1, B = 2, C = c"]
    assert ask(c, "concurrent(2, [A = 1, A = 2], [])") == []
    assert ask(c, "concurrent_forall(member(X, [1, 2, 3]), X > 0)") == ["true"]
    assert ask(c, "concurrent_forall(member(X, [1, 2, 3]), X > 1, [workers(1)])") == []

    assert ask(c, "concurrent_findall(X, [member(X, [a, b]), member(X, [c]), fail], Bs)") ==
             [~S|Bs = ["ab","c",[]]|]
  end

  test "first_solution/3: der Schnellste gewinnt, die anderen werden beendet", c do
    before = length(Process.list())

    assert ask(c, "first_solution(X, [(loop, X = 1), X = quick, (slow(S), X = S)], [])") ==
             ["X = quick"]

    Process.sleep(50)
    assert length(Process.list()) <= before + 1

    assert ask(c, "first_solution(X, [fail, (slow(S), X = S)], [on_fail(continue)])") ==
             ["X = slow"]

    assert ask(c, "first_solution(X, [fail, fail], [on_fail(continue)])") == []
    # Vorgabe on_fail(stop): das erste Scheitern beendet alles
    assert ask(c, "first_solution(X, [fail, (slow(S), X = S)], [])") == []
    assert ask(c, "first_solution(X, [fail, (slow(S), X = S)], [on_fail(stop)])") == []
    assert ask(c, "first_solution(_, [], [])") == []
  end

  test "Grenzen des Aufrufers gelten auch für die Kinder", c do
    {us, res} =
      :timer.tc(fn ->
        ask(c, ~S"catch(call_with_time_limit(0.3, concurrent_maplist(\_^loop, [1, 2])), E, true)")
      end)

    assert res == ["E = time_limit_exceeded"]
    assert us < 3_000_000

    assert ask(c, ~S"call_with_inference_limit(concurrent_maplist(\_^loop, [1]), 10000, R)") ==
             ["R = inference_limit_exceeded"]

    # die Inferenzen der Kinder zählen: jedes bleibt unter dem Budget
    # (fib(12): etwa 1400), zusammen nicht
    assert ask(
             c,
             ~S"call_with_inference_limit(concurrent_maplist(\_^fib(12, _), [1, 2, 3]), 4000, R)"
           ) ==
             ["R = inference_limit_exceeded"]

    assert ask(c, ~S"call_with_inference_limit(concurrent_maplist(\_^fib(12, _), [1]), 4000, R)") ==
             ["R = !"]

    assert ask(
             c,
             ~S"call_with_inference_limit(concurrent_maplist(\_^fib(15, _), [1, 2, 3]), 3000, R)"
           ) ==
             ["R = inference_limit_exceeded"]

    assert ask(
             c,
             ~S"call_with_inference_limit(concurrent_maplist(\_^fib(5, _), [1, 2]), 1000000, R)"
           ) ==
             ["R = !"]

    assert ask(
             c,
             ~S"catch(call_with_memory_limit(concurrent_maplist(\_^big(_), [1]), 1000000), error(E, _), true)"
           ) ==
             ["E = resource_error(memory)"]
  end

  test "attributierte Variablen: representation_error", c do
    assert ask(c, ~S"catch(concurrent_maplist(\X^dif(X, a), [_]), error(E, _), true)") ==
             ["E = representation_error(concurrent_attributed_variable)"]

    # im Ziel (nicht im Template): ohne Bedingung rechnete das Kind falsch
    assert ask(c, "dif(Y, a), catch(first_solution(X, [(Y = a, X = 1)], []), error(E, _), true)")
           |> hd() =~ "E = representation_error(concurrent_attributed_variable)"

    assert ask(c, ~S"dif(Y, a), catch(concurrent_maplist(\_^true, [Y]), error(E, _), true)")
           |> hd() =~
             "E = representation_error(concurrent_attributed_variable)"
  end

  test "im Bereich ohne Seiteneffekte erlaubt (die Kinder sind es ohnehin)", c do
    assert ask(c, "call_with_no_side_effects(concurrent_maplist(sq, [2, 3], Ys))") ==
             ["Ys = [4,9]"]
  end

  test "parallel schneller als nacheinander (bei mehr als einem Scheduler)", c do
    if System.schedulers_online() > 1 do
      [a] =
        ask(
          c,
          ~S"numlist(1, 4, L), statistics(walltime, [A0|_]), concurrent_maplist(\_^F^fib(20, F), L, Fs), " <>
            ~S"statistics(walltime, [A1|_]), maplist(\_^F^fib(20, F), L, Fs), statistics(walltime, [A2|_]), " <>
            "P is A1 - A0, S is A2 - A1"
        )

      [_, p] = Regex.run(~r/P = (\d+)/, a)
      [_, s] = Regex.run(~r/S = (\d+)/, a)
      assert String.to_integer(p) < String.to_integer(s), a
    end
  end
end
