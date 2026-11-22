defmodule PrologEx.InlineBodyTest do
  # Deterministische eingebaute Ziele am Anfang des Rumpfs (is, Vergleiche,
  # =, ==, \==, Typtests) laufen gleich beim Eintritt in die Klausel – mit
  # denselben Inferenzen, Grenzen, Weckzielen und Fehlern wie über den
  # Zielstapel.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(iso_ext)).
  :- use_module(library(lists)).
  :- use_module(library(swi)).
  p(X) :- X = 1, Y is X + 1, Y > 1, integer(Y), a == a.
  q(X, Y) :- X > 0, !, Y = pos.
  q(_, neg).
  r(X, Y) :- Y is 10 / X.
  s(X) :- X = f(_), atom(X).
  s(X) :- X = g.
  w(X, Y) :- X = 1, Y = done.
  t(X) :- !, X = 1.
  t(2).
  u(X, Y) :- X > 0, !, Y is X * 2.
  u(_, 0).
  det(G, D) :- setup_call_cleanup(true, G, D = ja), ( var(D) -> D = nein ; true ).
  lp(0) :- !.
  lp(N) :- a == a, N1 is N - 1, lp(N1).
  % Ausgabe-Slots: zuerst Ergebnis von is oder Seite von = im Präfix
  o1(X, Y) :- Z is X + 1, W = f(Z, V), V = Z, Y = W.
  o2(Y) :- X = f(X), Y = X.
  o3(Y) :- f(1) = X, Y = X.
  o4(Y) :- X is foo + 1, Y = X.
  o5(V, Y) :- X = V, Y = X.
  o6(X, Y) :- X > 0, Z is X * 2, Z > 3, integer(Z), Y = Z.
  % nichtdeterministisch: je Ebene ein Choice Point, ohne Bindungen
  dn(N) :- N > 0, N1 is N - 1, dn(N1).
  dn(_).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        {"p(X)", ["X = 1"]},
        {"q(5, Y)", ["Y = pos"]},
        {"q(-5, Y)", ["Y = neg"]},
        # Scheitern im ersten Ziel: die nächste Klausel
        {"findall(X, s(X), L)", ["L = [g]"]},
        # Fehler aus dem Rumpf, gefangen
        {"catch(r(0, _), error(E, _), true)", ["E = evaluation_error(zero_divisor)"]},
        {"catch(r(a, _), error(E, _), true)", ["E = type_error(evaluable,a/0)"]},
        # Inferenzen wie über den Zielstapel (dieselbe Grenze wie vorher)
        {"call_with_inference_limit(p(_), 5, R)", ["R = !"]},
        {"call_with_inference_limit(p(_), 4, R)", ["R = inference_limit_exceeded"]},
        # Weckziele nach einer Bindung im Rumpf, vor dem Rest
        {"freeze(X, write(w)), w(X, Y)", {:out, "w"}},
        {"freeze(X, fail), \\+ w(X, _)", :succeeds},
        # Schnitt im Präfix: nimmt den eigenen Choice Point, auch wenn danach
        # etwas scheitert
        {"t(1)", :succeeds},
        {"t(2)", :fails},
        {"findall(Y, u(3, Y), L)", ["L = [6]"]},
        {"findall(Y, u(-3, Y), L)", ["L = [0]"]},
        {"det(u(3, Y), D)", ["D = ja, Y = 6"]},
        {"findall(X, t(X), L)", ["L = [1]"]},
        # über Prüfpunkte hinweg (ground ==: markiertes Ziel)
        {"call_with_inference_limit(lp(5000), 100000, R)", ["R = !"]},
        {"catch(call_with_time_limit(5, lp(20000)), E, true)", :succeeds},
        # Ausgabe-Slots: dieselben Antworten, Fehler, Grenzen (Inferenzen wie
        # vorher: o6 6, o1 5), Wecken
        {"o1(1, Y)", ["Y = f(2,2)"]},
        {"o2(Y), Y = f(Z), Z == Y", :succeeds},
        {"set_prolog_flag(occurs_check, true), ( o2(_) -> R = ja ; R = nein ), " <>
           "set_prolog_flag(occurs_check, false)", ["R = nein"]},
        {"o3(Y)", ["Y = f(1)"]},
        {"catch(o4(_), error(E, _), true)", ["E = type_error(evaluable,foo/0)"]},
        {"freeze(V, write(w)), o5(V, Y), Y = 1", {:out, "w"}},
        {"o6(2, Y)", ["Y = 4"]},
        {"o6(1, Y)", :fails},
        {"call_with_inference_limit(o6(2, Y), 5, R)", ["R = inference_limit_exceeded"]},
        {"call_with_inference_limit(o6(2, Y), 6, R)", ["R = !, Y = 4"]},
        {"findall(N, (between(1, 6, L), call_with_inference_limit(o1(1, _), L, N)), Ns)",
         [
           "Ns = [inference_limit_exceeded,inference_limit_exceeded,inference_limit_exceeded,inference_limit_exceeded,!,!]"
         ]}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  # ein Choice Point je Ebene hält die Substitution von damals: N1 als
  # Ausgabe-Slot bindet nichts, die Choice Points teilen also alle dieselbe
  test "Ausgabe-Slots: keine Bindungen zwischen den Choice Points", c do
    [{:term, g, _}] = Reader.read_terms(c.reader, "dn(500).")
    assert {:ok, %{choicepoints: 500, bindings: 0}} = PrologEx.first_with_stats(c.db, g)
  end
end
