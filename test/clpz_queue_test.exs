defmodule PrologEx.ClpzQueueTest do
  # Ablage und Warteschlange von clpz in Elixir (PrologEx.Builtins.ClpzPrims)
  # gegen Triskas Code (die Originale mit der Endung _ref): Zufallsbedingungen
  # bauen einen Zustand auf, dann dieselbe Operation mit beiden Fassungen;
  # verglichen werden alle erreichbaren Attribute (Domänen, Propagatoren,
  # Warteschlangen) als Variante, dazu Erfolg/Fehlschlag/Fehler
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(clpz)).
  :- use_module(library(lists)).
  :- use_module(library(swi), [(=@=)/2, term_attvars/2]).
  % Zustand: die attributierten Variablen von T mit allen Attributen
  dump(T, Vs-As) :- term_attvars(T, Vs), maplist(attrs, Vs, As).
  attrs(V, A) :- clpz:get_atts(V, A).
  % alle Lösungen (höchstens 3) mit Zustand, oder err(E)
  run(G, T, R) :-
      catch(findall(T-D, (call(G), dump(T, D)), R0), error(E, _), R0 = err(E)),
      (   R0 = [_,_,_|_] -> R0 = [A,B,C|_], R = [A,B,C] ; R = R0 ).
  same(G1, G2, T) :-
      run(G1, T, R1), run(G2, T, R2),
      (   R1 =@= R2 -> true ; throw(verschieden(R1, R2)) ).
  % Einträge e(N) in die Warteschlangen einiger Variablen (Teil K)
  fill([], _).
  fill([V-K|Rest], N) :-
      (   var(V), clpz:variable_queue(V, Q) ->
          phrase(clpz:insert_queue_ref(e(N), K), [Q], _)
      ;   true
      ),
      N1 is N + 1, fill(Rest, N1).
  % eine Variable mit Domäne und eine neue, kleinere Domäne für sie
  pick(Vs, X, D, Ps) :-
      member(X, Vs), clpz:fd_get_ref(X, D0, Ps), D0 \\== from_to(inf,sup), !,
      clpz:domain_infimum_ref(D0, I), clpz:domain_supremum_ref(D0, S),
      (   I = n(N) -> clpz:domain_remove_ref(D0, N, D)
      ;   S = n(N) -> clpz:domain_remove_ref(D0, N, D)
      ;   clpz:domains_intersection_ref(D0, from_to(n(-1),n(1)), D)
      ).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.put(:prolog_ex_ops, c.ops)
    PrologEx.put_db(c.db)
    :rand.seed(:exsss, {2026, 11, 3})
    :ok
  end

  @vars ~w(X Y Z W)

  defp leaf, do: if(:rand.uniform(3) > 1, do: Enum.random(@vars), else: "#{Enum.random(-3..5)}")

  defp expr(0), do: leaf()

  defp expr(d) do
    a = fn -> expr(d - 1) end

    case :rand.uniform(7) do
      1 -> "(#{a.()} + #{a.()})"
      2 -> "(#{a.()} * #{a.()})"
      3 -> "abs(#{a.()})"
      4 -> "(#{a.()} - #{a.()})"
      5 -> "min(#{a.()}, #{a.()})"
      _ -> leaf()
    end
  end

  defp constraint do
    rel = Enum.random(~w(#= #\\= #< #>= #=<))

    case :rand.uniform(9) do
      1 -> "#{Enum.random(@vars)} in #{Enum.random(~w(0..5 -3..3 1..2\\/4..9 inf..4 0..sup))}"
      2 -> "[X,Y,Z,W] ins -4..6"
      3 -> "all_different([X,Y,Z])"
      4 -> "all_distinct([Y,Z,W])"
      5 -> "sum([X,Y,W], #{rel}, Z)"
      7 -> "abs(#{Enum.random(@vars)} - #{Enum.random(@vars)}) #\\= #{Enum.random(0..3)}"
      8 -> "#{Enum.random(@vars)} + #{Enum.random(@vars)} #= #{Enum.random(@vars)}"
      6 -> "B #<==> (X #> Y)"
      _ -> "#{expr(Enum.random(0..2))} #{rel} #{expr(Enum.random(0..2))}"
    end
  end

  defp setup_goal do
    Enum.join(for(_ <- 1..Enum.random(1..4), do: constraint()), ", ")
  end

  defp check(c, n, gen) do
    diffs =
      for _ <- 1..n,
          q = gen.(),
          r = TableCase.run(c.reader, c.db, q),
          not match?({_, {:answers, [_]}}, r),
          do: {q, r}

    assert diffs == [], inspect(Enum.take(diffs, 2), pretty: true, limit: :infinity)
  end

  # die Ausgangslage, dann same/3 (scheitert die Ausgangslage, gilt das
  # als bestanden)
  defp scenario(cmp) do
    "Vs = [X,Y,Z,W,B], ((#{setup_goal()}) -> #{cmp} ; true)"
  end

  test "variables_same_queue/1: Warteschlangen mit Einträgen zusammenlegen", c do
    check(c, 400, fn ->
      vs = ["X", "Y", "Z", "W", "B", "_", "3"]

      fill =
        Enum.map_join(1..Enum.random(0..6)//1, ",", fn _ ->
          "#{Enum.random(@vars)}-#{Enum.random(1..3)}"
        end)

      l = Enum.map_join(1..Enum.random(0..5)//1, ",", fn _ -> Enum.random(vs) end)

      scenario(
        "(fill([#{fill}], 0), L = [#{l}], " <>
          "same(clpz:variables_same_queue_ref(L), clpz:variables_same_queue(L), Vs-L))"
      )
    end)
  end

  # do_queue//0 gegen do_queue_ref//0: Ausgabe beim Wecken (Zustände der
  # Propagatoren, Reihenfolge der Teile der Queue)
  defp queue_outputs(c, db, setup) do
    for dq <- ["do_queue_ref", "do_queue"] do
      q =
        "X in 0..5, Y in 0..5, clpz:new_queue(Q), #{setup}, " <>
          "phrase(clpz:#{dq}, [Q], _), write(ende)"

      TableCase.run(c.reader, db, q)
    end
  end

  test "do_queue//0: Wecken nach kill/1 wie das Original (freeze am Zustand, Reihenfolge)", c do
    for setup <- [
          "P = propagator(pneq(X,3), S), freeze(S, write(s)), phrase(clpz:queue_fast(P), [Q], _)",
          "P1 = propagator(pneq(X,3), S1), freeze(S1, write(s1)), " <>
            "P2 = propagator(pneq(Y,4), S2), freeze(S2, write(s2)), " <>
            "phrase(clpz:queue_slow(P1), [Q], _), phrase(clpz:queue_fast(P2), [Q], _)",
          "P1 = propagator(pneq(X,3), S1), P2 = propagator(pneq(Y,X), S2), " <>
            "freeze(S2, write(s2)), phrase(clpz:queue_fast(P1), [Q], _), " <>
            "phrase(clpz:queue_fast(P2), [Q], _), X = 2"
        ] do
      [ref, new] = queue_outputs(c, c.db, setup)
      assert ref == new, setup
      assert {o, {:answers, [_]}} = new
      assert o =~ "s", setup
    end
  end

  test "do_queue//0: ein weiteres Modul mit verify_attributes/3 sieht jedes Wecken", c do
    PrologEx.put_db(c.db)

    ExUnit.CaptureIO.capture_io(fn ->
      {:ok, _} = PrologEx.Consult.load_file("test/fixtures/atts/alle.pl")
    end)

    db = PrologEx.current_db()

    for setup <- [
          "P = propagator(pneq(X,3), S), phrase(clpz:queue_fast(P), [Q], _)",
          "P1 = propagator(pneq(X,3), _), P2 = propagator(pneq(Y,4), _), " <>
            "phrase(clpz:queue_slow(P1), [Q], _), phrase(clpz:queue_fast(P2), [Q], _)"
        ] do
      [ref, new] = queue_outputs(c, db, setup)
      assert ref == new, setup
      assert {o, {:answers, [_]}} = new
      assert o =~ "h", setup
    end
  end

  test "variables_same_queue/1: drei eigene Queues mit Einträgen, abgeschaltete Queue", c do
    for {fill, extra, l} <- [
          # drei Queues mit Einträgen im selben Teil: die Kette des Originals
          {"X-1,Y-1,Z-1,X-2,Z-2", "true", "X,Y,Z"},
          {"Z-3,Y-3,X-3,Y-3", "true", "Z,X,Y,W"},
          {"X-1,Y-2,Z-3,W-1", "true", "W,Z,Y,X"},
          # danach weiter einreihen: wohin der Eintrag kommt
          {"X-1,Y-1,Z-1",
           "clpz:variable_queue(X, Q), phrase(clpz:insert_queue_ref(n, 1), [Q], _)", "X,Y,Z"},
          # eine abgeschaltete Queue
          {"X-1,Y-1", "clpz:variable_queue(Y, queue(_,_,_,A)), clpz:put_atts(A, disabled)",
           "X,Y,Z"},
          {"X-1", "clpz:variable_queue(X, queue(_,_,_,A)), clpz:put_atts(A, disabled)", "Z,Y,X"}
        ] do
      q =
        "Vs = [X,Y,Z,W], X in 0..3, Y in 1..4, Z in 2..5, W in 0..9, fill([#{fill}], 0), " <>
          "L = [#{l}], same((clpz:variables_same_queue_ref(L), #{extra}), " <>
          "(clpz:variables_same_queue(L), #{extra}), Vs-L)"

      assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), q
    end
  end

  test "verify_attributes/3: Wert in oder außerhalb der Domäne, ohne clpz-Attribut, Variable",
       c do
    check(c, 400, fn ->
      other =
        case :rand.uniform(12) do
          1 -> "a"
          2 -> "f(_)"
          3 -> "_"
          4 -> Enum.random(@vars)
          _ -> "#{Enum.random(-5..7)}"
        end

      v = Enum.random(@vars ++ ["B", "S"])

      scenario(
        "(clpz:put_atts(S, clpz_aux(queued)), Vs1 = [S|Vs], O = #{other}, " <>
          "same(clpz:verify_attributes_ref(#{v}, O, G), " <>
          "clpz:verify_attributes(#{v}, O, G), Vs1-O-G))"
      )
    end)
  end

  test "put_terminating//3: neue Domäne ablegen und Propagatoren einreihen", c do
    check(c, 250, fn ->
      scenario(
        "(pick(Vs, V, D, Ps) -> clpz:new_queue(Q), " <>
          "same(clpz:put_terminating_ref(V, D, Ps, [Q], _), " <>
          "clpz:put_terminating(V, D, Ps, [Q], _), Vs-Q) ; true)"
      )
    end)
  end

  test "put_terminating//3: Einzelwert (Ziel in die Queue), leere Domäne, neue Variable", c do
    check(c, 150, fn ->
      d = Enum.random(["from_to(n(2),n(2))", "empty", "from_to(n(0),n(3))", "from_to(inf,n(1))"])
      v = Enum.random(["V", "N", "7"])

      scenario(
        "(member(V, Vs), clpz:fd_get_ref(V, _, Ps) -> clpz:new_queue(Q), " <>
          "same(clpz:put_terminating_ref(#{v}, #{d}, Ps, [Q], _), " <>
          "clpz:put_terminating(#{v}, #{d}, Ps, [Q], _), Vs-Q-N) ; true)"
      )
    end)
  end

  test "trigger_props//1,2,3, trigger_prop//1, insert_queue//2", c do
    for {ref, new} <- [
          {"trigger_props_ref(Ps, V, D0, D, [Q], _)", "trigger_props(Ps, V, D0, D, [Q], _)"},
          {"trigger_props_ref(Ps, V, [Q], _)", "trigger_props(Ps, V, [Q], _)"},
          {"trigger_props_ref(Ps, [Q], _)", "trigger_props(Ps, [Q], _)"},
          {"(Ps = fd_props([P|_],_,_) ; Ps = fd_props(_,[P|_],_) ; Ps = fd_props(_,_,[P|_])), " <>
             "trigger_prop_ref(P, [Q], _)",
           "(Ps = fd_props([P|_],_,_) ; Ps = fd_props(_,[P|_],_) ; Ps = fd_props(_,_,[P|_])), " <>
             "trigger_prop(P, [Q], _)"},
          {"insert_queue_ref(foo(V), 2, [Q], _), insert_queue_ref(g, 2, [Q], _), " <>
             "queue_goal_ref(V = 1, [Q], _)",
           "insert_queue(foo(V), 2, [Q], _), insert_queue(g, 2, [Q], _), queue_goal(V = 1, [Q], _)"}
        ] do
      check(c, 120, fn ->
        scenario(
          "(pick(Vs, V, D, Ps), clpz:fd_get_ref(V, D0, _) -> clpz:new_queue(Q), " <>
            "same(clpz:(#{ref}), clpz:(#{new}), Vs-Q) ; true)"
        )
      end)
    end
  end

  test "die ganze Propagation: ablegen und do_queue//0 bis zum Fixpunkt", c do
    check(c, 250, fn ->
      scenario(
        "(pick(Vs, V, D, Ps) -> clpz:new_queue(Q), " <>
          "same(phrase((clpz:put_terminating_ref(V, D, Ps), clpz:do_queue_ref), [Q], _), " <>
          "phrase((clpz:put_terminating(V, D, Ps), clpz:do_queue), [Q], _), Vs) ; true)"
      )
    end)
  end

  test "do_queue//0: abgeschaltete Queue, Ziele vor Propagatoren", c do
    for q <- [
          "clpz:new_queue(Q), Q = queue(_,_,_,A), clpz:put_atts(A, disabled), " <>
            "clpz:insert_queue(X = 1, 1, [Q], _), " <>
            "same(phrase(clpz:do_queue_ref, [Q], _), phrase(clpz:do_queue, [Q], _), X-Q)",
          "X in 0..3, Y #> X, clpz:new_queue(Q), clpz:insert_queue(X = 2, 1, [Q], _), " <>
            "same(phrase(clpz:do_queue_ref, [Q], _), phrase(clpz:do_queue, [Q], _), X-Y-Q)",
          "clpz:new_queue(Q), clpz:insert_queue(fail, 1, [Q], _), " <>
            "same(phrase(clpz:do_queue_ref, [Q], _), phrase(clpz:do_queue, [Q], _), Q)"
        ] do
      assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), q
    end
  end

  test "gezielt: laufender Propagator, gebundenes X, Reihenfolge der Queue", c do
    for q <- [
          # der laufende Propagator (no_reactivation) wird nicht eingereiht
          "clpz:new_queue(Q), P = propagator(pdistinct([A,B]), S), " <>
            "clpz:bb_b_put('$clpz_current_propagator', S), " <>
            "same(clpz:trigger_prop_ref(P, [Q], _), clpz:trigger_prop(P, [Q], _), P-Q)",
          # gebundenes X: auch die Propagatoren für ground (Gs)
          "clpz:new_queue(Q), " <>
            "Ps = fd_props([propagator(pneq(3,Y),S1)], [propagator(pgeq(Y,3),S2)], " <>
            "[propagator(pplus(3,Y,Z,_),S3)]), " <>
            "same(clpz:trigger_props_ref(Ps, 3, from_to(n(0),n(5)), from_to(n(3),n(3)), [Q], _), " <>
            "clpz:trigger_props(Ps, 3, from_to(n(0),n(5)), from_to(n(3),n(3)), [Q], _), Q-S1-S2-S3)",
          # erst Ziele, dann schnelle, dann langsame Propagatoren
          "clpz:new_queue(Q), clpz:insert_queue_ref(slow1, 3, [Q], _), " <>
            "clpz:insert_queue_ref(fast1, 2, [Q], _), clpz:insert_queue_ref(goal1, 1, [Q], _), " <>
            "clpz:insert_queue_ref(fast2, 2, [Q], _), " <>
            "clpz:'$clpz_queue_next'([Q], N1), clpz:'$clpz_queue_next'([Q], N2), " <>
            "clpz:'$clpz_queue_next'([Q], N3), clpz:'$clpz_queue_next'([Q], N4), " <>
            "clpz:'$clpz_queue_next'([Q], N5), " <>
            "[N1,N2,N3,N4,N5] == [goal(goal1), prop(fast1), prop(fast2), prop(slow1), none]"
        ] do
      assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), q
    end
  end

  # ein Argument: Variable (mit oder ohne Domäne) oder Zahl
  defp parg, do: if(:rand.uniform(3) == 1, do: "#{Enum.random(-3..5)}", else: Enum.random(@vars))

  defp plist, do: "[" <> Enum.map_join(1..Enum.random(0..3)//1, ",", fn _ -> parg() end) <> "]"

  defp synth do
    case :rand.uniform(15) do
      14 ->
        "pabs(#{parg()}, #{parg()})"

      11 ->
        "ptimes(#{parg()}, #{parg()}, #{parg()}, _)"

      12 ->
        "pmax(#{parg()}, #{parg()}, #{parg()})"

      13 ->
        "pmin(#{parg()}, #{parg()}, #{parg()})"

      7 ->
        b = Enum.random(["B", "0", "1", "B"])
        dx = Enum.random(["1", "1", "0", "DX"])
        dy = Enum.random(["1", "1", "0", "DY"])
        "reified_geq(#{dx}, #{parg()}, #{dy}, #{parg()}, #{ents()}, #{b})"

      8 ->
        "reified_and(#{Enum.random(["0", "1", "X", "Y"])}, #{ents()}, " <>
          "#{Enum.random(["0", "1", "Y", "Z"])}, #{ents()}, #{Enum.random(["B", "0", "1", "W"])})"

      9 ->
        n = Enum.random(0..4)
        cs = Enum.map_join(1..max(n, 1), ",", fn _ -> Enum.random([-3, -2, -1, 1, 1, 2, 3]) end)
        vs = Enum.map_join(1..max(n, 1), ",", fn _ -> parg() end)
        "scalar_product_leq([#{cs}], [#{vs}], #{Enum.random(-4..12)})"

      10 ->
        "pgeq(#{parg()}, #{parg()})"

      1 ->
        "pneq(#{parg()}, #{parg()})"

      2 ->
        "absdiff_neq(#{parg()}, #{parg()}, #{Enum.random(-1..4)})"

      3 ->
        "pexclude(#{plist()}, #{plist()}, #{parg()})"

      4 ->
        "pdifferent(#{plist()}, #{plist()}, #{parg()}, _)"

      5 ->
        "pplus(#{parg()}, #{parg()}, #{parg()}, _)"

      _ ->
        n = Enum.random(0..4)

        cs =
          Enum.map_join(1..max(n, 1), ",", fn _ -> Enum.random([-3, -2, -1, 1, 1, 2, 3, 0]) end)

        vs = Enum.map_join(1..max(n, 1), ",", fn _ -> parg() end)
        "scalar_product_eq([#{cs}], [#{vs}], #{Enum.random(-4..8)})"
    end
  end

  # Liste für kill_entailed/1: p(Propagator), a(V), a(X,B), a(X,Y,B)
  defp ents do
    "[" <>
      Enum.map_join(1..Enum.random(0..3)//1, ",", fn _ ->
        Enum.random([
          "p(propagator(pneq(X,Y),_))",
          "a(#{Enum.random(@vars)})",
          "a(X,#{Enum.random(@vars)})",
          "a(X,Y,#{Enum.random(@vars)})"
        ])
      end) <> "]"
  end

  defp doms do
    for v <- @vars, :rand.uniform(4) > 1 do
      "#{v} in #{Enum.random(~w(0..5 -3..3 1..2\\/4..9 inf..4 0..sup 2..3 1..1\\/3..3 -2..sup))}"
    end
    |> Enum.join(", ")
    |> case do
      "" -> "true"
      d -> d
    end
  end

  test "activate_propagator//1: synthetische Propagatoren, allein und bis zum Fixpunkt", c do
    check(c, 1600, fn ->
      t = synth()

      bdom = Enum.random(["true", "B in 0..1", "B in 0..1, DX in 0..1"])

      "Vs = [X,Y,Z,W,B,DX,DY], (#{doms()}, #{bdom} -> clpz:new_queue(Q), " <>
        "P = propagator(#{t}, S), " <>
        "same(phrase(clpz:activate_propagator_ref(P), [Q], _), " <>
        "phrase(clpz:activate_propagator(P), [Q], _), Vs-Q-S), " <>
        "same(phrase((clpz:activate_propagator_ref(P), clpz:do_queue_ref), [Q], _), " <>
        "phrase((clpz:activate_propagator(P), clpz:do_queue), [Q], _), Vs-S) ; true)"
    end)
  end

  # vergleicht einen Propagator mit festen Domänen (allein und bis zum
  # Fixpunkt)
  defp prop_case(c, setup, t) do
    q =
      "Vs = [X,Y,Z,W], (#{setup} -> clpz:new_queue(Q), P = propagator(#{t}, S), " <>
        "same(phrase(clpz:activate_propagator_ref(P), [Q], _), " <>
        "phrase(clpz:activate_propagator(P), [Q], _), Vs-Q-S), " <>
        "same(phrase((clpz:activate_propagator_ref(P), clpz:do_queue_ref), [Q], _), " <>
        "phrase((clpz:activate_propagator(P), clpz:do_queue), [Q], _), Vs-S) ; true)"

    r = TableCase.run(c.reader, c.db, q)
    if match?({_, {:answers, [_]}}, r), do: [], else: [{q, r}]
  end

  @doms ["0..3", "3..5", "6..9", "2..2", "1..4\\/7..8", "inf..3", "4..sup", "inf..sup", "-5.. -1"]

  test "ptimes, pmax, pmin: Tripel aus Domänen mit Vorzeichen, Null, unendlich", c do
    doms = @doms ++ ["-3..3", "-4.. -2\\/2..3", "0..0\\/2..6"]

    diffs =
      for dx <- doms,
          dy <- doms,
          dz <- Enum.take_random(doms, 4),
          t <- [
            "ptimes(X, Y, Z, _)",
            "ptimes(X, -2, Z, _)",
            "ptimes(X, Y, 6, _)",
            "ptimes(X, Y, 0, _)",
            "pmax(X, Y, Z)",
            "pmax(X, 3, Z)",
            "pmin(X, Y, Z)",
            "pmin(X, 3, Z)",
            "pabs(X, Y)",
            "pabs(X, 3)",
            "pabs(-2, Y)",
            "pabs(X, X)"
          ] do
        prop_case(c, "X in #{dx}, Y in #{dy}, Z in #{dz}", t)
      end ++
        for {setup, t} <- [
              # X·X = Z: X in -R \/ R (das Original)
              {"X in -3..3", "ptimes(X, X, 4, _)"},
              {"X in 0..5", "ptimes(X, X, 9, _)"},
              {"X in -3..3", "ptimes(X, X, 0, _)"},
              # Z negativ, Y um 0, X ohne 0: Schranke L1 (min_factor/5)
              {"X in -20.. -1, Y in -2..2, Z in -10.. -5", "ptimes(X, Y, Z, _)"},
              {"X in 1..20, Y in -2..2, Z in 5..10", "ptimes(X, Y, Z, _)"},
              {"X in -20.. -1, Y in -2..2, Z in 5..10", "ptimes(X, Y, Z, _)"}
            ] do
          prop_case(c, setup, t)
        end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  test "pneq und pplus: alle Paare/Tripel aus berührenden, getrennten, unendlichen Domänen", c do
    diffs =
      for dx <- @doms, dy <- @doms do
        prop_case(c, "X in #{dx}, Y in #{dy}", "pneq(X, Y)")
      end ++
        for dx <- @doms,
            dy <- @doms,
            dz <- Enum.take_random(@doms, 4),
            t <- ["pplus(X, Y, Z, _)", "pplus(X, 2, Z, _)", "pplus(X, Y, 4, _)"] do
          prop_case(c, "X in #{dx}, Y in #{dy}, Z in #{dz}", t)
        end ++
        for dx <- @doms,
            # Zweige mit einer Bindung
            t <- [
              "pplus(0, X, Y, _)",
              "pplus(2, 3, X, _)",
              "pplus(2, 3, 5, _)",
              "pplus(2, X, 5, _)",
              "pplus(X, X, 4, _)",
              "pplus(X, X, 5, _)",
              "pplus(X, Y, X, _)",
              "pplus(X, Y, Y, _)",
              "pplus(X, X, Y, _)"
            ] do
          prop_case(c, "X in #{dx}, Y in #{Enum.random(@doms)}", t)
        end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  test "scalar_product_eq: die Sonderfälle der Koeffizienten, P innerhalb und außerhalb", c do
    css = [
      [1, 1],
      [1, -1],
      [-1, 1],
      [-1, -1],
      [1, 1, -1],
      [1, -1, 1],
      [-1, 1, 1],
      [2, 3],
      [1, 2, -1],
      [-1, -2, 1],
      [3],
      [1, 1, 1]
    ]

    diffs =
      for cs <- css,
          p <- [-7, 0, 4, 30],
          ds <- [
            ~w(0..3 3..5 2..2),
            ~w(inf..3 0..5 1..4),
            ~w(4..sup inf..sup 0..1),
            ~w(inf..2 inf..0 -1..sup)
          ] do
        vs = Enum.take(~w(X Y Z), length(cs))
        setup = Enum.zip(vs, ds) |> Enum.map_join(", ", fn {v, d} -> "#{v} in #{d}" end)

        prop_case(
          c,
          setup,
          "scalar_product_eq([#{Enum.join(cs, ",")}], [#{Enum.join(vs, ",")}], #{p})"
        )
      end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  # eine Zufallsmenge aus 1..m als Domäne (Vereinigung einzelner Werte)
  defp subset_dom(m) do
    case Enum.take_random(1..m, Enum.random(1..m)) do
      [] -> "1"
      vs -> vs |> Enum.sort() |> Enum.join("\\/")
    end
  end

  defp distinct_case(n, prop) do
    names = Enum.take(~w(A B C D E F G), n)

    {items, setup} =
      Enum.map_reduce(names, [], fn v, acc ->
        case :rand.uniform(12) do
          1 -> {"#{Enum.random(1..n)}", acc}
          2 -> {v, ["#{v} in 0..sup" | acc]}
          3 -> {Enum.random(names), acc}
          _ -> {v, ["#{v} in #{subset_dom(n + 1)}" | acc]}
        end
      end)

    setup = if setup == [], do: "true", else: Enum.join(Enum.reverse(setup), ", ")
    vs = "[" <> Enum.join(names, ",") <> "]"

    "Vs = #{vs}, (#{setup} -> clpz:new_queue(Q), P = propagator(#{prop}([#{Enum.join(items, ",")}]), S), " <>
      "same(phrase(clpz:activate_propagator_ref(P), [Q], _), " <>
      "phrase(clpz:activate_propagator(P), [Q], _), Vs-Q-S), " <>
      "same(phrase((clpz:activate_propagator_ref(P), clpz:do_queue_ref), [Q], _), " <>
      "phrase((clpz:activate_propagator(P), clpz:do_queue), [Q], _), Vs-S) ; true)"
  end

  test "pdistinct (all_distinct/1): Zufallsdomänen, auch gebunden, unendlich, doppelt", c do
    check(c, 400, fn -> distinct_case(Enum.random(1..6), "pdistinct") end)
  end

  test "pcircuit (circuit/1): Zufallsdomänen in 1..n+1", c do
    check(c, 400, fn -> distinct_case(Enum.random(1..6), "pcircuit") end)
  end

  test "all_distinct/1 und circuit/1 aufgestellt, dann gebunden: wie das Original", c do
    for q <- [
          # der Propagator hängt an seinen Variablen: beim Entfernen der
          # Werte reiht er sich nicht selbst wieder ein (no_reactivation)
          "Vs = [X,Y,Z], X in 1..3, Y in 1..2, Z in 1..2, " <>
            "P = propagator(pdistinct(Vs), S), clpz:init_propagator(X, P), clpz:init_propagator(Y, P), clpz:init_propagator(Z, P), " <>
            "clpz:new_queue(Q), " <>
            "same(phrase(clpz:activate_propagator_ref(P), [Q], _), " <>
            "phrase(clpz:activate_propagator(P), [Q], _), Vs-Q-S)",
          "length(Vs, 5), Vs ins 1..5, all_distinct(Vs), Vs = [1,X|_], " <>
            "clpz:new_queue(Q), member(V, Vs), clpz:fd_get_ref(V, _, fd_props(G, B, O)), " <>
            "append([G,B,O], Ps), member(P, Ps), " <>
            "same(phrase(clpz:activate_propagator_ref(P), [Q], _), " <>
            "phrase(clpz:activate_propagator(P), [Q], _), Vs-Q), fail ; true",
          "length(Vs, 5), circuit(Vs), Vs = [2|_], " <>
            "clpz:new_queue(Q), member(V, Vs), clpz:fd_get_ref(V, _, fd_props(G, B, O)), " <>
            "append([G,B,O], Ps), member(P, Ps), " <>
            "same(phrase(clpz:activate_propagator_ref(P), [Q], _), " <>
            "phrase(clpz:activate_propagator(P), [Q], _), Vs-Q), fail ; true"
        ] do
      assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), q
    end
  end

  test "activate_propagator//1: die Propagatoren eines aufgestellten Zustands", c do
    check(c, 200, fn ->
      scenario(
        "(clpz:new_queue(Q), member(V, Vs), clpz:fd_get_ref(V, _, fd_props(Gs, Bs, Os)), " <>
          "append([Gs, Bs, Os], Props), member(P, Props), " <>
          "same(phrase(clpz:activate_propagator_ref(P), [Q], _), " <>
          "phrase(clpz:activate_propagator(P), [Q], _), Vs-Q), fail ; true)"
      )
    end)
  end

  test "fd_get/3,5 wie das Original", c do
    check(c, 150, fn ->
      scenario(
        "(member(V, [N, 3|Vs]), same(clpz:fd_get_ref(V, D, Ps), clpz:fd_get(V, D, Ps), V-D-Ps), " <>
          "same(clpz:fd_get_ref(V, D, I, S, Ps), clpz:fd_get(V, D, I, S, Ps), V-D-I-S-Ps), fail ; true)"
      )
    end)
  end

  test "global_constraint/1: dieselben wie in clpz.pl", c do
    assert {_, {:answers, [a]}} =
             TableCase.run(c.reader, c.db, "findall(F, clpz:global_constraint(F), L)")

    assert a == "L = [" <> Enum.join(PrologEx.Builtins.ClpzPrims.global_constraints(), ",") <> "]"
  end
end
