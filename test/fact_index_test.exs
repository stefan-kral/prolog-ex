defmodule PrologEx.FactIndexTest do
  # Index auf weitere Argumente (xindex/5: erstes Argument ungebunden, ein
  # anderes gebunden, ab 8 Klauseln), ground Fakten ohne Umfeld und
  # Vergleich ground gegen ground (ground_eq/2): dieselben Lösungen in
  # derselben Reihenfolge wie ohne, Weckziele, Occurs-Check, assert/retract
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(dif)).
  :- use_module(library(freeze)).
  :- use_module(library(iso_ext)).
  e(1, a, f(x)).
  e(2, b, f(y)).
  e(3, a, g(x)).
  e(4, c, f(x)).
  e(5, b, [1,2]).
  e(6, a, []).
  e(7, d, f(x, y)).
  e(8, a, 1.0).
  e(9, b, 1).
  e(10, c, '[]').
  % mit Variablen an der zweiten Stelle (kommen in jede Liste)
  v(1, a).
  v(2, X) :- X = any.
  v(3, b).
  v(4, a).
  v(5, _).
  v(6, c).
  v(7, a).
  v(8, b).
  v(9, d).
  % Regeln mit Köpfen wie Fakten
  r(1, x, one).
  r(2, y, two) :- true.
  r(3, x, three) :- 1 < 2.
  r(4, z, four).
  r(5, x, five).
  r(6, y, six).
  r(7, x, seven).
  r(8, w, eight).
  :- dynamic(d/2).
  d(1, a). d(2, b). d(3, a). d(4, c). d(5, a). d(6, b). d(7, a). d(8, c).
  % zu wenige Klauseln für den Index (gleiches Ergebnis)
  s(1, a). s(2, b). s(3, a).
  inf(G, I) :- statistics(inferences, I0), call(G), statistics(inferences, I1), I is I1 - I0.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        # zweites Argument gebunden: nur die passenden, in Klauselreihenfolge
        {"findall(I, e(I, a, _), L)", ["L = [1,3,6,8]"]},
        {"findall(I, e(I, b, _), L)", ["L = [2,5,9]"]},
        {"findall(I, e(I, zz, _), L)", ["L = []"]},
        # drittes: Funktor/Stelligkeit, Liste, [], Zahlen streng (1 \\= 1.0)
        {"findall(I, e(I, _, f(x)), L)", ["L = [1,4]"]},
        {"findall(I, e(I, _, f(_)), L)", ["L = [1,2,4]"]},
        {"findall(I-T, e(I, _, f(T, _)), L)", ["L = [7-x]"]},
        {"findall(I, e(I, _, [_|_]), L)", ["L = [5]"]},
        {"findall(I, e(I, _, []), L)", ["L = [6,10]"]},
        {"findall(I, e(I, _, '[]'), L)", ["L = [6,10]"]},
        {"findall(I, e(I, _, 1), L)", ["L = [9]"]},
        {"findall(I, e(I, _, 1.0), L)", ["L = [8]"]},
        {"findall(I, e(I, a, f(x)), L)", ["L = [1]"]},
        {"findall(I-X, e(I, X, f(y)), L)", ["L = [2-b]"]},
        # ground gegen ground, auch zusammengesetzt
        {"findall(I, e(I, _, f(y)), L)", ["L = [2]"]},
        {"findall(I, e(I, _, [1,2]), L)", ["L = [5]"]},
        {"findall(I, e(I, _, [1,3]), L)", ["L = []"]},
        # Variablen im Kopf: in jeder Liste, an ihrer Stelle
        {"findall(I, v(I, a), L)", ["L = [1,4,5,7]"]},
        {"findall(I, v(I, b), L)", ["L = [3,5,8]"]},
        {"findall(I, v(I, any), L)", ["L = [2,5]"]},
        {"findall(I, v(I, q), L)", ["L = [5]"]},
        # Regeln
        {"findall(N, r(_, x, N), L)", ["L = [one,three,five,seven]"]},
        {"findall(N, r(_, y, N), L)", ["L = [two,six]"]},
        # weniger als 8 Klauseln: wie bisher
        {"findall(I, s(I, a), L)", ["L = [1,3]"]},
        # nach der letzten passenden kein Choice Point mehr
        {"call_with_inference_limit(e(_, d, _), 100, R)", ["R = !"]},
        {"call_with_inference_limit(r(_, w, _), 100, R)", ["R = !"]},
        # dieselben Inferenzen
        {"inf(findall(I, e(I, a, _), _), N)", ["N = 3"]},
        # Weckziele beim Binden durch einen Fakt
        {"freeze(X, (X == 3 -> write(drei) ; true)), e(X, a, g(_))", {:out, "drei"}},
        {"dif(X, 1), findall(X, e(X, a, _), L)", ["L = [3,6,8], dif(X,1)"]},
        {"dif(X, 1), findall(X-Y, e(X, a, Y), L)", ["L = [3-g(x),6-[],8-1.0], dif(X,1)"]},
        # eine Variable zweimal
        {"findall(X, v(X, X), L)", ["L = [5]"]},
        # Occurs-Check: ground bildet keinen Zyklus
        {"set_prolog_flag(occurs_check, error), findall(I, e(I, a, _), L)", ["L = [1,3,6,8]"]},
        # assert/retract: der Index gilt für die neue Klauselliste
        {"findall(I, d(I, a), L1), assertz(d(9, a)), findall(I, d(I, a), L2), retract(d(3, a)), findall(I, d(I, a), L3)",
         ["L1 = [1,3,5,7], L2 = [1,3,5,7,9], L3 = [1,5,7,9]"]},
        {"findall(I, d(I, c), L1), asserta(d(0, c)), findall(I, d(I, c), L2)",
         ["L1 = [4,8], L2 = [0,4,8]"]}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
