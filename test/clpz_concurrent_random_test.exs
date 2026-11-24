defmodule PrologEx.ClpzConcurrentRandomTest do
  # Differenztests mit Zufallsmodellen: concurrent_labeling/3 muss genau die
  # Lösung von once(labeling/2) geben, concurrent_labelings/4 genau
  # findall(Vs, labeling/2, L) – für zufällige Modelle (Summen, Ungleich,
  # all_different, Reifikation, mod, Produkte), zufällige Optionen von
  # labeling/2 (Variablenwahl, Reihenfolge, Verzweigung, min/max, auch
  # mehrere) und zufällige Optionen des Aufteilens (serial, parts, steal).
  # Ein Teil der Runden mit erzwungenen Verzögerungen (PrologEx.Chaos),
  # auch mit flachen Abgaben (steal: :top). Feste Anfragen prüfen, woran
  # man denkt; Zufallsmodelle auch den Rest.
  #
  # Fester Seed; CLPZ_RANDOM_SEED=N wählt einen anderen, CLPZ_RANDOM_N=K
  # vervielfacht die Zahl der Modelle (für lange Läufe). Eine Abweichung
  # zeigt die Anfrage, sie lässt sich so im Toplevel nachrechnen.
  use ExUnit.Case, async: false
  alias PrologEx.{Chaos, Reader, TableCase}

  @prog """
  % G: die Constraints über Vs, O: Optionen von labeling/2 (auch min/max
  % über Vs), C: Optionen des Aufteilens. Beide Seiten auf einer Kopie
  same1(G, Vs, O, C, R) :-
      copy_term(G-Vs-O, G0-V0-O0), side(G0, once(labeling(O0, V0)), V0, S0),
      copy_term(G-Vs-O, G1-V1-O1), side(G1, concurrent_labeling(O1, V1, C), V1, S1),
      verdict(O, S0, S1, R0),
      limit(R0, G, Vs, O, first, S1, R).
  sameall(G, Vs, O, C, R) :-
      copy_term(G-Vs-O, G0-V0-O0), side(G0, findall(V0, labeling(O0, V0), L0), L0, S0),
      copy_term(G-Vs-O, G1-V1-O1), side(G1, concurrent_labelings(O1, V1, L1, C), L1, S1),
      verdict(O, S0, S1, R0),
      limit(R0, G, Vs, O, all, S1, R).
  % die bekannte Grenze (README): die Kinder setzen das Modell aus
  % copy_term/3 neu auf, das kann anders propagieren oder später andere
  % Propagatoren anhängen; bei ff, ffc, min, max wählen sie dann womöglich
  % andere Variablen. Abweichung zulässig, wenn labeling/2 auf genau so
  % einem neu aufgesetzten Modell dasselbe gibt wie parallel
  limit(gleich, _, _, _, _, _, gleich) :- !.
  limit(R0, G, Vs, O, Kind, S1, R) :-
      R0 = verschieden(S0, _),
      (   ( memberchk(ff, O) ; memberchk(ffc, O) ; memberchk(min, O) ; memberchk(max, O) ),
          copy_term(G-Vs-O, G2-V2-O2),
          catch(call(G2), _, fail),
          copy_term(V2-O2, V3-O3, Gs0), clpz_concurrent:goal_conj(Gs0, Gs),
          catch(( call(Gs),
                  ( memberchk(ffc, O) -> maplist(clpz_concurrent:props_count, V2, Ns),
                                         clpz_concurrent:pad_props(V3, Ns) ; true ) ), _, fail),
          (   Kind == first -> side(true, once(labeling(O3, V3)), V3, S3)
          ;   side(true, findall(V3, labeling(O3, V3), L3), L3, S3)
          ),
          (   S3 == S1 -> true
          ;   % das neu aufgesetzte Modell gibt selbst etwas anderes als das
              % Original (die Grenze trifft dieses Modell); mit serial(S)
              % mischen sich beide (der Anfang im Aufrufer): dann nur
              % dieselbe Menge bzw. eine Lösung aus ihr
              R0 = verschieden(S0, _),
              ( S3 \\== S0 ; Kind == all, group_prone(G, Vs, O) ),
              same_set(Kind, G, Vs, O, S0, S1)
          )
      ->  R = gleich
      ;   R = R0
      ).
  same_set(all, _, _, _, ok(L0), ok(L1)) :- msort(L0, M), msort(L1, M).
  same_set(first, G, Vs, O, ok(_), ok(Sol)) :-
      copy_term(G-Vs-O, G4-V4-O4), call(G4), findall(V4, labeling(O4, V4), All),
      memberchk(Sol, All).
  % alle Lösungen mit min(E)/max(E): je Gruppe ein eigener Zustand (S #= E,
  % S #\\= die vorigen Werte, S #= Wert), die Kinder setzen ihn neu auf –
  % trifft die Grenze diesen Zustand (labeling/2 neu aufgesetzt anders als
  % im Original), gilt nur dieselbe Menge
  % (bei mehreren Kriterien: die Gruppen des ersten, die übrigen bleiben in
  % den Optionen – labeling/2 optimiert sie in der Gruppe selbst)
  group_prone(G, Vs, O) :-
      append(Pre, [W|Post], O), W =.. [Dir, _], memberchk(Dir, [min, max]), !,
      append(Pre, Post, B0),
      copy_term(G-Vs-W-B0, G1-V1-W1-B1), arg(1, W1, E1),
      catch(call(G1), _, fail),
      catch(findall(X, ( labeling(B1, V1), X is E1 ), Xs), _, fail),
      sort(Xs, Asc), ( Dir == min -> Vals = Asc ; reverse(Asc, Vals) ),
      append(Prev, [V|_], Vals),
      copy_term(G-Vs-W-B0, G2-V2-W2b-B2), arg(1, W2b, E2),
      call(G2), S #= E2, maplist(expr_neq(S), Prev), S #= V,
      findall(V2, labeling(B2, V2), L2),
      maplist(clpz_concurrent:props_count, V2, Ns),
      copy_term(V2-B2, V3-B3, Gs0), clpz_concurrent:goal_conj(Gs0, Gs), call(Gs),
      ( memberchk(ffc, B2) -> clpz_concurrent:pad_props(V3, Ns) ; true ),
      findall(V3, labeling(B3, V3), L3),
      L2 \\== L3, !.
  expr_neq(S, V) :- S #\\= V.
  side(G, Goal, Out, S) :-
      catch(( call(G) -> ( call(Goal) -> S = ok(Out) ; S = none ) ; S = none ),
            E, ( E = error(F, _) -> S = error(F) ; S = ball(E) )).
  % mit min/max hängt, ob ein Knoten mit Ausnahme erreicht wird, an der
  % Schranke, die dort gilt (nacheinander und parallel verschieden): dann
  % zählt nur, haben beide eine Lösung, dieselbe
  verdict(O, S0, S1, R) :-
      (   S0 == S1 -> R = gleich
      ;   ( memberchk(min(_), O) ; memberchk(max(_), O) ),
          ( S0 = ball(_) ; S1 = ball(_) ) -> R = gleich
      ;   R = verschieden(S0, S1)
      ).
  """

  setup_all do
    PrologEx.TestEnv.apply_jit()
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ~w(clpz clpz_concurrent concurrent lists))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @prog))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup do
    on_exit(fn -> Chaos.disable() end)
  end

  # --- Zufallsmodelle -------------------------------------------------------

  defp pick(l), do: Enum.at(l, :rand.uniform(length(l)) - 1)
  defp chance(p), do: :rand.uniform() < p

  # n Variablen mit kleinen Bereichen; die Zahl der Blätter der Suche bleibt
  # beschränkt (max_leaves), damit auch Modelle ohne Lösung schnell sind
  defp model(n, max_leaves) do
    vs = for i <- 1..n, do: "_X#{i}"

    doms =
      Enum.reduce(vs, {[], 1}, fn _, {acc, prod} ->
        lo = pick([0, 0, 1, -2])
        w = Enum.min([pick([2, 3, 4, 5, 6]), max(div(max_leaves, prod) - 1, 1)])
        {[{lo, lo + w} | acc], prod * (w + 1)}
      end)
      |> elem(0)
      |> Enum.reverse()

    ins = for {v, {lo, hi}} <- Enum.zip(vs, doms), do: "#{v} in #{lo} .. #{hi}"
    cs = for _ <- 1..(1 + :rand.uniform(4)), do: constraint(vs)
    # manchmal eine Ausnahme mitten in der Suche: freeze/2 kommt über
    # copy_term/3 in die Kinder; wirft, sobald zwei Variablen eine Summe
    # aus einer Menge haben
    fz = if chance(0.25), do: [thrower(vs)], else: []
    # manchmal ein Ausdruck, dessen Variable erst danach gebunden wird:
    # copy_term/3 nennt dann die Gleichung, neu gepostet propagiert sie
    # mitunter stärker (bis zum Scheitern im Arbeiter, part_empty/2)
    bd = if chance(0.2), do: ["_B #= #{lin(vs)}, _B = #{:rand.uniform(7) - 3}"], else: []
    {vs, Enum.join(ins ++ cs ++ bd ++ fz, ", ")}
  end

  defp thrower(vs) do
    [a, b | _] = Enum.shuffle(vs)
    ks = Enum.map_join(1..:rand.uniform(3), ", ", fn _ -> :rand.uniform(9) - 2 end)

    "freeze(#{a}, freeze(#{b}, ( S is #{a} + #{b}, memberchk(S, [#{ks}]) -> " <>
      "throw(boom(#{a}-#{b})) ; true )))"
  end

  defp lin(vs) do
    k = min(length(vs), pick([1, 2, 2, 3]))

    vs
    |> Enum.shuffle()
    |> Enum.take(k)
    |> Enum.map(fn v ->
      case pick([1, 1, 1, 2, -1, 3, -2]) do
        1 -> v
        c -> "#{c}*#{v}"
      end
    end)
    |> Enum.join(" + ")
  end

  defp rel, do: pick(~w(#= #\\= #< #=< #> #>=))

  defp constraint(vs) do
    [a, b | _] = Enum.shuffle(vs) ++ vs

    case :rand.uniform(9) do
      1 ->
        "#{lin(vs)} #{rel()} #{:rand.uniform(9) - 3}"

      2 ->
        "#{lin(vs)} #{rel()} #{lin(vs)}"

      3 ->
        "#{a} #\\= #{b}"

      4 ->
        "abs(#{a} - #{b}) #\\= #{:rand.uniform(3)}"

      5 ->
        "all_different([#{vs |> Enum.shuffle() |> Enum.take(min(3, length(vs))) |> Enum.join(", ")}])"

      6 ->
        "(#{lin(vs)} #{rel()} #{:rand.uniform(4)}) #==> (#{lin(vs)} #{rel()} #{:rand.uniform(4)})"

      7 ->
        "(#{a} #{rel()} #{b}) #\\/ (#{lin(vs)} #= #{:rand.uniform(5)})"

      8 ->
        "#{a} mod #{pick([2, 3])} #= #{:rand.uniform(2) - 1}"

      9 ->
        "#{a} * #{b} #{rel()} #{:rand.uniform(8)}"
    end
  end

  # Optionen von labeling/2; min/max über die Variablen
  defp lopts(vs) do
    sel = if chance(0.6), do: [pick(~w(leftmost ff ffc min max))], else: []
    ord = if chance(0.4), do: [pick(~w(up down))], else: []
    br = if chance(0.5), do: [pick(~w(step enum bisect))], else: []

    opt =
      cond do
        chance(0.6) -> []
        chance(0.75) -> ["#{pick(~w(min max))}(#{lin(vs)})"]
        true -> ["#{pick(~w(min max))}(#{lin(vs)})", "#{pick(~w(min max))}(#{lin(vs)})"]
      end

    Enum.shuffle(sel ++ ord ++ br) ++ opt
  end

  # Optionen des Aufteilens
  defp copts(kind) do
    serial = if chance(0.8), do: ["serial(#{pick(~w(0 0 0.0005 0.002))})"], else: []

    parts =
      cond do
        chance(0.3) -> []
        kind == :first -> ["parts(#{pick([1, 2, 2, 3, 4, 8])})"]
        true -> ["parts(#{pick([1, 2, 3, 5, 16])})"]
      end

    steal = if chance(0.5), do: ["steal(#{pick(~w(0 0 0.0005 0.002))})"], else: []
    Enum.shuffle(serial ++ parts ++ steal)
  end

  defp query(kind) do
    {vs, g} =
      case kind do
        :first -> model(3 + :rand.uniform(5), 60_000)
        :all -> model(3 + :rand.uniform(3), 6000)
      end

    o = lopts(vs)
    c = copts(kind)
    p = if kind == :first, do: "same1", else: "sameall"
    "#{p}((#{g}), [#{Enum.join(vs, ", ")}], [#{Enum.join(o, ", ")}], [#{Enum.join(c, ", ")}], R)"
  end

  # --- Läufe ----------------------------------------------------------------

  defp run(c, q) do
    Task.async(fn ->
      PrologEx.TestEnv.apply_jit()
      Reader.put_current(c.reader)
      Process.put(:prolog_ex_ops, c.ops)
      {_, ans} = TableCase.run(c.reader, c.db, q)
      {:messages, msgs} = Process.info(self(), :messages)
      {ans, msgs}
    end)
    |> Task.await(120_000)
  end

  defp seed, do: String.to_integer(System.get_env("CLPZ_RANDOM_SEED", "20261123"))
  defp scale, do: String.to_integer(System.get_env("CLPZ_RANDOM_N", "1"))

  # n Anfragen der Art kind; chaos: nil oder Optionen für Chaos.enable/1
  defp rounds(c, salt, kind, n, chaos) do
    :rand.seed(:exsss, {seed(), salt, 7})
    qs = for _ <- 1..(n * scale()), do: query(kind)
    if chaos, do: Chaos.enable([seed: salt] ++ chaos)

    try do
      for q <- qs do
        {ans, msgs} = run(c, q)

        if System.get_env("CLPZ_RANDOM_COLLECT") do
          if ans != {:answers, ["R = gleich"]},
            do:
              IO.puts(
                :stderr,
                "ABWEICHUNG #{q}\n  => #{inspect(ans, limit: 30, printable_limit: 400)}"
              )
        else
          assert ans == {:answers, ["R = gleich"]}, "#{q}\n=> #{inspect(ans, limit: :infinity)}"
        end

        assert msgs == [], q
      end
    after
      Chaos.disable()
    end

    length(qs)
  end

  test "eine Lösung: wie once(labeling/2)", c do
    rounds(c, 1, :first, 60, nil)
  end

  test "alle Lösungen: wie findall/3 über labeling/2", c do
    rounds(c, 2, :all, 30, nil)
  end

  test "mit Verzögerungen, auch flachen Abgaben", c do
    rounds(c, 3, :first, 25, p: 0.2, max_ms: 1)
    rounds(c, 4, :first, 25, p: 0.2, max_ms: 1, steal: :top)
    rounds(c, 5, :all, 15, p: 0.2, max_ms: 1)
  end

  @tag :slow
  @tag timeout: :infinity
  test "viele Modelle", c do
    rounds(c, 11, :first, 600, nil)
    rounds(c, 12, :all, 300, nil)
    rounds(c, 13, :first, 200, p: 0.3, max_ms: 2)
    rounds(c, 14, :first, 200, p: 0.3, max_ms: 1, steal: :top)
    rounds(c, 15, :all, 100, p: 0.3, max_ms: 2, steal: :top)
  end
end
