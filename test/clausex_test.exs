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

  # clause/2 legt den Kopf der Quelle gegen das Ziel, statt ihn zu kopieren
  @heads """
  r(X, X).
  r(f(X, Y), [X|Y]) :- g(X).
  r(1, a).
  r(1.0, b).
  r([a,b|T], T).
  r(g(A, h(A)), A).
  """

  defp heads(c, q) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, @heads))
    inspect(elem(TableCase.run(c.reader, db, q), 1))
  end

  test "clause/2: Köpfe gegen das Ziel gelegt", c do
    assert heads(c, "findall(B, clause(r(1, X), B), L)") =~ "L = [true,true]"
    assert heads(c, "findall(X, clause(r(1.0, X), _), L)") =~ "L = [1.0,b]"
    assert heads(c, "findall(X-B, clause(r(f(1,2), X), B), L)") =~ "L = [f(1,2)-true,[1|2]-g(1)]"
    assert heads(c, "findall(X, clause(r([a,b,c], X), _), L)") =~ "L = [[a,b,c],[c]]"
    assert heads(c, "findall(X, clause(r(g(1,h(2)), X), _), L)") =~ "L = [g(1,h(2))]"
    assert heads(c, "findall(X, clause(r(g(1,h(1)), X), _), L)") =~ "L = [g(1,h(1)),1]"

    assert heads(c, "findall(Y, clause(r(Y, [p|q]), _), L)") =~
             "L = [[p|q],f(p,q),[a,b,p|q],g([p|q],h([p|q]))]"

    assert heads(c, "set_prolog_flag(occurs_check, true), findall(B, clause(r(W, f(W)), B), L)") =~
             "L = []"
  end

  test "ohne Import nicht sichtbar", c do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, "p(1).\n"))

    o =
      inspect(elem(TableCase.run(c.reader, db, "catch(clausex(p(_), _), error(E, _), true)"), 1))

    assert o =~ "existence_error(procedure,clausex/2)"
  end
end
