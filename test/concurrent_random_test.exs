defmodule PrologEx.ConcurrentRandomTest do
  # Differenztests für library(concurrent) mit Zufallseingaben: jedes
  # concurrent_X gegen sein Vorbild nacheinander (maplist/2,3,4, concurrent/3
  # gegen Aufrufe der Reihe nach, forall/2, findall/3 je Ziel, (Gen, Test),
  # include/exclude/partition, foldl/4, aggregate_all/3, first_solution/3
  # gegen die Menge möglicher Gewinner). Die Elemente tragen ihr Verhalten:
  # ok(V), nd(L) (mehrere Lösungen), no (scheitert), err(E) (wirft),
  # out(V) (schreibt), nap(Ms, V) (schläft), work(N, V) (rechnet). Zufällig
  # auch threads(N), chunk(K); ein Teil der Runden mit erzwungenen
  # Verzögerungen (PrologEx.Chaos).
  #
  # Gleich heißt: dasselbe Ergebnis (Bindungen) und dieselbe Ausgabe. Wo die
  # Parallelität mehrere Ausgänge zulässt (mehrere Ziele werfen oder
  # scheitern: welches zuerst, entscheidet der Scheduler), muss der Ausgang
  # einer der möglichen sein – dann ohne Ausgabe (die Doku: bei Scheitern
  # oder Ausnahme nichts).
  #
  # CONC_RANDOM_SEED=N, CONC_RANDOM_N=K (K-mal so viele), CONC_RANDOM_COLLECT=1
  # (alle Abweichungen ausgeben statt anzuhalten).
  use ExUnit.Case, async: false
  alias PrologEx.{Chaos, Reader, TableCase}

  @prog ~S"""
  p(ok(V), V).
  p(nd(L), V) :- member(V, L).
  p(no, _) :- fail.
  p(err(E), _) :- throw(E).
  p(out(V), V) :- write(V), write(' ').
  p(nap(Ms, V), V) :- S is Ms / 1000, sleep(S).
  p(work(N, V), V) :- numlist(1, N, L), sum_list(L, _).
  % verschachtelt: nacheinander maplist/3, in einem Kind (die parallele
  % Seite: p/2 läuft dort immer in Kindern) concurrent_maplist/3; die
  % Ausgabe nacheinander nur bei Erfolg, wie bei concurrent_maplist/3
  p(sub(L), V) :-
      (   concurrent_child(_) -> concurrent_maplist(o, L, Vs)
      ;   with_output_to(atom(A), maplist(o, L, Vs)), write(A)
      ),
      sum_list(Vs, V).
  t(X) :- p(X, _).
  o(X, V) :- once(p(X, V)).
  o2(X, V, W) :- o(X, V), W is V * 2.
  cmp3(X, O) :- o(X, V), compare(O, V, 3).
  % assoziativ auf Listen; boom wirft, auch als Akkumulator (concurrent_foldl
  % nimmt das erste Element eines Abschnitts als Startwert)
  app(X, A0, A) :- ( ( X == boom ; A0 == boom ) -> throw(boom) ; append(A0, X, A) ).
  bag(T, G, B) :- findall(T, G, B).
  goals([], [], []).
  goals([X|Xs], [V|Vs], [o(X, V)|Gs]) :- goals(Xs, Vs, Gs).
  pgoals([], _, []).
  pgoals([X|Xs], V, [p(X, V)|Gs]) :- pgoals(Xs, V, Gs).

  % Ausgang: ok(T) (T nach dem Ziel), fail oder ex(E); dazu die Ausgabe
  run(T, G, R-O) :-
      with_output_to(atom(O), catch(( call(G) -> R = ok(T) ; R = fail ), E, R = ex(E))).

  % S nacheinander, C parallel; Xs die Elemente (für die möglichen Ausgänge),
  % Fails: kann ein scheiterndes Element das Ganze scheitern lassen?
  judge(Xs, Fails, S, C, V) :-
      (   S == C -> V = gleich
      ;   S = R0-_, C = R1-O1, R0 \= ok(_), R1 \= ok(_), O1 == '',
          possible(R1, Xs, Fails) -> V = gleich
      ;   V = verschieden(S, C)
      ).
  possible(fail, Xs, yes) :- has(no, Xs).
  possible(fail, Xs, _) :- member(sub(L), Xs), has(no, L).
  possible(ex(E), Xs, _) :- has(err(E), Xs).
  possible(ex(boom), Xs, _) :- memberchk(boom, Xs).
  % X kommt vor, auch in sub(L)
  has(X, Xs) :- member(Y, Xs), ( Y = X -> true ; Y = sub(L), has(X, L) ), !.

  diff(Xs, Fails, T0, G0, T1, G1, V) :-
      copy_term(T0-G0, T0c-G0c), copy_term(T1-G1, T1c-G1c),
      ( catch(b_getval(px_wrap, W), _, fail) -> true ; W = none ),
      wrap(W, G1c, G1w),
      run(T0c, G0c, S),
      run(T1c, G1w, C),
      % (die Grenze kann auch erst nach dem parallelen Teil zuschlagen, etwa
      % in findall/3 um concurrent_and/3: dann ist die Ausgabe schon da)
      (   C = ex(limit)-O1 -> ( ( O1 == '' ; S = ok(_)-O1 ) -> V = gleich ; V = verschieden(S, C) )
      ;   judge(Xs, Fails, S, C, V)
      ).

  % lim(W, Fall): die parallele Seite unter einer Grenze des Aufrufers –
  % das Ergebnis ist das ohne Grenze, oder die Grenze schlug zu (dann ohne
  % Ausgabe); die Kinder rechnen im selben Budget, die Zahl der Inferenzen
  % ist also eine andere als nacheinander
  lim(W, G) :- b_setval(px_wrap, W), call(G).
  wrap(none, G, G).
  wrap(time(T), G, catch(call_with_time_limit(T, G), time_limit_exceeded, throw(limit))).
  wrap(inf(N), G, ( call_with_inference_limit(G, N, R),
                    ( R == inference_limit_exceeded -> throw(limit) ; true ) )).

  % die Fälle
  case(maplist2, Xs, _, V) :- diff(Xs, yes, x, maplist(t, Xs), x, concurrent_maplist(t, Xs), V).
  case(maplist3, Xs, _, V) :- diff(Xs, yes, Vs, maplist(o, Xs, Vs), Vs, concurrent_maplist(o, Xs, Vs), V).
  case(maplist4, Xs, _, V) :-
      diff(Xs, yes, Vs-Ws, maplist(o2, Xs, Vs, Ws), Vs-Ws, concurrent_maplist(o2, Xs, Vs, Ws), V).
  case(concurrent, Xs, Os, V) :-
      goals(Xs, Vs, Gs), ( memberchk(n(N), Os) -> true ; N = 2 ),
      diff(Xs, yes, Vs, maplist(call, Gs), Vs, concurrent(N, Gs, []), V).
  case(forall, Xs, Os, V) :-
      diff(Xs, yes, x, forall(member(X, Xs), t(X)), x, concurrent_forall(member(X, Xs), t(X), Os), V).
  case(findall, Xs, _, V) :-
      pgoals(Xs, W, Gs), diff(Xs, no, Bs, maplist(bag(W), Gs, Bs), Bs, concurrent_findall(W, Gs, Bs), V).
  case(and, Xs, Os, V) :-
      diff(Xs, no, L, findall(X-W, (member(X, Xs), p(X, W)), L),
           L, findall(X-W, concurrent_and(member(X, Xs), p(X, W), Os), L), V).
  case(include, Xs, _, V) :- diff(Xs, no, I, include(t, Xs, I), I, concurrent_include(t, Xs, I), V).
  case(exclude, Xs, _, V) :- diff(Xs, no, I, exclude(t, Xs, I), I, concurrent_exclude(t, Xs, I), V).
  case(partition4, Xs, _, V) :-
      diff(Xs, no, I-E, partition(t, Xs, I, E), I-E, concurrent_partition(t, Xs, I, E), V).
  case(partition5, Xs, _, V) :-
      diff(Xs, yes, L-E-G, partition(cmp3, Xs, L, E, G), L-E-G, concurrent_partition(cmp3, Xs, L, E, G), V).
  case(foldl, Xs, _, V) :- diff(Xs, no, A, foldl(app, Xs, [], A), A, concurrent_foldl(app, Xs, [], A), V).
  case(aggregate(K), Xs, Os, V) :-
      tmpl(K, X, W, T),
      diff(Xs, no, R, aggregate_all(T, (member(X, Xs), p(X, W)), R),
           R, concurrent_aggregate_all(T, member(X, Xs), p(X, W), R, Os), V).
  tmpl(count, _, _, count).
  tmpl(sum, _, W, sum(W)).
  tmpl(max, _, W, max(W)).
  tmpl(min, _, W, min(W)).
  tmpl(maxw, X, W, max(W, X)).
  tmpl(minw, X, W, min(W, X)).
  tmpl(bag, _, W, bag(W)).
  tmpl(set, _, W, set(W)).
  tmpl(bagxw, X, W, bag(X-W)).
  tmpl(countsum, _, W, count-sum(W)).

  % first_solution/3: das Ergebnis ist eine der ersten Lösungen der Ziele,
  % oder – je nach on_fail/on_error – Scheitern oder eine der Ausnahmen
  first(Xs, Os, V) :-
      pgoals(Xs, W, Gs), copy_term(W-Gs, W1-Gs1),
      run(W1, first_solution(W1, Gs1, Os), R-_),
      findall(C, ( member(X, Xs), catch(once(p(X, C)), _, fail) ), Cands),
      ( memberchk(on_fail(continue), Os) -> FS = continue ; FS = stop ),
      ( memberchk(on_error(continue), Os) -> ES = continue ; ES = stop ),
      ( first_ok(R, Xs, Cands, FS, ES) -> V = gleich ; V = verschieden(R, Cands) ).
  first_ok(ok(C), _, Cands, _, _) :- memberchk(C, Cands).
  first_ok(fail, Xs, _, stop, _) :- has(no, Xs), !.
  first_ok(fail, Xs, _, stop, continue) :- has(err(_), Xs), !.
  first_ok(fail, Xs, [], _, ES) :- ( ES == continue -> true ; \+ has(err(_), Xs) ).
  first_ok(ex(E), Xs, _, _, stop) :- has(err(E), Xs).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ~w(concurrent lists between aggregate time swi))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @prog))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup do
    on_exit(fn -> Chaos.disable() end)
  end

  # --- Zufallseingaben ----------------------------------------------------

  defp pick(l), do: Enum.at(l, :rand.uniform(length(l)) - 1)
  defp chance(p), do: :rand.uniform() < p
  defp v, do: :rand.uniform(6)

  # p: Wahrscheinlichkeit für Scheitern und Werfen je Element
  defp elem(p) do
    x = :rand.uniform()

    cond do
      x < p / 2 ->
        "no"

      x < p ->
        "err(e#{:rand.uniform(3)})"

      true ->
        case :rand.uniform(11) do
          11 -> "sub(#{list(sub_leaves(p))})"
          n when n <= 5 -> "ok(#{v()})"
          6 -> "nd([#{Enum.map_join(1..:rand.uniform(3), ", ", fn _ -> v() end)}])"
          7 -> "out(#{v()})"
          8 -> "nap(#{pick([0, 1, 2, 5])}, #{v()})"
          _ -> "work(#{pick([10, 200, 2000])}, #{v()})"
        end
    end
  end

  # Scheitern und Werfen nicht zugleich in einem sub(L): sonst hinge schon,
  # ob das Element scheitert oder wirft, am Scheduler (concurrent_maplist/3
  # darin) – außen zählt Scheitern bei include, aggregate, ... nicht als
  # Fehler, das Ergebnis wäre beides
  defp sub_leaves(p) do
    ls = for _ <- 1..:rand.uniform(4), do: leaf(p)

    if "no" in ls and Enum.any?(ls, &String.starts_with?(&1, "err(")),
      do: Enum.map(ls, &if(&1 == "no", do: "ok(1)", else: &1)),
      else: ls
  end

  # in sub(L): ohne weitere Verschachtelung
  defp leaf(p) do
    case elem(p) do
      "sub(" <> _ -> "ok(#{v()})"
      e -> e
    end
  end

  defp elems(n, p), do: for(_ <- 1..n//1, do: elem(p))

  defp list(es), do: "[" <> Enum.join(es, ", ") <> "]"

  defp opts do
    for(
      o <- [
        if(chance(0.4), do: "threads(#{:rand.uniform(4)})"),
        if(chance(0.4), do: "chunk(#{:rand.uniform(4)})")
      ],
      o,
      do: o
    )
    |> Enum.shuffle()
  end

  @templates ~w(count sum max min maxw minw bag set bagxw countsum)

  # (wie oft ein Fall schiefgehen darf: p; sonst zu oft gleich vorbei)
  defp query do
    p = pick([0.0, 0.0, 0.05, 0.15, 0.4])
    n = if chance(0.05), do: pick([30, 100]), else: pick([0, 1, 2, 3, 5, 8, 12])
    xs = list(elems(n, p))

    c =
      case :rand.uniform(15) do
        1 -> "case(maplist2, #{xs}, [], V)"
        2 -> "case(maplist3, #{xs}, [], V)"
        3 -> "case(maplist4, #{xs}, [], V)"
        4 -> "case(concurrent, #{xs}, [n(#{:rand.uniform(4)})], V)"
        5 -> "case(forall, #{xs}, #{list(opts())}, V)"
        6 -> "case(findall, #{xs}, [], V)"
        7 -> "case(and, #{xs}, #{list(opts())}, V)"
        8 -> "case(include, #{xs}, [], V)"
        9 -> "case(exclude, #{xs}, [], V)"
        10 -> "case(partition4, #{xs}, [], V)"
        11 -> "case(partition5, #{xs}, [], V)"
        12 -> "case(aggregate(#{pick(@templates)}), #{xs}, #{list(opts())}, V)"
        13 -> "case(aggregate(#{pick(@templates)}), #{xs}, #{list(opts())}, V)"
        14 -> "case(foldl, #{list(folds(n))}, [], V)"
        15 -> "first(#{list(elems(max(n, 1), p))}, #{list(first_opts())}, V)"
      end

    # ab und zu unter einer Zeit- oder Inferenzgrenze (nicht first/3: das
    # hat kein Vorbild nacheinander, an dem sich die Grenze messen ließe)
    cond do
      String.starts_with?(c, "first(") -> c
      chance(0.05) -> "lim(time(#{pick(~w(0.001 0.005 0.02 0.1))}), #{c})"
      chance(0.05) -> "lim(inf(#{pick([50, 500, 5000, 50000])}), #{c})"
      true -> c
    end
  end

  defp folds(n) do
    for _ <- 1..n//1 do
      if chance(0.05), do: "boom", else: list(for(_ <- 1..:rand.uniform(3)//1, do: "#{v()}"))
    end
  end

  defp first_opts do
    for(
      o <- [
        if(chance(0.5), do: "on_fail(#{pick(~w(stop continue))})"),
        if(chance(0.5), do: "on_error(#{pick(~w(stop continue))})")
      ],
      o,
      do: o
    )
  end

  # --- Läufe ----------------------------------------------------------------

  defp run(c, q) do
    Task.async(fn ->
      Reader.put_current(c.reader)
      if c.ops, do: Process.put(:prolog_ex_ops, c.ops)
      {_, ans} = TableCase.run(c.reader, c.db, q)
      {:messages, msgs} = Process.info(self(), :messages)
      {:trap_exit, trap} = Process.info(self(), :trap_exit)
      {ans, msgs, trap}
    end)
    |> Task.await(60_000)
  end

  defp seed, do: String.to_integer(System.get_env("CONC_RANDOM_SEED", "20261123"))
  defp scale, do: String.to_integer(System.get_env("CONC_RANDOM_N", "1"))

  defp rounds(c, salt, n, chaos) do
    :rand.seed(:exsss, {seed(), salt, 11})
    qs = for _ <- 1..(n * scale()), do: query()
    if chaos, do: Chaos.enable([seed: salt] ++ chaos)

    try do
      for q <- qs do
        {ans, msgs, trap} = run(c, q)

        if System.get_env("CONC_RANDOM_COLLECT") do
          if ans != {:answers, ["V = gleich"]},
            do: IO.puts(:stderr, "ABWEICHUNG #{q}\n  => #{inspect(ans)}")
        else
          assert ans == {:answers, ["V = gleich"]}, "#{q}\n=> #{inspect(ans, limit: :infinity)}"
        end

        assert msgs == [], q
        assert trap == false, q
      end
    after
      Chaos.disable()
    end
  end

  test "wie nacheinander", c do
    rounds(c, 1, 250, nil)
  end

  test "wie nacheinander, mit Verzögerungen", c do
    rounds(c, 2, 120, p: 0.25, max_ms: 1)
  end

  @tag :slow
  @tag timeout: :infinity
  test "viele Eingaben", c do
    # warm (Bibliotheken, JIT), dann messen
    rounds(c, 10, 200, nil)
    before = footprint()
    rounds(c, 11, 3000, nil)
    rounds(c, 12, 1000, p: 0.3, max_ms: 2)
    rounds(c, 13, 500, p: 0.5, max_ms: 0)
    # nichts bleibt zurück: Prozesse, ETS-Tabellen, persistent_term (der
    # JIT darf noch ein paar Module mehr übersetzt haben; ein Leck je Lauf
    # wären Tausende)
    after_ = settle(before)
    assert after_.procs <= before.procs + 3, inspect({before, after_})
    assert after_.ets <= before.ets + 3, inspect({before, after_})
    assert after_.pterms <= before.pterms + 50, inspect({before, after_})
  end

  defp footprint do
    %{
      procs: length(Process.list()),
      ets: length(:ets.all()),
      pterms: :persistent_term.info().count
    }
  end

  # bis zu 2 s, bis die letzten Arbeiter weg sind
  defp settle(before) do
    Enum.reduce_while(1..20, nil, fn _, _ ->
      f = footprint()
      if f.procs <= before.procs + 3, do: {:halt, f}, else: Process.sleep(100) && {:cont, f}
    end)
  end
end
