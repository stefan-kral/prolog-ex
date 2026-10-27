defmodule PrologEx.WriterOpsTest do
  # Writer mit Operatoren: gleiche Ausgabe wie gprologs writeq (über den
  # Reader, '$writeq'), und jede Ausgabe liest sich als derselbe Term.
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  import PrologEx, only: [a: 1, mk: 2, list: 1, v: 1]
  alias PrologEx.{Reader, Writer}

  @moduletag :gprolog
  @cases Path.expand("fixtures/writer/gprolog_cases.txt", __DIR__)

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Ops.reset()
    :ok
  end

  # Term aus kanonischem Text (als Argument gelesen), Variablen einheitlich
  defp read_canonical(r, text) do
    case Reader.read_terms(r, "'$x'(#{text}).") do
      [{:term, t, _}] ->
        {:struct, "$x", [t]} = PrologEx.unmark(t)
        {:ok, PrologEx.copy_fresh(t, %{})}

      _ ->
        :unreadable
    end
  end

  defp norm(s), do: Regex.replace(~r/\b_[BG]?\d+/, s, "_")
  defp canon(t), do: norm(Writer.format(t, quoted: true, ignore_ops: true))

  # bewusste Abweichung von gprolog: nach alphanumerischem Präfix-Operator
  # immer ein Leerzeichen (gprolog: dynamic-a, multifile'x')
  @alpha ~r/\b(dynamic|discontiguous|initialization|meta_predicate|module_transparent|multifile|table|attribute) (?=[^\w\s(])/

  defp check(r, t) do
    ours = Writer.format(t, quoted: true, numbervars: true)
    {:ok, gp} = Reader.gprolog_writeq(r, Writer.format(t, quoted: true, ignore_ops: true))
    ours_n = norm(ours)

    assert ours_n == norm(gp) or
             Regex.replace(@alpha, ours_n, "\\1") == Regex.replace(@alpha, norm(gp), "\\1"),
           "ours: #{ours}  gprolog: #{gp}"

    # wieder einlesen (außer '$VAR': das wird zum Variablennamen)
    unless String.contains?(canon(t), "$VAR") do
      assert [{:term, back, _}] = Reader.read_terms(r, ours <> " .\n"), ours
      assert canon(back) == canon(t), ours
    end
  end

  test "ausgewählte Fälle wie gprolog", c do
    for line <- File.read!(@cases) |> String.split("\n", trim: true) do
      {:ok, t} = read_canonical(c.reader, line)
      check(c.reader, t)
    end
  end

  test "Zufallsterme wie gprolog", c do
    :rand.seed(:exsss, {7, 8, 9})
    ops = PrologEx.Ops.default() |> Map.keys() |> Enum.reject(&(&1 == "|"))
    q = &Writer.atom(&1, %{quoted: true})

    atoms =
      ["a", "foo", "[]", "{}", "'hello world'", "'X'", "'.'", "''", "!", ";", "','", "'|'"] ++
        Enum.map(ops, q)

    leaf = fn ->
      case :rand.uniform(7) do
        1 -> Integer.to_string(:rand.uniform(200) - 100)
        2 -> Float.to_string((:rand.uniform(40) - 20) / 4)
        3 -> Enum.random(["X", "Y", "_"])
        _ -> Enum.random(atoms)
      end
    end

    gen = fn gen, d ->
      if d == 0 or :rand.uniform(3) == 1 do
        leaf.()
      else
        case :rand.uniform(6) do
          1 ->
            "[" <> Enum.map_join(1..:rand.uniform(3), ",", fn _ -> gen.(gen, d - 1) end) <> "]"

          2 ->
            "'{}'(" <> gen.(gen, d - 1) <> ")"

          3 ->
            "f(" <> gen.(gen, d - 1) <> ")"

          _ ->
            f = q.(Enum.random(ops))
            ar = Enum.random([1, 2, 2])
            f <> "(" <> Enum.map_join(1..ar, ",", fn _ -> gen.(gen, d - 1) end) <> ")"
        end
      end
    end

    checked =
      Enum.count(1..600, fn _ ->
        case read_canonical(c.reader, gen.(gen, 4)) do
          {:ok, t} -> check(c.reader, t) || true
          :unreadable -> false
        end
      end)

    assert checked > 550
  end

  test "write_canonical-Form liest sich zurück", c do
    for line <- File.read!(@cases) |> String.split("\n", trim: true) do
      {:ok, t} = read_canonical(c.reader, line)
      text = Writer.format(t, quoted: true, ignore_ops: true)
      assert [{:term, back, _}] = Reader.read_terms(c.reader, text <> " .\n"), text
      assert canon(back) == canon(t), text
    end
  end

  describe "Optionen" do
    test "numbervars, max_depth, spacing, priority, operand, variable_names" do
      t = mk("f", [mk("$VAR", [0]), mk("$VAR", [25]), mk("$VAR", [26]), mk("$VAR", [a("x")])])
      assert Writer.format(t, numbervars: true) == "f(A,Z,A1,$VAR(x))"
      assert Writer.format(t) == "f($VAR(0),$VAR(25),$VAR(26),$VAR(x))"

      assert Writer.format(list([1, 2, 3, 4]), max_depth: 2) == "[1,2|...]"
      assert Writer.format(mk("f", [mk("g", [mk("h", [1])])]), max_depth: 2) == "f(g(...))"

      assert Writer.format(mk("f", [1, list([2, 3])]), spacing: :next_argument) == "f(1, [2, 3])"
      assert Writer.format(mk(",", [a("a"), a("b")]), spacing: :next_argument) == "a, b"

      assert Writer.format(mk(":-", [a("a"), a("b")]), priority: 999) == "(a:-b)"
      assert Writer.format(a("-"), operand: true) == "(-)"
      assert Writer.format(a("-")) == "-"

      x = v("X")
      assert Writer.format(mk("f", [x, v("Y")]), variable_names: %{x => "Foo"}) == "f(Foo,_Y)"
    end

    test "ignore_ops: kanonisch" do
      t = mk(":-", [a("a"), mk(",", [mk("-", [1]), mk("{}", [a("x")])])])
      assert Writer.format(t, quoted: true, ignore_ops: true) == ":-(a,','(-(1),{}(x)))"
    end
  end

  describe "Operatortabelle der Sitzung" do
    defp ask(c, text) do
      [{:term, g, _}] = Reader.read_terms(c.reader, text)

      PrologEx.current_db()
      |> PrologEx.query(g)
      |> Enum.take(1)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    end

    test "op/3 ändert die Ausgabe, Priorität 0 nimmt sie zurück", c do
      PrologEx.put_db(%{})
      assert ask(c, "X = '~~>'(a, b).") == ["X = ~~>(a, b)"]
      assert ask(c, "op(700, xfx, ~~>).") == ["true"]
      assert ask(c, "X = '~~>'(a, b), Y = f('~~>'(a, b)).") == ["X = (a~~>b), Y = f(a~~>b)"]
      assert ask(c, "op(0, xfx, ~~>).") == ["true"]
      assert ask(c, "X = '~~>'(a, b).") == ["X = ~~>(a, b)"]
    end

    test "Operatorname in Hochkommas: Leerzeichen nach einer Ziffer (0'q wäre ein Zeichencode)",
         c do
      PrologEx.put_db(%{})
      assert ask(c, "op(700, xfx, 'q q').") == ["true"]
      t = mk("q q", [0, 2])
      text = Writer.format(t, quoted: true)
      assert text == "0 'q q'2"
      assert [{:term, back, _}] = Reader.read_terms(c.reader, text <> " .\n")
      assert PrologEx.unmark(back) == PrologEx.unmark(t)
    end

    @tag :tmp_dir
    test "Operatoren aus der Exportliste eines Moduls", c do
      file = Path.join(c.tmp_dir, "opmod.pl")
      File.write!(file, ":- module(opmod, [op(200, xfy, ++>)]).\n")
      PrologEx.put_db(%{})
      assert ask(c, "use_module('#{file}').") == ["true"]
      assert ask(c, "X = '++>'(a, '++>'(b, c)).") == ["X = a++>b++>c"]
    end

    test "Operatoren aus Bibliotheken (+\\\\ aus library(lambda))", c do
      PrologEx.put_db(%{})
      assert ask(c, "use_module(library(lambda)).") == ["true"]
      # Leerzeichen zwischen +\\ und \\: sonst ein Token +\\\\
      assert ask(c, "X = '+\\\\'(N, '\\\\'('^'(Y, f(Y, N)))).") == ["X = N+\\ \\Y^f(Y, N)"]
    end
  end

  describe "Ausgabe-Prädikate" do
    defp out(c, text) do
      [{:term, g, _}] = Reader.read_terms(c.reader, text)
      capture_io(fn -> [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1) end)
    end

    test "write, print, writeq, write_canonical, write_term", c do
      PrologEx.put_db(%{})
      t = "f('A b', 1+2*3, (a:-b,c), -(1), [x|T], '$VAR'(1), \"ab\")"

      w = out(c, "write(#{t}).")
      assert w =~ ~r/^f\(A b,1\+2\*3,\(a:-b,c\),- \(1\),\[x\|\w+\],B,\[a,b\]\)$/
      q = out(c, "writeq(#{t}).")
      assert q =~ ~r/^f\('A b',1\+2\*3,\(a:-b,c\),- \(1\),\[x\|\w+\],B,\"ab\"\)$/
      assert out(c, "print(#{t}).") == q
      wc = out(c, "write_canonical(#{t}).")

      # ISO 7.10.5: auch Listen in funktionaler Schreibweise
      assert wc =~
               ~r/^f\('A b',\+\(1,\*\(2,3\)\),:-\(a,','\(b,c\)\),-\(1\),'\.'\(x,\w+\),'\$VAR'\(1\),'\.'\(a,'\.'\(b,\[\]\)\)\)$/

      assert out(c, "write_term(f(X, 'a b'), [quoted(true), variable_names(['Foo'=X])]).") ==
               "f(Foo,'a b')"

      assert out(c, "write_term([1,2,3,4], [max_depth(2)]).") == "[1,2|...]"
      assert out(c, "write_term(1+2, [ignore_ops(true)]).") == "+(1,2)"
      assert out(c, "write_term(f(a,b), [spacing(next_argument)]).") == "f(a, b)"
    end

    test "write_term/2: Fehler", c do
      PrologEx.put_db(%{})

      for {opts, err} <- [
            {"_", "instantiation_error"},
            {"[quoted(true)|_]", "instantiation_error"},
            {"[_]", "instantiation_error"},
            {"foo", "type_error(list, foo)"},
            {"[bogus(1)]", "domain_error(write_option, bogus(1))"},
            {"[quoted(maybe)]", "domain_error(write_option, quoted(maybe))"},
            {"[max_depth(-1)]", "domain_error(write_option, max_depth(-1))"},
            {"[variable_names([1=X])]", "domain_error(write_option"}
          ] do
        [{:term, g, _}] = Reader.read_terms(c.reader, "write_term(a, #{opts}).")
        e = assert_raise(PrologEx.Error, fn -> PrologEx.query(%{}, g) |> Enum.take(1) end)
        assert Exception.message(e) =~ err, opts
      end
    end
  end

  test "listing: portray_clause-Stil mit Wenn-dann-sonst", c do
    program = """
    max(X, Y, Z) :- ( X >= Y -> Z = X ; Z = Y ).
    sign(X, S) :- ( X < 0 -> S = neg ; X =:= 0 -> S = zero ; S = pos ), write(S).
    either(X) :- ( X = a ; X = b, true ), \\+ X == c.
    """

    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, program))

    assert PrologEx.Listing.listing(db, {:atom, "max"}) == """
           max(X, Y, Z) :-
               (   X>=Y
               ->  Z=X
               ;   Z=Y
               ).
           """

    assert PrologEx.Listing.listing(db, {:atom, "sign"}) == """
           sign(X, S) :-
               (   X<0
               ->  S=neg
               ;   X=:=0
               ->  S=zero
               ;   S=pos
               ),
               write(S).
           """

    assert PrologEx.Listing.listing(db, {:atom, "either"}) == """
           either(X) :-
               (   X=a
               ;   X=b,
                   true
               ),
               \\+X==c.
           """
  end
end
