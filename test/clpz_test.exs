defmodule PrologEx.ClpzTest do
  # library(clpz) (Markus Triska, aus Scryer Prolog): Beispiele aus der
  # Dokumentation und die Beispielprogramme aus github.com/triska/clpz
  # (Public Domain, test/fixtures/clpz) mit den Ausgaben von Scryer
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ["clpz"])
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.put(:prolog_ex_ops, c.ops)
    PrologEx.put_db(c.db)
    :ok
  end

  defp answers(c, q) do
    {_out, r} = TableCase.run(c.reader, c.db, q)
    r
  end

  test "Beispiele der Dokumentation", c do
    for {q, expect} <- [
          {"X #= 1+2", ["X = 3"]},
          {"3 #= Y+2", ["Y = 1"]},
          {"X in 1..10, X #> 7", ["X in 8..10"]},
          {"X #> 3, X #< 6", ["X in 4..5"]},
          {"X #= Y*Y, Y in -2..2", ["X in 0..4, Y^2#=X, Y in -2..2"]},
          {"length(Q, 3), Q ins 1..3, all_different(Q), label(Q)",
           ["Q = [1,2,3]", "Q = [1,3,2]", "Q = [2,1,3]", "Q = [2,3,1]", "Q = [3,1,2]"]},
          {"X #= 1/0", []},
          {"X in 0..5, X #\\= 3, fd_dom(X, D)", ["D = 0..2\\/4..5, X in 0..2\\/4..5"]},
          {"X #> 3 #<==> B, X in 0..9, B = 1, fd_dom(X, D)", ["B = 1, D = 4..9, X in 4..9"]},
          {"zcompare(O, 3, 5)", ["O = (<)"]},
          {"X in 1..3, labeling([max(X)], [X])", ["X = 3", "X = 2", "X = 1"]},
          {"tuples_in([[X,Y]], [[1,2],[2,3]]), X = 2", ["X = 2, Y = 3"]},
          {"sum([X,Y,Z], #=, 10), [X,Y,Z] ins 0..3", []},
          {"X #= 2^100", ["X = 1267650600228229401496703205376"]}
        ] do
      assert answers(c, q) == {:answers, expect}, q
    end
  end

  test "Schranken ohne n/1: kein n(_) in den Attributen nach vielen Constraints", c do
    # Schranken sind ganze Zahlen, inf oder sup (das Original hüllt sie in
    # n/1); hier alle Arten von Constraints, danach alle Attribute absuchen
    prog = """
    :- use_module(library(swi), [term_attvars/2]).
    :- use_module(library(lists)).
    no_n(T) :- ( var(T) -> true ; T = n(_) -> throw(n_gefunden(T)) ; T =.. [_|As], maplist(no_n, As) ).
    attrs_ok(Vs) :- term_attvars(Vs, AVs), maplist(attr_ok, AVs).
    attr_ok(V) :- clpz:get_atts(V, As), no_n(As).
    """

    goals = [
      "X in 0..9, Y in inf..5, Z in 3..sup, X #= Y + Z, X #\\= 4, abs(X-Y) #\\= 1",
      "[X,Y,Z] ins -5..5, X #= Y * Z, Z #= X // Y, W #= X mod 2, V #= Y rem 3, U #= X ^ 2",
      "[X,Y,Z] ins -5..5, X #= max(Y,Z), W #= min(X,Y), V #= abs(Z), U #= -X",
      "[X,Y,Z] ins 0..3, all_different([X,Y,Z]), all_distinct([X,Y]), sum([X,Y,Z], #=<, 5)",
      "[X,Y] ins 0..3, (X #> Y) #<==> B, (X #= 1 #\\/ Y #= 2) #==> C, #\\ (X #< Y) #<==> D",
      "[X,Y,Z] ins 1..3, global_cardinality([X,Y,Z], [1-A,2-B,3-C]), tuples_in([[X,Y]], [[1,2],[2,3]])",
      "[X,Y,Z] ins 1..3, circuit([X,Y,Z]), element(X, [Y,Z,2], W), zcompare(O, X, Y)",
      "[S1,S2] ins 0..10, cumulative([task(S1,2,_,1,a), task(S2,3,_,1,b)], [limit(1)])",
      "X in 0..100, X #= 2^Y, Y in 0..6, lex_chain([[Y],[X]]), X #=< Y + 50",
      "length(L, 3), L ins 0..2, label(L), X in 0..3, labeling([max(X)], [X])"
    ]

    {db, _} = PrologEx.Consult.load(c.db, Reader.read_terms(c.reader, prog))

    for g <- goals do
      q = "#{g}, term_variables((#{g}), Vs), attrs_ok(Vs)"
      r = TableCase.run(c.reader, db, "catch((#{q}, true), E, (write(E), fail))")
      assert match?({_, {:answers, [_ | _]}}, r), inspect({g, r})
    end
  end

  test "freeze und dif an einer Variablen, die ein Propagator bindet", c do
    # die Bindung im Propagator weckt auch die Suspensionen (das Wecken
    # bleibt dann bei der Maschine, nicht in der Schleife der Queue)
    assert {:answers, [a]} = answers(c, "freeze(X, W = 1), X in 0..9, X #= Y + Z, Y = 2, Z = 3")
    assert a =~ "W = 1"
    assert answers(c, "dif(X, 5), X in 0..9, X #= Y + Z, Y = 2, Z = 3") == {:answers, []}

    assert {:answers, [b]} =
             answers(c, "freeze(X, W = 1), X in 0..9, Y in 0..9, X #= Y + 1, Y #> 7")

    assert b =~ "W = 1"
  end

  test "zusammengelegte Warteschlangen behalten ihre Einträge (wie Scryer)", c do
    # T #= Y*Y verwandelt sich in pexp, der eingereiht wird; das Aufstellen
    # von Y + Z #\= 4*Z legt die Warteschlangen zusammen
    # (variables_same_queue/1). Ging die bleibende Queue dabei verloren,
    # lief pexp nach Y = 2 nie, und T blieb offen.
    assert {:answers, ["T = 4, Y = 2, " <> _]} = answers(c, "T #= Y*Y, Y + Z #\\= 4*Z, Y = 2")

    # Lösungszahlen wie in Scryer (vorher 1380 und 1012)
    assert {:answers, ["N = 390"]} =
             answers(
               c,
               "findall(t, (all_distinct([X,Y,W]), Y #= ((Y ^ 2) // min(-1, Z)), " <>
                 "(Y + Z) #\\= (4 * Z), [X,Y,Z,W] ins -3..3, labeling([ff], [X,Y,Z,W])), _L), " <>
                 "length(_L, N)"
             )

    assert {:answers, ["N = 506"]} =
             answers(
               c,
               "findall(t, ((W #> (- (Z ^ 3)) #<==> (Z #> X #/\\ min((Y div X), (W * 5)) #< " <>
                 "((1 + 0) * -3))), zcompare(O, W, X), W in 0..sup, (- X) #\\= (2 * Y), " <>
                 "[X,Y,Z,W] ins -3..3, label([X,Y,Z,W])), _L), length(_L, N)"
             )
  end

  test "reifiziertes #>=: Grenzfälle der Schranken wie in Scryer", c do
    # Restziele in Scryers Form (Flag-Werte gelten je Prozess)
    PrologEx.Flags.set("clpz_residuals", PrologEx.a("scryer"))
    on_exit(fn -> PrologEx.Flags.reset() end)

    for {q, expect} <- [
          {"X in 0..3, B #<==> (3 #>= X)", "B = 1, X in 0..3"},
          {"X in 0..3, B #<==> (0 #>= X)", "B in 0..1, 0#>=X#<==>B, X in 0..3"},
          {"X in 0..3, B #<==> (-1 #>= X)", "B = 0, X in 0..3"},
          {"X in 0..3, B #<==> (X #>= 3)", "B in 0..1, X#>=3#<==>B, X in 0..3"},
          {"X in 0..3, B #<==> (X #>= 4)", "B = 0, X in 0..3"},
          {"X in 0..3, Y in 3..5, B #<==> (X #>= Y)",
           "B in 0..1, X#>=Y#<==>B, X in 0..3, Y in 3..5"},
          {"X in 3..5, Y in 0..3, B #<==> (X #>= Y)", "B = 1, X in 3..5, Y in 0..3"},
          {"X in 0..2, Y in 3..5, B #<==> (X #>= Y)", "B = 0, X in 0..2, Y in 3..5"},
          {"X in 0..3, B #<==> (X #>= Y), Y in 3..5, X = 3",
           "X = 3, B in 0..1, 3#>=Y#<==>B, Y in 3..5"},
          # entschieden: die Hilfspropagatoren der Teilausdrücke sterben mit
          {"X in 5..9, Y in 0..2, Z in 0..2, B #<==> (X #>= Y+Z)",
           "B = 1, X in 5..9, Y in 0..2, Z in 0..2"},
          {"B #<==> (X #>= Y*Z), X in 5..9, Y in 0..2, Z in 0..2",
           "B = 1, X in 5..9, Y in 0..2, Z in 0..2"},
          {"B #<==> (X #>= abs(Y)), Y in -2..2, X = 4", "B = 1, X = 4, Y in -2..2"}
        ] do
      assert answers(c, q) == {:answers, [expect]}, q
    end
  end

  test "Fehler wie in Scryer", c do
    assert {:error, "domain_error(clpz_domain,a..b)"} = answers(c, "X in a..b")
    assert {:error, "domain_error(clpz_expression,a)"} = answers(c, "X #= a")
    assert {:error, "type_error(integer,a)"} = answers(c, "label([a])")
  end

  # Beispielprogramme: Ausgaben wie in Scryer
  @examples [
    {"n_queens.pl", "n_queens(8, Qs), labeling([ff], Qs), write(Qs)", "[1,5,8,6,3,7,2,4]"},
    {"n_queens.pl", "findall(Qs, (n_queens(6, Qs), label(Qs)), L), length(L, N), write(N)", "4"},
    {"n_queens.pl", "n_queens(30, Qs), labeling([ff], Qs), write(Qs)",
     "[1,3,5,24,26,4,23,7,28,16,18,15,6,22,20,27,8,30,2,29,25,12,9,21,19,14,11,13,10,17]"},
    {"sendmory.pl", "puzzle(As+Bs=Cs), label(As), write(As+Bs=Cs)",
     "[9,5,6,7]+[1,0,8,5]=[1,0,6,5,2]"},
    {"sudoku.pl", "problem(1, Rows), sudoku(Rows), maplist(labeling([ff]), Rows), write(Rows)",
     "[[1,5,6,8,9,4,3,2,7],[9,2,8,7,3,1,4,5,6],[4,7,3,2,6,5,9,1,8],[3,6,2,4,1,7,8,9,5]," <>
       "[7,8,9,3,5,2,6,4,1],[5,1,4,9,8,6,2,7,3],[8,3,1,5,4,9,7,6,2],[6,9,7,1,2,3,5,8,4]," <>
       "[2,4,5,6,7,8,1,3,9]]"},
    {"magic_square.pl",
     "findall(S, (magic_square(3, S), append(S, Vs), label(Vs)), L), length(L, N), write(N)",
     "8"},
    {"magic_square.pl", "magic_square(4, S), append(S, Vs), label(Vs), write(S)",
     "[[1,2,15,16],[12,14,3,5],[13,7,10,4],[8,11,6,9]]"},
    {"knight_tour.pl", "n_tour(6, Ts), maplist(label, Ts), write(Ts)",
     "[[9,10,7,8,16,17],[15,19,5,6,3,4],[2,1,26,12,21,29],[32,31,25,18,34,11]," <>
       "[14,13,35,36,33,22],[27,28,20,30,24,23]]"},
    {"tasks.pl", "tasks(Tasks, Starts, End), labeling([min(End)], Starts), write(Starts-End)",
     "[0,0,4,3]-6"},
    {"n_factorial.pl", "n_factorial(47, F), write(F)",
     "258623241511168180642964355153611979969197632389120000000000"},
    {"n_factorial.pl", "n_factorial(N, 3628800), write(N)", "10"},
    {"magic_hexagon.pl", "magic_hexagon(Vs), labeling([ff], Vs), write(Vs)",
     "[3,17,18,19,7,1,11,16,2,5,6,9,12,4,8,14,10,13,15]"}
  ]

  for {file, goal, out} <- @examples do
    @file_name file
    @goal goal
    @out out
    test "#{file}: #{goal}", c do
      db = fixture(c, @file_name)
      assert output(c, db, @goal) == @out
    end
  end

  defp fixture(_c, name) do
    PrologEx.put_db(%{})
    capture_io(fn -> PrologEx.Consult.load_file("test/fixtures/clpz/#{name}") end)

    PrologEx.current_db()
  end

  defp output(c, db, goal) do
    [{:term, g, _}] = Reader.read_terms(c.reader, "once((#{goal})).")

    capture_io(fn ->
      assert [_] = db |> PrologEx.query(g) |> Enum.take(1)
    end)
  end

  test "goal_expansion beim Laden: Ziele in Klauseln vorübersetzt, Ergebnis gleich", c do
    # n_factorial/2 enthält #= im Rumpf: die Klauseln laufen über
    # user:goal_expansion/2 von clpz
    db = fixture(c, "n_factorial.pl")

    assert {:answers, ["F = 120"]} = TableCase.run(c.reader, db, "n_factorial(5, F)") |> elem(1)

    assert {:answers, ["N = 5"]} =
             TableCase.run(c.reader, db, "once(n_factorial(N, 120))") |> elem(1)
  end

  test "Laden: Hilfsprädikate stehen der goal_expansion schon zur Verfügung", c do
    # wie clpz: goal_expansion/2 ruft ein weiter oben definiertes Prädikat
    text = """
    goal_expansion(twice(X), (X, X)) :- helper.
    helper.
    p :- twice(write(a)).
    """

    PrologEx.put_db(%{})
    {db, msgs} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, text))
    assert msgs == []
    assert TableCase.run(c.reader, db, "p") == {"aa", {:answers, ["true"]}}
  end

  test "Operatoren von library(debug): nicht in user, wenn nur clpz sie lädt", c do
    # in Scryer ist * nach use_module(library(clpz)) kein Präfixoperator
    assert {_, {:answers, ["L = []"]}} =
             TableCase.run(c.reader, c.db, "findall(P-T, current_op(P, T, $), L)")

    assert {_, {:answers, ["L = [400-yfx]"]}} =
             TableCase.run(c.reader, c.db, "findall(P-T, current_op(P, T, *), L)")
  end

  test "Operatoren von library(debug): mit eigenem use_module in user", c do
    Process.delete(:prolog_ex_ops)
    db = TableCase.db(c.reader, ["clpz", "debug"])

    assert {_, {:answers, ["L = [900-fx]"]}} =
             TableCase.run(c.reader, db, "findall(P-T, current_op(P, T, $), L)")

    Process.delete(:prolog_ex_ops)
    db = TableCase.db(c.reader, ["debug"])

    assert {_, {:answers, ["L = [950-fy,400-yfx]"]}} =
             TableCase.run(c.reader, db, "findall(P-T, current_op(P, T, *), L)")
  end

  test "Operatoren von library(debug): vorherige Definitionen bleiben", c do
    Process.delete(:prolog_ex_ops)
    text = ":- op(200, fy, *).\n:- use_module(library(clpz)).\n"
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, text))

    assert {_, {:answers, ["L = [200-fy,400-yfx]"]}} =
             TableCase.run(c.reader, db, "findall(P-T, current_op(P, T, *), L)")
  end

  test "library(arithmetic): wie Scryer", c do
    db = TableCase.db(c.reader, ["arithmetic"])

    assert {_, {:answers, ["L = [9,3,6,12,2]"]}} =
             TableCase.run(
               c.reader,
               db,
               "msb(1000, M), lsb(1000, L0), popcount(1000, P), lcm(4, 6, C), expmod(3, 200, 7, E), L = [M,L0,P,C,E]"
             )
             |> then(fn {o, {:answers, [a]}} ->
               {o, {:answers, [Regex.replace(~r/^.*(L = \[[^\]]*\]).*$/, a, "\\1")]}}
             end)

    assert {_, {:error, "domain_error(not_less_than_one,0)"}} =
             TableCase.run(c.reader, db, "msb(0, _)")

    assert {_, {:error, "type_error(integer,a)"}} = TableCase.run(c.reader, db, "popcount(a, _)")

    # Brüche: der einfachste im Intervall [Real - Eps, Real + Eps]
    for {q, a} <- [
          {"number_to_rational(0.1, F)", "F = 1r10"},
          {"number_to_rational(3.14159265, F)", "F = 355r113"},
          {"number_to_rational(-2.5, F)", "F = -5r2"},
          {"number_to_rational(7, F)", "F = 7"},
          {"number_to_rational(1.0e-6, -2.0, F)", "F = -2"},
          {"number_to_rational(1.0e-6, 2.0000001, F)", "F = 2"},
          {"number_to_rational(0.01, 0.3, F)", "F = 3r10"},
          {"number_to_rational(1r100, 1r3, F)", "F = 1r3"},
          {"number_to_rational(1, 0.5, F)", "F = 0"},
          {"number_to_rational(0, 0.1, F)", "F = 3602879701896397r36028797018963968"},
          {"number_to_rational(1.0e-9, 2.718281828, F)", "F = 49171r18089"},
          {"number_to_rational(0, 1.0e-300, F), F > 0",
           "F = 6032057205060441r" <>
             "6032057205060440848842124543157735677050252251748505781796615064961622344493727293370973578138265743708225425014400837164813540499979063179105919597766951022193355091707896034850684039059079180396788349106095584290087446076413771468940477241550670753145517602931224392424029547429993824129889235158145614364972941312"},
          {"rational_numerator_denominator(3r4, N, D)", "D = 4, N = 3"},
          {"rational_numerator_denominator(5, N, D)", "D = 1, N = 5"}
        ] do
      assert {_, {:answers, [^a]}} = TableCase.run(c.reader, db, q), q
    end

    assert {_, {:answers, []}} =
             TableCase.run(c.reader, db, "rational_numerator_denominator(0.5, _, _)")

    for {q, e} <- [
          {"number_to_rational(x, _)", "type_error(number,x)"},
          {"number_to_rational(_, _)", "instantiation_error"},
          {"number_to_rational(-1, 0.5, _)", "domain_error(not_less_than_zero,-1)"},
          {"number_to_rational(0.1, x, _)", "type_error(number,x)"},
          {"number_to_rational(_, 1.0, _)", "instantiation_error"}
        ] do
      assert {_, {:error, ^e}} = TableCase.run(c.reader, db, q), q
    end
  end

  test "library(terms) und library(freeze) wie Scryer (eingebaut)", c do
    text =
      ":- use_module(library(terms), [numbervars/3]).\n" <>
        ":- use_module(library(freeze), [freeze/2]).\n"

    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, text))

    assert {_, {:answers, ["B = B, E = 2, N = 1"]}} =
             TableCase.run(c.reader, db, "numbervars(f(_, B), 0, E), B = '$VAR'(N)")

    assert {_, {:answers, ["X = 1"]}} = TableCase.run(c.reader, db, "freeze(X, true), X = 1")
  end
end
