defmodule PrologEx.ClpzConcurrentTest do
  # library(clpz_concurrent): concurrent_labelings/3 gibt genau, was
  # findall(Vs, labeling(Opts, Vs), L) gibt – auch die Reihenfolge –, für
  # alle Arten der Variablenwahl, Reihenfolge und Verzweigung; Fehler wie
  # labeling/2. concurrent_labeling/2,3 gibt die Lösung von
  # once(labeling/2) (mit solution(any) eine der Lösungen).
  use ExUnit.Case, async: true
  alias PrologEx.Reader

  @prog """
  queens(N, Qs) :- length(Qs, N), Qs ins 1..N, safe(Qs).
  safe([]).
  safe([Q|Qs]) :- no_attack(Q, Qs, 1), safe(Qs).
  no_attack(_, [], _).
  no_attack(Q, [Q1|Qs], D) :- Q #\\= Q1, abs(Q - Q1) #\\= D, D1 is D + 1, no_attack(Q, Qs, D1).
  % gemischtes Modell: Summen, Reifikation, große Bereiche (enum in Abschnitten)
  mixed([X, Y, Z, B]) :- X in 0..200, Y in 0..9, Z in -5..5, B in 0..1,
      X mod 7 #= 3, X + Y #> 50, (Y #> Z) #<==> B, X #< 120 + Z.
  % ein Constraint ist nach dem Aufsetzen schon erfüllt (-X3 + 3*X5 #< 6):
  % sein toter Propagator hängt noch an X3 und X5, copy_term/3 nennt ihn
  % nicht mehr – ffc zählt ihn aber (aus dem Zufallstest)
  entailed([X1,X2,X3,X4,X5]) :- X1 in 0..4, X2 in 1..5, X3 in -2..0, X4 in 1..4, X5 in -2..1,
      X5 mod 2 #= 0, -1*X3 + 3*X5 #< 6, abs(X4 - X5) #\\= 3.
  % zum Optimieren mit ff, ffc, min, max: die Reihenfolge in einer Gruppe
  % hängt an dem, was labeling/2 postet (eine Variable je Ausdruck, E #\\=
  % die vorigen Werte, E #= Wert; aus dem Zufallstest)
  grp([X1,X2,X3,X4,X5], X2 + -2*X4 + 2*X1) :- X1 in 0..3, X2 in 0..3, X3 in -2..4, X4 in 1..3,
      X5 in 0..3, abs(X4 - X1) #\\= 2, (3*X4 + X3 #=< 4) #==> (-2*X4 #>= 4).
  grp_opts(O0, Dirs, E, O) :- maplist(dir_w(E), Dirs, Ws), append(O0, Ws, O).
  dir_w(E, D, W) :- W =.. [D, E].
  same_grp(O0, Dirs, COpts, R) :-
      grp(L, E), grp_opts(O0, Dirs, E, O), findall(L, labeling(O, L), S1),
      grp(L2, E2), grp_opts(O0, Dirs, E2, O2), concurrent_labelings(O2, L2, S2, COpts),
      grp(L3, E3), grp_opts(O0, Dirs, E3, O3), once(labeling(O3, L3)),
      grp(L4, E4), grp_opts(O0, Dirs, E4, O4), concurrent_labeling(O4, L4, COpts),
      ( S1 == S2, L3 == L4 -> R = gleich ; R = verschieden(L3, L4) ).
  % zum Optimieren: viele gleich gute Lösungen (es zählt, welche zuerst)
  small([X, Y, Z]) :- [X, Y, Z] ins 0..9, X + Y #>= Z, X #\\= Y, Z #\\= 3.
  opt(1, [X, _, _], [min(X)]).
  opt(2, [X, Y, _], [max(X + Y)]).
  opt(3, [X, _, Z], [min(Z), max(X)]).
  opt(4, [X, Y, Z], [ff, max(X * Y - Z)]).
  opt(5, [X, Y, _], [down, min(abs(X - Y))]).
  opt(6, [_, _, Z], [enum, min(Z)]).
  opt(7, [_, Y, _], [bisect, max(Y)]).
  opt(8, [X, Y, Z], [max(X), min(Y), max(Z)]).
  opt(9, [X, Y, Z], [ffc, down, min(X + Y + Z)]).
  % eine Lösung mit Optimierung: dieselbe wie once(labeling/2)
  same_first(K, COpts, R) :- small(L), opt(K, L, O), ( once(labeling(O, L)) -> F1 = L ; F1 = none ),
      small(L2), opt(K, L2, O2), ( concurrent_labeling(O2, L2, COpts) -> F2 = L2 ; F2 = none ),
      ( F1 == F2 -> R = gleich ; R = verschieden(F1, F2) ).
  same_all(K, R) :- same_all(K, [], R).
  same_all(K, COpts, R) :- small(L), opt(K, L, O), findall(L, labeling(O, L), S1),
      small(L2), opt(K, L2, O2), concurrent_labelings(O2, L2, S2, COpts),
      ( S1 == S2 -> R = gleich ; R = verschieden ).
  % ohne Lösung (die Propagation sieht es nicht); mit Lösungen weit rechts
  ph(N, Vs) :- N1 is N + 1, length(Vs, N1), Vs ins 1..N, all_different(Vs).
  qr(N, Qs) :- queens(N, Qs), Qs = [A, B|_], A #> N // 2, B #< 3.
  % eine Lösung: dieselbe wie once(labeling/2)
  first(Model, Opts, COpts, R) :- call(Model, L), ( once(labeling(Opts, L)) -> F1 = L ; F1 = none ),
      call(Model, L2), ( concurrent_labeling(Opts, L2, COpts) -> F2 = L2 ; F2 = none ),
      ( F1 == F2 -> R = gleich ; R = verschieden(F1, F2) ).
  % das Modell zweimal aufbauen: einmal labeling/2, einmal parallel
  same(Model, Opts, R) :- same(Model, Opts, [], R).
  same(Model, Opts, COpts, R) :- call(Model, L), findall(L, labeling(Opts, L), S1),
      call(Model, L2), concurrent_labelings(Opts, L2, S2, COpts),
      ( S1 == S2 -> R = gleich ; R = verschieden(S1, S2) ).
  % widersprüchlich, aber erst neu aufgesetzt sichtbar: copy_term/3 nennt
  % 2*X4 #= 2*X1 + X2, neu gepostet ist X2 gerade – mit X2 ungerade
  % scheitert schon das Aufsetzen im Arbeiter (im Aufrufer erst die Suche)
  % (Y vorn: der Aufrufer teilt nach Y auf, ohne den Widerspruch zu sehen –
  % die Teile gehen an Arbeiter, und dort scheitert das Aufsetzen)
  odd([Y, X1, X2, X4]) :- Y in 1..40, [X1, X2, X4] ins 0..3, S #= X2 + 2*X1 - 2*X4, S = 0,
      X2 mod 2 #= 1.
  % Ausnahmen mitten in der Suche: wirft boom(Q2-Q3), sobald Q2 + Q3 in S
  % liegt (freeze/2 kommt über copy_term/3 mit in die Kinder)
  bq(N, S, Qs) :- queens(N, Qs), Qs = [_, Q2, Q3|_],
      freeze(Q2, freeze(Q3, ( Q is Q2 + Q3, memberchk(Q, S) -> throw(boom(Q2-Q3)) ; true ))).
  outcome(G, R) :- catch(( call(G) -> R = ok ; R = fail ), E, R = ex(E)).
  % eine Lösung, alle, das Beste: dieselbe Lösung oder dieselbe Ausnahme
  same_ex(first, N, S, O, C, R) :-
      bq(N, S, A), outcome(once(labeling(O, A)), R0),
      bq(N, S, B), outcome(concurrent_labeling(O, B, C), R1),
      ( R0-A == R1-B -> R = gleich(R0) ; R0 \\== ok, R0 == R1 -> R = gleich(R0) ; R = verschieden(R0-A, R1-B) ).
  same_ex(all, N, S, O, C, R) :-
      bq(N, S, A), outcome(findall(A, labeling(O, A), L0), R0),
      bq(N, S, B), outcome(concurrent_labelings(O, B, L1, C), R1),
      ( R0 == R1, ( R0 \\== ok ; L0 == L1 ) -> R = gleich(R0) ; R = verschieden(R0, R1) ).
  % Branch and Bound: ob ein Knoten mit Ausnahme erreicht wird, hängt an der
  % Schranke, die dort gerade gilt – nacheinander jeder Schritt neu von
  % links, parallel schneiden auch Lösungen rechts davon ab (die gemeinsame
  % Schranke). Darum nur: haben beide eine Lösung, dieselbe
  same_ex(Dir, N, S, O, C, R) :-
      memberchk(Dir, [min, max]),
      bq(N, S, A), A = [Q1|_], W0 =.. [Dir, Q1], outcome(once(labeling([W0|O], A)), R0),
      bq(N, S, B), B = [P1|_], W1 =.. [Dir, P1], outcome(concurrent_labeling([W1|O], B, C), R1),
      (   R0-A == R1-B -> R = gleich(R0)
      ;   ( R0 = ex(_) ; R1 = ex(_) ) -> R = gleich(ex_bb)
      ;   R = verschieden(R0-A, R1-B)
      ).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    # erst die Bibliotheken (ihre Operatoren), dann das Programm lesen
    db = PrologEx.TableCase.db(r, ~w(clpz clpz_concurrent lists time))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @prog))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup c do
    Reader.put_current(c.reader)
    # die Operatoren von clpz (#=, in, ...) gelten je Prozess
    Process.put(:prolog_ex_ops, c.ops)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch((#{goal}), error(E, _), true)")

  @options [
    "[]",
    "[ff]",
    "[ffc]",
    "[min]",
    "[max]",
    "[down]",
    "[ff, down]",
    "[enum]",
    "[ff, enum, down]",
    "[bisect]",
    "[ffc, bisect, down]",
    "[max, enum]",
    "[min, step, down]"
  ]

  for o <- @options do
    test "concurrent_labelings #{o}: wie labeling/2, gleiche Reihenfolge", c do
      # mit den Vorgaben (kleine Aufgaben nacheinander) und gleich parallel,
      # jeder Knoten darf abgegeben werden (viele Teile)
      for copts <- ["[]", "[serial(0), steal(0)]", "[serial(0), steal(0), parts(3)]"],
          model <- ["queens(6)", "mixed", "qr(8)"] do
        assert ask(c, "same(#{model}, #{unquote(o)}, #{copts}, R), R == gleich") != [],
               "#{model} #{copts}"
      end
    end
  end

  for o <- @options do
    test "concurrent_labeling #{o}: dieselbe Lösung wie once(labeling/2)", c do
      # gleich parallel, jeder Knoten darf abgegeben werden (viele kleine
      # Teile); und mit den Vorgaben
      for copts <- ["[serial(0), steal(0), parts(3)]", "[]"],
          model <- ["queens(8)", "mixed", "qr(9)"] do
        assert ask(c, "first(#{model}, #{unquote(o)}, #{copts}, R), R == gleich") != [],
               "#{model} #{copts}"
      end
    end
  end

  test "concurrent_labeling: viele Teile, ohne Lösung, Zeitgrenze, solution(any)", c do
    for copts <- [
          "[serial(0), steal(0), parts(4)]",
          "[serial(0), steal(0.001), parts(2)]",
          "[serial(0), parts(1)]"
        ],
        model <- ["qr(11)", "ph(5)"],
        opts <- ["[]", "[ff, down]", "[enum]", "[bisect]"] do
      assert ask(c, "first(#{model}, #{opts}, #{copts}, R), R == gleich") != [],
             "#{model} #{opts} #{copts}"
    end

    # die Zeitgrenze des Aufrufers gilt (und beendet die Arbeiter)
    assert ask(
             c,
             "catch(call_with_time_limit(0.3, (queens(40, Qs), concurrent_labeling([], Qs, [serial(0)]))), E, true), E == time_limit_exceeded"
           ) != []

    assert ask(c, "queens(8, Qs), concurrent_labeling([], Qs, [solution(any)]), ground(Qs)") !=
             []
  end

  test "Lösungen zählen wie labeling: 7 Damen, alle Teile", c do
    assert ask(c, "queens(7, Qs), concurrent_labelings([ff], Qs, S), length(S, N), Qs = [_|_]")
           |> hd() =~ "N = 40"
  end

  test "Variablen schon gebunden, doppelt, ohne Lösung", c do
    assert ask(c, "X in 1..3, Y in 1..2, concurrent_labelings([], [X, 3, X, Y], S)") ==
             [
               "S = [[1,3,1,1],[1,3,1,2],[2,3,2,1],[2,3,2,2],[3,3,3,1],[3,3,3,2]], X in 1..3, Y in 1..2"
             ]

    assert ask(c, "concurrent_labelings([], [1, 2], S)") == ["S = [[1,2]]"]
    assert ask(c, "concurrent_labelings([], [], S)") == ["S = [[]]"]
    assert ask(c, "queens(3, Qs), concurrent_labelings([], Qs, S), S == []") != []
    assert ask(c, "queens(3, Qs), concurrent_labeling([], Qs)") == []
  end

  test "concurrent_labeling: eine Lösung, die Constraints des Aufrufers halten", c do
    assert ask(
             c,
             "queens(8, Qs), concurrent_labeling([ff], Qs), findall(Qs, labeling([], Qs), [_])"
           ) != []

    assert ask(c, "mixed(L), concurrent_labeling([], L), ground(L), \\+ \\+ labeling([], L)") !=
             []

    assert ask(c, "queens(10, Qs), concurrent_labeling([], Qs, [parts(1)]), ground(Qs)") != []
  end

  test "die Variablen des Aufrufers bleiben offen (concurrent_labelings)", c do
    assert ask(
             c,
             "queens(5, Qs), concurrent_labelings([], Qs, _), term_variables(Qs, Vs), length(Vs, 5)"
           ) !=
             []
  end

  test "Fehler wie labeling/2", c do
    for {goal, same_as} <- [
          {"concurrent_labelings(foo, [X], _)", "labeling(foo, [X])"},
          {"X in 1..2, concurrent_labelings([_], [X], _)", "X in 1..2, labeling([_], [X])"},
          {"X in 1..2, concurrent_labelings([nix], [X], _)", "X in 1..2, labeling([nix], [X])"},
          {"X in 1..2, concurrent_labelings([ff, ff], [X], _)",
           "X in 1..2, labeling([ff, ff], [X])"},
          {"X in 1..2, concurrent_labelings([ff, min], [X], _)",
           "X in 1..2, labeling([ff, min], [X])"},
          {"concurrent_labelings([], [X], _)", "labeling([], [X])"},
          {"concurrent_labelings([], foo, _)", "labeling([], foo)"},
          {"concurrent_labelings([], [a], _)", "labeling([], [a])"}
        ] do
      expect = err(c, same_as) |> Enum.map(&String.replace(&1, ~r/, X in .*$/, ""))
      got = err(c, goal) |> Enum.map(&String.replace(&1, ~r/, X in .*$/, ""))
      assert got == expect, "#{goal}: #{inspect(got)} statt #{inspect(expect)}"
    end
  end

  for k <- 1..9 do
    test "min/max #{k}: alle Lösungen wie labeling/2; eine wie once(labeling/2), auch gleich parallel",
         c do
      k = unquote(k)
      assert ask(c, "same_all(#{k}, R), R == gleich") != []
      assert ask(c, "same_all(#{k}, [serial(0), steal(0), parts(2)], R), R == gleich") != []
      # nacheinander (Vorgabe: kleine Schritte), gleich parallel in 1, 3, 8 Teilen
      for copts <- [
            "[]",
            "[serial(0), parts(1)]",
            "[serial(0), parts(3)]",
            "[serial(0), parts(8)]",
            "[serial(0), steal(0), parts(2)]",
            "[serial(0), steal(0), parts(4)]"
          ] do
        assert ask(c, "same_first(#{k}, #{copts}, R), R == gleich") != [], "#{k} #{copts}"
      end
    end
  end

  test "min/max ohne Lösung; Ausdruck mit fremder Variable wie labeling/2", c do
    # keine Lösung, die Propagation sieht es aber nicht (drei paarweise
    # verschiedene in 1..2)
    nosol = "Vs = [X, Y, Z], Vs ins 1..2, X #\\= Y, Y #\\= Z, X #\\= Z"
    assert ask(c, "#{nosol}, concurrent_labeling([min(X)], Vs)") == []
    assert ask(c, "#{nosol}, concurrent_labeling([min(X)], Vs, [serial(0)])") == []
    assert ask(c, "#{nosol}, concurrent_labelings([max(X + Y)], Vs, S), S == []") != []

    assert err(c, "X in 1..3, Y in 1..3, concurrent_labeling([min(X + Y)], [X], [serial(0)])") ==
             err(c, "X in 1..3, Y in 1..3, labeling([min(X + Y)], [X])")
  end

  test "upto_in (noch) nicht; parts(N), serial(S), solution(M), steal(S) geprüft", c do
    assert err(c, "X in 1..3, concurrent_labelings([upto_in], [X], _)") |> hd() =~
             "domain_error(concurrent_labeling_option,upto_in)"

    assert err(c, "X in 1..3, concurrent_labelings([], [X], _, [parts(0)])") |> hd() =~
             "type_error(positive_integer,0)"

    assert err(c, "X in 1..3, concurrent_labeling([min(X)], [X], [serial(-1)])") |> hd() =~
             "domain_error(not_less_than_zero,-1)"

    assert err(c, "X in 1..3, concurrent_labeling([min(X)], [X], [serial(bald)])") |> hd() =~
             "type_error(number,bald)"

    assert err(c, "X in 1..3, concurrent_labeling([], [X], [solution(eine)])") |> hd() =~
             "domain_error(solution,eine)"

    assert err(c, "X in 1..3, concurrent_labeling([], [X], [steal(-1)])") |> hd() =~
             "domain_error(not_less_than_zero,-1)"
  end

  defp stats(answer) do
    [_, list] = Regex.run(~r/\bS = \[([^\]]*)\]/, answer)

    for kv <- String.split(list, ","), into: %{} do
      [_, k, v] = Regex.run(~r/(\w+)\(([-\d.e]+)\)/, kv)
      {k, if(String.contains?(v, "."), do: String.to_float(v), else: String.to_integer(v))}
    end
  end

  test "stats(S): Teile, Work Stealing, Anfang nacheinander", c do
    # gleich parallel: ein Lauf mit Work Stealing, jeder Arbeiter baut das
    # Modell auf
    [a] = ask(c, "queens(12, Qs), concurrent_labeling([], Qs, [serial(0), stats(S)])")
    st = stats(a)
    assert %{"runs" => 1, "phases" => 0, "handovers" => 0} = st
    assert st["parts"] >= 1 and st["parts"] == st["packets"]
    assert st["steals"] + st["refused"] <= st["requests"]
    assert st["setup"] > 0 and st["setup"] <= st["busy"]
    assert a =~ "Qs = [1,3,5,8,10,12,6,11,2,7,9,4]"

    # klein: alles im Anfang nacheinander, kein paralleler Lauf
    [a] = ask(c, "queens(6, Qs), concurrent_labelings([], Qs, L, [stats(S)]), length(L, N)")
    assert %{"runs" => 0, "phases" => 1, "handovers" => 0} = stats(a)
    assert a =~ "N = 4"

    # alle Lösungen, feste Teile
    [a] =
      ask(
        c,
        "queens(7, Qs), concurrent_labelings([], Qs, L, [serial(0), parts(8), stats(S)]), " <>
          "length(L, N)"
      )

    st = stats(a)
    assert %{"runs" => 1, "phases" => 0} = st
    assert st["fixed"] >= 1 and st["parts"] >= st["fixed"]
    assert a =~ "N = 40"

    # Branch and Bound: neue Schranken
    [a] = ask(c, "small(L), opt(2, L, O), concurrent_labeling(O, L, [serial(0), stats(S)])")
    assert stats(a)["runs"] >= 1
    assert err(c, "concurrent_labeling([], [X], foo)") == ["E = type_error(list,foo)"]
  end

  # '$clpz_conc_step'/5 (Builtin) und conc_step_ref/5 (Prolog, der Weg für
  # alles, was das Builtin nicht selbst kann): derselbe Schritt
  test "Suchschritt: Builtin und Referenz in Prolog gleich", c do
    for model <- [
          "small(Vs)",
          "mixed(Vs)",
          "queens(6, Vs)",
          "Vs = [1, 2]",
          "small(Vs), Vs = [1|_]"
        ],
        sel <- ~w(leftmost ff ffc min max),
        ord <- ~w(up down) do
      q =
        "#{model}, clpz_concurrent:'$clpz_conc_step'(Vs, #{sel}, #{ord}, Vs, S1), " <>
          "clpz_concurrent:conc_step_ref(Vs, #{sel}, #{ord}, Vs, S2), " <>
          "( S1 == S2 -> R = gleich ; R = verschieden )"

      assert [a] = ask(c, q)
      assert a =~ "R = gleich", q <> "\n" <> a
    end
  end

  test "mehr Teile als Knoten; schon gebundene Variablen", c do
    assert ask(
             c,
             "X in 1..2, Y in 1..2, concurrent_labelings([], [X, Y], L, [serial(0), parts(16)])"
           ) == ["L = [[1,1],[1,2],[2,1],[2,2]], X in 1..2, Y in 1..2"]

    # alles schon gebunden
    assert ask(c, "concurrent_labelings([], [1, 2], L, [serial(0)])") == ["L = [[1,2]]"]
    assert ask(c, "concurrent_labeling([], [1, 2], [serial(0)])") == ["true"]
  end

  # ffc entscheidet Gleichstände nach der Zahl der Propagatoren, auch
  # toter: die Kinder bekommen sie nachgebildet (pad_props/2), sonst wählten
  # sie andere Variablen – andere Reihenfolge, andere erste Lösung
  test "ffc: tote Propagatoren zählen auch in den Kindern", c do
    for o <- ["[ffc]", "[enum, ffc]", "[ffc, down]", "[bisect, ffc]"],
        co <- ["[serial(0), parts(1)]", "[serial(0.0005)]", "[serial(0), parts(3)]"] do
      assert ask(c, "same(entailed, #{o}, #{co}, R)") == ["R = gleich"], "#{o} #{co}"
      assert ask(c, "first(entailed, #{o}, #{co}, R)") == ["R = gleich"], "#{o} #{co}"
    end
  end

  # labeling/2 mit min/max: je Ausdruck eine Variable (S #= Ausdruck), die
  # Gruppe des k-ten Werts unter S #\\= V1..Vk-1, S #= Vk, die übrigen
  # Kriterien mit neuen Variablen; ff, ffc, min, max wählen nach Domänen –
  # nur im selben Zustand dieselbe Reihenfolge, dieselbe erste Lösung
  test "min/max mit ff, ffc, min, max: Zustand wie labeling/2", c do
    # (nicht [max, bisect] mit parts(1): die Kinder setzen das Modell aus
    # copy_term/3 neu auf und propagieren hier stärker als das Original –
    # eine Grenze des Verfahrens, siehe README)
    for o <- ["[ff]", "[ff, down]", "[ffc]", "[min]", "[max, down]"],
        d <- ["[max]", "[min]", "[max, min]"],
        co <- ["[serial(0)]", "[serial(10)]", "[serial(0), parts(1)]"] do
      assert ask(c, "same_grp(#{o}, #{d}, #{co}, R)") == ["R = gleich"], "#{o} #{d} #{co}"
    end
  end

  # eine Ausnahme in einem Teil (auch einem abgegebenen): concurrent_labeling
  # wirft dieselbe wie once(labeling/2) – die erste in der Reihenfolge der
  # Suche –, liegt sie rechts der Lösung, gilt die Lösung; ebenso alle
  # Lösungen (vorher kam bei Work Stealing mitunter eine spätere an, je nach
  # Zeit). min/max: nur die Lösung, wenn beide eine haben (siehe same_ex/6)
  test "Ausnahmen in den Teilen wie labeling/2", c do
    seen =
      for {mode, n} <- [{"first", 8}, {"all", 7}, {"min", 8}, {"max", 7}],
          s <- ["[5]", "[7, 9]", "[6, 10, 13]", "[15]"],
          o <- ["[]", "[ff]", "[down]"],
          co <- [
            "[serial(0)]",
            "[serial(0), parts(1)]",
            "[serial(0), parts(4)]",
            "[serial(0.001)]"
          ] do
        q = "same_ex(#{mode}, #{n}, #{s}, #{o}, #{co}, R)"
        assert [a] = ask(c, q), q
        assert a =~ "R = gleich(", "#{q}: #{a}"
        if a =~ "ex(", do: :ex, else: :ok
      end

    # beides kommt vor: Ausnahmen links der Lösung und rechts davon
    assert :ex in seen and :ok in seen
  end

  # das Modell scheitert erst im Arbeiter (part_empty/2): wie labeling/2
  # keine Lösung – eine, alle (Work Stealing, feste Teile), das Beste
  test "Modell erst im Arbeiter widersprüchlich: keine Lösung", c do
    for co <- ["[serial(0)]", "[serial(0), parts(1)]", "[serial(0), parts(16)]"] do
      assert [_] = ask(c, "odd(L), \\+ concurrent_labeling([], L, #{co})"), co
      assert ask(c, "odd(L), concurrent_labelings([], L, S, #{co})") |> hd() =~ "S = []", co

      assert [_] = ask(c, "odd(L), L = [_, X|_], \\+ concurrent_labeling([min(X)], L, #{co})"), co

      assert ask(c, "odd(L), L = [_, X|_], concurrent_labelings([max(X)], L, S, #{co})")
             |> hd() =~ "S = []",
             co
    end
  end

  test "copy_term/3 mit mehr als 255 Restzielen (16 Damen; vorher max_arity)", c do
    assert ask(c, "queens(16, Qs), copy_term(Qs, Vs, Gs), Gs \\== true, length(Vs, 16)") != []
  end
end
