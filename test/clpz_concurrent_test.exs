defmodule PrologEx.ClpzConcurrentTest do
  # library(clpz_concurrent): concurrent_labelings/3 gibt genau, was
  # findall(Vs, labeling(Opts, Vs), L) gibt – auch die Reihenfolge –, für
  # alle Arten der Variablenwahl, Reihenfolge und Verzweigung; Fehler wie
  # labeling/2. concurrent_labeling/2 gibt eine der Lösungen.
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
  % zum Optimieren: viele gleich gute Lösungen (es zählt, welche zuerst)
  small([X, Y, Z]) :- [X, Y, Z] ins 0..9, X + Y #>= Z, X #\= Y, Z #\= 3.
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
  same_all(K, R) :- small(L), opt(K, L, O), findall(L, labeling(O, L), S1),
      small(L2), opt(K, L2, O2), concurrent_labelings(O2, L2, S2),
      ( S1 == S2 -> R = gleich ; R = verschieden ).
  % das Modell zweimal aufbauen: einmal labeling/2, einmal parallel
  same(Model, Opts, R) :- call(Model, L), findall(L, labeling(Opts, L), S1),
      call(Model, L2), concurrent_labelings(Opts, L2, S2),
      ( S1 == S2 -> R = gleich ; R = verschieden(S1, S2) ).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    # erst die Bibliotheken (ihre Operatoren), dann das Programm lesen
    db = PrologEx.TableCase.db(r, ~w(clpz clpz_concurrent lists))
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
      assert ask(c, "same(queens(6), #{unquote(o)}, R), R == gleich") != []
      assert ask(c, "same(mixed, #{unquote(o)}, R), R == gleich") != []
    end
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
      # nacheinander (Vorgabe: kleine Schritte), gleich parallel in 1, 3, 8 Teilen
      for copts <- [
            "[]",
            "[serial(0), parts(1)]",
            "[serial(0), parts(3)]",
            "[serial(0), parts(8)]"
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

  test "upto_in (noch) nicht; parts(N), serial(S) geprüft", c do
    assert err(c, "X in 1..3, concurrent_labelings([upto_in], [X], _)") |> hd() =~
             "domain_error(concurrent_labeling_option,upto_in)"

    assert err(c, "X in 1..3, concurrent_labelings([], [X], _, [parts(0)])") |> hd() =~
             "type_error(positive_integer,0)"

    assert err(c, "X in 1..3, concurrent_labeling([min(X)], [X], [serial(-1)])") |> hd() =~
             "domain_error(not_less_than_zero,-1)"

    assert err(c, "X in 1..3, concurrent_labeling([min(X)], [X], [serial(bald)])") |> hd() =~
             "type_error(number,bald)"
  end

  test "copy_term/3 mit mehr als 255 Restzielen (16 Damen; vorher max_arity)", c do
    assert ask(c, "queens(16, Qs), copy_term(Qs, Vs, Gs), Gs \\== true, length(Vs, 16)") != []
  end
end
