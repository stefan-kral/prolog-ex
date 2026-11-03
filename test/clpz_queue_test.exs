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
