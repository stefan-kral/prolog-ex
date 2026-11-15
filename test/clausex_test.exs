defmodule PrologEx.ClausexTest do
  # clausex/2 aus library(iso_ext): wie clause/2, scheitert aber statt
  # permission_error(access, private_procedure, …) – für Meta-Interpreter
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  @prog """
  :- use_module(library(lists)).
  :- use_module(library(iso_ext)).
  p(1). p(2).
  q(X) :- append(X, _, [1,2]).
  solve(true) :- !.
  solve((A,B)) :- !, solve(A), solve(B).
  solve(G) :- if(clausex(G, B), solve(B), call(G)).
  n(G, N) :- findall(B, clausex(G, B), L), length(L, N).
  """

  defp out(c, q) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, @prog))
    inspect(elem(TableCase.run(c.reader, db, q), 1))
  end

  test "Klauseln wie clause/2, sonst scheitern", c do
    assert out(c, "n(p(_), N)") =~ "N = 2"

    for g <- ["append(_,_,_)", "lists:append(_,_,_)", "_ is _", "(_,_)", "undefined_xyz(_)"],
        do: assert(out(c, "n(#{g}, N)") =~ "N = 0", g)
  end

  test "andere Fehler wie clause/2", c do
    assert out(c, "catch(clausex(_, _), error(E, _), true)") =~ "E = instantiation_error"
    assert out(c, "catch(clausex(3, _), error(E, _), true)") =~ "type_error(callable,3)"
  end

  test "Meta-Interpreter über Bibliotheksprädikate", c do
    assert out(c, "findall(X, solve(q(X)), L)") =~ "L = [[],[1],[1,2]]"
  end

  test "ohne Import nicht sichtbar", c do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, "p(1).\n"))

    o =
      inspect(elem(TableCase.run(c.reader, db, "catch(clausex(p(_), _), error(E, _), true)"), 1))

    assert o =~ "existence_error(procedure,clausex/2)"
  end
end
