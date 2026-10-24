defmodule PrologEx.BlackboardMutablesTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :gprolog

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)

    db =
      Enum.reduce(["lists", "blackboard", "mutables"], %{}, &PrologEx.use_library(&2, &1, "user"))

    PrologEx.put_db(db)
    :ok
  end

  defp goal(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    g
  end

  # Anfrage auf der Sitzungsdatenbank (bb_put wirkt über Anfragen hinweg)
  defp ask(c, text, opts \\ []) do
    g = goal(c, text)

    PrologEx.current_db()
    |> PrologEx.query(g, opts)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, text), do: Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end))

  # frische Variablen nach Reihenfolge benennen
  defp norm(answers),
    do: Enum.map(answers, &Regex.replace(~r/_B\d+/, &1, "_"))

  describe "library(blackboard)" do
    test "put, get, update, delete", c do
      assert ask(c, "bb_get(k, X).") == []
      assert ask(c, "bb_put(k, f(a)).") == ["true"]
      assert ask(c, "bb_get(k, X).") == ["X = f(a)"]
      assert ask(c, "bb_update(k, f(A), g(A, A)).") == ["A = a"]
      assert ask(c, "bb_get(k, X).") == ["X = g(a, a)"]
      assert ask(c, "bb_update(k, h(_), x).") == []
      assert ask(c, "bb_get(k, X).") == ["X = g(a, a)"]
      assert ask(c, "bb_delete(k, h(_)).") == []
      assert ask(c, "bb_delete(k, X).") == ["X = g(a, a)"]
      assert ask(c, "bb_get(k, X).") == []
      assert ask(c, "bb_delete(k, X).") == []
      assert ask(c, "bb_update(k, _, 1).") == []
    end

    test "gespeichert wird eine Kopie (Variablen frisch, Sharing erhalten)", c do
      assert ask(c, "bb_put(k, f(X, Y, X)), X = 1.") == ["X = 1"]
      assert norm(ask(c, "bb_get(k, T).")) == ["T = f(_, _, _)"]
      assert ask(c, "bb_get(k, f(A, B, C)), A == C, A \\== B.") |> length() == 1
      # bb_update speichert New mit den Bindungen aus Old
      assert ask(c, "bb_put(n, 1), bb_update(n, X, s(X)), bb_get(n, V).") ==
               ["V = s(1), X = 1"]
    end

    test "nicht backtrackbar", c do
      assert ask(c, "(bb_put(c, 1) ; bb_put(c, 2)), fail.") == []
      assert ask(c, "bb_get(c, V).") == ["V = 2"]

      assert ask(
               c,
               "bb_put(c, 0), between(1, 5, I), bb_get(c, V), W is V + I, bb_put(c, W), fail."
             ) == []

      assert ask(c, "bb_get(c, V).") == ["V = 15"]
    end

    test "Schlüssel: Atom oder Ganzzahl, je Modul", c do
      assert ask(c, "bb_put(1, eins), bb_put([], leer), bb_get(1, A), bb_get([], B).") ==
               ["A = eins, B = leer"]

      assert ask(
               c,
               "bb_put(k, user), bb_put(m:k, m), bb_get(k, A), bb_get(m:k, B), bb_get(user:k, C)."
             ) ==
               ["A = user, B = m, C = user"]

      assert ask(c, "bb_put(a:b:k, 1), bb_get(b:k, V).") == ["V = 1"]
    end

    test "Fehler", c do
      assert err(c, "bb_put(K, 1).") =~ "instantiation_error"
      assert err(c, "bb_get(f(x), V).") =~ "type_error(atomic, f(x))"
      assert err(c, "bb_put(1.5, x).") =~ "type_error(atomic, 1.5)"
      assert err(c, "bb_put(M:k, 1).") =~ "instantiation_error"
      assert err(c, "bb_put(1:k, 1).") =~ "type_error(atom, 1)"
    end

    test "nur nach use_module sichtbar", c do
      PrologEx.put_db(%{})
      assert err(c, "bb_put(k, 1).") =~ "existence_error(procedure, bb_put/2)"
      assert ask(c, "use_module(library(blackboard)), bb_put(k, 1), bb_get(k, V).") == ["V = 1"]
    end
  end

  describe "library(mutables)" do
    test "anlegen, lesen, ändern", c do
      assert ask(c, "create_mutable(a, M), get_mutable(V, M).") == ["M = '$mutable'(a), V = a"]

      assert ask(c, "create_mutable(a, M), update_mutable(b, M), get_mutable(V, M).") ==
               ["M = '$mutable'(b), V = b"]

      assert ask(c, "create_mutable(a, M), get_mutable(b, M).") == []
      assert ask(c, "create_mutable(1, M), mutable(M).") == ["M = '$mutable'(1)"]
      assert ask(c, "mutable(foo).") == []
      assert ask(c, "mutable(X).") == []
      assert ask(c, "mutable('$mutable'(X)).") == []
      # Zelle mit fremdem Attribut ist kein Mutable
      assert ask(c, "freeze(X, true), mutable('$mutable'(X)).") == []
    end

    test "Zuweisung wird beim Backtracking zurückgenommen", c do
      assert ask(c, "create_mutable(0, M), (update_mutable(1, M), fail ; get_mutable(V, M)).") ==
               ["M = '$mutable'(0), V = 0"]

      assert ask(
               c,
               "create_mutable(0, M), (update_mutable(1, M) ; update_mutable(2, M)), get_mutable(V, M)."
             ) ==
               ["M = '$mutable'(1), V = 1", "M = '$mutable'(2), V = 2"]
    end

    test "Wert wird nicht kopiert", c do
      assert ask(c, "create_mutable(f(X), M), X = 1, get_mutable(V, M).") ==
               ["M = '$mutable'(f(1)), V = f(1), X = 1"]
    end

    test "Anzeige: Wert statt Zelle, auch verschachtelt und zyklisch", c do
      assert ask(c, "create_mutable(1, A), create_mutable(A, B), update_mutable(2, A).") ==
               ["A = '$mutable'(2), B = '$mutable'('$mutable'(2))"]

      [answer] = ask(c, "create_mutable(0, M), update_mutable(f(M), M).")
      assert answer =~ ~r/^M = '\$mutable'\(f\('\$mutable'\(_V\d+\)\)\)$/

      assert ask(c, "create_mutable(1, M), L = [a|M].") ==
               ["L = [a|'$mutable'(1)], M = '$mutable'(1)"]

      # Restziele von Variablen im Wert
      assert ask(c, "create_mutable(f(X), M), freeze(X, true).") ==
               ["M = '$mutable'(f(X)), freeze(X, true)"]
    end

    test "viele Änderungen, auch bei Kompaktierung in jedem Schritt", c do
      program = """
      sum(M, I, N) :- I > N, !, get_mutable(_, M).
      sum(M, I, N) :- get_mutable(V0, M), V is V0 + I, update_mutable(V, M), I1 is I + 1, sum(M, I1, N).
      """

      {db, []} =
        PrologEx.Consult.load(PrologEx.current_db(), Reader.read_terms(c.reader, program))

      PrologEx.put_db(db)

      for t <- [4096, 1] do
        assert ask(c, "create_mutable(0, M), sum(M, 1, 2000), get_mutable(V, M).",
                 compact_threshold: t
               ) ==
                 ["M = '$mutable'(2001000), V = 2001000"]
      end
    end

    test "Fehler", c do
      assert err(c, "create_mutable(X, M).") =~ "instantiation_error"
      assert err(c, "create_mutable(1, M), update_mutable(X, M).") =~ "instantiation_error"
      assert err(c, "get_mutable(V, M).") =~ "instantiation_error"
      assert err(c, "get_mutable(V, foo).") =~ "type_error(mutable, foo)"
      assert err(c, "update_mutable(1, f(x)).") =~ "type_error(mutable, f(x))"
    end
  end
end
