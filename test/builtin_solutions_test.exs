defmodule PrologEx.BuiltinSolutionsTest do
  # Lösungen nichtdeterministischer Builtins (between/3, member/2, nth1/3,
  # ...): der schnelle Weg (freie Variable direkt binden, Choice Point an
  # Ort und Stelle weiterschalten) gibt dieselben Antworten wie die
  # allgemeine Unifikation – auch mit Occurs-Check, attributierten
  # Variablen, schon gebundenen Ausgaben und Floats.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {db, _} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(r, """
        :- use_module(library(lists)).
        :- use_module(library(between)).
        :- use_module(library(swi)).
        f(1). f(2.0). f(a). f(g(1)). f(g(2)). f([x]). f(3).
        k(a, 1). k(b, 2). k(a, 3). k(c, 4).
        """)
      )

    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        {"findall(X, between(1, 5, X), L)", ["L = [1,2,3,4,5]"]},
        {"findall(X, (between(1, 5, X), X > 3), L)", ["L = [4,5]"]},
        {"findall(X-Y, nth1(X, [a, b, c], Y), L)", ["L = [1-a,2-b,3-c]"]},
        {"findall(X, member(f(X), [f(1), g(2), f(3)]), L)", ["L = [1,3]"]},
        {"findall(Y, member(Y, [f(_), g(a)]), L), L = [f(Z)|_], var(Z)", :succeeds},
        # Ausgabe schon gebunden: Vergleich statt Bindung
        {"X = 3, findall(X, between(1, 5, X), L)", ["L = [3], X = 3"]},
        {"findall(Y, (Y = b, member(Y, [a, b, c])), L)", ["L = [b]"]},
        {"findall(Y, (Y = f(1), member(Y, [f(2), f(1)])), L)", ["L = [f(1)]"]},
        # Floats über den allgemeinen Weg (wie =/2)
        {"( member(0.0, [-0.0]) -> R = ja ; R = nein ), ( 0.0 = -0.0 -> S = ja ; S = nein ), R == S",
         :succeeds},
        {"\\+ member(1, [1.0])", :succeeds},
        # attributierte Variable: weckt wie sonst
        {"freeze(X, write(w(X))), findall(X, member(X, [1, 2]), _)", {:out, "w(1)w(2)"}},
        {"freeze(X, X > 1), findall(X, member(X, [1, 2, 3]), L)", ["L = [2,3], freeze(X,X>1)"]},
        # Occurs-Check: über den allgemeinen Weg
        {"set_prolog_flag(occurs_check, true), ( member(X, [f(X)]) -> R = ja ; R = nein ), " <>
           "set_prolog_flag(occurs_check, false)", ["R = nein"]},
        {"catch((set_prolog_flag(occurs_check, error), member(X, [f(X)])), error(E, _), true), " <>
           "set_prolog_flag(occurs_check, false), E = occurs_check(_, _)", :succeeds},
        # Zähler im Choice Point (between/3, repeat/1): nach der letzten
        # Lösung keiner mehr; unendlich; attributierte Variable; schon
        # gebunden
        {"findall(X, (between(1, inf, X), (X >= 3, ! ; true)), L)", ["L = [1,2,3]"]},
        {"call_cleanup(between(3, 3, X), D = det)", ["D = det, X = 3"]},
        {"findall(D, call_cleanup(between(1, 2, _), D = det), L)", ["L = [_A,det]"]},
        {"\\+ between(3, 2, _)", :succeeds},
        {"freeze(X, write(X)), findall(X, between(1, 3, X), _)", {:out, "123"}},
        {"freeze(X, X > 1), findall(X, between(1, 3, X), L)", ["L = [2,3], freeze(X,X>1)"]},
        {"findall(x, repeat(4), L)", ["L = [x,x,x,x]"]},
        {"findall(D, call_cleanup(repeat(2), D = det), L)", ["L = [_A,det]"]},
        {"catch(repeat(a), error(E, _), true)", ["E = type_error(integer,a)"]},
        {"findall(N, (between(1, 3, X), N is X * 10), L)", ["L = [10,20,30]"]},
        # Fakten ohne Variablen: Reihenfolge, Filter, gebundene Teile,
        # Wecken, Determinismus nach dem letzten passenden
        {"findall(X, f(X), L)", ["L = [1,2.0,a,g(1),g(2),[x],3]"]},
        {"findall(Y, f(g(Y)), L)", ["L = [1,2]"]},
        {"\\+ f(2), f(2.0), \\+ f(1.0)", :succeeds},
        {"findall(X-Y, k(X, Y), L)", ["L = [a-1,b-2,a-3,c-4]"]},
        {"findall(Y, k(a, Y), L)", ["L = [1,3]"]},
        {"call_cleanup(k(c, Y), D = det)", ["D = det, Y = 4"]},
        {"findall(D, call_cleanup(f(_), D = det), L)", ["L = [_A,_B,_C,_D,_E,_F,det]"]},
        {"freeze(X, write(X)), findall(X, f(X), _)", {:out, "12.0ag(1)g(2)[x]3"}},
        {"freeze(X, atom(X)), findall(X, f(X), L)", ["L = [a], freeze(X,atom(X))"]},
        {"findall(X, (f(X), integer(X)), L)", ["L = [1,3]"]},
        # zurücksetzen: die Bindung der vorigen Lösung ist weg
        {"findall(X-Y, (between(1, 3, X), (X =:= 2 -> Y = zwei ; Y = sonst)), L)",
         ["L = [1-sonst,2-zwei,3-sonst]"]}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
