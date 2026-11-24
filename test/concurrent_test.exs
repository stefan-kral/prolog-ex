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
  :- use_module(library(random)).
  :- use_module(library(memo)).
  :- use_module(library(tabling)).
  :- use_module(library(swi), [b_setval/2, b_getval/2, nb_setval/2, with_output_to/2,
                                call_with_depth_limit/3]).
  deep(0) :- !.
  deep(N) :- N1 is N-1, deep(N1).
  dq(X) :- deep(X).
  :- dynamic(f/1).
  :- memo mfib/2.
  mfib(N, F) :- N < 2 -> F = N ; N1 is N-1, N2 is N-2, mfib(N1, F1), mfib(N2, F2), F is F1+F2.
  :- table path/2.
  edge(a, b). edge(b, c). edge(c, a).
  path(X, Y) :- edge(X, Y).
  path(X, Y) :- path(X, Z), edge(Z, Y).
  rnd(_, X) :- random_between(1, 1000000000, X).
  sq(X, Y) :- Y is X * X.
  fib(0, 0).
  fib(1, 1).
  fib(N, F) :- N > 1, N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.
  loop :- loop.
  % wie fib/2, aber nicht übersetzbar (atom_length/2 kann der JIT nicht;
  % functor/3 kann er inzwischen): hier soll Rechenzeit vergehen
  sfib(N, F) :- N < 2, !, atom_length('', 0), F = N.
  sfib(N, F) :- N1 is N-1, N2 is N-2, sfib(N1, F1), sfib(N2, F2), F is F1+F2.
  slow(X) :- sfib(20, _), X = slow.
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

  # die Datenbank geht über Aufrufe hinweg geteilt an die Kinder (ein
  # persistent_term je Schlüssel): Änderungen dazwischen müssen sie sehen
  test "Änderungen der Datenbank zwischen zwei Aufrufen sehen die Kinder", c do
    assert ask(
             c,
             ~S"assertz(f(1)), concurrent_maplist(f, [1]), retract(f(1)), assertz(f(2)), " <>
               ~S"\+ concurrent_maplist(f, [1]), concurrent_maplist(f, [2]), " <>
               ~S"op(700, xfx, ===>), concurrent_maplist(\O^current_op(700, xfx, O), [===>])"
           ) == ["true"]
  end

  # stats(S) / concurrent_statistics/2: Einblick in die parallelen Läufe
  @stat_keys ~w(time parallel serial serial_phase prepare runs workers parts packets fixed
                requests steals refused pruned bounds busy setup idle utilization phases
                handovers)

  defp stats(answer) do
    [_, list] = Regex.run(~r/\bS = \[([^\]]*)\]/, answer)

    for kv <- String.split(list, ","), into: %{} do
      [_, k, v] = Regex.run(~r/(\w+)\(([-\d.e]+)\)/, kv)
      {k, if(String.contains?(v, "."), do: String.to_float(v), else: String.to_integer(v))}
    end
  end

  test "concurrent_statistics/2: Läufe, Teile, Auslastung; deterministisch", c do
    [a] =
      ask(
        c,
        "numlist(1, 30, L), concurrent_statistics(concurrent_maplist(sq, L, _), S), " <>
          "call_cleanup(true, Det = true)"
      )

    st = stats(a)
    assert Map.keys(st) |> Enum.sort() == Enum.sort(@stat_keys)
    assert a =~ ~r/S = \[time\(/
    assert %{"runs" => 1, "parts" => 30, "fixed" => 0, "steals" => 0, "phases" => 0} = st
    assert st["workers"] == min(System.schedulers_online(), 30)
    assert st["packets"] >= st["workers"] and st["packets"] <= 30
    assert st["utilization"] in 0..100
    assert st["time"] >= st["parallel"] and st["parallel"] >= st["prepare"]
    assert_in_delta st["serial"], st["time"] - st["parallel"], 0.11
    assert Process.get(:conc_stats) == nil

    # verschachtelt: die äußere Messung zählt die inneren Läufe mit
    [a] =
      ask(
        c,
        "concurrent_statistics((concurrent_maplist(sq, [1, 2], _), " <>
          "concurrent_statistics(concurrent_maplist(sq, [3], _), S1)), S)"
      )

    assert %{"runs" => 2, "parts" => 3} = stats(a)
    [_, s1] = Regex.run(~r/S1 = (\[[^\]]*\])/, a)
    assert %{"runs" => 1, "parts" => 1} = stats("S = " <> s1)

    # Scheitern und Ausnahmen: wie das Ziel, die Messung ist danach zu
    assert ask(c, ~S"concurrent_statistics(concurrent_maplist(\X^(X > 1), [1, 2]), _)") == []

    assert ask(
             c,
             ~S"catch(concurrent_statistics(concurrent_maplist(\X^(X > a), [1]), S), " <>
               "error(E, _), true)"
           ) == ["E = type_error(evaluable,a/0)"]

    assert Process.get(:conc_stats) == nil
    # ohne parallelen Lauf: nur die Zeit
    [a] = ask(c, "concurrent_statistics(true, S)")
    assert %{"runs" => 0, "busy" => +0.0, "utilization" => 0} = stats(a)
  end

  test "Option stats(S): concurrent/3, concurrent_forall/3, concurrent_and/3, first_solution/3",
       c do
    [a] = ask(c, "concurrent(2, [sq(1, A), sq(2, B), sq(3, C)], [stats(S)])")
    assert %{"runs" => 1, "workers" => 2, "parts" => 3} = stats(a)
    assert a =~ "A = 1, B = 4, C = 9"

    [a] = ask(c, "concurrent_forall(between(1, 5, X), sq(X, _), [threads(1), stats(S)])")
    assert %{"runs" => 1, "workers" => 1, "parts" => 5} = stats(a)

    [a | _] = ask(c, "concurrent_and(between(1, 3, X), sq(X, Y), [stats(S)])")
    assert %{"runs" => 1, "parts" => 3} = stats(a)

    [a] = ask(c, "first_solution(X, [sq(2, X), sq(3, X)], [stats(S)])")
    assert %{"runs" => 1, "workers" => 2} = stats(a)

    assert ask(c, "catch(concurrent(1, [true], foo), error(E, _), true)") ==
             ["E = type_error(list,foo)"]
  end

  test "concurrent_include/3, concurrent_exclude/3, concurrent_partition/4,5", c do
    assert ask(c, ~S"concurrent_include(\X^(X > 1), [1, 2, 3, 0, 5], I)") == ["I = [2,3,5]"]
    assert ask(c, ~S"concurrent_exclude(\X^(X > 1), [1, 2, 3, 0, 5], I)") == ["I = [1,0]"]

    assert ask(c, ~S"concurrent_partition(\X^(X > 1), [1, 2, 3, 0], I, E)") ==
             ["E = [1,0], I = [2,3]"]

    assert ask(c, ~S"concurrent_partition(\X^D^compare(D, X, 2), [1, 2, 3, 2], L, E, G)") ==
             ["E = [2,2], G = [3], L = [1]"]

    # wie nacheinander: Bindungen der Elemente, Fehler, deterministisch
    assert ask(c, ~S"concurrent_include(\X^(X = a), [Y, Z, b], I)") ==
             ["I = \"aa\", Y = a, Z = a"]

    assert ask(c, ~S"concurrent_include(\X^(X > 1), [], I)") == ["I = []"]

    assert ask(c, ~S"call_cleanup(concurrent_exclude(\X^(X > 1), [1, 2], I), Det = true)") ==
             ["Det = true, I = [1]"]

    for {g, e} <- [
          {~S"concurrent_include(\X^(X > 1), _, _)", "instantiation_error"},
          {~S"concurrent_include(\X^(X > a), [1], _)", "type_error(evaluable,a/0)"},
          {~S"concurrent_partition(\_^D^(D = foo), [1], _, _, _)", "domain_error(order,foo)"},
          {~S"concurrent_partition(\_^_^true, [1], _, _, _)", "instantiation_error"}
        ] do
      assert ask(c, "catch(#{g}, error(E, _), true)") == ["E = #{e}"], g
    end

    assert ask(c, ~S"concurrent_partition(\_^_^fail, [1], _, _, _)") == []
    # alle zugleich (mehr Elemente als Scheduler)
    assert ask(c, ~S"numlist(1, 50, L), concurrent_include(\X^(X mod 7 =:= 0), L, I)") |> hd() =~
             "I = [7,14,21,28,35,42,49]"
  end

  # dasselbe wie aggregate_all(T, (Gen, Test), R): über between/3 (Teil-
  # bereiche je Kind) und über andere Erzeuger (gesammelte Lösungen)
  test "concurrent_aggregate_all/4,5 wie aggregate_all/3", c do
    src = @src <> ":- use_module(library(aggregate)).\n"

    for gen <- ["between(1, 60, X)", "member(X, [3,1,4,1,5,9,2,6,5,3,5,8,9,7,9])"],
        {t, test} <- [
          {"count", "X mod 3 =:= 0"},
          {"sum(X)", "true"},
          {"max(X)", "X < 50"},
          {"min(Y)", "Y is X mod 7"},
          {"max(Y, X)", "Y is X mod 7"},
          {"min(Y, X)", "Y is X mod 4"},
          {"bag(X-Y)", "member(Y, [a, b])"},
          {"set(Y)", "Y is X mod 5"},
          {"r(count, sum(X), max(X, X), bag(X))", "X > 4"},
          {"max(X)", "X > 100"},
          {"count", "fail"}
        ] do
      seq = ask(c, "aggregate_all(#{t}, (#{gen}, #{test}), R)", src)
      par = ask(c, "concurrent_aggregate_all(#{t}, #{gen}, #{test}, R)", src)

      par2 =
        ask(c, "concurrent_aggregate_all(#{t}, #{gen}, #{test}, R, [threads(2), chunk(2)])", src)

      assert par == seq, "#{t} / #{gen} / #{test}"
      assert par2 == seq, "#{t} / #{gen} / #{test} (chunk 2)"
    end

    # mehrere Variablen im Erzeuger; leerer Bereich; Fehler; stats(S)
    assert ask(c, "concurrent_aggregate_all(bag(X-Y), member(X-Y, [1-a, 2-b]), true, R)", src) ==
             ["R = [1-a,2-b]"]

    assert ask(c, "concurrent_aggregate_all(count, between(5, 1, _), true, R)", src) == ["R = 0"]

    assert ask(c, "catch(concurrent_aggregate_all(foo, true, true, _), error(E, _), true)", src) ==
             ["E = domain_error(aggregate_template,foo)"]

    assert ask(
             c,
             "catch(concurrent_aggregate_all(sum(X), member(X, [1, a]), true, _), error(E, _), true)",
             src
           ) == ["E = type_error(evaluable,a/0)"]

    [a] =
      ask(c, "concurrent_aggregate_all(count, between(1, 100, X), X > 50, C, [stats(S)])", src)

    assert a =~ "C = 50"
    assert %{"runs" => 1} = stats(a)
  end

  test "concurrent_foldl/4: Map-Reduce mit assoziativer Verknüpfung", c do
    assert ask(c, ~S"numlist(1, 1000, L), concurrent_foldl(\X^A^B^(B is A + X), L, 0, S)")
           |> hd() =~ "S = 500500"

    assert ask(c, ~S"concurrent_foldl(\X^A^B^(B is A + X), [], 7, S)") == ["S = 7"]
    assert ask(c, ~S"concurrent_foldl(\X^A^B^(B is A + X), [3], 7, S)") == ["S = 10"]

    # nicht kommutativ: die Reihenfolge bleibt (wie foldl/4)
    assert ask(
             c,
             ~S"numlist(1, 200, L), maplist(\X^[X]^true, L, Ls), " <>
               ~S"concurrent_foldl(\X^A^B^append(A, X, B), Ls, [0], S), " <>
               ~S"foldl(\X^A^B^append(A, X, B), Ls, [0], S2), S == S2, " <>
               ~S"call_cleanup(concurrent_foldl(\X^A^B^(B is A * X), [1, 2], 1, P), Det = true)"
           )
           |> hd() =~ "Det = true, L = "

    assert ask(c, "catch(concurrent_foldl(_, [1|_], 0, _), error(E, _), true)") ==
             ["E = instantiation_error"]
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
    assert ask(c, "concurrent_forall(member(X, [1, 2, 3]), X > 1, [threads(1)])") == []

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

  test "Zufall in den Kindern: eigener Generator, reproduzierbar", c do
    # mit festem Startwert: dieselben Zahlen, je Kind verschiedene
    [a] =
      ask(
        c,
        "set_random(seed(42)), concurrent_maplist(rnd, [a, b, c], L1), " <>
          "set_random(seed(42)), concurrent_maplist(rnd, [a, b, c], L2), " <>
          "L1 == L2, sort(L1, S), length(S, N)"
      )

    assert a =~ "N = 3"

    # der Generator des Aufrufers wird weitergeschaltet: zwei Aufrufe nacheinander
    # geben andere Zahlen
    assert ask(
             c,
             "set_random(seed(1)), concurrent_maplist(rnd, [a], L1), " <>
               "concurrent_maplist(rnd, [a], L2), L1 \\== L2"
           )
           |> length() == 1

    # Zufall in Ausdrücken und mit Neustarts (der Erste gewinnt)
    assert ask(
             c,
             ~S"concurrent_maplist(\_^X^(X is random(10)), [a, b], [P, Q]), integer(P), integer(Q)"
           )
           |> length() == 1

    assert ask(c, "first_solution(X, [(repeat, random_between(1, 100, X), X > 90)], [])") |> hd() =~
             ~r/X = (9[1-9]|100)/

    # ein innerer Bereich im Kind bleibt streng
    [e] =
      ask(
        c,
        ~S"catch(concurrent_maplist(\_^call_with_no_side_effects(random(_)), [a]), error(E, _), true)"
      )

    assert e =~ "permission_error(perform,side_effect"
    # außerhalb der Kinder bleibt Zufall im Bereich verboten
    [e] = ask(c, "catch(call_with_no_side_effects(random(_)), error(E, _), true)")
    assert e =~ "permission_error(perform,side_effect"
  end

  test "Ausgabe in eigene Speicher-Streams im Kind", c do
    assert ask(c, ~S|concurrent_maplist(\X^A^format(atom(A), "<~w>", [X]), [a, b], As)|) ==
             ["As = ['<a>','<b>']"]
  end

  test "memo, tabling und b_setval/2 im Kind (Kopien, die mit ihm verschwinden)", c do
    assert ask(c, ~S"concurrent_maplist(\N^F^mfib(N, F), [80, 90], Fs)") ==
             ["Fs = [23416728348467685,2880067194370816120]"]

    assert ask(c, "concurrent_findall(Y, [path(a, Y)], [B]), msort(B, S)") |> hd() =~
             ~S|S = "abc"|

    assert ask(c, ~S"concurrent_maplist(\X^(b_setval(k, X), b_getval(k, Y), Y == X), [1, 2])") ==
             ["true"]

    # nb_setval/2 bleibt verboten (gemeint ist eine Wirkung über das Kind hinaus)
    [e] = ask(c, ~S"catch(concurrent_maplist(\X^nb_setval(k, X), [1]), error(E, _), true)")
    assert e =~ "permission_error(perform,side_effect,nb_setval(k,1))"
    # ein innerer Bereich im Kind bleibt streng
    [e] =
      ask(
        c,
        ~S"catch(concurrent_maplist(\N^F^call_with_no_side_effects(mfib(N, F)), [5], _), error(E, _), true)"
      )

    assert e =~ "permission_error(perform,side_effect"
  end

  test "concurrent_child/1: Position und Anzahl im Kind", c do
    assert ask(c, ~S"concurrent_maplist(\_^P^concurrent_child(P), [a, b, c], Ps)") ==
             ["Ps = [1/3,2/3,3/3]"]

    assert ask(c, ~S"first_solution(P, [fail, concurrent_child(P)], [on_fail(continue)])") ==
             ["P = 2/2"]

    assert ask(c, "concurrent(2, [concurrent_child(A/N), concurrent_child(B/N)], [])") ==
             ["A = 1, B = 2, N = 2"]

    # verschachtelt: der innerste Aufruf
    assert ask(
             c,
             ~S"concurrent_maplist(\_^P^concurrent_maplist(\_^Q^concurrent_child(Q/_), [x, y], P), [a], Ps)"
           ) == ["Ps = [[1,2]]"]

    # außerhalb eines Kinds: scheitert
    assert ask(c, "concurrent_child(_)") == []

    # die ganze Kette, innerster zuerst; außerhalb []
    assert ask(
             c,
             ~S"concurrent_maplist(\_^P^concurrent_maplist(\_^Q^concurrent_child_stack(Q), [x, y], P), [a, b], Ps)"
           ) == ["Ps = [[[1/2,1/2],[2/2,1/2]],[[1/2,2/2],[2/2,2/2]]]"]

    assert ask(c, ~S"concurrent_maplist(\_^P^concurrent_child_stack(P), [a], Ps)") ==
             ["Ps = [[1/1]]"]

    assert ask(c, "concurrent_child_stack(P)") == ["P = []"]
  end

  test "concurrent_and/2,3: wie (Gen, Test), Tests parallel, Reihenfolge von (Gen, Test)", c do
    assert ask(
             c,
             "findall(X, concurrent_and(member(X, [1,2,3,4,5,6,7,8,9,10]), " <>
               "(X > 1, \\+ (member(D, [2,3]), X > D, X mod D =:= 0))), L)"
           ) == ["L = [2,3,5,7]"]

    # alle Lösungen von Test, je Lösung von Gen
    assert ask(
             c,
             "findall(X-Y, concurrent_and(member(X, [a,b,c]), member(Y-X, [1-a, 2-b, 3-a])), L)"
           ) == ["L = [a-1,a-3,b-2]"]

    assert ask(c, "concurrent_and(member(X, [1,2,3]), X > 1, [threads(2)])") ==
             ["X = 2", "X = 3"]

    assert ask(c, "concurrent_and(fail, true)") == []
    [e] = ask(c, "catch(concurrent_and(member(X, [1,a]), _ is X + 1), error(E, _), true)")
    assert e =~ "type_error(evaluable,a/0)"
    [e] = ask(c, "catch(concurrent_and(true, true, [threads(0)]), error(E, _), true)")
    assert e =~ "domain_error(positive_integer,0)"
  end

  test "first_solution/3 mit on_error(continue): eine Ausnahme wie ein Scheitern", c do
    assert ask(
             c,
             "first_solution(X, [throw(oops), (numlist(1, 100000, L), sum_list(L, _), X = slow)], [on_error(continue)])"
           ) == ["X = slow"]

    # alle werfen oder scheitern: scheitert (wie SWI)
    assert ask(
             c,
             "first_solution(_, [throw(oops), fail], [on_error(continue), on_fail(continue)])"
           ) == []

    # Vorgabe stop: die Ausnahme kommt an
    [e] =
      ask(
        c,
        "catch(first_solution(X, [throw(oops), (numlist(1, 100000, L), sum_list(L, _), X = b)], []), E, true)"
      )

    assert e =~ "E = oops"
    [e] = ask(c, "catch(first_solution(X, [X = a], [on_error(foo)]), error(E, _), true)")
    assert e =~ "domain_error(on_error,foo)"
  end

  test "Blockung: ein Arbeiter, viele Elemente – jedes auf frischem Zustand", c do
    # threads(1): alle Elemente im selben Arbeiter; b_setval des Vorgängers
    # ist trotzdem unsichtbar, ebenso die Position je Element
    assert ask(
             c,
             "findall(X-V-P, concurrent_and(between(1, 4, X), " <>
               "((catch(b_getval(k, V), _, V = none)), b_setval(k, X), concurrent_child(P)), " <>
               "[threads(1), chunk(2)]), L)"
           ) == ["L = [1-none-1/4,2-none-2/4,3-none-3/4,4-none-4/4]"]

    # Zufall je Element, unabhängig von der Blockung
    assert ask(
             c,
             "set_random(seed(7)), findall(R, concurrent_and(between(1, 6, _), random_between(1, 1000000, R), [threads(1)]), L1), " <>
               "set_random(seed(7)), findall(R, concurrent_and(between(1, 6, _), random_between(1, 1000000, R), [threads(3), chunk(1)]), L2), " <>
               "L1 == L2"
           )
           |> length() == 1

    # Scheitern beendet alles, auch mitten im Paket
    assert ask(c, "concurrent_forall(between(1, 50, X), X < 20, [threads(2), chunk(10)])") == []
    [e] = ask(c, "catch(concurrent_forall(true, true, [chunk(0)]), error(E, _), true)")
    assert e =~ "domain_error(positive_integer,0)"
  end

  test "Tiefengrenze des Aufrufers gilt in den Kindern, R wie nacheinander", c do
    for {seq, par} <- [
          {"maplist(deep, [3, 7, 5])", "concurrent_maplist(deep, [3, 7, 5])"},
          {"maplist(dq, [3, 7])", "concurrent_maplist(dq, [3, 7])"},
          {"(deep(2), maplist(dq, [3]))", "(deep(2), concurrent_maplist(dq, [3]))"},
          {"maplist(deep, [3, 30])", "concurrent_maplist(deep, [3, 30])"}
        ] do
      [a1] = ask(c, "call_with_depth_limit(#{seq}, 20, R)")
      [a2] = ask(c, "call_with_depth_limit(#{par}, 20, R)")
      assert a1 == a2, seq
    end

    assert ask(c, "call_with_depth_limit(concurrent_maplist(deep, [3, 30]), 20, R)") ==
             ["R = depth_limit_exceeded"]

    # viele Kinder schreiben gleichzeitig in denselben Rahmen: die größte
    # Ebene darf nicht von einer kleineren überschrieben werden
    for _ <- 1..5 do
      assert ask(
               c,
               "numlist(1, 60, L0), reverse(L0, L), " <>
                 "call_with_depth_limit(concurrent_maplist(deep, L), 100, R), " <>
                 "call_with_depth_limit(maplist(deep, L), 100, R)"
             )
             |> length() == 1
    end

    # ein Kind, das nichts fängt: die Rekursion scheitert an der Grenze
    assert ask(c, "call_with_depth_limit(concurrent_maplist(deep, [1000]), 50, R)") ==
             ["R = depth_limit_exceeded"]
  end

  test "Brüche reisen zu den Kindern und zurück", c do
    assert ask(c, ~S"concurrent_maplist(\X^Y^(Y is X * 1r3), [1, 2r5, 0.5], L)") ==
             ["L = [1r3,2r15,0.16666666666666666]"]
  end

  test "Ausgabe der Kinder: gepuffert, nach Erfolg in der Reihenfolge der Ziele", c do
    assert ask(
             c,
             ~S|with_output_to(atom(A), concurrent_maplist(\X^(format("<~w>", [X])), [3, 1, 2]))|
           ) == ["A = '<3><1><2>'"]

    # bei Scheitern oder Ausnahme: nichts
    assert ask(
             c,
             ~S|with_output_to(atom(A), \+ concurrent_maplist(\X^(write(X), X < 2), [1, 2, 3]))|
           ) == ["A = ''"]

    assert ask(
             c,
             ~S|with_output_to(atom(A), catch(concurrent_maplist(\X^(write(X), X > 0), [1, a]), _, true))|
           ) == ["A = ''"]

    # andere Streams bleiben verboten
    [e] =
      ask(c, ~S|catch(concurrent_maplist(\X^write(user_error, X), [1]), error(E, _), true)|)

    assert e =~ "permission_error(perform,side_effect,write(user_error,1))"

    # im Bereich ohne Seiteneffekte nur in einen Stream des Bereichs
    [e] =
      ask(
        c,
        ~S|catch(call_with_no_side_effects(concurrent_maplist(\X^write(X), [1])), error(E, _), true)|
      )

    assert e =~ "permission_error(perform,side_effect,write('1'))"

    assert ask(
             c,
             ~S|call_with_no_side_effects(with_output_to(atom(A), concurrent_maplist(\X^write(X), [1, 2])))|
           ) == ["A = '12'"]
  end

  test "first_solution/3: Ausgabe des Gewinners; output(all) zeigt die übrigen auf user_error",
       c do
    # der Gewinner rechnet etwas, damit Ziel 1 schon geschrieben hat
    q =
      ~S|with_output_to(atom(A), first_solution(X, [(write(a1), repeat, fail), (write(b1), numlist(1, 200000, L), sum_list(L, _), X = b), (write(c1), fail)], [on_fail(continue), output(all)]))|

    {[ans], err} = with_err(fn -> ask(c, q) end)
    assert ans == "A = b1, X = b"
    assert err =~ "% Ziel 1: abgebrochen\na1\n"
    assert err =~ "% Ziel 3: gescheitert\nc1\n"
    refute err =~ "b1"

    # ohne output(all): nur der Gewinner
    {[ans], err} =
      with_err(fn ->
        ask(
          c,
          ~S|with_output_to(atom(A), first_solution(X, [(write(a1), repeat, fail), (write(b1), X = b)], []))|
        )
      end)

    assert ans == "A = b1, X = b"
    refute err =~ "Ziel"

    # alle gescheitert: mit output(all) trotzdem alles
    {[], err} =
      with_err(fn ->
        ask(
          c,
          ~S|first_solution(_, [(write(f1), fail), (write(f2), fail)], [on_fail(continue), output(all)])|
        )
      end)

    assert err =~ "% Ziel 1: gescheitert\nf1\n% Ziel 2: gescheitert\nf2\n"

    [e] = ask(c, "catch(first_solution(X, [X = a], [output(foo)]), error(E, _), true)")
    assert e =~ "domain_error(output,foo)"

    # ein Verlierer warf (on_error(continue)): seine Kopfzeile sagt es
    {[ans], err} =
      with_err(fn ->
        ask(
          c,
          ~S|with_output_to(atom(A), first_solution(X, [(write(e1), throw(x)), (write(b1), numlist(1, 200000, L), sum_list(L, _), X = b)], [on_error(continue), output(all)]))|
        )
      end)

    assert ans == "A = b1, X = b"
    assert err =~ "% Ziel 1: Ausnahme\ne1\n"

    # zwei sofort fertig: der Verlierer ist fertig oder abgebrochen, je nach
    # Zeit (ab und zu beides vorkommen lassen: zehn Runden)
    for _ <- 1..10 do
      {[ans], err} =
        with_err(fn ->
          ask(
            c,
            ~S|with_output_to(atom(A), first_solution(X, [(write(a1), X = a), (write(b1), X = b)], [output(all)]))|
          )
        end)

      assert ans in ["A = a1, X = a", "A = b1, X = b"]
      assert err =~ ~r/% Ziel [12]: (fertig|abgebrochen)\n/
    end
  end

  defp with_err(f) do
    me = self()
    err = ExUnit.CaptureIO.capture_io(:stderr, fn -> send(me, {:res, f.()}) end)

    receive do
      {:res, r} -> {r, err}
    end
  end

  # Zeitmessung, darum robust gemacht: erst einmal warm laufen lassen (sonst
  # zahlte der zuerst gemessene parallele Lauf das Laden/Übersetzen), dann
  # drei Runden und je die schnellste vergleichen (ein einzelner Ausreißer
  # der Maschine kippt das Ergebnis nicht; mit 2 Schedulern ist parallel
  # nur etwa 1,4-mal schneller). Nur mit mehr als einem Scheduler und nicht
  # mehr Schedulern als Kernen (+S 10 auf 2 Kernen: die Arbeiter teilen sich
  # die Kerne, parallel ist dann nicht schneller)
  test "parallel schneller als nacheinander (bei mehr als einem Scheduler)", c do
    s = System.schedulers_online()

    cores =
      Enum.find(
        [:logical_processors_available, :logical_processors_online, :logical_processors],
        &is_integer(:erlang.system_info(&1))
      )
      |> then(&if(&1, do: :erlang.system_info(&1), else: s))

    if s > 1 and s <= cores do
      [a] =
        ask(
          c,
          ~S"numlist(1, 4, L), maplist(\_^F^sfib(20, F), L, _), " <>
            ~S"findall(P-S, (between(1, 3, _), statistics(walltime, [A0|_]), " <>
            ~S"concurrent_maplist(\_^F^sfib(20, F), L, _), statistics(walltime, [A1|_]), " <>
            ~S"maplist(\_^F^sfib(20, F), L, _), statistics(walltime, [A2|_]), " <>
            "P is A1 - A0, S is A2 - A1), Runden), " <>
            "findall(P, member(P-_, Runden), Ps), min_list(Ps, Par), " <>
            "findall(S, member(_-S, Runden), Ss), min_list(Ss, Seq)"
        )

      [_, par] = Regex.run(~r/\bPar = (\d+)/, a)
      [_, seq] = Regex.run(~r/\bSeq = (\d+)/, a)
      assert String.to_integer(par) < String.to_integer(seq), a
    end
  end
end
