defmodule PrologEx.WriterTest do
  use ExUnit.Case, async: false
  import PrologEx, only: [a: 1, mk: 2, list: 1, v: 1]
  alias PrologEx.{Reader, Writer}

  # als Argument gelesen: höchstens Priorität 999
  defp q(t), do: Writer.format(t, quoted: true, strings: true, priority: 999)

  test "write_canonical: Listen und {} funktional (ISO 7.10.5, 8.14.2.4)" do
    c = &Writer.format(&1, quoted: true, ignore_ops: true)
    assert c.([1, 2, 3]) == "'.'(1,'.'(2,'.'(3,[])))"
    assert c.([a("a") | v("T")]) == "'.'(a,_T)"
    assert c.({:glist, [1, 2]}) == "'.'(1,'.'(2,[]))"
    assert c.([1 | {:glist, [2]}]) == "'.'(1,'.'(2,[]))"
    assert c.([]) == "[]"
    assert c.(mk("{}", [mk(",", [a("x"), a("y")])])) == "{}(','(x,y))"
    # Zeichenlisten auch bei strings: true nicht als "..."
    assert Writer.format([a("a"), a("b")], quoted: true, ignore_ops: true, strings: true) ==
             "'.'(a,'.'(b,[]))"

    # ohne ignore_ops wie bisher
    assert Writer.format([1, 2], quoted: true) == "[1,2]"
  end

  test "Atome: wann Hochkommas" do
    for n <- ~w(a abc a1 a_B [] {} ! ; + - ** =.. \\+ :- @>= ~) do
      assert q(a(n)) == n, n
    end

    for {n, out} <- [
          {"1", "'1'"},
          {"A", "'A'"},
          {"_x", "'_x'"},
          {"hello world", "'hello world'"},
          {".", "'.'"},
          {",", "','"},
          {"|", "'|'"},
          {"", "''"},
          {"it's", "'it\\\\'s'"},
          {"a\nb", "'a\\\\nb'"},
          {"/*", "'/*'"},
          {"äb", "'äb'"},
          {"a-b", "'a-b'"}
        ] do
      assert q(a(n)) == out |> String.replace("\\\\", "\\"), n
    end
  end

  test "Zeichenlisten als String, andere Listen nicht" do
    assert q(list([a("1"), a("2"), a("3")])) == ~s("123")
    assert q(mk("f", [list([a("a"), a("b")])])) == ~s{f("ab")}
    assert q(list([a("a"), a("bc")])) == "[a,bc]"
    assert q(list([1, 2])) == "[1,2]"
    assert q(list([a("\""), a("\\")])) == ~S("\"\\")
    assert q(PrologEx.cons(a("a"), v("T"))) == "[a|_T]"
    # ohne strings: Liste mit gequoteten Zeichen
    assert Writer.format(list([a("1"), a("2")]), quoted: true) == "['1','2']"
    # write/1: nichts gequotet
    assert Writer.format(list([a("1"), a("hello world")])) == "[1,hello world]"
  end

  describe "über den Reader" do
    setup do
      {:ok, r} = Reader.start_link()
      {:ok, reader: r}
    end

    test "number_chars wie Scryer", %{reader: r} do
      ask = fn text ->
        [{:term, g, _}] = Reader.read_terms(r, text)
        %{} |> PrologEx.query(g) |> Enum.map(&PrologEx.format_answer/1)
      end

      assert ask.("number_chars(123, X).") == [~s(X = "123")]
      assert ask.("number_chars(123, X), X =.. Zs.") == [~s(X = "123", Zs = ['.', '1', "23"])]
      assert ask.("number_chars(X, ['1', '2', '1']).") == ["X = 121"]
    end

    test "writeq-Ausgabe liest sich als derselbe Term", %{reader: r} do
      atoms = [
        "a",
        "1",
        "A",
        "hello world",
        ".",
        ",",
        "|",
        "",
        "it's",
        "a\nb",
        "äb",
        "Äpfel€",
        "[]",
        "{}",
        "+",
        "\\+",
        "/*",
        "%"
      ]

      :rand.seed(:exsss, {4, 5, 6})

      gen = fn gen, d ->
        case :rand.uniform(if d == 0, do: 3, else: 6) do
          1 -> a(Enum.random(atoms))
          2 -> Enum.random([0, -5, 42, 1.5, -0.25, 123_456_789_012_345_678_901])
          3 -> a(Enum.random(["x", "y", "1", "'"]))
          4 -> mk(Enum.random(atoms -- ["", "[]", "{}"]), [gen.(gen, d - 1), gen.(gen, d - 1)])
          5 -> list(for _ <- 1..:rand.uniform(3), do: gen.(gen, d - 1))
          6 -> list(for c <- Enum.take_random(~w(a b c 1 . '), :rand.uniform(4)), do: a(c))
        end
      end

      for _ <- 1..200 do
        t = gen.(gen, 3)
        text = q(t)
        [{:term, back, _}] = Reader.read_terms(r, "'$t'(" <> text <> ").")
        {_, "$t", [b]} = PrologEx.unmark_top(back)
        assert PrologEx.unmark(b) == PrologEx.unmark(t), text
      end
    end
  end
end
