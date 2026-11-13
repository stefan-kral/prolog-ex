defmodule PrologEx.JsonTest do
  # library(http/json) (SWI, klassische Darstellung) und
  # library(serialization/json) (Scryer, json_chars//1). Die Erwartungen
  # für http/json sind Ausgaben von SWI-Prolog 9.0.4 (Fehlerposition
  # stream(S, Zeile, Spalte, Zeichen) eingeschlossen); Abweichungen sind
  # vermerkt
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    prog = """
    :- use_module(library(http/json)).
    :- use_module(library(serialization/json)).
    :- use_module(library(lists)).
    :- use_module(library(dcgs)).
    :- use_module(library(swi)).
    r(A, T) :- r(A, T, []).
    r(A, T, O) :- catch(atom_json_term(A, T, O), error(E, stream(_, L, P, C)), T = err(E, L, P, C)).
    % Ausgabe über with_output_to: der Stream beginnt in Spalte 0
    w(T) :- w(T, []).
    w(T, O) :- out(json_write(current_output, T, O)).
    we(T, O, E) :- out(catch(json_write(current_output, T, O), error(E, _), true)).
    out(G) :- with_output_to(chars(Cs), G), atom_chars(A, Cs), write(A).
    """

    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, prog))
    {:ok, reader: r, db: db}
  end

  defp check(c, q, expect) do
    Reader.put_current(c.reader)
    actual = TableCase.run(c.reader, c.db, q)

    assert TableCase.matches?(expect, actual),
           "#{q}\nerwartet: #{inspect(expect)}\nerhalten: #{inspect(actual)}"
  end

  # --- Lesen ---------------------------------------------------------------

  @reads [
    {"'1'", "1"},
    {"'-0'", "0"},
    {"'01'", "1"},
    {"'1.'", "1"},
    {"'1e5'", "100000.0"},
    {"'1E+5'", "100000.0"},
    {"'-1.5e-3'", "-0.0015"},
    {"'12345678901234567890123'", "12345678901234567890123"},
    {"'1.50'", "1.5"},
    {"'-1.0E2'", "-100.0"},
    {"'.5'", "err(syntax_error(json(illegal_json)),1,1,1)"},
    {"'+1'", "err(syntax_error(json(illegal_json)),1,1,1)"},
    {"'1.5e'", "err(syntax_error(illegal_number),1,4,4)"},
    {"'1e400'", "err(syntax_error(illegal_number),1,5,5)"},
    {"'\"a\\\\u00e9b\"'", "aéb"},
    {"'\"tab\\there\"'", "'tab\\there'"},
    {"'\"\\\\/\"'", "(/)"},
    {"'\"bad\\\\x\"'", "err(syntax_error(json(illegal_string_escape)),1,6,6)"},
    {"'\"\\\\u00\"'", "err(syntax_error(json(illegal_string_escape)),1,6,6)"},
    {"'\"unterminated'", "err(syntax_error(json(eof_in_string)),1,13,13)"},
    {"'[1,2,]'", "[1,2]"},
    {"'{\"a\":1,}'", "json([a=1])"},
    {"'{\"a\" : 1 , \"b\":[ ]}'", "json([a=1,b=[]])"},
    {"'{\"1\":2}'", "json(['1'=2])"},
    {"' // c\\n 1'", "err(syntax_error(json(illegal_json)),1,2,2)"},
    {"'true'", "@(true)"},
    {"'tru'", "err(syntax_error(json(json_expected(true))),1,3,3)"},
    {"'[1 2]'", "err(syntax_error(json(illegal_array)),1,4,4)"},
    {"''", "err(syntax_error(json(unexpected_end_of_file)),1,0,0)"},
    {"'  '", "err(syntax_error(json(unexpected_end_of_file)),1,2,2)"},
    {"x", "err(syntax_error(json(illegal_json)),1,1,1)"},
    {"'{\"a\":1}{\"b\":2}'", "json([a=1])"},
    {"'1 2'", "1"},
    {"'{\"a\":\\n  [1,\\n   2,\\n   x]}'", "err(syntax_error(json(illegal_json)),4,4,22)"},
    # anders als SWI 9.0.4: ein Ersatzpaar wird ein Zeichen
    {"'\"\\\\ud83d\\\\ude00\"'", "'😀'"},
    {"'\"\\\\ud83d!\"'", "'\u{FFFD}!'"}
  ]

  for {text, t} <- @reads do
    test "atom_json_term(#{text})", c do
      check(c, "r(#{unquote(text)}, T)", ["T = #{unquote(t)}"])
    end
  end

  test "Optionen beim Lesen", c do
    check(c, "r('[true,false,null]', T, [true(yes), false(no), null(nil)])", ["T = [yes,no,nil]"])
    check(c, "r('\"abc\"', T, [value_string_as(codes)])", ["T = [97,98,99]"])
    check(c, "r('\"ab\"', T, [value_string_as(chars)])", ["T = [a,b]"])
    check(c, "r(\"[1]\", T)", ["T = [1]"])
  end

  test "json_read: Werte und Fehlerposition aus einer Datei", c do
    path =
      Path.join(System.tmp_dir!(), "prolog_ex_json_#{System.unique_integer([:positive])}.json")

    File.write!(path, "1 2 [3] {\"a\":\"b\"}   \n\n  {\"a\":tru}")

    try do
      q =
        "open('#{path}', read, S), json_read(S, A), json_read(S, B), json_read(S, C), " <>
          "json_read(S, D, [end_of_file(eof)]), " <>
          "catch(json_read(S, _), error(E, stream(_, L, P, N)), true), close(S), " <>
          "X = [A, B, C, D, E, L, P, N]"

      Reader.put_current(c.reader)
      {_, {:answers, [ans]}} = TableCase.run(c.reader, c.db, q)

      assert ans =~
               "X = [1,2,[3],json([a=b]),syntax_error(json(json_expected(true))),3,11,33]"
    after
      File.rm(path)
    end
  end

  # --- Schreiben -----------------------------------------------------------

  @writes [
    {"1", "1"},
    {"1.0e10", "10000000000.0"},
    {"123456789012345678901234567890", "123456789012345678901234567890"},
    {"-0.0", "-0.0"},
    {"a", ~S("a")},
    {~S('quo"te'), ~S("quo\"te")},
    {~S('back\\slash'), ~S("back\\slash")},
    {~S('nl\nx'), ~S("nl\nx")},
    {~S('ctl\x01\x'), ~S("ctl\u0001x")},
    {"'</script>'", ~S("<\/script>")},
    {"'é€😀'", ~S("é€😀")},
    {"[]", "[]"},
    {"[1,2,3]", "[1, 2, 3 ]"},
    {"json([])", "{}"},
    {"json([a=1, b-2, c(3)])", ~S({"a":1, "b":2, "c":3})},
    {"json([a=[1,2], b=json([x= @(true), y= @(false), z= @(null)])])",
     ~S({"a": [1, 2 ], "b": {"x":true, "y":false, "z":null}})},
    {"[json([a=1]), json([b=2])]", ~S([ {"a":1},  {"b":2} ])},
    {"[json([name='Demo term', created=json([day= @(null), month='December', year=2007]), confirmed= @(true), members=[1,2,3]])]",
     """
     [
       {
         "name":"Demo term",
         "created": {"day":null, "month":"December", "year":2007},
         "confirmed":true,
         "members": [1, 2, 3 ]
       }
     ]\
     """},
    {"json([a=json([b=json([c=json([d=json([e=json([f=json([g='a long string value to force vertical layout here and there'])])])])])])])",
     "{\n  \"a\": {\n    \"b\": {\n      \"c\": {\n\t\"d\": {\n\t  \"e\": {\n\t    \"f\": {\n" <>
       "\t      \"g\":\"a long string value to force vertical layout here and there\"\n" <>
       "\t    }\n\t  }\n\t}\n      }\n    }\n  }\n}"},
    {"#(foo(x,y))", ~S|"foo(x,y)"|},
    {"#(abc)", ~S("abc")},
    {"#([a,b])", ~S("[a,b]")}
  ]

  for {t, out} <- @writes do
    test "json_write(#{t})", c do
      check(c, "w(#{unquote(t)})", {:out, unquote(out)})
    end
  end

  test "Optionen beim Schreiben", c do
    check(c, "w(json([a=1,b=[1,2]]), [width(0)])", {:out, ~S({"a":1, "b": [1, 2 ]})})

    check(
      c,
      "w(json([a=1,b=[1,2]]), [step(4), width(5)])",
      {:out, "{\n    \"a\":1,\n    \"b\": [\n\t1,\n\t2\n    ]\n}"}
    )

    check(
      c,
      "w(json([a=json([b=json([c=1])])]), [width(5), tab(2), step(2)])",
      {:out, "{\n\t\"a\": {\n\t\t\"b\": {\n\t\t\t\"c\":1\n\t\t}\n\t}\n}"}
    )

    check(c, "w(f(x), [serialize_unknown(true)])", {:out, ~S|"f(x)"|})
    check(c, "w(json([a=null]), [null(null)])", {:out, ~S({"a":null})})
    check(c, "w(json([a=1]), [indent(4), width(4)])", {:out, "{\n      \"a\":1\n    }"})
  end

  test "Spalte des Streams zählt (Leerzeichen, Einrückung)", c do
    check(
      c,
      "out((write(abc), json_write(current_output, [json([a=1])])))",
      {:out, ~S(abc [ {"a":1} ])}
    )

    check(
      c,
      "out((write('    '), json_write(current_output, json([a=json([b=1])]), [width(10)])))",
      {:out, "     {\n  \"a\": {\"b\":1}\n}"}
    )
  end

  test "Fehler beim Schreiben (das Geschriebene bleibt, wie bei SWI)", c do
    check(c, "catch(w(f(x)), error(E, _), true)", ["E = type_error(json_term,f(x))"])
    check(c, "catch(w(@(foo)), error(E, _), true)", ["E = type_error(json_term,@(foo))"])
    check(c, "catch(w(json([1=2])), error(E, _), true)", ["E = type_error(text,1)"])
    check(c, "we(json([a=_]), [], E)", {:out, "{", ["E = instantiation_error"]})

    check(
      c,
      "we(json([foo]), [], E)",
      {:out, "{", ["E = type_error(pair,foo)"]}
    )

    check(
      c,
      "we(json([f(a,b)]), [width(0)], E)",
      {:out, "{", ["E = type_error(json_pair,f(a,b))"]}
    )
  end

  test "atom_json_term/3 schreibend", c do
    check(c, "atom_json_term(A, json([a=1,b=[x,y]]), [])", [~S(A = '{"a":1, "b": ["x", "y" ]}')])
    check(c, "atom_json_term(A, json([a=1]), [as(codes)]), atom_codes(X, A)", :succeeds)
    check(c, "atom_json_term(A, [1,2], [as(chars), width(0)]), atom_chars(X, A)", :succeeds)

    check(c, "catch(atom_json_term(_, [1], [as(foo)]), error(E, _), true)", [
      "E = type_error(oneof([atom,string,codes,chars]),foo)"
    ])
  end

  test "is_json_term/1,2", c do
    check(c, "is_json_term(json([a=1, b=[x, @(true)], c=json([])]))", :succeeds)
    check(c, "is_json_term(json([a-1]))", :fails)
    check(c, "is_json_term(f(x))", :fails)
    check(c, "is_json_term(@(yes), [true(@(yes))])", :succeeds)
    check(c, "is_json_term(_)", :fails)
    check(c, "is_json_term([1|_])", :fails)
  end

  test "Rundreise", c do
    check(
      c,
      "T0 = json([a=[1,2.5,json([])], b= @(null), 'c d'='x\"y']), atom_json_term(A, T0, []), atom_json_term(A, T, []), T == T0",
      :succeeds
    )
  end

  # --- Scryer: json_chars//1 ---------------------------------------------------

  test "json_chars//1 lesen", c do
    check(
      c,
      ~S|atom_chars('{"a": [1, 2.5, -3e2, true, null, "xéy"], "b": {}}', Cs), phrase(json_chars(J), Cs)|,
      :succeeds
    )

    check(
      c,
      ~S|atom_chars('{"a": [1, true, null, "x"], "b": {}}', Cs), phrase(json_chars(J), Cs), J = pairs([string([a])-list(L), B]), L = [number(1), boolean(true), null, string([x])], B = string([b])-pairs([])|,
      :succeeds
    )
  end

  test "json_chars//1 erzeugen", c do
    check(
      c,
      "once(phrase(json_chars(pairs([string([k])-list([number(1), string([v])])])), Cs)), atom_chars(A, Cs)",
      [~S(A = '{"k":[1,"v"]}', Cs = ['{','"',k,'"',:,'[','1',',','"',v,'"',']','}'])]
    )
  end
end
