defmodule PrologEx.DatabaseTest do
  # assert/retract, dynamic, acyclic_term/1, call/N – über den gprolog-Reader
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.{Consult, Reader}

  @moduletag :gprolog

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  @prog """
  :- use_module(library(lists)).
  :- use_module(library(apply)).
  :- dynamic counter/1, leer/0.
  counter(0).
  inc :- retract(counter(N)), N1 is N + 1, assertz(counter(N1)).
  statisch(a).
  plus3(A, B, C, R) :- R is A + B + C.
  """

  defp load(r, text \\ @prog) do
    {db, []} = Consult.load(%{}, Reader.read_terms(r, text))
    db
  end

  defp goal(r, text) do
    [{:term, g, _}] = Reader.read_terms(r, text)
    g
  end

  defp ask(r, db, text),
    do: db |> PrologEx.query(goal(r, text)) |> Enum.map(&PrologEx.format_answer/1)

  # Antworten mit "noch Choice Points?" (wie im Toplevel)
  defp sols(r, db, text), do: db |> PrologEx.solutions(goal(r, text)) |> Enum.to_list()

  defp err(r, db, text) do
    e = assert_raise(PrologEx.Error, fn -> ask(r, db, text) end)
    Exception.message(e)
  end

  describe "assert" do
    test "assertz hängt an, asserta stellt voran, assert = assertz", %{reader: r} do
      db = load(r)

      assert ask(r, db, "assertz(p(1)), assert(p(2)), asserta(p(0)), findall(X, p(X), L).") ==
               ["L = [0, 1, 2]"]
    end

    test "Regeln, Variablen werden kopiert", %{reader: r} do
      db = load(r)

      assert ask(r, db, "assertz((q(X, Y) :- Y is X * 2)), X = 7, q(3, Z).") == ["X = 7, Z = 6"]
      # spätere Bindung von X ändert die gespeicherte Klausel nicht
      assert ask(r, db, "assertz(k(X)), X = 1, k(2).") == ["X = 1"]
    end

    test "Zähler mit retract/assertz", %{reader: r} do
      db = load(r)
      assert ask(r, db, "inc, inc, inc, counter(X).") == ["X = 3"]
    end

    test "Fehler", %{reader: r} do
      db = load(r)
      assert err(r, db, "assertz(_).") =~ "instantiation_error"
      assert err(r, db, "assertz(3).") =~ "type_error(callable"
      assert err(r, db, "assertz((foo :- 3)).") =~ "type_error(callable"

      assert err(r, db, "assertz(statisch(b)).") =~
               "permission_error(modify, static_procedure, statisch/1)"

      assert err(r, db, "assertz(call(x)).") =~ "permission_error"
      assert err(r, db, "assertz((a, b)).") =~ "permission_error"
    end

    test "assert in findall und in Direktiven bleibt erhalten", %{reader: r} do
      db = load(r)
      assert ask(r, db, "findall(x, assertz(f(1)), _), f(X).") == ["X = 1"]

      db = load(r, ":- assertz(g(7)).\n:- assertz(g(8)).\n")
      assert ask(r, db, "findall(X, g(X), L).") == ["L = [7, 8]"]
    end

    test "listing zeigt dynamische Prädikate mit lesbaren Variablen", %{reader: r} do
      db = load(r)

      out =
        capture_io(fn -> ask(r, db, "assertz((w(Foo, Bar) :- Bar is Foo)), listing(w/2).") end)

      assert out =~ ":- dynamic w/2."
      assert out =~ "w(A, B) :-"
    end
  end

  describe "retract" do
    test "entfernt beim Backtracking alle passenden, der letzte ist deterministisch", %{reader: r} do
      db = load(r)
      q = "assertz(p(1)), assertz(p(2)), assertz(p(3)), retract(p(X))."
      assert [{_, true}, {_, true}, {ans, false}] = sols(r, db, q)
      assert PrologEx.format_answer(ans) == "X = 3"

      assert ask(
               r,
               db,
               "assertz(p(1)), assertz(p(2)), (retract(p(_)), fail ; true), findall(X, p(X), L)."
             ) ==
               ["L = []"]
    end

    test "einzige passende Klausel: kein Choice Point", %{reader: r} do
      db = load(r)
      assert [{_, false}] = sols(r, db, "assertz(p(1)), assertz(p(2)), retract(p(1)).")
    end

    test "mit Rumpf, unifiziert", %{reader: r} do
      db = load(r)

      assert [ans] = ask(r, db, "assertz((h(X) :- X > 1, write(x))), retract((h(Y) :- B)).")
      assert ans == "B = (Y>1, write(x))"

      assert ask(
               r,
               db,
               "assertz((h(1) :- true)), assertz(h(2)), retract(h(2)), findall(X, h(X), L)."
             ) ==
               ["L = [1]"]
    end

    test "unbekannt scheitert, statisch ist Fehler", %{reader: r} do
      db = load(r)
      assert ask(r, db, "retract(gibtsnicht(_)).") == []
      assert err(r, db, "retract(statisch(a)).") =~ "permission_error"
      assert err(r, db, "retract(_).") =~ "instantiation_error"
    end

    test "logical update view: laufende Aufrufe sehen den alten Stand", %{reader: r} do
      db = load(r)

      # neue Klauseln während der Iteration werden nicht gesehen
      assert ask(r, db, "assertz(m(1)), assertz(m(2)), findall(X, (m(X), assertz(m(3))), L).") ==
               ["L = [1, 2]"]

      # zurückgezogene werden trotzdem noch geliefert
      assert ask(r, db, "assertz(m(1)), assertz(m(2)), findall(X, (m(X), retractall(m(_))), L).") ==
               ["L = [1, 2]"]

      # retract selbst arbeitet auf einem Schnappschuss
      assert ask(r, db, "assertz(m(1)), findall(X, (retract(m(X)), assertz(m(9))), L).") ==
               ["L = [1]"]
    end
  end

  describe "abolish/1" do
    test "entfernt ein dynamisches Prädikat ganz (anders als retractall)", %{reader: r} do
      db = load(r)

      # nach retractall: leer, aber noch dynamisch – nach abolish: unbekannt
      assert ask(
               r,
               db,
               "retractall(counter(_)), \\+ counter(_), predicate_property(counter(_), dynamic)."
             ) ==
               ["true"]

      assert err(r, db, "abolish(counter/1), counter(_).") =~
               "existence_error(procedure, counter/1)"

      assert ask(r, db, "assertz(z(1)), abolish(z/1), \\+ predicate_property(z(_), _).") ==
               ["true"]

      # neu angelegt ist es wieder dynamisch
      assert ask(r, db, "assertz(z(1)), abolish(z/1), assertz(z(2)), findall(X, z(X), L).") ==
               ["L = [2]"]

      # mit Modul
      assert err(r, db, "assertz(m:q(1)), abolish(m:q/1), m:q(_).") =~
               "existence_error(procedure, m:q/1)"

      assert ask(r, db, "assertz(m:q(1)), m:abolish(q/1), \\+ predicate_property(m:q(_), _).") ==
               ["true"]
    end

    test "auch die dynamic-Eigenschaft ist weg: neu geladen ist es statisch", %{reader: r} do
      db = load(r)
      assert ask(r, db, "abolish(counter/1).") == ["true"]
      {db, []} = Consult.load(PrologEx.current_db(), Reader.read_terms(r, "counter(7).\n"))
      assert ask(r, db, "counter(X).") == ["X = 7"]

      assert err(r, db, "assertz(counter(8)).") =~
               "permission_error(modify, static_procedure, counter/1)"
    end

    test "unbekannt: kein Fehler", %{reader: r} do
      db = load(r)
      assert ask(r, db, "abolish(gibtsnicht/3).") == ["true"]
      assert ask(r, db, "abolish(leer/0), abolish(leer/0).") == ["true"]
    end

    test "logical update view: ein laufender Aufruf behält seine Klauseln", %{reader: r} do
      db = load(r)

      assert ask(r, db, "assertz(w(1)), assertz(w(2)), findall(X, (w(X), abolish(w/1)), L).") ==
               ["L = [1, 2]"]
    end

    test "Fehler wie ISO", %{reader: r} do
      db = load(r)

      for {goal, e} <- [
            {"abolish(_)", "instantiation_error"},
            {"abolish(foo/_)", "instantiation_error"},
            {"abolish(_/1)", "instantiation_error"},
            {"abolish(foo)", "type_error(predicate_indicator, foo)"},
            {"abolish(foo(1))", "type_error(predicate_indicator, foo(1))"},
            {"abolish(1/1)", "type_error(atom, 1)"},
            {"abolish(foo/a)", "type_error(integer, a)"},
            {"abolish(foo/(-1))", "domain_error(not_less_than_zero, -1)"},
            # geladen, also statisch
            {"abolish(statisch/1)", "permission_error(modify, static_procedure, statisch/1)"},
            # eingebaut und aus einer Bibliothek importiert
            {"abolish(abolish/1)", "permission_error(modify, static_procedure, abolish/1)"},
            {"abolish(atom_length/2)",
             "permission_error(modify, static_procedure, atom_length/2)"},
            {"abolish(append/3)", "permission_error(modify, static_procedure, append/3)"},
            {"abolish(m:foo/_)", "instantiation_error"}
          ] do
        assert err(r, db, goal <> ".") =~ e, goal
      end

      # statisch bleibt unverändert
      assert ask(r, db, "statisch(X).") == ["X = a"]
    end
  end

  describe "retractall und dynamic" do
    test "retractall entfernt passende Köpfe", %{reader: r} do
      db = load(r)

      assert ask(
               r,
               db,
               "assertz(p(1, a)), assertz(p(2, b)), assertz(p(3, a)), retractall(p(_, a)), findall(X, p(X, _), L)."
             ) ==
               ["L = [2]"]
    end

    test "retractall legt unbekannte Prädikate dynamisch an", %{reader: r} do
      db = load(r)
      assert ask(r, db, "retractall(neu(_)), \\+ neu(_).") == ["true"]
      assert err(r, db, "retractall(statisch(_)).") =~ "permission_error"
    end

    test ":- dynamic und dynamic/1 als Ziel", %{reader: r} do
      db = load(r)
      assert ask(r, db, "leer.") == []
      assert ask(r, db, "dynamic((x/1, y/2)), \\+ x(_), \\+ y(_, _).") == ["true"]
      assert ask(r, db, "dynamic([z/0]), \\+ z.") == ["true"]
      assert err(r, db, "dynamic(statisch/1).") =~ "permission_error"
    end

    test "consult ersetzt dynamische Prädikate wie gehabt", %{reader: r} do
      db = load(r)
      {db2, []} = Consult.load(db, Reader.read_terms(r, "counter(10).\n"))
      assert ask(r, db2, "counter(X).") == ["X = 10"]
    end
  end

  test "Toplevel behält die Datenbank zwischen Anfragen" do
    out =
      capture_io([input: "assertz(t(1)).\nassertz(t(2)).\nfindall(X, t(X), L).\nhalt.\n"], fn ->
        catch_halt(fn -> PrologEx.Toplevel.main(["-q"]) end)
      end)

    assert out =~ "L = [1, 2]"
  end

  defp catch_halt(f) do
    f.()
  catch
    {:prolog_halt, _} -> :ok
  end

  describe "Leistung" do
    test "viele asserts, retracts und abwechselnde Aufrufe bleiben schnell", %{reader: r} do
      db =
        load(r, """
        :- dynamic f/1.
        fill(N) :- between(1, N, I), assertz(f(I)), fail.
        fill(_).
        drain :- retract(f(_)), !, drain.
        drain.
        mix(N) :- between(1, N, I), assertz(f(I)), f(I), fail.
        mix(_).
        """)

      {t, ["true"]} =
        :timer.tc(fn -> ask(r, db, "fill(50000), f(50000), drain, \\+ f(_), mix(2000).") end)

      # vor dem Umbau: drain allein quadratisch (40000 → 21 s)
      assert t < 5_000_000
    end
  end

  describe "acyclic_term/1" do
    test "endliche und zyklische Terme", %{reader: r} do
      db = load(r)
      assert ask(r, db, "acyclic_term(f(X, [1, 2|Y], g(X))).") == ["true"]
      assert ask(r, db, "X = f(Y), Y = g(a), acyclic_term(X).") != []
      assert ask(r, db, "acyclic_term(a).") == ["true"]
    end

    test "Zyklus über Listenrest und gemeinsam genutzte Teilterme", %{reader: r} do
      db = load(r)
      ok? = fn q -> PrologEx.first_with_stats(db, goal(r, q)) != false end
      assert ok?.("X = f(X), \\+ acyclic_term(X).")
      assert ok?.("X = [a, b|X], \\+ acyclic_term(g(X)).")
      assert ok?.("X = f(Y, Y), Y = g(Z, Z), Z = h, acyclic_term(X).")
      assert ok?.("X = f(Y), Y = g(X), \\+ acyclic_term(h(1, Y)).")
      refute ok?.("X = f(X), acyclic_term(X).")
    end
  end

  describe "countall/2" do
    test "zählt Lösungen", %{reader: r} do
      db = load(r)
      assert ask(r, db, "countall(member(_, [a, b, c]), N).") == ["N = 3"]
      assert ask(r, db, "countall(fail, N).") == ["N = 0"]
      assert ask(r, db, "countall(between(1, 5, _), 5).") == ["true"]
      assert ask(r, db, "countall(between(1, 5, _), 4).") == []
      # Cut ist lokal, Bindungen aus dem Ziel bleiben nicht
      assert ask(r, db, "countall((member(X, [1, 2, 3]), !), N).") == ["N = 1"]
      assert err(r, db, "countall(true, a).") =~ "type_error(integer, a)"
      assert err(r, db, "countall(_, N).") =~ "instantiation_error"
    end

    test "Seiteneffekte bleiben, Datenbank-Änderungen auch", %{reader: r} do
      db = load(r)
      assert ask(r, db, "countall(inc, N), counter(C).") == ["C = 1, N = 1"]
    end

    test "große Anzahlen ohne Sammeln, findnsols nicht mehr quadratisch", %{reader: r} do
      db = load(r)
      {t, ["N = 300000"]} = :timer.tc(fn -> ask(r, db, "countall(between(1, 300000, _), N).") end)
      assert t < 3_000_000

      # vorher: length/1 je Lösung im Sammler, 200000 → 34 s
      {t, ["true"]} =
        :timer.tc(fn ->
          ask(
            r,
            db,
            "\\+ \\+ (findnsols(100000, x, between(1, 100000, _), L), !, length(L, 100000))."
          )
        end)

      assert t < 3_000_000
    end
  end

  describe "call/2..8" do
    test "Argumente werden angehängt", %{reader: r} do
      db = load(r)
      assert ask(r, db, "call(plus3, 1, 2, 3, R).") == ["R = 6"]
      assert ask(r, db, "call(plus3(1), 2, 3, R).") == ["R = 6"]
      assert ask(r, db, "call(plus3(1, 2, 3), R).") == ["R = 6"]
      assert ask(r, db, "call(=, X, a).") == ["X = a"]
      assert ask(r, db, "call(append, X, Y, [1]).") == ["X = [], Y = [1]", "X = [1], Y = []"]
      assert [ans] = ask(r, db, "call(functor, T, f, 2).")
      assert ans =~ ~r/^T = f\(_\w+, _\w+\)$/
    end

    test "volle Stelligkeit bis call/8", %{reader: r} do
      db = load(r, "s7(A, B, C, D, E, F, G, S) :- S is A+B+C+D+E+F+G.\n")
      assert ask(r, db, "call(s7, 1, 2, 3, 4, 5, 6, 7, S).") == ["S = 28"]
      assert ask(r, db, "call(s7(1), 2, 3, 4, 5, 6, 7, S).") == ["S = 28"]
      assert ask(r, db, "call(s7(1, 2, 3, 4, 5, 6, 7), S).") == ["S = 28"]
    end

    test "Cut ist lokal, Fehler bei Nicht-Aufrufbarem", %{reader: r} do
      db = load(r)

      assert ask(r, db, "member(X, [1, 2]), call((Y = X, !)).") == [
               "X = 1, Y = 1",
               "X = 2, Y = 2"
             ]

      assert err(r, db, "call(_, a).") =~ "instantiation_error"
      assert err(r, db, "call(3, a).") =~ "type_error(callable"
    end
  end
end
