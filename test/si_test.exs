defmodule PrologEx.SiTest do
  use ExUnit.Case, async: false
  import PrologEx, only: [a: 1, mk: 2, list: 1, v: 1]
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = Enum.reduce(["lists", "apply", "si"], %{}, &PrologEx.use_library(&2, &1, "user"))
    {:ok, reader: r, db: db}
  end

  # :true | :fail | :inst | {:error, text} | Antworten
  defp run(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")

    try do
      case c.db |> PrologEx.query(g) |> Enum.take(2) do
        [] ->
          :fail

        [ans] ->
          if map_size(ans) == 0,
            do: true,
            else: PrologEx.format_answer(ans, PrologEx.query_var_names(g))

        more ->
          more
      end
    rescue
      e in PrologEx.Error ->
        msg = Exception.message(e)
        if msg == "instantiation_error", do: :inst, else: {:error, msg}
    end
  end

  test "Typtests", c do
    for {q, exp} <- [
          {"atom_si(_)", :inst},
          {"atom_si(a)", true},
          {"atom_si([])", true},
          {"atom_si(1)", :fail},
          {"atom_si(f(_))", :fail},
          {"integer_si(_)", :inst},
          {"integer_si(1)", true},
          {"integer_si(1.0)", :fail},
          {"integer_si(a)", :fail},
          {"integer_si(f(x))", :fail},
          {"atomic_si(_)", :inst},
          {"atomic_si(1.5)", true},
          {"atomic_si(a)", true},
          {"atomic_si([])", true},
          {"atomic_si(f(_))", :fail},
          {"atomic_si([_])", :fail},
          {"list_si(_)", :inst},
          {"list_si([])", true},
          {"list_si([a,_,c])", true},
          {"list_si([a|_])", :inst},
          {"list_si([a|b])", :fail},
          {"list_si(foo)", :fail},
          {"list_si(f(x))", :fail},
          {"character_si(_)", :inst},
          {"character_si(a)", true},
          {"character_si('ä')", true},
          {"character_si(ab)", :fail},
          {"character_si(1)", :fail},
          {"character_si([])", :fail},
          {"chars_si(_)", :inst},
          {"chars_si([h|_])", :inst},
          {"chars_si(\"hello\")", true},
          {"chars_si([])", true},
          {"chars_si(hello)", :fail},
          {"chars_si([a,_])", :inst},
          {"chars_si([ab,_])", :fail},
          {"chars_si([_,ab])", :inst},
          {"chars_si([a|b])", :fail}
        ] do
      assert run(c, q) == exp, q
    end
  end

  test "dif_si/2", c do
    for {q, exp} <- [
          {"dif_si(a, b)", true},
          {"dif_si(a, a)", :fail},
          {"dif_si(X, X)", :fail},
          {"dif_si(f(X, Y), f(X, Y))", :fail},
          {"dif_si(_, a)", :inst},
          {"dif_si(f(_, a), f(_, b))", true},
          {"dif_si(f(X), f(Y))", :inst},
          {"dif_si([a|_], [b|_])", true},
          {"dif_si(1, 1.0)", true}
        ] do
      assert run(c, q) == exp, q
    end
  end

  test "compare_si/3", c do
    for {q, exp} <- [
          {"compare_si(O, a, b)", "O = (<)"},
          {"compare_si(O, f(a, X), f(b, Y))", "O = (<)"},
          {"compare_si(O, f(X, a), f(X, b))", "O = (<)"},
          {"compare_si(O, f(X, a), f(Y, b))", :inst},
          {"compare_si(O, X, X)", "O = (=)"},
          {"compare_si(O, X, Y)", :inst},
          {"compare_si(O, X, a)", :inst},
          {"compare_si(O, 1, X)", :inst},
          # Stelligkeit und Name entscheiden vor den Argumenten
          {"compare_si(O, f(X), g(Y))", "O = (<)"},
          {"compare_si(O, f(X, Y), g(Z))", "O = (>)"},
          {"compare_si(O, [X|T], foo)", "O = (>)"},
          {"compare_si(O, 1.0, 1)", "O = (<)"},
          {"compare_si(<, a, b)", true},
          {"compare_si(>, a, b)", :fail},
          {"compare_si(foo, a, b)", {:error, "domain_error(order, foo)"}},
          {"compare_si(1, a, b)", {:error, "type_error(atom, 1)"}}
        ] do
      assert run(c, q) == exp, q
    end
  end

  test "sort_si/2, msort_si/2, keysort_si/2", c do
    for {q, exp} <- [
          {"sort_si([cc,aa,bb,aa], L)", "L = [aa, bb, cc]"},
          {"sort_si([X, X], L)", "L = [X]"},
          {"sort_si([X], L)", "L = [X]"},
          {"sort_si([], L)", "L = []"},
          {"sort_si([X, a], L)", :inst},
          {"sort_si([X, Y], L)", :inst},
          {"sort_si([f(a, X), f(b, Y)], L)", "L = [f(a, X), f(b, Y)]"},
          {"sort_si([f(Y, b), f(X, a)], L)", :inst},
          {"sort_si([a|_], L)", :inst},
          {"sort_si(foo, L)", {:error, "type_error(list, foo)"}},
          {"msort_si([bb,aa,bb], L)", "L = [aa, bb, bb]"},
          {"msort_si([X, X], L)", "L = [X, X]"},
          {"msort_si([X, Y], L)", :inst},
          {"keysort_si([b-1, a-X, b-0], L)", "L = [a-X, b-1, b-0]"},
          {"keysort_si([X-1, X-2], L)", "L = [X-1, X-2]"},
          {"keysort_si([K-1, a-2], L)", :inst},
          {"keysort_si([a-1, _], L)", :inst},
          {"keysort_si([a-1, b], L)", {:error, "type_error(pair, b)"}}
        ] do
      assert run(c, q) == exp, q
    end
  end

  test "term_si/1, not_si/1", c do
    for {q, exp} <- [
          {"term_si(a)", true},
          {"term_si(f(a, [1, g(b)]))", true},
          {"term_si(_)", :inst},
          {"term_si(f(a, _))", :inst},
          {"X = b, term_si(f(a, X))", "X = b"},
          {"not_si(1 = 2)", true},
          {"not_si(a = a)", :fail},
          {"not_si(X = a)", :inst},
          {"X = b, not_si(X = a)", "X = b"},
          {"not_si(_)", :inst},
          {"not_si(member(c, [a, b]))", true},
          {"not_si(member(a, [a, b]))", :fail},
          {"not_si(member(_, [a, b]))", :inst},
          # im Kontextmodul gerufen
          {"assertz(q_si(1)), not_si(q_si(2))", true},
          {"assertz(q_si2(1)), not_si(q_si2(1))", :fail}
        ] do
      assert run(c, q) == exp, "#{q}: #{inspect(run(c, q))}"
    end
  end

  test "when_si/2", c do
    for {q, exp} <- [
          {"when_si(nonvar(X), atom(X))", :inst},
          {"X = a, when_si(nonvar(X), atom(X))", "X = a"},
          {"X = 1, when_si(nonvar(X), atom(X))", :fail},
          # Reihenfolge zählt (when/2 gäbe hier X = a)
          {"when_si(nonvar(X), atom(X)), X = a", :inst},
          {"when_si(ground(f(a, X)), true)", :inst},
          {"X = b, when_si(ground(f(a, X)), true)", "X = b"},
          {"when_si(?=(X, X), true)", "true"},
          {"when_si(?=(f(X), g(Y)), true)", "true"},
          {"when_si(?=(f(X), f(Y)), true)", :inst},
          {"when_si((nonvar(X) ; nonvar(a)), true)", "true"},
          {"when_si((nonvar(a), nonvar(X)), true)", :inst},
          {"when_si(foo, true)", {:error, "domain_error(when_condition, foo)"}},
          {"when_si(_, true)", :inst},
          {"when_si(nonvar(a), _)", :inst},
          {"when_si(nonvar(a), (X = 1 ; X = 2))", [%{"X" => 1}, %{"X" => 2}]},
          # Ziel im Kontextmodul
          {"assertz(p_si(7)), when_si(nonvar(a), p_si(X))", "X = 7"}
        ] do
      got = run(c, q)
      assert got == exp, "#{q}: #{inspect(got)}"
    end
  end

  # die Tests lassen sich mit when_si/2 ausdrücken
  test "atom_si/1 und dif_si/2 über when_si/2", c do
    terms = ["_", "a", "1", "f(_)", "f(a)", "[]", "A"]

    for x <- terms, y <- terms do
      assert run(c, "atom_si(#{x})") == run(c, "when_si(nonvar(#{x}), atom(#{x}))"), x

      assert run(c, "A = Z, dif_si(#{x}, #{y})") ==
               run(c, "A = Z, when_si(?=(#{x}, #{y}), #{x} \\== #{y})"),
             "#{x} #{y}"
    end
  end

  test "nur nach use_module sichtbar", c do
    [{:term, g, _}] = Reader.read_terms(c.reader, "atom_si(a).")
    e = assert_raise(PrologEx.Error, fn -> PrologEx.query(%{}, g) |> Enum.take(1) end)
    assert Exception.message(e) =~ "existence_error(procedure, atom_si/1)"
  end

  # compare_si entscheidet nur, was unter jeder Bindung gilt: nach
  # zufälligen Bindungen der Variablen liefert compare/3 dasselbe
  test "compare_si/3 ist korrekt (Eigenschaft)" do
    :rand.seed(:exsss, {11, 12, 13})
    vars = for n <- ~w(A B C), do: v(n)

    gen = fn gen, d ->
      case :rand.uniform(if d == 0, do: 3, else: 5) do
        1 -> Enum.random(vars)
        2 -> Enum.random([a("a"), a("b"), 1, 2, 1.0])
        3 -> Enum.random(vars)
        4 -> mk(Enum.random(["f", "g"]), for(_ <- 1..:rand.uniform(2), do: gen.(gen, d - 1)))
        5 -> list([gen.(gen, d - 1)])
      end
    end

    ground = fn gen, d ->
      case :rand.uniform(if d == 0, do: 2, else: 3) do
        1 -> Enum.random([a("a"), a("b"), 1, 2, 1.0, a("z")])
        2 -> Enum.random([a("c"), 0])
        3 -> mk(Enum.random(["f", "g"]), for(_ <- 1..:rand.uniform(2), do: gen.(gen, d - 1)))
      end
    end

    decided =
      Enum.count(1..2000, fn _ ->
        x = gen.(gen, 3)
        y = gen.(gen, 3)

        case PrologEx.Order.compare_si(x, y, %{}) do
          :undecided ->
            false

          r ->
            for _ <- 1..10 do
              s = Map.new(vars, &{&1, ground.(ground, 2)})
              assert PrologEx.Order.compare(x, y, s) == r
            end

            true
        end
      end)

    # genug entschiedene Fälle, damit der Test etwas prüft
    assert decided > 500
  end
end
