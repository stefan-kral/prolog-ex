defmodule PrologEx.ListUtilsTest do
  use ExUnit.Case, async: false
  alias PrologEx.{Consult, Reader}

  setup_all do
    {:ok, r} = Reader.start_link()

    prog = """
    :- use_module(library(lists)).
    :- use_module(library(apply)).
    add(X, A0, A) :- A is A0 + X.
    add2(X, Y, A0, A) :- A is A0 + X * Y.
    ref_max_list([H|T], R) :- lists:'$max_list'(T, H, R).
    ref_min_list([H|T], R) :- lists:'$min_list'(T, H, R).
    ref_max_member(R, [H|T]) :- lists:'$max_member'(T, H, R).
    ref_min_member(R, [H|T]) :- lists:'$min_member'(T, H, R).
    ref_memberchk(X, L) :- member(X, L), !.
    """

    {db, []} = Consult.load(%{}, Reader.read_terms(r, prog))
    {:ok, reader: r, db: db}
  end

  defp goal(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    g
  end

  defp ask(c, text, n \\ 20),
    do:
      c.db |> PrologEx.query(goal(c, text)) |> Enum.take(n) |> Enum.map(&PrologEx.format_answer/1)

  defp det?(c, text),
    do: c.db |> PrologEx.solutions(goal(c, text)) |> Enum.map(&elem(&1, 1)) == [false]

  defp err(c, text), do: Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end))

  test "last/2, reverse/2, proper_length/2", c do
    assert ask(c, "last([1, 2, 3], X).") == ["X = 3"]
    assert det?(c, "last([1, 2, 3], X).")
    assert ask(c, "last([], X).") == []
    assert [a1, a2] = ask(c, "last(L, x).", 2)
    assert a1 == "L = \"x\""
    assert a2 =~ ~r/^L = \[_\w+,x\]$/

    assert ask(c, "reverse([1, 2, 3], X).") == ["X = [3,2,1]"]
    assert det?(c, "reverse([1, 2, 3], X).")
    assert ask(c, "reverse(X, [1, 2, 3]).") == ["X = [3,2,1]"]
    assert ask(c, "reverse([1|T], [3, 2, 1]).") == ["T = [2,3]"]
    assert ask(c, "reverse([], X).") == ["X = []"]

    assert ask(c, "proper_length([a, b], N).") == ["N = 2"]
    assert ask(c, "proper_length([a, b|_], N).") == []
    assert ask(c, "proper_length(foo, N).") == []
  end

  test "sum_list/2, max_list/2, min_list/2", c do
    assert ask(c, "sum_list([1, 2.5, 3], S).") == ["S = 6.5"]
    assert ask(c, "sum_list([], S).") == ["S = 0"]
    assert ask(c, "sumlist([1, 2], S).") == ["S = 3"]
    # Ausdrücke werden wie in SWI ausgerechnet
    assert ask(c, "sum_list([1 + 1, 2], S).") == ["S = 4"]

    assert ask(c, "sum_list([123456789012345678901234567890, 1], S).") ==
             ["S = 123456789012345678901234567891"]

    assert ask(c, "max_list([3, 1, 4, 1, 5], M).") == ["M = 5"]
    assert ask(c, "min_list([3, 1, 4, 1, 5], M).") == ["M = 1"]
    assert ask(c, "max_list([2.5, 1.5], M).") == ["M = 2.5"]
    assert ask(c, "max_list([], M).") == []
    assert ask(c, "max_list([1, 3 - 1, 0], M).") == ["M = 2"]
    assert err(c, "sum_list([a], S).") =~ "type_error"
  end

  test "member/2 mit gebundenem X: unpassende Zellen ohne Choice Point übersprungen", c do
    assert ask(c, "member(b, [a, b, c, b]).") == ["true", "true"]

    assert ask(c, "member(f(X), [a, g(1), f(1), Y, f(2, 3), [f(2)]]).") ==
             ["X = 1", "Y = f(X)"]

    assert ask(c, "member([H|_], [a, [], [1], f(x), [2, 3]]).") == ["H = 1", "H = 2"]
    assert ask(c, "member(1, [1.0, 1, X]).") == ["true", "X = 1"]
    assert ask(c, "member(1.0, [1, 1.0]).") == ["true"]

    assert ask(c, "member(a, [B, a, C | T]).") |> Enum.take(4) == [
             "B = a",
             "true",
             "C = a",
             "T = [a|_A]"
           ]

    # letzte passende Zelle am Listenende: deterministisch
    assert det?(c, "member(c, [a, b, c]).")
    assert det?(c, "member(c, [c, b, a]).") == false
    assert ask(c, "member(z, [a, b | c]).") == []
    assert det?(c, "member(c, [a, f(_), c]).")
    assert det?(c, "member(f(1), [a, f(_)]).")
  end

  test "member/2: Filter aus dem ersten Argument" do
    import PrologEx, only: [a: 1, mk: 2, v: 1]
    alias PrologEx.Builtins.Lists
    m = fn x, h -> Lists.member_match(Lists.member_key(x), h) end

    assert m.(a("a"), a("a")) == :eq
    assert m.(a("a"), a("b")) == :skip
    assert m.(1, 1) == :eq
    assert m.(1, 1.0) == :skip
    assert m.(1.0, 1.0) == :unify
    assert m.(1.0, 1) == :skip
    assert m.(1, v("X")) == :unify
    assert m.(mk("f", [v("X")]), mk("f", [1])) == :unify
    assert m.(mk("f", [v("X")]), mk("f", [1, 2])) == :skip
    assert m.(mk("f", [v("X")]), mk("g", [1])) == :skip
    assert m.(mk("f", [v("X")]), a("f")) == :skip
    assert m.([v("H") | v("T")], PrologEx.list([1])) == :unify
    assert m.([v("H") | v("T")], [v("H") | v("T")]) == :unify
    assert m.([v("H") | v("T")], []) == :skip
    assert m.([v("H") | v("T")], mk("f", [1, 2])) == :skip
    assert m.(v("X"), a("a")) == :unify
  end

  test "max_member/2, min_member/2: Standardordnung", c do
    assert ask(c, "max_member(M, [b, f(a), 3, a]).") == ["M = f(a)"]
    assert ask(c, "min_member(M, [b, f(a), 3, a]).") == ["M = 3"]
    assert ask(c, "min_member(M, [b, X, 3]).") == ["M = X"]
    assert ask(c, "max_member(M, []).") == []
    assert det?(c, "max_member(M, [1, 2]).")
  end

  test "memberchk/2, delete/3, list_to_set/2, nextto/3", c do
    assert ask(c, "memberchk(X, [a, b]).") == ["X = a"]
    assert det?(c, "memberchk(b, [a, b, c, b]).")
    assert ask(c, "memberchk(f(X), [a, f(1), f(2)]).") == ["X = 1"]
    assert ask(c, "memberchk(z, [a, b]).") == []
    assert [ans] = ask(c, "memberchk(x, L).")
    assert ans =~ ~r/^L = \[x\|_\w+\]$/

    assert ask(c, "delete([a, b, a, c], a, R).") == ["R = \"bc\""]
    assert ask(c, "delete([f(1), g(2), f(3)], f(_), R).") == ["R = [g(2)]"]
    # unifizierbar heißt: auch die Variable B fällt weg, ohne gebunden zu werden
    assert ask(c, "delete([a, B, c], a, R).") == ["R = \"c\""]

    assert ask(c, "list_to_set([a, b, a, 1, 1.0, X, Y, X], S).") == ["S = [a,b,1,1.0,X,Y]"]
    assert err(c, "list_to_set(L, S).") =~ "instantiation_error"

    assert ask(c, "nextto(X, Y, [1, 2, 3]).") == ["X = 1, Y = 2", "X = 2, Y = 3"]
  end

  test "subtract/3, intersection/3, union/3", c do
    assert ask(c, "subtract([1, 2, 3, 4], [2, 4], R).") == ["R = [1,3]"]
    assert ask(c, "intersection([1, 2, 3], [3, 1, 5], I).") == ["I = [1,3]"]
    assert ask(c, "union([1, 2], [2, 3], U).") == ["U = [1,2,3]"]
  end

  test "include/3, exclude/3, partition/4, foldl/4..6", c do
    assert ask(c, "include(integer, [a, 1, b, 2], I).") == ["I = [1,2]"]
    assert ask(c, "exclude(integer, [a, 1, b, 2], I).") == ["I = \"ab\""]
    assert ask(c, "partition(integer, [a, 1, b, 2], I, E).") == ["E = \"ab\", I = [1,2]"]
    assert det?(c, "include(integer, [a, 1, b, 2], I).")
    assert ask(c, "foldl(add, [1, 2, 3], 0, S).") == ["S = 6"]
    assert ask(c, "foldl(add2, [1, 2], [3, 4], 0, S).") == ["S = 11"]
    assert ask(c, "foldl(add, [], 0, S).") == ["S = 0"]
  end

  test "Antworten: Variablenketten und frische Variablen wie SWI", c do
    show = fn text ->
      g = goal(c, text)
      [ans | _] = PrologEx.query(c.db, g) |> Enum.take(1)
      PrologEx.format_answer(ans, PrologEx.query_var_names(g))
    end

    assert show.("reverse([Y, 2], R).") == "R = [2,Y]"
    assert show.("lists:'$reverse'([Y, 2], R, [], R).") == "R = [2,Y]"
    assert show.("X = Y, Y = Z.") == "X = Y, Y = Z"
    assert show.("Y = X.") == "Y = X"
    assert show.("X = f(A), A = B.") == "A = B, X = f(B)"
    assert show.("min_member(R, [Y, 2]).") == "R = Y"
  end

  # Elixir-Schnellweg gegen die Prolog-Definition aus der Bibliothek
  test "Schnellwege == Prolog-Definitionen", c do
    :rand.seed(:exsss, {3, 1, 4})

    for _ <- 1..150 do
      l =
        for _ <- 1..(:rand.uniform(7) - 1)//1,
            do: Enum.random(["1", "2", "3", "2.5", "a", "b", "f(a)", "f(X)", "[]", "Y"])

      ints = for _ <- 1..:rand.uniform(6), do: Integer.to_string(:rand.uniform(50) - 25)
      lt = "[" <> Enum.join(l, ", ") <> "]"
      it = "[" <> Enum.join(ints, ", ") <> "]"

      pairs = [
        {"last(#{lt}, R)", "lists:'$last'(#{lt}, R)"},
        {"reverse(#{lt}, R)", "lists:'$reverse'(#{lt}, R, [], R)"},
        {"delete(#{lt}, f(_), R)", "lists:'$delete'(#{lt}, f(_), R)"},
        {"delete(#{lt}, 2, R)", "lists:'$delete'(#{lt}, 2, R)"},
        {"sum_list(#{it}, R)", "lists:'$sum_list'(#{it}, 0, R)"},
        {"max_list(#{it}, R)", "ref_max_list(#{it}, R)"},
        {"min_list(#{it}, R)", "ref_min_list(#{it}, R)"},
        {"max_member(R, #{lt})", "ref_max_member(R, #{lt})"},
        {"min_member(R, #{lt})", "ref_min_member(R, #{lt})"},
        {"memberchk(f(R), #{lt})", "ref_memberchk(f(R), #{lt})"}
      ]

      for {fast, slow} <- pairs do
        assert ask(c, fast <> ".", 1) == ask(c, slow <> ".", 1), "#{fast} vs #{slow}"
      end
    end
  end
end
