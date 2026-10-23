defmodule PrologEx.CoroutiningTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.{Consult, Reader}

  @moduletag :gprolog

  @prog """
  :- use_module(library(lists)).
  p(a).
  p(b).
  zaehle(0) :- !.
  zaehle(N) :- N1 is N - 1, zaehle(N1).
  ausgabe(X) :- write(X), nl.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    {db, []} = Consult.load(%{}, Reader.read_terms(r, @prog))
    {:ok, reader: r, db: db}
  end

  defp goal(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    g
  end

  defp ask(c, text, opts \\ []) do
    g = goal(c, text)

    c.db
    |> PrologEx.query(g, opts)
    |> Enum.take(20)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp out(c, text, opts \\ []),
    do: capture_io(fn -> send(self(), {:ans, ask(c, text, opts)}) end)

  describe "freeze/2, frozen/2" do
    test "weckt beim Binden, in Reihenfolge, sofort wenn schon gebunden", c do
      assert out(c, "freeze(X, ausgabe(X)), write(vorher), nl, X = 5.") == "vorher\n5\n"
      assert out(c, "freeze(X, write(a)), freeze(X, write(b)), X = 1.") == "ab"
      assert out(c, "freeze(a, write(sofort)).") == "sofort"
      assert ask(c, "freeze(X, fail), X = 1.") == []
      assert ask(c, "freeze(X, Y = 1), X = 2.") == ["X = 2, Y = 1"]
    end

    test "offene Ziele als Restziele, auch über frozen/2", c do
      assert ask(c, "freeze(X, true).") == ["freeze(X, true)"]
      assert ask(c, "freeze(X, true), frozen(X, G).") |> hd() =~ "G = freeze(X, :(user, true))"
      assert ask(c, "frozen(X, G).") == ["G = true"]
      assert ask(c, "frozen(a, G).") == ["G = true"]
    end

    test "Variable an Variable: das Ziel wandert mit", c do
      assert out(c, "freeze(X, write(x)), X = Y, write(gebunden), Y = 3.") == "gebundenx"

      assert out(c, "freeze(X, write(x)), freeze(Y, write(y)), X = Y, write(eq), X = 1.") ==
               "eqyx"

      # normale Variable an attributierte: nichts zu wecken
      assert out(c, "freeze(X, write(x)), Y = X, write(eq), Y = 1.") == "eqx"
    end

    test "Wecken an allen Bindestellen: Klauselkopf, Builtins, is", c do
      assert ask(c, "freeze(X, ausgabe(geweckt)), p(X).") |> length() == 2
      assert out(c, "freeze(X, write(k)), p(X), fail ; true.") == "kk"
      assert out(c, "freeze(X, write(arg)), arg(1, f(a), X).") == "arg"
      assert out(c, "freeze(X, write(is)), X is 1 + 1.") == "is"
      assert out(c, "freeze(X, write(m)), member(X, [1, 2]).") == "mm"
    end

    test "Backtracking nimmt Attribute zurück; \\\\+ und findall", c do
      assert out(c, "(freeze(X, write(nein)), fail ; X = 1).") == ""
      assert out(c, "freeze(X, write(w)), (X = 1 ; X = 2), fail ; true.") == "ww"
      assert out(c, "freeze(X, write(h)), \\+ X = 1.") == "h"

      assert ask(c, "freeze(X, X > 1), findall(X, member(X, [1, 2, 3]), L).") == [
               "L = [2, 3], freeze(X, >(X, 1))"
             ]
    end

    test "Ausnahmen aus geweckten Zielen", c do
      assert ask(c, "catch((freeze(X, throw(oops)), X = 1), E, true).") == ["E = oops"]
    end

    test "Kontextmodul des Ziels", c do
      {db, []} =
        Consult.load(
          c.db,
          Reader.read_terms(c.reader, """
          :- module(m, [setze/1]).
          setze(X) :- freeze(X, privat).
          privat :- write(privat).
          """)
        )

      g = goal(c, "setze(X), X = 1.")
      assert capture_io(fn -> Enum.take(PrologEx.query(db, g), 1) end) == "privat"
    end

    test "Kompaktierung der Substitution behält die Attribute", c do
      assert out(c, "freeze(X, write(da)), zaehle(5000), X = 1.", compact_threshold: 1) == "da"
      assert out(c, "freeze(X, write(w)), X = 1.", compact_threshold: 1) == "w"
      # _Y kommt nur noch im Attribut von X vor; seine Attribute müssen bleiben
      assert ask(c, "dif(_Y, 1), freeze(X, _Y = 1), zaehle(3000), X = a.", compact_threshold: 1) ==
               []

      assert ask(c, "dif(X, a), zaehle(3000), dif(Y, X), zaehle(3000), Y = b.",
               compact_threshold: 1
             ) ==
               ["Y = b, dif(X, a), dif(b, X)"]
    end
  end

  describe "dif/2" do
    test "sofort entschieden oder offen", c do
      assert ask(c, "dif(a, b).") == ["true"]
      assert ask(c, "dif(a, a).") == []
      assert ask(c, "dif(X, a).") == ["dif(X, a)"]
      assert ask(c, "dif(X, a), X = a.") == []
      assert ask(c, "dif(X, a), X = b.") == ["X = b"]
    end

    test "zusammengesetzte Terme und Variablen auf beiden Seiten", c do
      assert ask(c, "dif(f(X, Y), f(1, 2)), X = 1.") == ["X = 1, dif(f(1, Y), f(1, 2))"]
      assert ask(c, "dif(f(X, Y), f(1, 2)), X = 1, Y = 2.") == []
      assert ask(c, "dif(f(X, Y), f(1, 2)), X = 3.") == ["X = 3"]
      assert ask(c, "dif(X, Y), X = Y.") == []
      assert ask(c, "dif(X, Y), Y = X.") == []
      assert ask(c, "dif(X, Y), X = a, Y = b.") == ["X = a, Y = b"]
      assert ask(c, "dif(X, Y), X = a, Y = a.") == []
      assert ask(c, "dif([X|T], [1, 2]), X = 1, T = [2].") == []
      assert ask(c, "dif([X|T], [1, 2]), X = 1, T = [3].") == ["T = [3], X = 1"]
    end

    test "als Generator-Filter", c do
      assert ask(c, "dif(X, b), member(X, [a, b, c]).") == ["X = a", "X = c"]

      assert ask(c, "findall(X-Y, (dif(X, Y), member(X, [1, 2]), member(Y, [1, 2])), L).") ==
               ["L = [-(1, 2), -(2, 1)]"]
    end

    test "?=/2", c do
      assert ask(c, "?=(a, b).") == ["true"]
      assert ask(c, "?=(X, X).") == ["true"]
      assert ask(c, "?=(X, a).") == []
      assert ask(c, "?=(f(X), g(Y)).") == ["true"]
    end
  end

  describe "when/2" do
    test "Bedingungen", c do
      assert out(c, "when(nonvar(X), write(go)), write(vor), X = 1.") == "vorgo"
      assert out(c, "when(ground(f(X, Y)), write(g)), X = 1, write(mitte), Y = 2.") == "mitteg"
      assert out(c, "when(?=(X, Y), write(dec)), X = a, write(mitte), Y = b.") == "mittedec"
      assert out(c, "when(?=(X, Y), write(dec)), X = Y.") == "dec"

      assert out(c, "when((nonvar(X), nonvar(Y)), write(und)), X = 1, write(mitte), Y = 2.") ==
               "mitteund"

      assert out(c, "when(nonvar(a), write(sofort)).") == "sofort"
    end

    test "Disjunktion läuft genau einmal", c do
      assert out(c, "when((nonvar(X) ; nonvar(Y)), write(oder)), Y = 1, X = 2.") == "oder"
      assert out(c, "when((nonvar(X) ; nonvar(Y)), write(oder)), Y = 1.") == "oder"
    end

    test "Restziel und Fehler", c do
      assert ask(c, "when(nonvar(X), true).") == ["when(nonvar(X), true)"]

      assert_raise PrologEx.Error, ~r/domain_error\(when_condition, foo\)/, fn ->
        ask(c, "when(foo, true).")
      end

      assert_raise PrologEx.Error, ~r/instantiation_error/, fn -> ask(c, "when(C, true).") end
    end
  end

  test "ground/1", c do
    assert ask(c, "ground(f(a, [b])).") == ["true"]
    assert ask(c, "ground(f(a, X)).") == []
  end
end
