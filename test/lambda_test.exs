defmodule PrologEx.LambdaTest do
  # library(lambda) (Elixir) und library(lambda_pl) (Prolog, wie Neumerkels
  # lambda.pl): dieselben Fälle für beide Varianten
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @fixtures Path.expand("fixtures/lambda", __DIR__)

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(4)
    |> Enum.map(&(PrologEx.format_answer(&1, PrologEx.query_var_names(g)) |> norm()))
  end

  defp err(c, text),
    do: norm(Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end)))

  defp norm(text), do: Regex.replace(~r/_B\d+/, text, "_")

  for lib <- ["lambda", "lambda_pl"] do
    describe "library(#{lib})" do
      setup c do
        Reader.put_current(c.reader)
        PrologEx.put_db(%{})

        for l <- ["apply", "lists", unquote(lib)],
            do: ["true"] = ask(c, "use_module(library(#{l})).")

        :ok
      end

      test "Parameter und Rumpf", c do
        assert ask(c, "maplist(\\X^Y^(Y is X*2), [1,2,3], L).") == ["L = [2,4,6]"]
        assert ask(c, "maplist(\\X^Y^Z^(Z is X+Y), [1,2], [3,4], L).") == ["L = [4,6]"]
        assert ask(c, "foldl(\\X^A0^A^(A is A0+X), [1,2,3], 0, S).") == ["S = 6"]
        assert ask(c, "include(\\X^(X > 1), [1,2,3], L).") == ["L = [2,3]"]
        assert ask(c, "maplist(\\X^(X > 0), [1,-2]).") == []
        # übrige Argumente gehen an den Rumpf
        assert ask(c, "call(\\X^Y^append(X,Y), [a], [b], L).") == ["L = \"ab\""]
        assert ask(c, "call(\\X^member(X), Y, [a,b]).") == ["Y = a", "Y = b"]
        # geschachtelt
        assert ask(c, "call(\\X^(\\Y^Z^(Z is X*Y)), 3, 4, R).") == ["R = 12"]
        # Parameter als Muster
        # (\\(K-_)^.. ohne Klammer um alles wäre Funktionsschreibweise)
        assert ask(c, "maplist(\\((K-_)^K^true), [a-1, b-2], L).") == ["L = \"ab\""]
        assert ask(c, "call(\\f(X)^true, g(1)).") == []
        assert ask(c, "X = 2, call(X^true, 1).") == []
        # ohne Parameter
        assert ask(c, "call(\\true).") == ["true"]
        assert ask(c, "call(\\member(X), [a]).") == ["true"]
      end

      test "Kopie: lokale Variablen frisch, gebundene bleiben", c do
        # Y je Aufruf neu: sonst würde das zweite Element scheitern
        assert ask(c, "maplist(\\X^(Y = X), [1, 2]).") == ["true"]
        # Variablen außerhalb werden mitkopiert, also nicht gebunden
        assert ask(c, "call(\\X^(Y = X), 1), var(Y).") == ["true"]
        # schon gebundene Variablen sind Werte
        assert ask(c, "N = 10, maplist(\\X^Y^(Y is X+N), [1,2], L).") ==
                 ["L = [11,12], N = 10"]
      end

      test "Free+\\\\Lambda: globale Variablen", c do
        # N muss beim Aufruf gebunden sein
        assert err(c, "maplist(N+\\X^Y^(Y is X+N), [1,2], L), N = 3.") =~ "instantiation_error"
        assert ask(c, "N = 3, maplist(N+\\X^Y^(Y is X+N), [1,2], L).") == ["L = [4,5], N = 3"]
        # Bindung globaler Variablen bleibt sichtbar
        assert ask(c, "call(G+\\X^(G = X), 1).") == ["G = 1"]
        assert ask(c, "maplist(G+\\X^(G = X), [1, 1]).") == ["G = 1"]
        # Free zusammengesetzt: alle Variablen darin bleiben global
        assert ask(c, "call(f(A, g(B))+\\X^(A = X, B = 2), 1).") == ["A = 1, B = 2"]
        assert ask(c, "maplist(G+\\X^(G = X), [1, 2]).") == []
        # mehrere globale Variablen als Liste (A-B+\\L hieße A-(B+\\L))
        assert ask(c, "call([A,B]+\\X^(A = X, B = f(X)), 1).") == ["A = 1, B = f(1)"]
      end

      test "X^G ohne \\\\: keine Kopie", c do
        assert ask(c, "F = X^Y^(Y is X+1), call(F, 1, R).") ==
                 ["F = 1^2^(2 is 1+1), R = 2, X = 1, Y = 2"]

        # zweiter Aufruf mit anderem Wert scheitert (X ist schon gebunden)
        assert ask(c, "F = X^Y^(Y is X+1), call(F, 1, _), call(F, 2, _).") == []
      end

      test "Fehler", c do
        assert err(c, "call(\\X^Y^foo(X,Y), 1).") =~
                 "existence_error(lambda_parameter,user:_^foo(1,_))"

        assert err(c, "call(\\X^true, 1, 2).") =~ "existence_error(procedure,true/1)"
        assert err(c, "call(\\G, 1).") =~ "instantiation_error"
        assert err(c, "call(\\X^Y, 1).") =~ "instantiation_error"

        assert err(c, "maplist(\\X^Y^nosuch(X,Y), [1], L).") =~
                 "existence_error(procedure,nosuch/2)"
      end

      test "Lambda in einem Modul ruft dessen private Prädikate", c do
        file = Path.join(@fixtures, "m_#{unquote(lib)}.pl")
        assert ask(c, "use_module('#{file}').") == ["true"]
        assert ask(c, "doubled([1,2,3], L).") == ["L = [2,4,6]"]
        assert ask(c, "scaled(3, [1,2], L).") == ["L = [3,6]"]
        assert err(c, "twice(1, X).") =~ "existence_error(procedure,twice/2)"
      end

      test "meta_predicate-Deklarationen", c do
        assert ask(c, "predicate_property(\\(_, _), meta_predicate(M)).") == ["M = \\(1,?)"]

        assert ask(c, "predicate_property(+\\(_, _, _), meta_predicate(M)).") == [
                 "M = +\\(?,1,?)"
               ]

        assert ask(c, "predicate_property(^(_, _, _, _), meta_predicate(M)).") == [
                 "M = ^(?,1,?,?)"
               ]
      end
    end
  end

  test "ohne use_module: nicht sichtbar", c do
    Reader.put_current(c.reader)
    PrologEx.put_db(%{})
    assert err(c, "call(\\X^true, 1).") =~ "existence_error(procedure,(\\)/2)"
  end
end
