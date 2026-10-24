defmodule PrologEx.AttsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.{Consult, Reader}

  @moduletag :gprolog
  @dir Path.expand("fixtures/atts", __DIR__)

  setup do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})

    for f <- ~w(plain spy domain myfreeze),
        do: {:ok, _} = Consult.load_file(Path.join(@dir, f <> ".pl"))

    PrologEx.update_db(&PrologEx.use_library(&1, "lists"))
    {:ok, reader: r}
  end

  defp goal(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    g
  end

  defp ask(c, text, opts \\ []) do
    g = goal(c, text)

    PrologEx.current_db()
    |> PrologEx.query(g, opts)
    |> Enum.take(10)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp out(c, text, opts \\ []), do: capture_io(fn -> send(self(), {:a, ask(c, text, opts)}) end)

  defp err(c, text), do: Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end))

  describe "put_atts/2, get_atts/2" do
    test "setzen, ersetzen, entfernen, abfragen", c do
      assert ask(c, "p(X, a(1)), g(X, a(V)).") |> hd() =~ "V = 1"
      assert ask(c, "p(X, a(1)), p(X, a(2)), g(X, a(V)).") |> hd() =~ "V = 2"
      assert ask(c, "p(X, [a(1), b(2, 3)]), g(X, L).") |> hd() =~ "L = [a(1), b(2, 3)]"
      # Deklarationsreihenfolge, unabhängig von der Setzreihenfolge
      assert ask(c, "p(X, b(2, 3)), p(X, a(1)), g(X, L).") |> hd() =~ "L = [a(1), b(2, 3)]"
      assert ask(c, "p(X, a(1)), p(X, -a(_)), g(X, L).") |> hd() =~ "L = []"
      assert ask(c, "p(X, a(1)), g(X, -b(_, _)), g(X, +a(_)).") |> length() == 1
      assert ask(c, "p(X, a(1)), g(X, -a(_)).") == []
      assert ask(c, "g(X, a(_)).") == []
      assert ask(c, "g(foo, a(_)).") == []
    end

    test "Backtracking nimmt put_atts zurück", c do
      assert ask(c, "(p(X, a(1)), fail ; true), g(X, L).") == ["L = []"]
    end

    test "Fehler", c do
      assert err(c, "p(X, c(1)).") =~ "existence_error(attribute, plain:c/1)"
      assert err(c, "p(foo, a(1)).") =~ "uninstantiation_error(foo)"

      assert err(c, "use_module(library(atts)), put_atts(X, a(1)).") =~
               "existence_error(attribute_declaration, user)"
    end
  end

  describe "verify_attributes/3 (SICStus-Ablauf)" do
    test "alle Hooks sehen alle beteiligten Variablen ungebunden, Goals danach", c do
      assert out(c, "tag(X, x, Y), tag(Y, y, X), f(X, Y) = f(1, 2).") ==
               "hook(x, 1, frei)\nhook(y, 2, frei)\ngoal(x, 1)\ngoal(y, 2)\n"
    end

    test "auch im Klauselkopf und in Builtins", c do
      {db, []} = Consult.load(PrologEx.current_db(), Reader.read_terms(c.reader, "k(7).\n"))
      PrologEx.put_db(db)
      assert out(c, "tag(X, x, _), k(X).") == "hook(x, 7, frei)\ngoal(x, 7)\n"
      assert out(c, "tag(X, x, _), arg(1, f(5), X).") == "hook(x, 5, frei)\ngoal(x, 5)\n"
    end

    test "Scheitern, Alternativen und Ausnahmen des Hooks", c do
      assert ask(c, "domain(X, [a, b]), X = c.") == []
      assert out(c, "mehrfach(X), X = 1, fail ; true.") == "einszwei"
      assert ask(c, "catch((wirft(X), X = 1), E, true).") == ["E = aus_dem_hook"]
    end

    test "Variable an Variable: Hook bekommt die andere Variable", c do
      assert ask(c, "domain(X, [a, b, c]), domain(Y, [b, c, d]), X = Y.") ==
               ["X = Y, domain(Y, \"bc\")"]

      assert ask(c, "domain(X, [a, b]), domain(Y, [b, c]), X = Y.") == ["X = b, Y = b"]
      assert ask(c, "domain(X, [a, b]), domain(Y, [c]), X = Y.") == []

      assert out(c, "myfreeze(X, write(a)), myfreeze(Y, write(b)), X = Y, write(eq), X = 1.") ==
               "eqab"
    end

    test "Hooks aller Attributmodule, auch ohne Attribute dort; freeze danach", c do
      assert out(c, "freeze(X, write(fr)), domain(X, [1, 2]), X = 2.") == "fr"
      assert ask(c, "freeze(X, true), X = 1.") == ["X = 1"]

      assert out(c, "freeze(X, write(fr)), tag(X, x, _), X = 3.") ==
               "hook(x, 3, frei)\ngoal(x, 3)\nfr"
    end

    test "Kompaktierung während der Hooks", c do
      {db, []} =
        Consult.load(
          PrologEx.current_db(),
          Reader.read_terms(c.reader, "z(0) :- !.\nz(N) :- N1 is N - 1, z(N1).\n")
        )

      PrologEx.put_db(db)

      assert ask(c, "domain(X, [1, 2, 3]), z(2000), X = 2, z(2000).", compact_threshold: 1) == [
               "X = 2"
             ]

      assert ask(c, "domain(X, [1, 2, 3]), z(2000), X = 5.", compact_threshold: 1) == []
    end
  end

  describe "Restziele: attribute_goal/2, frozen/2, copy_term/3, term_attvars/2" do
    test "Toplevel zeigt attribute_goal", c do
      assert ask(c, "domain(X, [a, b, c]), domain(X, [a, c]).") == ["domain(X, \"ac\")"]
      assert ask(c, "myfreeze(X, foo).") == ["myfreeze(X, foo)"]
      assert ask(c, "dif(X, a), domain(X, [a, b, c]).") == ["dif(X, a), domain(X, \"abc\")"]
    end

    test "frozen/2 und copy_term/3", c do
      assert ask(c, "domain(X, [a, b]), frozen(X, G).") |> hd() =~
               "G = :(domain, domain(X, \"ab\"))"

      assert ask(c, "frozen(f(a), G).") == ["G = true"]

      [ans] =
        ask(c, "domain(X, [a, b]), copy_term(f(X), C, B), C = f(Y), B = M:domain(Z, D), Y == Z.")

      assert ans =~ "D = \"ab\"" and ans =~ "M = domain"
      assert ask(c, "copy_term(f(X), C, B).") |> hd() =~ "B = true"
      # die Kopie trägt keine Attribute
      assert ask(c, "domain(X, [a, b]), copy_term(X, Y, _), term_attvars(Y, L).") |> hd() =~
               "L = []"
    end

    test "term_attvars/2 folgt Attributen", c do
      [ans] = ask(c, "freeze(X, Y = 1), dif(Y, 2), term_attvars(f(X), L), length(L, N).")
      assert ans =~ "N = 2"
      assert ask(c, "term_attvars(f(X, a), L).") == ["L = []"]
    end
  end
end
