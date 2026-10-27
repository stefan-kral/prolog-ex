defmodule PrologEx.ParserTest do
  # Der Elixir-Reader (PrologEx.Parser): ISO 6.3/6.4, verglichen mit dem
  # gprolog-Reader (conformance/reader_diff.exs für ganze Korpora)
  use ExUnit.Case, async: true
  alias PrologEx.Parser

  # gelesene Terme kanonisch (ohne Operatoren), Fehler als :error
  defp r(text, opts \\ []) do
    opts = Keyword.merge([ops: PrologEx.Ops.default(), double_quotes: "codes"], opts)

    for item <- Parser.read_terms(text, opts) do
      case item do
        {:term, t, _} -> PrologEx.format(t, quoted: true, ignore_ops: true)
        {:error, _} -> :error
      end
    end
  end

  defp r1(text, opts \\ []) do
    [x] = r(text <> " .\n", opts)
    x
  end

  test "Zahlen" do
    assert r1("x(12, 0'a, 0''', 0'\\n, 0' , 0x1F, 0o17, 0b101)") ==
             "x(12,97,39,10,32,31,15,5)"

    assert r1("x(1.5, 1.0e10, 1.0E-2, 0.1e+1)") == "x(1.5,10000000000.0,0.01,1.0)"
    assert r1("123456789012345678901234567890") == "123456789012345678901234567890"
    assert r1("x(1_000_000, 1_000_ 000)") == "x(1000000,1000000)"
    # ISO: Gleitkommazahlen brauchen Nachkommastellen
    assert r1("x(1e10)") == :error
    assert r1("x(1.0e400)") == :error
    assert r1("x(0'')") == :error
  end

  test "negative Zahlen: - vor einer Zahl in Operandenstellung (ISO 6.3.4.1)" do
    assert r1("x(-1, - 1, '-'1, -0'a, - 1.5)") == "x(-1,-1,-1,-97,-1.5)"
    assert r1("x(-(1), - (1), -(-(1)))") == "x(-(1),-(1),-(-(1)))"
    assert r1("x(a-1, a - 1, a- -1, 1 - -1)") == "x(-(a,1),-(a,1),-(a,-1),-(1,-1))"
    assert r1("x(-1^2, - 1^2, -a^2, -(1)^2)") == "x(^(-1,2),^(-1,2),-(^(a,2)),^(-(1),2))"
  end

  test "Operatoren als Atome: Priorität 1201, außer als Argument und in Klammern" do
    assert r1("x(-, [-], f(- , a), [a|-], (-), {-})") == "x(-,'.'(-,[]),f(-,a),'.'(a,-),-,{}(-))"
    assert r1("x(- = a)") == :error
    assert r1("x((-) = a)") == "x(=(-,a))"
    assert r1("x(- - a, \\+ \\+ a)") == "x(-(-(a)),\\+(\\+(a)))"
    assert r1("x(a = \\+)") == :error
    assert r1("x(- (1,2), -(1,2), \\+ (a,b))") == "x(-(','(1,2)),-(1,2),\\+(','(a,b)))"
    assert r1("x('<<'/2)") == :error
    assert r1("x((<<)/2)") == "x(/(<<,2))"
    # allein ist ein Operator ein ganzer Term (wie gprolog), als Operand nicht
    assert r("- .\n:- .\n") == ["-", ":-"]
    assert r1("x :- - ") == :error
    # fx verlangt ein Argument niedrigerer Priorität, fy nicht
    assert r1("x((:- :- a))") == :error
    assert r1("x((?- \\+ \\+ a))") == "x(?-(\\+(\\+(a))))"
  end

  test "Postfixoperatoren, auch neben gleichnamigem Infixoperator" do
    text = ":- op(200, xf, $).\n:- op(700, xfx, $).\nx(a $, a $ b, (a $) $ b).\n"
    assert r(text) |> List.last() == "x($(a),$(a,b),$($(a),b))"
    # xfy: links nur niedrigere Priorität ($ ist 200 wie ^)
    assert r(":- op(200, xf, $).\nx(a $ ^ b).\n") |> List.last() == :error
  end

  test "Präfixoperator über der erlaubten Priorität" do
    assert r1("x(f(:- a))") == :error
    assert r1("x(f((:- a)))") == "x(f(:-(a)))"
    assert r1(":- dynamic foo/1, bar/2") == ":-(dynamic(','(/(foo,1),/(bar,2))))"
  end

  test "Infix, Assoziativität, Komma und Bar" do
    assert r1("x(1+2*3-4, 2^3^4, a:b:c)") == "x(-(+(1,*(2,3)),4),^(2,^(3,4)),:(a,:(b,c)))"
    assert r1("x(a=b=c)") == :error
    assert r1("x(2**3**4)") == :error
    assert r1("(a :- b, c ; d -> e)") == ":-(a,;(','(b,c),->(d,e)))"
    assert r1("x((a|b), (a->b|c))") == "x('|'(a,b),'|'(->(a,b),c))"
    assert r1("x(a|b)") == :error
    assert r1("x(a :- b :- c)") == :error
  end

  test "Funktionsschreibweise nur ohne Leerraum vor der Klammer" do
    assert r1("x(f(a), 'f'(a), -(a))") == "x(f(a),f(a),-(a))"
    assert r1("x(f (a))") == :error
    assert r1("x(f/*c*/(a))") == :error
    assert r1("x(f(a)(b))") == :error
  end

  test "Listen, geschweifte Klammern, [] und {}" do
    assert r1("x([a,b|c], [a|[]], [ ], { }, '[]', '{}', {a,b})") ==
             "x('.'(a,'.'(b,c)),'.'(a,[]),[],{},[],{},{}(','(a,b)))"

    assert r1("x([a|b,c])") == :error
    assert r1("x([a b])") == :error
  end

  test "Quotes und Escapes (ISO 6.4.2.1)" do
    assert r1("x('a''b', '\\x41\\\\101\\', '\\a\\b\\f\\n\\r\\t\\v\\\\\\'\\\"\\`')") ==
             "x('a\\'b','AA','\\a\\b\\f\\n\\r\\t\\v\\\\\\'\"`')"

    assert r1("x('a\\\nb')") == "x(ab)"
    assert r1("x('\\e')") == :error
    assert r1("x('\\x41')") == :error
    assert r1("x('a\nb')") == :error
    assert r1("x('a\tb')") == :error
    assert r1("x(\"a\tb\")") == :error
    assert r1("x(0'\t)") == :error
    assert r1("x('\\x1F600\\')") == "x('😀')"
  end

  test "double_quotes und back_quotes" do
    assert r1(~S{x("ab")}) == "x('.'(97,'.'(98,[])))"
    assert r1(~S{x("ab")}, double_quotes: "chars") == "x('.'(a,'.'(b,[])))"
    assert r1(~S{x("ab", "")}, double_quotes: "atom") == "x(ab,'')"
    assert r1(~S{x("a""b")}, double_quotes: "atom") == "x('a\"b')"
    # Backquotes wie gprolog als Atom, aber mit Escapes (ISO 6.4.7)
    assert r1("x(`a\\nb`)") == "x('a\\nb')"
    assert r1("x(`ab`)", back_quotes: "codes") == "x('.'(97,'.'(98,[])))"
  end

  test "Variablen: Namen, jede _ eine eigene, kein Zusammenstoß mit _N im Text" do
    [{:term, t, names}] = Parser.read_terms("f(X, _, _Y, X, _, _0).", ops: PrologEx.Ops.default())

    assert {:struct, "f",
            [{:var, "X"}, {:var, a1}, {:var, "_Y"}, {:var, "X"}, {:var, a2}, {:var, "_0"}]} = t

    assert a1 != a2 and a1 not in ["_0", "_Y"] and a2 not in ["_0", "_Y"]
    assert names == %{"X" => "X", "_Y" => "_Y", "_0" => "_0"}
  end

  test "Kommentare, Endezeichen, Symbolfolgen" do
    assert r("a. b.%c\nc. /*x*/d.") == ["a", "b", "c", "d"]
    # ISO 6.4.8: nach dem Endepunkt Leerraum oder %, kein /*
    assert r("c./*x*/d.") == [:error]
    assert r("x(a/*c*/= /*c*/b).") == ["x(=(a,b))"]
    # ein Symbolfolge darf /* enthalten, nur nicht damit beginnen
    assert r("x(a/*c*/=/*c*/b).") == [:error]
    assert r("x :- a =.. b.") == [":-(x,=..(a,b))"]
    # Punkt am Dateiende ohne Leerraum
    assert r("a.") == ["a"]
    assert r("a") == [:error]
    assert r("x('abc") == [:error]
    assert r("/* offen") == [:error]
    assert r("  % nur Kommentar\n") == []
  end

  test "Wiederaufsetzen nach Syntaxfehlern" do
    assert r("f( ) :- a. ok.") == [:error, "ok"]
    # in Quotes und 0'. endet nichts; in =.. auch nicht
    assert r("f( ) :- 'a. b', c. ok.") == [:error, "ok"]
    assert r("f( ) :- 0'. , c. ok.") == [:error, "ok"]
    assert r("f( ) :- a =.. b. ok.") == [:error, "ok"]
    # ein Symbolzeichen vor dem Punkt hindert nicht (wie gprolog)
    assert r("f( ) :- ?????.\nok.") == [:error, "ok"]
    assert r("x('\\e'). ok.") == [:error, "ok"]
    assert r("f( ) :- 0'\\', c. ok.") == [:error, "ok"]
  end

  test "Syntaxfehler nennen Zeile und Spalte" do
    assert [{:error, msg}] =
             Parser.read_terms("a.\n  f(,).\n", ops: PrologEx.Ops.default())
             |> Enum.drop(1)

    assert msg =~ "Zeile 2, Spalte 5"
  end

  test "op/3, module/2 und double_quotes-Direktiven gelten für den Rest des Textes" do
    text = """
    :- op(700, xfx, ===>).
    a ===> b.
    :- module(m, [op(200, xfy, ::), p/1]).
    a::b::c.
    :- set_prolog_flag(double_quotes, atom).
    x("s").
    """

    assert r(text) == [
             ":-(op(700,xfx,===>))",
             "===>(a,b)",
             ":-(module(m,'.'(op(200,xfy,::),'.'(/(p,1),[]))))",
             "::(a,::(b,c))",
             ":-(set_prolog_flag(double_quotes,atom))",
             "x(s)"
           ]

    # die Tabelle der Sitzung bleibt unverändert
    refute Map.has_key?(PrologEx.Ops.default(), "===>")
  end

  test "end_of_file beendet den Text; Byte-Order-Mark wird übersprungen" do
    assert r("a.\nend_of_file.\nb.\n") == ["a"]
    assert r(<<0xEF, 0xBB, 0xBF>> <> "a.\n") == ["a"]
  end

  test "Unicode: Großbuchstabe am Anfang ist Variable, Symbole bilden Symbolfolgen" do
    [{:term, t, _}] = Parser.read_terms("f(Ärger, über, →≠).", ops: PrologEx.Ops.default())
    assert {:struct, "f", [{:var, "Ärger"}, {:atom, "über"}, {:atom, "→≠"}]} = PrologEx.unmark(t)
  end

  describe "gleich wie der gprolog-Reader" do
    @describetag :gprolog

    # bewusste Abweichungen: gprolog verbietet NUL in Atomen, liest
    # Backquotes ohne Escapes und 1.0e400 als inf
    @deviations ["x('\\0\\').", "x(`a\\nb`).", "x(1.0e400)."]

    test "conformance/reader_cases.txt" do
      {:ok, reader} = PrologEx.Reader.start_link()

      cases =
        File.read!("conformance/reader_cases.txt")
        |> String.split("\n")
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#") or &1 in @deviations))

      # mehrzeilige Fälle stehen über zwei Zeilen; nur einzeilige vergleichen
      for c <- cases, String.ends_with?(c, ".") do
        g =
          for item <- PrologEx.Reader.read_terms(reader, c <> "\n") do
            case item do
              {:term, t, _} -> PrologEx.format(t, quoted: true, ignore_ops: true)
              {:error, _} -> :error
            end
          end

        assert {c, normalize(r(c <> "\n", double_quotes: "chars"))} == {c, normalize(g)}
      end
    end
  end

  # nach einem Fehler setzt gprolog manchmal früher wieder auf (Folgefehler)
  # anonyme Variablen heißen verschieden
  defp normalize(items) do
    items
    |> Enum.map(fn
      :error -> :error
      s -> Regex.replace(~r/\b_\d+\b/, s, "_")
    end)
    |> Enum.dedup()
  end
end
