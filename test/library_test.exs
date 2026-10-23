defmodule PrologEx.LibraryTest do
  use ExUnit.Case, async: true
  import PrologEx
  import ExUnit.CaptureIO

  @x v("X")
  @y v("Y")
  @z v("Z")
  @n v("N")
  @l v("L")
  @t v("T")

  defp db, do: consult([fact(s("p", [1]))])

  defp all(goal, limit \\ 20),
    do: db() |> query(goal) |> Enum.take(limit) |> Enum.map(&format_answer/1)

  defp error(goal) do
    assert_raise RuntimeError, fn -> Enum.take(query(db(), goal), 1) end
  end

  # Antworten als Varianten vergleichbar machen: alle Variablen (Anfrage-
  # und frische) in Reihenfolge des ersten Auftretens durchnummerieren
  defp norm(answers) do
    Enum.map(answers, fn ans ->
      terms = ans |> Enum.sort() |> Enum.map(&elem(&1, 1))
      {terms, _} = renumber(terms, %{})
      terms
    end)
  end

  defp renumber({:var, _} = x, m) do
    case Map.fetch(m, x) do
      {:ok, i} -> {{:v, i}, m}
      :error -> {{:v, map_size(m)}, Map.put(m, x, map_size(m))}
    end
  end

  defp renumber({:struct, f, args}, m) do
    {args, m} = Enum.map_reduce(args, m, &renumber/2)
    {{:struct, f, args}, m}
  end

  defp renumber([h | t], m) do
    {h, m} = renumber(h, m)
    {t, m} = renumber(t, m)
    {[h | t], m}
  end

  defp renumber(t, m), do: {t, m}

  describe "false/0" do
    test "scheitert" do
      assert all(a("false")) == []
      assert all(s(";", [a("false"), a("true")])) == ["true"]
    end
  end

  describe "functor/3" do
    test "zerlegt gebundene Terme" do
      assert all(s("functor", [s("f", [a("a"), @y]), @n, @x])) == ["N = f, X = 2"]
      assert all(s("functor", [a("foo"), @n, @x])) == ["N = foo, X = 0"]
      assert all(s("functor", [42, @n, @x])) == ["N = 42, X = 0"]
      assert all(s("functor", [list([1]), @n, @x])) == ["N = ., X = 2"]
      assert all(s("functor", [list([]), @n, @x])) == ["N = [], X = 0"]
    end

    test "baut Terme mit frischen Variablen" do
      [ans] = query(db(), s("functor", [@t, a("g"), 3])) |> Enum.take(1)
      assert {:struct, "g", [{:var, _} = a1, {:var, _} = a2, {:var, _}]} = ans["T"]
      assert a1 != a2
      assert all(s("functor", [@t, a("foo"), 0])) == ["T = foo"]
      assert all(s("functor", [@t, 7, 0])) == ["T = 7"]
      assert all(s("functor", [@t, a("."), 2])) |> hd() =~ ~r/^T = \[_B\d+ \| _B\d+\]$/
    end

    test "prüft" do
      assert all(s("functor", [s("f", [1]), a("f"), 1])) == ["true"]
      assert all(s("functor", [s("f", [1]), a("g"), 1])) == []
    end

    test "Fehler" do
      error(s("functor", [@t, @n, 2]))
      error(s("functor", [@t, a("f"), @n]))
      error(s("functor", [@t, a("f"), -1]))
      error(s("functor", [@t, s("f", [1]), 1]))
      error(s("functor", [@t, 3, 1]))
    end
  end

  describe "=../2" do
    test "zerlegt" do
      assert all(s("=..", [s("f", [a("a"), list([1])]), @l])) == ["L = [f, a, [1]]"]
      assert all(s("=..", [a("foo"), @l])) == ["L = [foo]"]
      assert all(s("=..", [3, @l])) == ["L = [3]"]
      assert all(s("=..", [list([a("a")], a("b")), @l])) == ["L = [., a, b]"]
    end

    test "baut" do
      assert all(s("=..", [@t, list([a("h"), @x, 2])])) == ["T = h(X, 2)"]
      assert all(s("=..", [@t, list([a("foo")])])) == ["T = foo"]
      assert all(s("=..", [@t, list([a("."), 1, list([])])])) == ["T = [1]"]
    end

    test "Fehler" do
      error(s("=..", [@t, @l]))
      error(s("=..", [@t, list([a("f")], @x)]))
      error(s("=..", [@t, list([])]))
      error(s("=..", [@t, list([1, 2])]))
      error(s("=..", [@t, list([s("f", [1])])]))
    end
  end

  describe "append/3" do
    test "erstes Argument fertig: deterministisch, auch mit offenem Rest" do
      assert all(s("append", [list([1, 2]), list([3]), @l])) == ["L = [1, 2, 3]"]
      assert all(s("append", [list([1, @x]), @y, @l])) == ["L = [1, X | Y]"]
      assert all(s("append", [list([]), @y, @l])) == ["L = Y"]
      [{_, more?}] = db() |> solutions(s("append", [list([1, 2]), @y, @l])) |> Enum.take(1)
      refute more?, "fertiges erstes Argument darf keinen Choice Point hinterlassen"
    end

    test "ground Listen bleiben markiert" do
      [ans] = db() |> query(s("append", [list([1, 2]), list([3, 4]), @l])) |> Enum.take(1)
      assert ans["L"] == [1, 2, 3, 4]
      # intern: der Rumpf sieht die Markierung (glist)
      out =
        capture_io(fn ->
          all(s(",", [s("append", [list([1]), list([2]), @l]), s("write", [@l])]))
        end)

      assert out == "[1, 2]"
    end

    test "offenes erstes Argument: klassische Aufzählung" do
      assert all(s("append", [@x, @y, list([1, 2])])) == [
               "X = [], Y = [1, 2]",
               "X = [1], Y = [2]",
               "X = [1, 2], Y = []"
             ]

      assert all(s("append", [list([1], @t), list([a("z")]), list([1, 2, a("z")])])) == [
               "T = [2]"
             ]
    end

    test "Hybrid und klassisch liefern dieselben Lösungen" do
      :rand.seed(:exsss, {7, 7, 7})

      # Elemente dürfen Variablen A, B enthalten; jedes Argument hat seine
      # eigene Rest-Variable (X, Y, Z). So überschneiden sich die Argumente,
      # aber es entstehen ohne Occurs-Check keine zyklischen Terme.
      gen_items = fn ->
        for _ <- 1..:rand.uniform(4)//1, do: Enum.random([1, 2, a("a"), v("A"), v("B")])
      end

      # echte (auch leere), offene oder gar keine Liste
      gen_list = fn tail ->
        items = Enum.drop(gen_items.(), 1)

        case :rand.uniform(4) do
          1 -> list(items, tail)
          2 -> tail
          _ -> list(items)
        end
      end

      # Damit beide Seiten terminieren, ist das erste oder das dritte
      # Argument eine echte Liste (sonst sucht schon die klassische
      # Definition z. B. bei append(X, [1], X) endlos).
      for _ <- 1..500 do
        [a1, a2, a3] = [gen_list.(@x), gen_list.(@y), gen_list.(@z)]
        proper = list(Enum.drop(gen_items.(), 1))
        args = if :rand.uniform(2) == 1, do: [proper, a2, a3], else: [a1, a2, proper]

        hybrid = db() |> query(s("append", args)) |> Enum.take(6) |> norm()
        classic = db() |> query(s("$append", args)) |> Enum.take(6) |> norm()

        assert hybrid == classic,
               "verschieden für append(#{Enum.map_join(args, ", ", &format/1)})"
      end
    end

    test "kann vom Benutzer ersetzt werden" do
      db = consult([fact(s("append", [a("mein"), a("eigenes"), a("append")]))])

      assert db |> query(s("append", [@x, @y, @z])) |> Enum.map(&format_answer/1) ==
               ["X = mein, Y = eigenes, Z = append"]
    end
  end

  describe "length/2" do
    test "echte Liste" do
      assert all(s("length", [list([a("a"), a("b"), a("c")]), @n])) == ["N = 3"]
      assert all(s("length", [list([]), @n])) == ["N = 0"]
      assert all(s("length", [list(Enum.to_list(1..1000)), 1000])) == ["true"]
      assert all(s("length", [list([1, 2]), 3])) == []
    end

    test "Liste erzeugen bei bekannter Länge" do
      [ans] = db() |> query(s("length", [@l, 2])) |> Enum.take(1)
      assert [{:var, _}, {:var, _}] = ans["L"]
      assert all(s("length", [list([a("a")], @t), 3])) |> hd() =~ ~r/^T = \[_B\d+, _B\d+\]$/
      assert all(s("length", [list([a("a"), a("b")], @t), 1])) == []
    end

    test "beides offen: zählt lazy auf" do
      answers = db() |> query(s("length", [@l, @n])) |> Enum.take(3) |> Enum.map(&format_answer/1)
      assert Enum.at(answers, 0) == "L = [], N = 0"
      assert Enum.at(answers, 2) =~ ~r/^L = \[_B\d+, _B\d+\], N = 2$/
      [{_, more?}] = db() |> solutions(s("length", [list([1, 2]), @n])) |> Enum.take(1)
      refute more?
    end

    test "Fehler" do
      error(s("length", [list([1], a("b")), @n]))
      error(s("length", [@l, -1]))
      error(s("length", [@l, a("x")]))
    end
  end

  describe "time/1" do
    test "meldet nur die Zeit, auch bei Fehlschlag, und reicht Lösungen durch" do
      err =
        capture_io(:stderr, fn ->
          assert all(s("time", [s("append", [@x, @y, list([1])])])) == [
                   "X = [], Y = [1]",
                   "X = [1], Y = []"
                 ]
        end)

      assert err =~ ~r/^% \d+\.\d{3} seconds$/m
      refute err =~ "inferences"

      err = capture_io(:stderr, fn -> assert all(s("time", [a("fail")])) == [] end)
      assert err =~ "seconds"
    end

    test "Cut im Ziel ist lokal" do
      capture_io(:stderr, fn ->
        assert all(s("time", [s(",", [s("append", [@x, @y, list([1])]), a("!")])])) == [
                 "X = [], Y = [1]"
               ]
      end)
    end

    test "kein zusätzlicher Choice Point, wenn das Ziel deterministisch ist" do
      capture_io(:stderr, fn ->
        more = fn goal -> db() |> solutions(goal) |> Enum.map(&elem(&1, 1)) end
        assert more.(s("time", [a("true")])) == [false]
        assert more.(s("time", [s("p", [@x])])) == [false]
        assert more.(s("time", [s("numlist", [1, 3, @l])])) == [false]
        # nichtdeterministisch: Choice Point bleibt, bis die letzte Lösung kommt
        assert more.(s("time", [s(";", [s("=", [@x, 1]), s("=", [@x, 2])])])) == [true, false]
      end)
    end
  end

  describe "repeat/0,1" do
    test "repeat/1: genau N Lösungen, nach der letzten kein Choice Point" do
      more = fn goal -> db() |> solutions(goal) |> Enum.map(&elem(&1, 1)) end
      assert more.(s("repeat", [3])) == [true, true, false]
      assert more.(s("repeat", [1])) == [false]
      assert more.(s("repeat", [0])) == []
      assert more.(s("repeat", [-2])) == []
    end

    test "repeat/1: Fehler" do
      error(s("repeat", [@n]))
      error(s("repeat", [a("a")]))
    end

    test "repeat/0: unendlich, lazy, mit Cut beendbar" do
      assert db() |> query(a("repeat")) |> Enum.take(5) |> length() == 5
      assert all(s(",", [a("repeat"), a("!")])) == ["true"]
    end

    test "repeat/0: lange Fehlschlag-Schleife mit konstantem Speicher" do
      # repeat, numlist(1, 10, L), fail  – 200.000 Runden in einem Prozess
      {pid, ref} =
        spawn_monitor(fn ->
          goal = s(",", [a("repeat"), s("numlist", [1, 10, @l])])
          db() |> query(goal) |> Stream.take(200_000) |> Stream.run()
          exit({:memory, Process.info(self(), :memory)})
        end)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:memory, {:memory, bytes}}}, 30_000
      assert bytes < 5_000_000, "Speicher wächst: #{bytes} Bytes"
    end

    test "listing zeigt repeat/1 als Prolog, repeat/0 als Elixir" do
      out = capture_io(fn -> all(s("listing", [a("repeat")])) end)
      assert out =~ "% repeat/0: eingebaut, in Elixir realisiert"
      assert out =~ "repeat(N) :-"
    end
  end

  describe "numlist/2,3" do
    test "baut Listen" do
      assert all(s("numlist", [1, 5, @l])) == ["L = [1, 2, 3, 4, 5]"]
      assert all(s("numlist", [-1, 1, @l])) == ["L = [-1, 0, 1]"]
      assert all(s("numlist", [3, 3, @l])) == ["L = [3]"]
      assert all(s("numlist", [5, 1, @l])) == []
      assert all(s("numlist", [3, @l])) == ["L = [1, 2, 3]"]
      assert all(s("numlist", [1, 3, list([1, 2, 3])])) == ["true"]
    end

    test "Ergebnis ist als ground Liste markiert" do
      [ans] = db() |> query(s("numlist", [1, 3, @l])) |> Enum.take(1)
      assert ans["L"] == [1, 2, 3]
      [{_, more?}] = db() |> solutions(s("numlist", [1, 3, @l])) |> Enum.take(1)
      refute more?
    end

    test "Fehler" do
      error(s("numlist", [@x, 3, @l]))
      error(s("numlist", [1, a("a"), @l]))
    end
  end

  describe "listing für Bibliotheksprädikate" do
    test "Prolog-Quelltext bzw. Hinweis auf Elixir" do
      out = capture_io(fn -> all(s("listing", [a("numlist")])) end)

      assert out ==
               "numlist(N, L) :-\n    numlist(1, N, L).\n\n" <>
                 "% numlist/3: eingebaut, in Elixir realisiert (PrologEx.Builtins.Lists)\n"

      # interne Hilfsprädikate ($append) bleiben verborgen, listing/0 zeigt
      # nur Benutzerprädikate
      out = capture_io(fn -> all(s("listing", [a("$append")])) end)
      assert out == ""
      out = capture_io(fn -> all(a("listing")) end)
      refute out =~ "numlist"
    end
  end

  test "format ist linear: lange Listen" do
    {us, text} = :timer.tc(fn -> format(list(Enum.to_list(1..200_000))) end)
    assert String.starts_with?(text, "[1, 2, 3")
    assert us < 2_000_000
  end

  test "Builtin-Tabelle und Schutz" do
    assert {"functor", 3} in PrologEx.Builtins.keys()
    assert PrologEx.Builtins.protected?({"functor", 3})
    assert PrologEx.Builtins.protected?({",", 2})
    refute PrologEx.Builtins.protected?({"append", 3})
    refute PrologEx.Builtins.protected?({"length", 2})
  end
end
