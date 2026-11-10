defmodule PrologEx.GuardIndexTest do
  # Wächter im Index: beginnt der Rumpf mit einem Typtest auf die Variable
  # des ersten Kopfarguments, lässt der Index die Klausel für Argumente
  # anderen Typs weg. Gleiche Antworten wie ohne, aber weniger Versuche und
  # kein Choice Point nach dem letzten passenden Kandidaten.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(iso_ext)).
  :- use_module(library(lists)).
  art(X, zahl) :- integer(X).
  art(X, gleit) :- float(X).
  art(X, atom) :- atom(X).
  art(X, liste) :- X = [_|_].
  art(X, struktur) :- compound(X).
  art(X, var) :- var(X).
  art(3, drei).
  n(X, n) :- number(X).
  n(X, a) :- atomic(X).
  n(X, c) :- callable(X).
  det(G, D) :- setup_call_cleanup(true, G, D = ja), ( var(D) -> D = nein ; true ).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        # dieselben Antworten
        {"findall(A, art(1, A), L)", ["L = [zahl]"]},
        {"findall(A, art(3, A), L)", ["L = [zahl,drei]"]},
        {"findall(A, art(1.5, A), L)", ["L = [gleit]"]},
        {"findall(A, art(a, A), L)", ["L = [atom]"]},
        {"findall(A, art([], A), L)", ["L = [atom]"]},
        {"findall(A, art([x], A), L)", ["L = [liste,struktur]"]},
        {"findall(A, art(f(x), A), L)", ["L = [struktur]"]},
        {"findall(A, art(1r3, A), L)", ["L = []"]},
        {"findall(A, art(_, A), L)", ["L = [liste,var,drei]"]},
        {"findall(A, n(1r3, A), L)", ["L = [n,a]"]},
        {"findall(A, n(x, A), L)", ["L = [a,c]"]},
        {"findall(A, n(f(x), A), L)", ["L = [c]"]},
        # deterministisch, auch ohne Schnitt
        {"det(art(1, _), D)", ["D = ja"]},
        {"det(art(7, _), D)", ["D = ja"]},
        {"det(art(a, _), D)", ["D = ja"]},
        {"det(art(f(y), _), D)", ["D = ja"]},
        {"det(art(3, A), D)", ["A = zahl, D = nein", "A = drei, D = ja"]},
        # clause/2 und retract/1 sehen alle Klauseln, deren Kopf passt (der
        # Wächter ist Rumpf; X = [_|_] steht in der Quelle im Rumpf)
        {"findall(B, clause(art(1, _), B), L), length(L, N)", :succeeds},
        {"findall(A, clause(art(1, A), _), L)", ["L = [zahl,gleit,atom,liste,struktur,var]"]},
        {"assertz((s(X) :- X = a)), clause(s(b), B)", ["B = (b=a)"]},
        {"assertz((s2(X) :- X = a)), retract((s2(b) :- _)), \\+ clause(s2(_), _)", :succeeds},
        # mit assertz: Neubau des Index
        {"assertz((q(X) :- integer(X))), assertz((q(X) :- atom(X))), " <>
           "det(q(1), D1), det(q(a), D2), \\+ q(f(x))", ["D1 = ja, D2 = ja"]},
        {"assertz((r(X) :- atom(X))), assertz(r(1)), assertz((r(X) :- integer(X))), " <>
           "findall(X, (member(X, [a, 1, 2, f]), r(X)), L)", ["L = [a,1,1,2,f]"]}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
