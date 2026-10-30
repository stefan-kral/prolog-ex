defmodule PrologEx.CompareStepTest do
  # compare/3 und @</2 usw. direkt in der Maschine; Fehler und
  # attributiertes Order über das Builtin
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

  defp err(c, g), do: ask(c, "catch((#{g}), error(E, _), true)")

  test "compare/3: Order frei, gebunden, falsch gebunden", c do
    assert ask(c, "compare(O, a, b)") == ["O = (<)"]
    assert ask(c, "compare(O, b, a)") == ["O = (>)"]
    assert ask(c, "compare(O, X, X)") == ["O = (=)"]

    assert ask(c, "compare(O, f(X), f(Y)), compare(P, f(Y), f(X))") |> hd() =~
             ~r/O = \(<\), P = \(>\)|O = \(>\), P = \(<\)/

    assert ask(c, "compare(<, 1, 2)") == ["true"]
    assert ask(c, "compare(=, 1, 1)") == ["true"]
    assert ask(c, "compare(>, 2, 1)") == ["true"]
    assert ask(c, "compare(<, 2, 1)") == []
    assert ask(c, "compare(=, 1, 2)") == []
    assert ask(c, "compare(>, 1, 2)") == []
    assert ask(c, "O = (<), compare(O, 1, 2)") == ["O = (<)"]
    assert ask(c, "compare(O, 1, 2), O == (<)") == ["O = (<)"]
    # Order wird nur einmal gebunden; Backtracking hebt die Bindung auf
    assert ask(c, "(compare(O, 2, 1), fail ; O = frei)") == ["O = frei"]
  end

  test "compare/3: attributiertes Order weckt", c do
    assert ask(c, "freeze(O, X = geweckt), compare(O, a, b)") == ["O = (<), X = geweckt"]
    assert ask(c, "freeze(O, O == (>)), compare(O, a, b)") == []
    assert ask(c, "when(nonvar(O), Y = O), compare(O, 1, 1)") == ["O = (=), Y = (=)"]
  end

  test "compare/3: Fehler wie bisher", c do
    assert err(c, "compare(foo, a, b)") == ["E = domain_error(order,foo)"]
    assert err(c, "compare([], a, b)") == ["E = domain_error(order,[])"]
    assert err(c, "compare(1, a, b)") == ["E = type_error(atom,1)"]
    assert err(c, "compare(f(x), a, b)") == ["E = type_error(atom,f(x))"]
  end

  test "@</2 usw.", c do
    for {g, r} <- [
          {"a @< b", true},
          {"b @< a", false},
          {"a @< a", false},
          {"a @> b", false},
          {"b @> a", true},
          {"a @> a", false},
          {"a @=< b", true},
          {"a @=< a", true},
          {"b @=< a", false},
          {"a @>= b", false},
          {"a @>= a", true},
          {"b @>= a", true},
          {"1.0 @< 1", true},
          {"X @< 1", true},
          {"f(X) @< f(a)", true},
          {"[a] @> f(a)", true},
          {"[a] @< f(a, b, c)", true},
          {"'[]' @< a", true},
          {"[] @> '[]'", false},
          {"[] @< '[]'", false}
        ] do
      assert ask(c, g) == if(r, do: ["true"], else: []), g
    end
  end

  test "lange Listen: Endrekursion", c do
    src = """
    t(O) :- numlist(1, 300000, A), numlist(1, 299999, B0), append(B0, [0], B), compare(O, A, B).
    v(O) :- length(L, 300000), append(L, [x], A), append(L, [y], B), compare(O, A, B).
    """

    assert ask(c, "t(O)", src) == ["O = (>)"]
    assert ask(c, "v(O)", src) == ["O = (<)"]
  end

  @tag timeout: 20_000
  test "spät verschieden: kein quadratischer Aufwand", c do
    src = "rep(0, _, _) :- !. rep(N, A, B) :- A @< B, N1 is N - 1, rep(N1, A, B)."

    assert ask(
             c,
             "length(L, 100000), append(L, [x], A), append(L, [y], B), rep(10, A, B), true",
             src
           )
           |> length() == 1
  end

  test "Inferenzen wie bisher", c do
    d = fn g ->
      [a] =
        ask(
          c,
          "statistics(inferences, A), (#{g} -> true ; true), statistics(inferences, B), D is B - A"
        )

      Regex.run(~r/D = (\d+)/, a) |> List.last() |> String.to_integer()
    end

    base = d.("true")

    for g <- [
          "compare(_, a, b)",
          "compare(<, a, b)",
          "compare(>, a, b)",
          "a @< b",
          "b @< a",
          "a @>= b"
        ],
        do: assert(d.(g) == base, g)
  end
end
