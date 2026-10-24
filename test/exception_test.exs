defmodule PrologEx.ExceptionTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.{Consult, Reader}

  @moduletag :gprolog

  @prog """
  :- use_module(library(lists)).
  :- use_module(library(apply)).
  p(1). p(2). p(3).
  tief(0) :- throw(unten).
  tief(N) :- N1 is N - 1, tief(N1).
  erst :- catch(p(X), _, true), !, X == 1.
  wirft(X) :- X > 1, throw(zu_gross(X)).
  wirft(_).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    {db, []} = Consult.load(%{}, Reader.read_terms(r, @prog))
    {:ok, reader: r, db: db}
  end

  defp goal(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    g
  end

  defp ask(c, text),
    do:
      c.db
      |> PrologEx.query(goal(c, text))
      |> Enum.take(20)
      |> Enum.map(&PrologEx.format_answer/1)

  defp more(c, text), do: c.db |> PrologEx.solutions(goal(c, text)) |> Enum.map(&elem(&1, 1))

  defp uncaught(c, text) do
    e = assert_raise(PrologEx.Error, fn -> ask(c, text) end)
    e.term
  end

  test "throw/catch: Ball wird unifiziert, Bindungen danach zurückgesetzt", c do
    assert ask(c, "catch(throw(foo), E, true).") == ["E = foo"]
    assert ask(c, "catch(throw(f(1, X)), f(A, B), true).") |> length() == 1
    assert ask(c, "catch(throw(f(1)), f(A), true).") == ["A = 1"]
    # Bindungen aus dem Ziel sind beim Fangen zurückgenommen
    assert ask(c, "catch((X = 1, throw(t)), t, true).") == ["true"]
    assert ask(c, "catch((X = 1, throw(t(X))), t(Y), true).") == ["Y = 1"]
    # der Catcher passt nicht: weiter nach außen
    assert ask(c, "catch(catch(throw(a), b, R = inner), a, R = outer).") == ["R = outer"]
    # Fehler in der Recovery geht nach außen
    assert ask(c, "catch(catch(throw(a), a, throw(b)), b, R = outer).") == ["R = outer"]
    # Ausnahme durch tiefe Rekursion
    assert ask(c, "catch(tief(10000), unten, true).") == ["true"]
  end

  test "Fehler der Builtins als error(Formal, _)", c do
    assert ask(c, "catch(X is foo + 1, error(E, _), true).") == [
             "E = type_error(evaluable, foo/0)"
           ]

    assert ask(c, "catch(X is Y + 1, error(E, _), true).") == ["E = instantiation_error"]

    assert ask(c, "catch(arg(x, f(a), _), error(type_error(T, C), _), true).") == [
             "C = x, T = integer"
           ]

    assert ask(c, "catch(atom_lenght(abc, N), error(existence_error(procedure, PI), _), true).") ==
             ["PI = atom_lenght/2"]

    assert ask(c, "catch(call(1), error(E, _), true).") == ["E = type_error(callable, 1)"]
    assert ask(c, "catch(G, error(E, _), true).") == ["E = instantiation_error"]
    assert ask(c, "catch(throw(_), error(E, _), true).") == ["E = instantiation_error"]

    assert ask(c, "catch(assertz(p(9)), error(permission_error(A, T, PI), _), true).") ==
             ["A = modify, PI = p/1, T = static_procedure"]

    # Kulprit mit gebundenen Variablen wird aufgelöst
    assert ask(
             c,
             "X = f(Y), Y = 2, catch(atom_codes(X, _), error(type_error(atom, C), _), true)."
           ) ==
             ["C = f(2), X = f(2), Y = 2"]
  end

  test "catch/3 ist transparent für Choice Points, aber nur während G läuft", c do
    assert ask(c, "catch(p(X), _, true).") == ["X = 1", "X = 2", "X = 3"]
    assert more(c, "catch(p(X), _, true).") == [true, true, false]
    # deterministisches Ziel: kein Choice Point
    assert more(c, "catch(true, _, true).") == [false]
    # Ausnahme NACH dem Verlassen von G: nicht von diesem catch gefangen
    assert uncaught(c, "catch(p(X), _, true), X >= 2, throw(danach).") == {:atom, "danach"}
    assert uncaught(c, "catch(true, _, true), throw(danach).") == {:atom, "danach"}
    # beim Backtracking zurück in G fängt der Rahmen wieder
    assert ask(c, "findall(R, catch((p(X), wirft(X), R = X), zu_gross(Y), R = g(Y)), L).") ==
             ["L = [1, g(2)]"]

    # Cut nach catch schneidet auch dessen Choice Points
    assert ask(c, "erst.") == ["true"]
    assert more(c, "erst.") == [false]
  end

  test "Ausnahmen aus Unter-Maschinen: findall, \\\\+, countall, findnsols, lazy Builtins", c do
    assert ask(c, "catch(findall(X, (p(X), X > a), L), error(E, _), true).") ==
             ["E = type_error(evaluable, a/0)"]

    assert ask(c, "catch(\\+ throw(x), x, true).") == ["true"]
    assert ask(c, "catch(countall(throw(x), N), x, true).") == ["true"]

    assert ask(c, "catch(findnsols(2, X, (p(X), X > 1, throw(x(X))), L), x(Y), true).") == [
             "Y = 2"
           ]

    assert ask(c, "catch(findnsols(1, X, (p(X), (X > 1 -> throw(x(X)) ; true)), L), x(Y), true).") ==
             ["L = [1]", "Y = 2"]

    assert ask(c, "catch((between(1, inf, X), X > 3, throw(x(X))), x(Y), true).") == ["Y = 4"]
    # Fehler beim Backtracking in ein nichtdeterministisches Builtin
    assert ask(c, "catch((nth0(I, [a, b], E), I > 0, throw(i(I))), i(J), true).") == ["J = 1"]
  end

  test "occurs_check=error: auch die Kopfunifikation ist fangbar", c do
    db = c.db
    {db2, []} = Consult.load(db, Reader.read_terms(c.reader, "same(X, X).\n"))

    g =
      goal(
        c,
        "set_prolog_flag(occurs_check, error), catch(same(X, f(X)), error(E, _), true), set_prolog_flag(occurs_check, false)."
      )

    assert [ans] = db2 |> PrologEx.query(g) |> Enum.map(&PrologEx.format_answer/1)
    assert ans =~ "occurs_check"
  end

  test "nicht gefangen: Toplevel und consult melden den Fehler", c do
    out = capture_io(fn -> ask_toplevel("throw(oops).\nX is foo + 1.\nfoo(1).\n") end)
    assert out =~ "Fehler: unbehandelte Ausnahme: oops"
    assert out =~ "Fehler: type_error(evaluable, foo/0)"
    assert out =~ "Fehler: existence_error(procedure, foo/1)"

    {_db, msgs} = Consult.load(%{}, Reader.read_terms(c.reader, ":- throw(boom).\n"))
    assert Enum.any?(msgs, &(&1 =~ "boom"))
  end

  defp ask_toplevel(input) do
    capture_io([input: input <> "halt.\n", capture_prompt: false], fn ->
      try do
        PrologEx.Toplevel.main(["-q"])
      catch
        {:prolog_halt, _} -> :ok
      end
    end)
    |> IO.write()
  end
end
