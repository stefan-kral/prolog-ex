defmodule PrologEx.ScryerFormatTest do
  # library(format) aus Scryer Prolog; Beispiele aus Scryers format.pl
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  @program """
  :- use_module(library(format)).
  :- dynamic(d/1).
  d(1).
  d(X) :- X > 1, ( X < 3 -> true ; fail ).
  s(a).
  gr --> "x", gr.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp ask(c, q, db \\ nil) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    (db || c.db)
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  # die beschriebene Zeichenliste als Elixir-String
  defp f_(c, fs, args) do
    capture_io(fn ->
      assert ask(c, "phrase(format_(#{fs}, #{args}), Cs), atom_chars(A, Cs), write(A)") != []
    end)
  end

  defp out(c, q), do: capture_io(fn -> ask(c, q) end)
  defp err(c, goal), do: ask(c, "catch(#{goal}, error(E, _), true)")

  test "format_//2: Beispiele aus Scryers Doku", c do
    assert f_(c, ~s|"~s~n~`.t~w!~12\|"|, ~s|["hello", there]|) == "hello\n......there!"
    assert f_(c, ~s|"~ta~t~4\|"|, "[]") == " a  "
    assert f_(c, ~s|"~ta~tb~tc~10\|"|, "[]") == "  a  b   c"
    assert f_(c, ~s|"~ta~t~tb~tc~20\|"|, "[]") == "    a        b     c"
    assert f_(c, ~s|"~2f"|, "[3]") == "3.00"
    assert f_(c, ~s|"~20f"|, "[0.1]") == "0.10000000000000000000"
    assert f_(c, ~s|"~7f"|, "[1.1071487177940906]") == "1.1071487"
    assert f_(c, ~s|"~`at~50\|"|, "[]") == String.duplicate("a", 50)
    assert f_(c, ~s|"~q"|, "['.']") == "'.'"
    assert f_(c, ~s|"~12r"|, "[300]") == "210"
  end

  test "format_//2: Direktiven", c do
    assert f_(c, ~s|"~w ~q ~a ~s"|, ~s|['A b', 'A b', ab, "cd"]|) == "A b 'A b' ab cd"
    assert f_(c, ~s|"~w"|, "[f(X, Y, X)]") == "f(_A,_B,_A)"
    assert f_(c, ~s|"~d ~2d ~0d ~3d"|, "[42, 1234, 7, 5]") == "42 12.34 7 0.005"
    assert f_(c, ~s|"~d"|, "[3+4]") == "7"

    assert f_(c, ~s|"~D ~2D ~U ~1U"|, "[1234567, 1234567, 1234567, 12345]") ==
             "1,234,567 12,345.67 1_234_567 1_234.5"

    assert f_(c, ~s|"~5L"|, "[1234567890123]") == "12345_\n67890_\n123"
    assert f_(c, ~s|"~r ~8R ~16r ~16R ~2r"|, "[8, 255, 255, 255, -5]") == "10 377 ff FF -101"
    assert f_(c, ~s|"~f ~0f ~1f"|, "[2.5, 2.5, -0.05]") == "2.500000 3.0 -0.1"
    assert f_(c, ~s|"a~ib~n~2nc~~"|, "[x]") == "ab\n\n\nc~"
  end

  test "format_//2: Spalten", c do
    assert f_(c, ~s|"~a~t~10\|~d"|, "[ab, 42]") == "ab        42"
    assert f_(c, ~s|"~t~d~6\|"|, "[123]") == "   123"
    assert f_(c, ~s|"~t~w~10\|~w"|, "[right, next]") == "     rightnext"
    assert f_(c, ~s|"~w~t~5+~w~t~5+~w"|, "[a, b, c]") == "a    b    c"
    assert f_(c, ~s|"~t~*\|x"|, "[3]") == "   x"
    assert f_(c, ~s|"abcdef~3\|x"|, "[]") == "abcdefx"
  end

  test "format_//2: Fehler wie Scryer", c do
    assert err(c, ~s|phrase(format_("~d", [a]), _)|) == ["E = type_error(evaluable,a/0)"]
    assert err(c, ~s|phrase(format_("~d", [1.5]), _)|) == ["E = type_error(integer,1.5)"]
    assert err(c, ~s|phrase(format_("~d", []), _)|) == ["E = domain_error(non_empty_list,[])"]
    assert err(c, ~s|phrase(format_("~a", [x, y]), _)|) == [~s|E = domain_error(empty_list,"y")|]

    assert err(c, ~s|phrase(format_("~e", [1.0]), _)|) == [
             ~s|E = domain_error(format_string,"~e")|
           ]

    assert err(c, ~s|phrase(format_("~1r", [10]), _)|) == [
             ~s|E = domain_error(format_string,"~1r")|
           ]

    assert err(c, ~s|phrase(format_(abc, []), _)|) == ["E = type_error(list,abc)"]
    assert err(c, ~s|phrase(format_("~w", x), _)|) == ["E = type_error(list,x)"]
    assert err(c, ~s|phrase(format_(_, []), _)|) == ["E = instantiation_error"]
  end

  test "format/2,3", c do
    assert out(c, ~s|format("~w und ~q~n", ['A b', 'A b'])|) == "A b und 'A b'\n"

    assert capture_io(:stderr, fn -> ask(c, ~s|format(user_error, "~a~n", [fehler])|) end) ==
             "fehler\n"

    assert out(c, ~s|format(user_output, "~d", [1])|) == "1"
    # Scryers format/2 gilt, nicht das eingebaute: ~e kennt es nicht
    assert err(c, ~s|format("~e", [1.0])|) == [~s|E = domain_error(format_string,"~e")|]

    assert err(c, ~s|format(user_output, "~e", [1.0])|) == [
             ~s|E = domain_error(format_string,"~e")|
           ]
  end

  test "ohne library(format): das eingebaute format/2 (PIP 0110)", c do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, "p.\n"))
    assert capture_io(fn -> ask(c, ~s|format("~e~n", [1.0])|, db) end) == "1.000000e+00\n"
  end

  test "portray_clause/1 (Beispiele aus Scryers format.pl)", c do
    assert out(c, "portray_clause(a)") == "a.\n"
    assert out(c, "portray_clause((a :- b))") == "a :-\n   b.\n"
    assert out(c, "portray_clause((a :- b, c, d))") == "a :-\n   b,\n   c,\n   d.\n"
    assert out(c, "portray_clause([a,b,c,d])") == ~s|"abcd".\n|
    assert out(c, "portray_clause(X)") == "A.\n"
    assert out(c, "portray_clause((f(X) :- X))") == "f(A) :-\n   A.\n"

    assert out(c, "portray_clause((h :- ( a -> b; c)))") ==
             "h :-\n   (  a ->\n      b\n   ;  c\n   ).\n"

    assert out(c, "portray_clause((h :- ( (a -> x ; y) -> b; c)))") ==
             "h :-\n   (  (  a ->\n         x\n      ;  y\n      ) ->\n      b\n   ;  c\n   ).\n"

    assert out(c, "portray_clause((h(X) :- ( (a(X) ; y(A,B)) -> b; c)))") ==
             "h(A) :-\n   (  (  a(A)\n      ;  y(B,C)\n      ) ->\n      b\n   ;  c\n   ).\n"

    assert out(c, "portray_clause((a :- b ; c ; d))") ==
             "a :-\n   (  b\n   ;  c\n   ;  d\n   ).\n"

    assert out(c, "portray_clause((h :- L = '.'))") == "h :-\n   A='.'.\n"
    assert out(c, "portray_clause(-->(a, (b, {t}, d)))") == "a -->\n   b,\n   {t},\n   d.\n"
    assert out(c, "portray_clause((A :- B))") == "A :-\n   B.\n"
    assert out(c, "portray_clause(f(X, Y, X, 'A', []))") == "f(A,B,A,'A',[]).\n"
    # Operator als Ziel: in Klammern
    assert out(c, "portray_clause((a :- (-)))") == "a :-\n   (-).\n"
  end

  test "listing/1 (im Modul des Aufrufers)", c do
    assert out(c, "listing(d/1)") ==
             "d(1).\nd(A) :-\n   A>1,\n   (  A<3 ->\n      true\n   ;  fail\n   ).\n"

    assert out(c, "listing(s/1)") == "s(a).\n"
    assert out(c, "listing(gr//0)") == "gr(A,B) :-\n   A=[x|C],\n   gr(C,B).\n"
    assert ask(c, "listing(nix/0)") == []
    assert ask(c, "listing(_)") == []
    assert err(c, "listing(foo)") == ["E = type_error(predicate_indicator,foo)"]
  end
end
