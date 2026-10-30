defmodule PrologEx.IdenticalTest do
  # ==/2 und \==/2: direkt in der Maschine über Order.equal?/3 – oben ein
  # ===, innen strukturell; Grenzfälle entscheidet compare/3
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    :ok
  end

  defp db(c, src) do
    libs = Enum.reduce(["lists", "swi"], %{}, &PrologEx.use_library(&2, &1))
    {db, []} = PrologEx.Consult.load(libs, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    db
  end

  defp goal(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")
    g
  end

  defp ask(c, q, src \\ "") do
    db = db(c, src)
    g = goal(c, q)

    db
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp yes?(c, g, src \\ "") do
    case ask(c, "(#{g}) -> R = ja ; R = nein", src) do
      [a] -> a =~ "R = ja"
    end
  end

  test "einfache Fälle", c do
    assert yes?(c, "X == X")
    refute yes?(c, "X == Y")
    assert yes?(c, "X = Y, X == Y")
    assert yes?(c, "a == a")
    refute yes?(c, "a == b")
    refute yes?(c, "a == ab")
    assert yes?(c, "1 == 1")
    refute yes?(c, "1 == 2")
    refute yes?(c, "1 == 1.0")
    assert yes?(c, "1.5 == 1.5")
    assert yes?(c, "X is 10 ** 30, Y is 10 ** 30, X == Y")
    assert yes?(c, "[] == []")
    refute yes?(c, "[] == a")
    refute yes?(c, "a == f(a)")
    refute yes?(c, "X == a")
    refute yes?(c, "a == X")
    refute yes?(c, "X == f(X)")
    assert yes?(c, "a \\== b")
    refute yes?(c, "X \\== X")
    assert yes?(c, "X \\== Y")
  end

  test "zusammengesetzt", c do
    assert yes?(c, "f(a, b, c) == f(a, b, c)")
    refute yes?(c, "f(a, b, c) == f(a, b, d)")
    refute yes?(c, "f(a, b) == g(a, b)")
    refute yes?(c, "f(a, b) == f(a, b, c)")
    refute yes?(c, "f(a) == [a]")
    assert yes?(c, "A = f(X, Y), B = f(X, Y), A == B")
    refute yes?(c, "g(1, X) == g(1, Y)")
    assert yes?(c, "X = 1, Y = 1, g(1, X) == g(1, Y)")
    refute yes?(c, "X = 1, Y = 2, g(X) == g(Y)")
    # oben verschieden, innen entschieden (kein === oben)
    refute yes?(c, "f(a, X) == f(b, X)")
    refute yes?(c, "[a, X] == [b, X]")
    assert yes?(c, "X = 1.5, f(X) == f(1.5)")
    refute yes?(c, "X = 1.5, f(X) == f(2.5)")
    assert yes?(c, "X is -0.0, f(X) == f(0.0)")
    assert yes?(c, "X = '.'(a, []), f(X) == f([a])")
    assert yes?(c, "[a, B, c] == [a, B, c]")
    refute yes?(c, "[a, b] == [a, b, c]")
    refute yes?(c, "[a, b | T] == [a, b]")
    assert yes?(c, "[a, b | T] == [a, b | T]")
    refute yes?(c, "[a | b] == [a | c]")
    assert yes?(c, "atom_chars(A, \"abc\"), atom_chars(B, \"abc\"), A == B")
  end

  # gleich wie compare/3: Darstellung und Markierung spielen keine Rolle
  test "Grenzfälle wie compare/3", c do
    assert yes?(c, "'[]' == []")
    assert yes?(c, "'.'(a, []) == [a]")
    assert yes?(c, "[a] == '.'(a, [])")
    refute yes?(c, "'.'(a, []) == [b]")
    assert yes?(c, "X is -0.0, Y is 0.0, compare(=, X, Y), X == Y")
    # markiert (ground, aus dem Programm) gegen zur Laufzeit gebaut
    assert yes?(c, "p(T), X = 2, T == f([1, X], g(X))", "p(f([1,2], g(2))).")
    assert yes?(c, "p(T), X = 2, f([1, X], g(X)) == T", "p(f([1,2], g(2))).")
    assert yes?(c, "p(T), numlist(1, 3, L), T == L", "p([1,2,3]).")
    assert yes?(c, "numlist(1, 3, L), M = [1, X, 3], X = 2, L == M")
    assert yes?(c, "freeze(X, true), X == X")
    refute yes?(c, "freeze(X, true), X == Y")
    assert yes?(c, "freeze(X, true), Y = X, X == Y")
  end

  test "lange Terme: Endrekursion, linear auch bei spätem Unterschied", c do
    assert yes?(c, "numlist(1, 300000, A), numlist(1, 300000, B), A == B")
    assert yes?(c, "length(A, 300000), copy_term(A, B), A = B, A == B")
    assert yes?(c, "length(A, 300000), length(B, 300000), A \\== B")

    assert yes?(
             c,
             "t(100000, A), t(100000, B), A == B",
             "t(0, z) :- !. t(N, f(N, T)) :- N1 is N - 1, t(N1, T)."
           )
  end

  # quadratisch (=== auf jeder Ebene) bräuchte hier Minuten
  @tag timeout: 20_000
  test "spät verschieden: kein quadratischer Aufwand", c do
    q = "length(L, 100000), append(L, [x], A), append(L, [y], B)"

    assert yes?(
             c,
             "#{q}, rep(10, A, B)",
             "rep(0, _, _) :- !. rep(N, A, B) :- A \\== B, N1 is N - 1, rep(N1, A, B)."
           )

    q2 = "numlist(1, 100000, A), numlist(1, 99999, B0), append(B0, [0], B)"

    assert yes?(
             c,
             "#{q2}, rep(10, A, B)",
             "rep(0, _, _) :- !. rep(N, A, B) :- A \\== B, N1 is N - 1, rep(N1, A, B)."
           )
  end

  test "geschützt, in Modulen, Inferenzen wie bisher", c do
    assert yes?(c, "lists:(a == a)")
    assert yes?(c, "call(==, a, a)")
    assert yes?(c, "G = (a \\== b), call(G)")

    assert ask(c, "catch(assertz((a == b)), error(E, _), true)") ==
             ["E = permission_error(modify,static_procedure,(==)/2)"]

    d = fn g ->
      [a] =
        ask(
          c,
          "statistics(inferences, A), (#{g} -> true ; true), statistics(inferences, B), D is B - A"
        )

      Regex.run(~r/D = (\d+)/, a) |> List.last() |> String.to_integer()
    end

    base = d.("true")
    assert d.("a == a") == base
    assert d.("a == b") == base
    assert d.("a \\== b") == base
  end
end
