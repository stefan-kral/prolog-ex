defmodule PrologEx.BacktrackFastTest do
  # Schnellwege des Interpreters (siehe run/1, backtrack/1, match_args/6,
  # unify/4, arithmetische Vergleiche als Ziel): Choice Points für Klauseln,
  # Disjunktionen, if-then-else und Builtin-Lösungen in einem Update, der
  # Schnitt ohne setup_call_cleanup/3, Variable gegen Zahl/Atom ohne
  # allgemeine Unifikation, zwei Zahlen ohne Auswerten. Gleiche Ergebnisse,
  # Bindungen und Weckziele wie auf den allgemeinen Wegen.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(dif)).
  :- use_module(library(freeze)).
  p(1). p(a). p(2.0). p(f(x)). p(3).
  q(1, a). q(2, b). q(3, c).
  r(X) :- q(_, X).
  r(z).
  mx(X, Y, X) :- X >= Y, !.
  mx(_, Y, Y).
  k(X, Y, R) :- ( X < Y -> R = lt ; X =:= Y -> R = eq ; R = gt ).
  e(L) :- findall(X-Y, ( member(X, [1, 2, 3]), ( X < 2 ; X > 2 ; Y = mid ) ), L).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        # Fakten: alle, in Reihenfolge, Bindungen zwischendurch zurückgesetzt
        {"findall(X, p(X), L)", ["L = [1,a,2.0,f(x),3]"]},
        {"findall(X, (p(X), number(X)), L)", ["L = [1,2.0,3]"]},
        {"p(2)", :fails},
        {"p(2.0)", :succeeds},
        {"findall(X, r(X), L)", ["L = [a,b,c,z]"]},
        {"findall(N-X, (between(1, 3, N), q(N, X)), L)", ["L = [1-a,2-b,3-c]"]},
        # Schnitt: nimmt die restlichen Klauseln und die Alternativen davor
        {"findall(Z, mx(3, 5, Z), L)", ["L = [5]"]},
        {"findall(Z, mx(7, 5, Z), L)", ["L = [7]"]},
        {"findall(X-Z, (member(X, [9, 1]), mx(X, 5, Z)), L)", ["L = [9-9,1-5]"]},
        # if-then-else und Disjunktion
        {"findall(R, (member(X, [1, 2, 3]), k(X, 2, R)), L)", ["L = [lt,eq,gt]"]},
        {"k(1, 2, eq)", :fails},
        {"e(L)", ["L = [1-_A,1-mid,2-mid,3-_B,3-mid]"]},
        {"findall(X, (between(1, 5, X), (X =< 1 ; X >= 5)), L)", ["L = [1,5]"]},
        # Vergleiche zweier Zahlen: ganz und Gleitkomma gemischt
        {"1 =:= 1.0", :succeeds},
        {"1 < 1.0", :fails},
        {"2.5 > 2", :succeeds},
        {"3 =\\= 3", :fails},
        {"X = 2, X < 1", :fails},
        {"X = 2, ( X < 1 ; X >= 2 )", ["X = 2"]},
        # ... sonst der allgemeine Weg: Ausdrücke, Fehler
        {"X = 1 + 1, X =:= 2", ["X = 1+1"]},
        {"catch(_ < 1, error(E, _), true)", ["E = instantiation_error"]},
        {"catch(a < 1, error(E, _), true)", ["E = type_error(evaluable,a/0)"]},
        # Variable gegen Zahl oder Atom
        {"X = 1, X = 1", ["X = 1"]},
        {"X = 1, X = 1.0", :fails},
        {"X = a, X = b", :fails},
        {"X = f(Y), X = a", :fails},
        {"X = Y, Y = a", ["X = a, Y = a"]},
        {"freeze(X, write(w)), X = 1", {:out, "w"}},
        {"freeze(X, fail), X = a", :fails},
        {"dif(X, a), X = a", :fails},
        {"dif(X, a), X = b", ["X = b"]},
        {"findall(X, (between(1, 3, X), dif(X, 2)), L)", ["L = [1,3]"]},
        {"findall(Y, (member(Y, [a, b]), freeze(Z, Z == b), Z = Y), L)", ["L = [b]"]}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
