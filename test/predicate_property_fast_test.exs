defmodule PrologEx.PredicatePropertyFastTest do
  # predicate_property/2 mit gegebenem Kopf und gegebener Eigenschaft
  # rechnet nur die gefragte (ohne Choice Point bei atomarer); das Ergebnis
  # muss dem Aufzählen mit anschließendem Vergleich gleichen
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
  :- use_module(library(apply)).
  :- dynamic(d/1).
  :- multifile(mf/1).
  :- meta_predicate(mp(0)).
  d(1). d(2).
  s(a).
  mf(1).
  mp(G) :- call(G).
  heads([s(_), d(_), mf(_), mp(_), append(_,_,_), maplist(_,_), _ is _, true, (_,_), user:s(_),
         lists:append(_,_,_), undefined_xyz, nothing(_)]).
  props([built_in, dynamic, static, multifile, discontiguous, exported, interpreted, compiled,
         defined, visible, number_of_clauses(_), number_of_clauses(2), imported_from(_),
         imported_from(lists), meta_predicate(_)]).
  check(Bad) :-
      heads(Hs), props(Ps),
      findall(H-P, ( member(H, Hs), member(P, Ps),
                     findall(P, predicate_property(H, P), L1),
                     findall(P, (predicate_property(H, Q), Q = P), L2),
                     msort(L1, S1), msort(L2, S2), S1 \\== S2 ), Bad).
  """

  test "gegebene Eigenschaft wie Aufzählen und Vergleichen", c do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, @prog))
    assert inspect(elem(TableCase.run(c.reader, db, "check(Bad)"), 1)) =~ "Bad = []"

    q =
      "predicate_property(d(_), dynamic), predicate_property(mp(_), meta_predicate(M)), " <>
        "predicate_property(append(_,_,_), imported_from(L)), " <>
        "predicate_property(d(_), number_of_clauses(N)), \\+ predicate_property(s(_), dynamic)"

    o = inspect(elem(TableCase.run(c.reader, db, q), 1))
    assert o =~ "M = mp(0)" and o =~ "L = lists" and o =~ "N = 2"
  end
end
