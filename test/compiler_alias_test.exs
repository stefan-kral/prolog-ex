defmodule PrologEx.CompilerAliasTest do
  # Übersetzen: Ziele X = V (zwei Variablen), deren V nur in den folgenden
  # Zielen derselben Konjunktion vorkommt, fallen weg (V wird zu X). Die
  # Klauseln hier verhalten sich mit und ohne das genau gleich; die
  # Struktur-Tests prüfen, welche Ziele wegfallen und welche bleiben.
  use ExUnit.Case, async: true
  alias PrologEx.{Compiler, Reader, TableCase}

  @program """
  :- use_module(library(lists)).
  :- use_module(library(dif)).
  p1(X, R) :- Y = X, R = f(Y).
  p2(A, R) :- ( A > 0, Y = A ; true ), R = f(Y).
  p3(R) :- _ = V, R = V.
  p4(R) :- A = B, B = c, R = A.
  p5 :- \\+ (X = Y, Y \\== X).
  p6(L) :- findall(V, (V = W, member(W, [1,2])), L).
  p7(R) :- ( X = Y, Y = 1 -> R = X ; R = no ).
  p8(X, W) :- freeze(X, W = woke), Y = X, Y = 1.
  p9(A, B, R) :- A = V, V = B, R = V.
  p10(R) :- X = Y, ( Y = 1 ; Y = 2 ), R = X.
  p11(R) :- ( X = Y ; X = z ), R = X-Y.
  p12(X, R) :- Y = X, dif(Y, a), R = Y.
  p13(R) :- X = Y, Y = Z, Z = W, W = 7, R = X.
  p14(R) :- X = Y, R = Y, X = 3.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _warnings} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        {"p1(a, R)", ["R = f(a)"]},
        {"p1(X, R)", ["R = f(X)"]},
        {"p2(3, R)", ["R = f(3)", "R = f(_A)"]},
        {"p2(-1, R), R = f(V), var(V)", :succeeds},
        {"p3(R)", :succeeds},
        {"p4(R)", ["R = c"]},
        {"p5", true},
        {"p6(L)", ["L = [1,2]"]},
        {"p7(R)", ["R = 1"]},
        {"p8(X, W)", ["W = woke, X = 1"]},
        {"p9(1, B, R)", ["B = 1, R = 1"]},
        {"p9(1, 2, R)", :fails},
        {"p10(R)", ["R = 1", "R = 2"]},
        {"p11(R)", ["R = _A-_A", "R = z-_A"]},
        {"p12(a, R)", :fails},
        {"p12(b, R)", ["R = b"]},
        {"p13(R)", ["R = 7"]},
        {"p14(R)", ["R = 3"]}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  # Anzahl der Ziele "=" im übersetzten Rumpf
  defp eqs(clause, c) do
    Reader.put_current(c.reader)
    [{:term, {:struct, ":-", [h, b]}, _}] = Reader.read_terms(c.reader, clause <> ".")
    count(Compiler.alias_vars(h, b))
  end

  defp count({:struct, "=", [_, _]}), do: 1
  defp count({:struct, _, args}), do: args |> Enum.map(&count/1) |> Enum.sum()
  defp count(_), do: 0

  test "welche Ziele wegfallen", c do
    # Kette aus einer Kopfvariablen: alle weg
    assert eqs("p(S0, S) :- S0 = S1, S1 = S2, q(S2, S3), S3 = S4, r(S4, S)", c) == 0
    # V kommt im Kopf vor: bleibt
    assert eqs("p(X, Y) :- X = Y", c) == 1
    # V kommt vorher vor: bleibt (V ist dann nicht frisch)
    assert eqs("p(R) :- q(V), X = V, R = X", c) == 1
    # V auch in einem anderen Zweig: bleibt
    assert eqs("p(R) :- ( X = Y ; X = z ), R = X-Y", c) == 3
    # V nach dem If-then-else (im else-Weg nicht gebunden): bleibt
    assert eqs("p(A, R) :- ( A > 0, Y = A ; true ), R = f(Y)", c) == 2
    # anonyme Variable (der Leser benennt sie eindeutig): beide weg
    assert eqs("p(R) :- _ = V, R = V", c) == 0
    assert eqs("p(R) :- _ = V, q(V), R = V", c) == 1
    # in der Bedingung, V auch im then-Zweig: bleibt (nur dieselbe Konjunktion)
    assert eqs("p(R) :- ( X = Y, q -> R = X-Y ; R = no )", c) == 3
    # innerhalb der Bedingung: weg
    assert eqs("p(R) :- ( X = Y, Y = 1 -> R = X ; R = no )", c) == 3
    # Argument eines Meta-Prädikats ist kein Ziel: bleibt
    assert eqs("p(L) :- findall(V, (V = W, q(W)), L)", c) == 1
    # in \\+: weg
    assert eqs("p :- \\+ (X = Y, q(Y))", c) == 0
  end

  test "clause/2 zeigt die Quelle", c do
    assert TableCase.run(c.reader, c.db, "clause(p13(R), B)") |> elem(1) ==
             {:answers, ["B = (_A=_B,_B=_C,_C=_D,_D=7,R=_A)"]}
  end
end
