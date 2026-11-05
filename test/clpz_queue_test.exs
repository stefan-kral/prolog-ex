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
  % die gcc-Propagatoren an X (pgcc_check, pgcc_check_single)
  gcc_props(X, Ps) :-
      clpz:get_atts(X, clpz(clpz_attr(_,_,_,_,fd_props(A,B,C),_))),
      append([A,B,C], L), include(is_gcc, L, Ps).
  % pgcc(Xs, Pairs, Pairs1) an X
  pgcc_of(X, Xs, Pairs1) :-
      clpz:get_atts(X, clpz(clpz_attr(_,_,_,_,fd_props(A,B,C),_))),
      append([A,B,C], L), member(propagator(pgcc(Xs, _, Pairs1), _), L), !.
  is_gcc(propagator(F, _)) :- functor(F, N, _), memberchk(N, [pgcc_check, pgcc_check_single]).
  % X = V bei abgeschalteter Queue von X (der Hook reiht nur ein)
  quiet_bind(X-V) :-
      (   var(X), clpz:variable_queue(X, Q), clpz:fd_get(X, D, _),
          clpz:domain_contains(D, V) ->
          phrase(clpz:disable_queue, [Q], _), X = V, phrase(clpz:enable_queue, [Q], _)
      ;   true
      ).
  % X ≠ V ohne Propagation (die Einträge in eine neue Queue)
  quiet_neq(X-V) :-
      (   var(X), clpz:fd_get(X, D, Ps) ->
          clpz:domain_remove(D, V, D1),
          clpz:new_queue(Q), phrase(clpz:fd_put(X, D1, Ps), [Q], _)
      ;   true
      ).
  % G mit ein- oder ausgeschalteten Abkürzern
  fast(F, G) :- clpz:'$clpz_fast'(F), call(G).
  % eine Variable mit Domäne und eine neue, kleinere Domäne für sie
  pick(Vs, X, D, Ps) :-
      member(X, Vs), clpz:fd_get(X, D0, Ps), clpz:default_domain(All), D0 \\== All, !,
      clpz:domain_infimum(D0, I), clpz:domain_supremum(D0, S),
      (   integer(I) -> clpz:domain_remove(D0, I, D)
      ;   integer(S) -> clpz:domain_remove(D0, S, D)
      ;   clpz:interval(-1, 1, M), clpz:domains_intersection(D0, M, D)
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

  # ein Argument für A #\\= B: Variable (mit oder ohne Domäne), Zahl,
  # abs(X-Y) und andere Ausdrücke (die nimmt der Abkürzer nicht)
  defp neq_arg do
    Enum.random([
      "X",
      "Y",
      "Z",
      "W",
      "B",
      "N",
      "3",
      "0",
      "-2",
      "abs(X-Y)",
      "abs(X-3)",
      "abs(2-Y)",
      "abs(N-X)",
      "abs(X-X)",
      "abs(X+Y)",
      "X+Y",
      "X-Y",
      "abs(X)",
      "#(X)",
      "?(Y)",
      "X*Y",
      "abs(f(a)-X)",
      "-(X-Y)"
    ])
  end

  # ein linearer (oder nicht linearer) Ausdruck für left_right_linsum_const/5
  defp lin_expr(0) do
    Enum.random([
      "X",
      "Y",
      "Z",
      "W",
      "B",
      "N",
      "M",
      "3",
      "0",
      "-2",
      "?(X)",
      "#(Y)",
      "#(N)",
      "?(4)",
      "#(f)"
    ])
  end

  defp lin_expr(d) do
    a = lin_expr(d - 1)
    b = lin_expr(:rand.uniform(d) - 1)

    Enum.random([
      "(#{a})+(#{b})",
      "(#{a})-(#{b})",
      "-(#{a})",
      "(#{Enum.random([2, -3, 0, 1])})*(#{a})",
      "(#{a})*(#{Enum.random([2, -1, 0])})",
      "(#{a})*(#{b})",
      "abs(#{a})",
      a
    ])
  end

  test "left_right_linsum_const/5 wie das Original", c do
    check(c, 700, fn ->
      l = lin_expr(Enum.random(0..3))
      r = lin_expr(Enum.random(0..3))
      mono = :rand.uniform(4) == 1

      scenario(
        "(#{if mono, do: "assertz(clpz:monotonic)", else: "true"}), " <>
          "catch(same(clpz:left_right_linsum_const_ref(#{l}, #{r}, Cs, Vs1, K), " <>
          "clpz:left_right_linsum_const(#{l}, #{r}, Cs, Vs1, K), Vs-N-M-Cs-Vs1-K), E, true), " <>
          "retractall(clpz:monotonic), var(E)"
      )
    end)
  end

  # eine reifizierbare (oder nicht reifizierbare) Formel
  defp reif_expr(0) do
    a =
      Enum.random([
        "X",
        "Y",
        "Z",
        "W",
        "N",
        "3",
        "0",
        "-1",
        "?(X)",
        "#(N)",
        "#(M)",
        "X+1",
        "abs(Y)",
        "Z*2",
        "X-Y",
        "Y mod 2"
      ])

    b = Enum.random(["X", "Y", "Z", "W", "N", "M", "2", "0", "Y+N", "#(M)", "max(X,Z)"])

    Enum.random([
      "#{a} #>= #{b}",
      "#{a} #=< #{b}",
      "#{a} #< #{b}",
      "#{a} #> #{b}",
      "#{a} #= #{b}",
      "#{a} #\\= #{b}",
      "B",
      "C",
      "1",
      "0",
      "?(C)",
      "#(D)",
      "X in 1..3",
      "N in 0..sup",
      "Y in 2",
      "a in 1..2",
      "f(X)",
      "2"
    ])
  end

  defp reif_expr(d) do
    a = reif_expr(d - 1)
    b = reif_expr(:rand.uniform(d) - 1)

    Enum.random([
      "(#{a}) #/\\ (#{b})",
      "(#{a}) #\\/ (#{b})",
      "(#{a}) #==> (#{b})",
      "(#{a}) #<== (#{b})",
      "(#{a}) #<==> (#{b})",
      "(#{a}) #\\ (#{b})",
      "#\\ (#{a})",
      a
    ])
  end

  test "a//3, a//2, a//1 wie das Original", c do
    for x <- ["X", "1"], y <- ["Y", "X", "2"], b <- ["B", "X", "0"], rest <- ["R", "[z]"] do
      for {r, n} <- [
            {"a_ref(#{x},#{y},#{b})", "a(#{x},#{y},#{b})"},
            {"a_ref(#{x},#{b})", "a(#{x},#{b})"},
            {"a_ref(#{b})", "a(#{b})"}
          ] do
        q = "phrase(clpz:#{r}, L1, #{rest}), phrase(clpz:#{n}, L2, #{rest}), L1 == L2"
        assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), q
      end
    end
  end

  test "in/2: der Abkürzer wie drep_to_domain/2 und domain/2", c do
    check(c, 300, fn ->
      v = Enum.random(["X", "Y", "N", "3", "a", "f(X)"])

      d =
        Enum.random(
          ~w(1..3 3..1 0..0 inf..2 -2..sup inf..sup sup..1 1..inf 4 -1 a..3 1..b foo 1\\/3 X..2)
        )

      scenario(
        "catch(same(fast(off, #{v} in #{d}), fast(on, #{v} in #{d}), Vs-N), E, true), var(E)"
      )
    end)
  end

  test "Reifikation: die Abkürzer und Schleifen in Elixir wie das Original", c do
    check(c, 500, fn ->
      e = reif_expr(Enum.random(0..2))
      mono = :rand.uniform(5) == 1
      goal = Enum.random(["clpz:reify(#{e}, R, Ps)", "(#{e}) #<==> R", "#{e}"])

      scenario(
        "(#{if mono, do: "assertz(clpz:monotonic)", else: "true"}), " <>
          "catch(same(fast(off, (#{goal})), fast(on, (#{goal})), " <>
          "Vs-N-M-C-D-R-Ps), E, true), " <>
          "clpz:'$clpz_fast'(on), retractall(clpz:monotonic), var(E)"
      )
    end)
  end

  test "clpz_neq/2: der Abkürzer wählt dieselbe Klausel wie der Matcher", c do
    check(c, 600, fn ->
      a = neq_arg()
      b = neq_arg()
      mono = :rand.uniform(4) == 1

      scenario(
        "(#{if mono, do: "assertz(clpz:monotonic)", else: "true"}), " <>
          "catch(same((clpz:'$clpz_fast'(off), clpz:clpz_neq(#{a}, #{b})), " <>
          "(clpz:'$clpz_fast'(on), clpz:clpz_neq(#{a}, #{b})), Vs-N), E, true), " <>
          "clpz:'$clpz_fast'(on), retractall(clpz:monotonic), var(E)"
      )
    end)
  end

  test "init_propagator_//2, init_propagator/2, reinforce/1 wie das Original", c do
    check(c, 400, fn ->
      vs = ["X", "Y", "Z", "W", "B", "_", "3", "N"]
      l = Enum.map_join(1..Enum.random(0..4)//1, ",", fn _ -> Enum.random(vs) end)
      t = synth()

      cmp =
        case :rand.uniform(3) do
          1 ->
            "clpz:new_queue(Q), P = propagator(#{t}, S), " <>
              "same(phrase(clpz:init_propagator__ref([#{l}], P), [Q], _), " <>
              "phrase(clpz:init_propagator_([#{l}], P), [Q], _), Vs-Q-P)"

          2 ->
            "P = propagator(#{t}, S), V = #{Enum.random(vs)}, " <>
              "same(clpz:init_propagator_ref(V, P), clpz:init_propagator(V, P), Vs-P)"

          _ ->
            "T = f(a, [#{l}]), same(clpz:reinforce_ref(T), clpz:reinforce(T), Vs-T)"
        end

      scenario("(#{cmp})")
    end)
  end

  test "init_propagator_//2, reinforce/1: Variable mit Einzelwert-Domäne, noch ungebunden", c do
    single =
      "X in 0..5, Y in 0..5, X #\\= Y, clpz:get_atts(X, clpz(clpz_attr(L,R,Sp,_,Ps,Q0))), " <>
        "clpz:put_atts(X, clpz(clpz_attr(L,R,Sp,[2],Ps,Q0)))"

    for cmp <- [
          "clpz:new_queue(Q), P = propagator(pneq(X,Y), _), " <>
            "same(phrase(clpz:init_propagator__ref([X,Y], P), [Q], _), " <>
            "phrase(clpz:init_propagator_([X,Y], P), [Q], _), [X,Y]-Q-P)",
          "same(clpz:reinforce_ref(f(X,Y)), clpz:reinforce(f(X,Y)), [X,Y])"
        ] do
      q = "#{single}, #{cmp}"
      assert {_, {:answers, [_]}} = TableCase.run(c.reader, c.db, q), q
    end
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
          # scheitert nach kill/1: das Original weckt vorher
          "P = propagator(pneq(X,X), S), freeze(S, write(s)), phrase(clpz:queue_fast(P), [Q], _)",
          "P = propagator(ptimes(2,X,-1,_), S), freeze(S, write(s)), " <>
            "phrase(clpz:queue_fast(P), [Q], _)",
          "P1 = propagator(pneq(X,3), S1), P2 = propagator(pneq(Y,X), S2), " <>
            "freeze(S2, write(s2)), phrase(clpz:queue_fast(P1), [Q], _), " <>
            "phrase(clpz:queue_fast(P2), [Q], _), X = 2"
        ] do
      [ref, new] = queue_outputs(c, c.db, setup)
      assert ref == new, setup

      # (die scheiternden Fälle: nur der Vergleich mit dem Original)
      unless setup =~ "X,X" or setup =~ "-1,_" do
        assert {o, {:answers, [_]}} = new
        assert o =~ "s", setup
      end
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

  test "Aufstellen mit einem weiteren Hook-Modul: Ausgabe und Ergebnis wie das Original", c do
    PrologEx.put_db(c.db)

    ExUnit.CaptureIO.capture_io(fn ->
      {:ok, _} = PrologEx.Consult.load_file("test/fixtures/atts/alle.pl")
    end)

    db = PrologEx.current_db()

    for g <- [
          "X #\\= Y",
          "X #\\= Y, Y #\\= Z",
          "(X #>= Y) #<==> B",
          "(X #= 3 #/\\ Y #< Z) #<==> B",
          "abs(X-Y) #\\= 2"
        ] do
      [ref, new] =
        for f <- ["off", "on"] do
          TableCase.run(
            c.reader,
            db,
            "X in 0..5, Y in 0..5, Z in 1..3, fast(#{f}, (#{g})), write(ende)"
          )
        end

      assert ref == new, g
    end
  end

  test "mit einem weiteren Hook-Modul: Ausgabe und Ergebnis wie das Original", c do
    PrologEx.put_db(c.db)

    ExUnit.CaptureIO.capture_io(fn ->
      {:ok, _} = PrologEx.Consult.load_file("test/fixtures/atts/alle.pl")
    end)

    db = PrologEx.current_db()

    diffs =
      for _ <- 1..300,
          t = synth(),
          d = doms(),
          fill =
            Enum.map_join(1..Enum.random(0..4)//1, ",", fn _ ->
              "#{Enum.random(@vars)}-#{Enum.random(1..3)}"
            end),
          l = Enum.map_join(1..Enum.random(0..4)//1, ",", fn _ -> Enum.random(@vars) end),
          [ref, new] <-
            [
              for {act, dq} <- [
                    {"activate_propagator_ref", "do_queue_ref"},
                    {"activate_propagator", "do_queue"}
                  ] do
                "Vs = [X,Y,Z,W,B,DX,DY,PE], #{d}, clpz:new_queue(Q), P = propagator(#{t}, S), " <>
                  "phrase((clpz:#{act}(P), clpz:#{dq}), [Q], _), write(ende)"
              end,
              for vsq <- ["variables_same_queue_ref", "variables_same_queue"] do
                "Vs = [X,Y,Z,W], #{d}, X #\\= Y, fill([#{fill}], 0), clpz:#{vsq}([#{l}]), write(ende)"
              end
            ],
          r1 = TableCase.run(c.reader, db, ref),
          r2 = TableCase.run(c.reader, db, new),
          r1 != r2,
          do: {new, r1, r2}

    assert diffs == [], inspect(Enum.take(diffs, 2), pretty: true)
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

  test "verify_attributes/3: zwei Variablen mit Domänen und gefüllten Queues", c do
    check(c, 400, fn ->
      [v, o] = Enum.take_random(@vars ++ ["B"], 2)

      fill =
        Enum.map_join(1..Enum.random(0..5)//1, ",", fn _ ->
          "#{Enum.random(@vars)}-#{Enum.random(1..3)}"
        end)

      scenario(
        "(fill([#{fill}], 0), " <>
          "same(clpz:verify_attributes_ref(#{v}, #{o}, G), " <>
          "clpz:verify_attributes(#{v}, #{o}, G), Vs-G))"
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
      d = Enum.random(["[2]", "[]", "[0..3]", "[inf..1]"])
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

  test "v_or_i/1: Zahl, Variable mit und ohne Domäne, anderes, monotonic", c do
    for t <- [
          "true",
          "X in 1..3",
          "X = 5",
          "X = -7",
          "X = a",
          "X = f(Y)",
          "X = 2^100, true",
          "X = 1.0",
          "X #= Y + 1"
        ] do
      for mono <- [false, true] do
        q =
          "#{t}, (#{if mono, do: "assertz(clpz:monotonic)", else: "true"}), " <>
            "catch(same(clpz:v_or_i_ref(X), clpz:v_or_i(X), X), E, true), " <>
            "retractall(clpz:monotonic), var(E)"

        r = TableCase.run(c.reader, c.db, q)
        assert match?({_, {:answers, [_]}}, r), inspect({q, r})
      end
    end
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
            "same(clpz:trigger_props_ref(Ps, 3, [0..5], [3], [Q], _), " <>
            "clpz:trigger_props(Ps, 3, [0..5], [3], [Q], _), Q-S1-S2-S3)",
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
    case :rand.uniform(32) do
      27 ->
        "x_neq_y_plus_z(#{parg()}, #{parg()}, #{parg()})"

      28 ->
        n = Enum.random(0..4)
        cs = Enum.map_join(1..max(n, 1), ",", fn _ -> Enum.random([-1, 1, 1, -1, 2, 0]) end)
        vs = Enum.map_join(1..max(n, 1), ",", fn _ -> parg() end)
        "scalar_product_neq([#{cs}], [#{vs}], #{Enum.random([0, 0, -2, 1, 3, 4])})"

      29 ->
        d =
          Enum.random([
            "[1..3]",
            "[inf..2]",
            "[0..sup]",
            "[0..1,4..sup]",
            "[0]",
            "[inf..sup]"
          ])

        "reified_in(#{parg()}, #{d}, #{Enum.random(["B", "B", "0", "1", "W"])})"

      30 ->
        "reified_fd(#{parg()}, #{Enum.random(["B", "B", "0", "1"])})"

      31 ->
        "pxor(#{parg()}, #{parg()}, #{parg()})"

      32 ->
        "psign(#{parg()}, #{Enum.random(["Y", "-1", "0", "1", "2", "W"])})"

      25 ->
        "pelement(#{Enum.random(["X", "W", "1", "2", "4", "0"])}, #{plist()}, #{parg()})"

      21 ->
        "reified_or(#{Enum.random(["0", "1", "X", "DX"])}, #{ents()}, " <>
          "#{Enum.random(["0", "1", "Y", "DY", "DX"])}, #{ents()}, #{Enum.random(["B", "0", "1", "W"])})"

      22 ->
        "reified_not(#{Enum.random(["0", "1", "B", "DX"])}, #{Enum.random(["0", "1", "W", "DY", "B"])})"

      23 ->
        "pimpl(#{Enum.random(["0", "1", "B", "DX"])}, #{Enum.random(["0", "1", "W", "DY", "B"])}, #{ents()})"

      24 ->
        "x_leq_y_plus_c(#{parg()}, #{parg()}, #{Enum.random(-3..3)})"

      18 ->
        "ptzdiv(#{parg()}, #{Enum.random(["Y", "2", "-3", "1", "-1", "0", "Y"])}, #{parg()}, _)"

      19 ->
        "prem(#{parg()}, #{Enum.random(["Y", "3", "-2", "1", "0", "Y"])}, #{parg()})"

      20 ->
        "pmod(#{parg()}, #{Enum.random(["Y", "3", "-2", "1", "0", "Y", "X"])}, #{parg()})"

      15 ->
        b = Enum.random(["B", "0", "1", "B"])
        dx = Enum.random(["1", "1", "0", "DX"])
        dy = Enum.random(["1", "1", "0", "DY"])

        "#{Enum.random(~w(reified_eq reified_neq))}(#{dx}, #{parg()}, #{dy}, #{parg()}, #{ents()}, #{b})"

      16 ->
        "pexp(#{parg()}, #{Enum.random(["Y", "2", "3", "1", "0", "-1", "-2", "Z"])}, #{parg()}, _)"

      17 ->
        "pexp(#{Enum.random(["X", "2", "-2", "3", "1", "0", "-1"])}, #{parg()}, #{Enum.random(["Z", "8", "9", "-8", "1", "0", "16"])}, _)"

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
          "p(PE)",
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

      "Vs = [X,Y,Z,W,B,DX,DY,PE], (#{doms()}, #{bdom} -> clpz:new_queue(Q), " <>
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

  # Tripel aus Domänen mit Vorzeichen, Null, unendlich: je Gruppe ein Test
  # (laufen parallel)
  @triple_doms @doms ++ ["-3..3", "-4.. -2\\/2..3", "0..0\\/2..6"]
  @triples [
    {"ptimes",
     ["ptimes(X, Y, Z, _)", "ptimes(X, -2, Z, _)", "ptimes(X, Y, 6, _)", "ptimes(X, Y, 0, _)"]},
    {"pmax pmin", ["pmax(X, Y, Z)", "pmax(X, 3, Z)", "pmin(X, Y, Z)", "pmin(X, 3, Z)"]},
    {"pabs", ["pabs(X, Y)", "pabs(X, 3)", "pabs(-2, Y)", "pabs(X, X)"]},
    {"reified_eq reified_neq",
     [
       "reified_eq(1, X, 1, Y, [], B)",
       "reified_neq(1, X, 1, Y, [], B)",
       "reified_eq(1, X, 1, 3, [], B)",
       "reified_neq(1, 2, 1, Y, [], B)",
       "reified_neq(1, X, 1, Y, [], 0)"
     ]},
    {"pexp",
     [
       "pexp(X, Y, Z, _)",
       "pexp(X, 2, Z, _)",
       "pexp(X, 3, Z, _)",
       "pexp(2, Y, Z, _)",
       "pexp(-2, Y, Z, _)",
       "pexp(X, Y, 16, _)",
       "pexp(X, 3, -8, _)",
       "pexp(3, Y, 81, _)",
       "pexp(X, -1, Z, _)"
     ]},
    {"ptzdiv",
     [
       "ptzdiv(X, Y, Z, _)",
       "ptzdiv(X, 3, Z, _)",
       "ptzdiv(X, -2, Z, _)",
       "ptzdiv(7, Y, Z, _)",
       "ptzdiv(-7, Y, Z, _)",
       "ptzdiv(X, Y, 2, _)",
       "ptzdiv(9, Y, 2, _)",
       "ptzdiv(-9, Y, 0, _)",
       "ptzdiv(X, 3, -2, _)"
     ]},
    {"pelement",
     [
       "pelement(X, [Y, Z, 3], W)",
       "pelement(X, [Y, 4, Z], Y)",
       "pelement(X, [1, 2, 3, 7], Y)",
       "pelement(X, [Z, Z], Y)",
       "pelement(2, [Y, Z], X)",
       "pelement(3, [Y, Z], X)",
       "pelement(X, [Y, Z, 3], 3)"
     ]},
    {"x_leq_y_plus_c",
     [
       "x_leq_y_plus_c(X, Y, 0)",
       "x_leq_y_plus_c(X, Y, 2)",
       "x_leq_y_plus_c(X, Y, -3)",
       "x_leq_y_plus_c(X, 3, 1)",
       "x_leq_y_plus_c(4, Y, -1)",
       "x_leq_y_plus_c(X, X, 0)",
       "x_leq_y_plus_c(X, X, -1)"
     ]},
    {"x_neq_y_plus_z scalar_product_neq",
     [
       "x_neq_y_plus_z(X, Y, Z)",
       "x_neq_y_plus_z(3, Y, Z)",
       "x_neq_y_plus_z(X, 2, Z)",
       "x_neq_y_plus_z(X, Y, 1)",
       "x_neq_y_plus_z(5, 2, Z)",
       "x_neq_y_plus_z(X, 2, 3)",
       "x_neq_y_plus_z(4, Y, 1)",
       "scalar_product_neq([1,2,1], [X,Y,Z], 4)",
       "scalar_product_neq([1,1,-1], [X,Y,Z], 1)",
       "scalar_product_neq([1,-1,1], [X,Y,Z], 0)",
       "scalar_product_neq([1,1,-1,2], [X,Y,Z,2], 4)"
     ]},
    {"pxor psign reified_in reified_fd",
     [
       "pxor(X, Y, Z)",
       "pxor(X, X, Z)",
       "pxor(X, 0, Z)",
       "pxor(X, Y, 0)",
       "psign(X, Y)",
       "psign(X, -1)",
       "psign(X, 2)",
       "reified_fd(X, Y)",
       "reified_in(X, [0..3], Y)",
       "reified_in(X, [-2..1,5..sup], Y)"
     ]},
    {"prem",
     ["prem(X, Y, Z)", "prem(X, 3, Z)", "prem(X, -4, Z)", "prem(X, 3, 1)", "prem(X, -4, -2)"]},
    {"pmod",
     [
       "pmod(X, Y, Z)",
       "pmod(X, 3, Z)",
       "pmod(X, -3, Z)",
       "pmod(X, 3, 2)",
       "pmod(X, -3, -1)",
       "pmod(7, Y, Z)",
       "pmod(-7, Y, Z)",
       "pmod(7, Y, 3)",
       "pmod(-7, Y, 1)",
       "pmod(7, Y, 0)",
       "pmod(X, Y, 2)",
       "pmod(X, Y, -2)",
       "pmod(X, X, Z)"
     ]}
  ]

  for {group, ts} <- @triples do
    @ts ts
    test "#{group}: Tripel aus Domänen mit Vorzeichen, Null, unendlich", c do
      diffs =
        for dx <- @triple_doms,
            dy <- @triple_doms,
            dz <- Enum.take_random(@triple_doms, 4),
            t <- @ts do
          prop_case(c, "X in #{dx}, Y in #{dy}, Z in #{dz}", t)
        end

      assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
    end
  end

  test "ptimes, pexp: Sonderfälle der Schranken", c do
    diffs =
      for {setup, t} <- [
            # X·X = Z: X in -R \/ R (das Original)
            {"X in -3..3", "ptimes(X, X, 4, _)"},
            {"X in 0..5", "ptimes(X, X, 9, _)"},
            {"X in -3..3", "ptimes(X, X, 0, _)"},
            # X^2 mit X ganz negativ: untere Schranke XU^2
            {"X in -5.. -2, Z in 0..100", "pexp(X, 2, Z, _)"},
            {"X in inf.. -3, Z in -10..sup", "pexp(X, 2, Z, _)"},
            {"X in -5.. -2, Z in -200..200", "pexp(X, 3, Z, _)"},
            # Z negativ, Y um 0, X ohne 0: Schranke L1 (min_factor/5)
            {"X in -20.. -1, Y in -2..2, Z in -10.. -5", "ptimes(X, Y, Z, _)"},
            {"X in 1..20, Y in -2..2, Z in 5..10", "ptimes(X, Y, Z, _)"},
            {"X in -20.. -1, Y in -2..2, Z in 5..10", "ptimes(X, Y, Z, _)"}
          ] do
        prop_case(c, setup, t)
      end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  test "reified_or, reified_not, pimpl: alle Kombinationen aus 0, 1, offen", c do
    bs = ["0", "1", "0..1"]

    diffs =
      for dx <- bs,
          dy <- bs,
          dz <- bs,
          t <- [
            "reified_or(X, [], Y, [], Z)",
            "reified_or(X, [p(P1)], Y, [p(P2)], Z)",
            "reified_not(X, Y)",
            "pimpl(X, Y, [])",
            "pimpl(X, Y, [p(P1)])"
          ] do
        prop_case(
          c,
          "X in #{dx}, Y in #{dy}, Z in #{dz}, P1 = propagator(_, _), W = P1-P2",
          t
        )
      end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  test "pgcc_check, pgcc_check_single: Zufallszustände nach global_cardinality/3", c do
    diffs =
      for _ <- 1..400 do
        doms =
          Enum.map_join(~w(A B C D E), ", ", fn v ->
            "#{v} in #{Enum.random(~w(1..3 1..2 2..3 1..1 3..3 1\\/3 0..4))}"
          end)

        nums =
          Enum.map_join(~w(N1 N2 N3), ", ", fn v ->
            "#{v} in #{Enum.random(~w(0..5 1..2 0..1 2..2 3..5 0..0 1..sup))}"
          end)

        vs = Enum.take_random(~w(A B C D E), Enum.random(2..5)) |> Enum.join(",")
        k = Enum.random([[1, 2, 3], [1, 2], [2, 3]])
        pairs = Enum.zip(k, ~w(N1 N2 N3)) |> Enum.map_join(",", fn {k, n} -> "#{k}-#{n}" end)

        mods =
          Enum.map_join(1..Enum.random(0..4)//1, ", ", fn _ ->
            x = Enum.random(~w(A B C D E N1 N2 N3))
            v = Enum.random(0..4)
            if :rand.uniform(2) == 1, do: "quiet_bind(#{x}-#{v})", else: "quiet_neq(#{x}-#{v})"
          end)

        mods = if mods == "", do: "true", else: mods
        pick = Enum.random(["A", "N1", "N2", "B"])
        qv = Enum.random(["", "N1", "N2", "N3", "A", "C"])

        q =
          "Vs = [A,B,C,D,E,N1,N2,N3], (#{doms}, #{nums}, " <>
            "global_cardinality([#{vs}], [#{pairs}], [consistency(value)]), #{mods}, " <>
            "gcc_props(#{pick}, Ps), member(P, Ps) -> #{gcc_queue(qv)}, " <>
            "same(phrase((clpz:activate_propagator_ref(P), clpz:do_queue_ref), [Q], _), " <>
            "phrase((clpz:activate_propagator(P), clpz:do_queue), [Q], _), Vs-Q-P) ; true)"

        r = TableCase.run(c.reader, c.db, q)
        if match?({_, {:answers, [_]}}, r), do: [], else: [{q, r}]
      end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  # die Queue für den gcc-Test: neu oder die einer Variablen (dann rechnet
  # Elixir auch die eine Bindung am Ende). Verglichen wird bis zum Fixpunkt:
  # die Bindung kommt hier nach enable_queue, der Hook rechnet die Queue
  # gleich (im Original erst die äußere Schleife)
  defp gcc_queue(""), do: "clpz:new_queue(Q)"
  defp gcc_queue(v), do: "(clpz:variable_queue(#{v}, Q) -> true ; clpz:new_queue(Q))"

  test "gcc_neq_goals: Wertenetz, Fluss, Komponenten wie das Original", c do
    xs = ~w(A B C D E F)

    diffs =
      for _ <- 1..900 do
        n = Enum.random(2..6)
        keys = Enum.take_random([1, 2, 3, 4], Enum.random(2..4)) |> Enum.sort()
        kd = Enum.join(keys, "\\/")

        doms =
          Enum.map_join(Enum.take(xs, n), ", ", fn v ->
            sub = Enum.take_random(keys, Enum.random(1..length(keys))) |> Enum.join("\\/")
            "#{v} in #{Enum.random([kd, kd, sub])}"
          end)

        ns = Enum.take(~w(N1 N2 N3 N4), length(keys))

        nums =
          Enum.map_join(ns, ", ", fn v ->
            "#{v} in #{Enum.random(~w(0..6 1..2 0..1 2..2 1..3 0..0 2..6 3..4 2..3 0..8))}"
          end)

        pairs = Enum.zip(keys, ns) |> Enum.map_join(",", fn {k, n} -> "#{k}-#{n}" end)

        mods =
          Enum.map_join(0..Enum.random(0..4)//1, ", ", fn _ ->
            x = Enum.random(Enum.take(xs, n) ++ ns)
            v = Enum.random(0..4)
            if :rand.uniform(2) == 1, do: "quiet_bind(#{x}-#{v})", else: "quiet_neq(#{x}-#{v})"
          end)

        xl = Enum.take(xs, n) |> Enum.join(",")

        # ohne Propagation: die Num0 wie gcc_pairs/3, gcc_check//1 (das
        # Original), dann das Netz; die
        # Variablen auch mehrfach und durcheinander (Kapazitäten über 1,
        # Sortieren)
        xl0 =
          if :rand.uniform(2) == 1,
            do: xl,
            else:
              Enum.map_join(1..Enum.random(2..8), ",", fn _ -> Enum.random(Enum.take(xs, n)) end)

        q0 =
          "Vs = [A,B,C,D,E,F,N1,N2,N3,N4], (#{doms}, #{nums}, Xs = [#{xl0}], " <>
            "clpz:gcc_pairs([#{pairs}], Xs, Ps1), clpz:new_queue(Q0), " <>
            "phrase(clpz:gcc_check(Ps1), [Q0], _) -> " <>
            "same(clpz:gcc_neq_goals_ref(Xs, Ps1, G), clpz:gcc_neq_goals(Xs, Ps1, G), Vs-G) ; true)"

        r0 = TableCase.run(c.reader, c.db, q0)

        q =
          "Vs = [A,B,C,D,E,F,N1,N2,N3,N4], (#{doms}, #{nums}, " <>
            "global_cardinality([#{xl}], [#{pairs}]), #{mods}, " <>
            "once((member(X0, [#{Enum.take(xs, n) |> Enum.join(",")}]), var(X0), " <>
            "pgcc_of(X0, Xs, Ps1))) -> " <>
            "same(clpz:gcc_neq_goals_ref(Xs, Ps1, G), clpz:gcc_neq_goals(Xs, Ps1, G), Vs-G) ; true)"

        r = TableCase.run(c.reader, c.db, q)

        if(match?({_, {:answers, [_]}}, r0), do: [], else: [{q0, r0}]) ++
          if match?({_, {:answers, [_]}}, r), do: [], else: [{q, r}]
      end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  test "gcc_neq_goals: Umleiten über Rückwärtskanten", c do
    diffs =
      for {setup, xl, pairs} <- [
            # Val2 nimmt zuerst B, Val1 kann nur B: über B zurück zu Val2, dann A
            {"A in 2..3, B in 1..2, N3 in 0..1", "A,B", "1-1,2-1,3-N3"},
            {"A in 2..3, B in 1..2, C in 1..3, N3 in 0..2", "A,B,C", "1-1,2-1,3-N3"},
            {"A in 2..3, B in 1..2, C in 2..3, D in 1..1\\/3", "A,B,C,D", "1-1,2-2,3-1"},
            {"A in 2..3, B in 1..2, C in 1..2", "A,B,C,B", "1-2,2-1,3-1"},
            {"A in 2..3, B in 1..2, C in 1..3", "C,B,A,B", "1-1,2-2,3-1"}
          ] do
        q =
          "Vs = [A,B,C,D,N3], (#{setup}, Xs = [#{xl}], " <>
            "clpz:gcc_pairs([#{pairs}], Xs, Ps1), clpz:new_queue(Q0), " <>
            "phrase(clpz:gcc_check(Ps1), [Q0], _) -> " <>
            "same(clpz:gcc_neq_goals_ref(Xs, Ps1, G), clpz:gcc_neq_goals(Xs, Ps1, G), Vs-G) ; fail)"

        r = TableCase.run(c.reader, c.db, q)
        if match?({_, {:answers, [_]}}, r), do: [], else: [{q, r}]
      end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  test "pgcc_check: Sonderfälle (alle ≠ Key, eine Bindung am Ende, zu viele)", c do
    diffs =
      for {setup, vs, pairs, qv, mods} <- [
            # Num = Occ1: Key aus den übrigen entfernen
            {"A in 1..3, B in 1..3, C in 1..3", "A,B,C", "1-N1,2-N2,3-N3", "N1",
             "quiet_bind(N1-0)"},
            {"A in 1..3, B in 1..3, C in 1..3", "A,B,C", "1-N1,2-N2,3-N3", "",
             "quiet_bind(N2-0)"},
            # das letzte Paar: Os = [], Num = Occ1 (eine Bindung)
            {"A in 1..2, B in 1..2", "A,B", "1-N1,2-N2", "N2",
             "quiet_bind(N1-1), quiet_bind(A-1), quiet_bind(B-2)"},
            # Os = [], Num bekannt und größer als Occ1
            {"A in 1..2, B in 1..2, C in 1..2", "A,B,C", "2-N2,1-N1", "N1",
             "quiet_bind(N2-2), quiet_bind(A-1), quiet_bind(B-2), quiet_bind(C-1)"},
            # das letzte Paar: Num bekannt, genau eine Variable bleibt
            {"A in 1..2, B in 1..2, C in 1..2", "A,B,C", "1-N1,2-N2", "C",
             "quiet_bind(N1-1), quiet_bind(N2-2), quiet_bind(A-1), quiet_bind(B-2)"},
            {"A in 1..2, B in 1..2, C in 1..2", "A,B,C", "1-N1,2-N2", "B",
             "quiet_bind(N1-1), quiet_bind(N2-2), quiet_bind(A-1), quiet_bind(C-2)"},
            # Num zu groß für die übrigen
            {"A in 1..2, B in 1..2", "A,B", "1-N1,2-N2", "", "quiet_bind(A-2), quiet_bind(N1-2)"},
            # Num offen, untere Schranke = Occ1 + L
            {"A in 1..2, B in 1..2, C in 1..2, N1 in 2..3", "A,B,C", "1-N1,2-N2", "",
             "quiet_bind(C-2)"}
          ] do
        q =
          "Vs = [A,B,C,D,E,N1,N2,N3], (#{setup}, " <>
            "global_cardinality([#{vs}], [#{pairs}], [consistency(value)]), #{mods}, " <>
            "once((member(X0, [A,B,C,N1,N2]), var(X0), gcc_props(X0, [P|_]))) -> " <>
            "#{gcc_queue(qv)}, " <>
            "same(phrase((clpz:activate_propagator_ref(P), clpz:do_queue_ref), [Q], _), " <>
            "phrase((clpz:activate_propagator(P), clpz:do_queue), [Q], _), Vs-Q-P) ; fail)"

        r = TableCase.run(c.reader, c.db, q)
        if match?({_, {:answers, [_]}}, r), do: [], else: [{q, r}]
      end

    assert List.flatten(diffs) == [], inspect(Enum.take(List.flatten(diffs), 2), pretty: true)
  end

  test "prem, pmod: Sonderfälle der Schranken", c do
    diffs =
      for {setup, t} <- [
            # X rem Y: Z-Schranke aus X statt aus Y
            {"X in -2..10", "prem(X, 5, Z)"},
            {"X in -10..2", "prem(X, 5, Z)"},
            # X mod Y = Z mit X, Z bekannt: unmöglich
            {"Y in -10..10", "pmod(3, Y, 2)"},
            {"Y in -10..10", "pmod(-3, Y, -2)"},
            # Y an der Grenze zu X (Y = X gibt 0, nicht X)
            {"Y in 7..9", "pmod(7, Y, Z)"},
            {"Y in -9.. -7", "pmod(-7, Y, Z)"},
            {"X in -5.. -1, Y in -9.. -5", "pmod(X, Y, Z)"},
            {"X in 1..5, Y in 5..9", "pmod(X, Y, Z)"},
            # Y halb unendlich
            {"Y in -3..sup", "pmod(X, Y, Z)"},
            {"Y in inf..3", "pmod(X, Y, Z)"}
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
