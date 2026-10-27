defmodule PrologEx.FormatTest do
  # format/1,2,3 nach PIP 0110; die gut 1 100 Fälle aus Logtalks
  # Konformitätstests bestehen alle (conformance/run.exs ... format)
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  @moduletag :gprolog
  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Stream.reset()
    PrologEx.put_db(PrologEx.use_library(%{}, "lists", "user"))
    {:ok, f: Path.join(c.tmp_dir, "out.txt")}
  end

  defp run(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(1)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  # Ausgabe von format(Control, Args) (Control und Args als Prolog-Text)
  # (jedes Mal in Spalte 0 beginnend)
  defp out(c, ctl, args) do
    PrologEx.Stream.reset()
    capture_io(fn -> assert run(c, "format(#{ctl}, #{args})") == ["true"] end)
  end

  defp err(c, ctl, args) do
    [res] = run(c, "catch(format(#{ctl}, #{args}), error(E, _), true)")
    res
  end

  test "Text und Terme", c do
    assert out(c, "'abc~~'", "[]") == "abc~"
    assert out(c, "\"~w ~q ~a\"", "['A b', 'A b', 'A b']") == "A b 'A b' A b"
    assert out(c, "'~k'", "[[1, 2]-x]") == "-('.'(1,'.'(2,[])),x)"
    assert out(c, "'~W'", "[a+'B', [quoted(true)]]") == "a+'B'"
    assert out(c, "'~w'", "['$VAR'(1)]") == "B"
    assert out(c, "'~p'", "[foo('X')]") == "foo('X')"
    assert out(c, "'~3c~s|~4s|~2s'", "[0'x, [0'a, 0'b], \"ab\", abc]") == "xxxab|ab  |ab"
    assert out(c, "'~a~i~a'", "[a, b, c]") == "ac"
    assert out(c, "'~w'", "[_]") =~ ~r/^_/
  end

  test "Zahlen", c do
    assert out(c, "'~d ~1d ~3d ~D ~2D'", "[123, 123, 5, 1234567, -1234567]") ==
             "123 12.3 0.005 1,234,567 -12,345.67"

    assert out(c, "'~2r ~16r ~16R ~r'", "[13, 255, 255, 8]") == "1101 ff FF 10"
    # wie C printf: exakter Binärwert, Gleichstand zur geraden Ziffer
    assert out(c, "'~f ~2f ~0f ~0f ~1f'", "[1, 2.675, 2.5, 3.5, 0.25]") ==
             "1.000000 2.67 2 4 0.2"

    assert out(c, "'~20f'", "[0.1]") == "0.10000000000000000555"
    assert out(c, "'~e ~0e ~2e'", "[0.0, 9.96, 9.996]") == "0.000000e+00 1e+01 1.00e+01"
    assert out(c, "'~f ~e'", "[-0.5, -1.0e-300]") == "-0.500000 -1.000000e-300"
    assert out(c, "'~e ~3E'", "[12.5, 0.000125]") == "1.250000e+01 1.250E-04"
    assert out(c, "'~g ~2g ~G'", "[0.00000123, 392.65, 1.0e20]") == "1.23e-06 3.9e+02 1E+20"
    # Argumente sind Ausdrücke, auch für *
    assert out(c, "'~*c~d'", "[1+2, 0'a, 6*7]") == "aaa42"
  end

  test "Zeilen und Spalten", c do
    assert out(c, "'a~2nb~Nc~N'", "[]") == "a\n\nb\nc\n"
    assert out(c, "'~`-t~30|~n'", "[]") == String.duplicate("-", 30) <> "\n"

    assert out(c, "'~t~w~10|~w~t~10+~t~w~t~9+|'", "[right, left, mid]") ==
             "     rightleft         mid   |"

    assert out(c, "'~a~`.t~15|~d'", "[total, 42]") == "total..........42"
    # zwei Füllstellen teilen sich den Platz
    assert out(c, "'~a~t~`.t~15|~d'", "[total, 42]") == "total     .....42"
    # zu lang: nichts abgeschnitten, die Grenze wandert mit
    assert out(c, "'~a~4|~a'", "[abcdef, x]") == "abcdefx"
    # spätere Füllstellen bekommen das übrige Zeichen
    assert out(c, "'~t~w~t~w~t~10|'", "[a, b]") == "  a   b   "
  end

  test "die Startspalte des Streams zählt", c do
    assert capture_io(fn ->
             assert run(c, "write(abc), format('~t~w~8|', [x])") == ["true"]
           end) == "abc    x"
  end

  test "format/3 auf einen Stream; format/1", c do
    assert run(c, "open('#{c.f}', write, S), format(S, '~w-~w~n', [a, b]), close(S)") |> length() ==
             1

    assert File.read!(c.f) == "a-b\n"
    assert capture_io(fn -> run(c, "format('hallo~n')") end) == "hallo\n"
  end

  test "Fehler", c do
    assert err(c, "_", "[]") == "E = instantiation_error"
    assert err(c, "'~w'", "_") == "E = instantiation_error"
    assert err(c, "'~w ~w'", "[a|_]") == "E = instantiation_error"
    assert err(c, "42", "[]") == "E = type_error(text, 42)"
    assert err(c, "'~w'", "a") == "E = type_error(list, a)"
    assert err(c, "'~a'", "[42]") == "E = type_error(atom, 42)"
    assert err(c, "'~d'", "[1.0]") == "E = type_error(integer, 1.0)"
    assert err(c, "'~d'", "[foo(bar)]") == "E = type_error(evaluable, foo/1)"
    assert err(c, "'~c'", "[a]") == "E = type_error(evaluable, a/0)"
    assert err(c, "'~*c'", "[-1, 0'a]") == "E = domain_error(not_less_than_zero, -1)"
    assert err(c, "'~a'", "[]") == "E = domain_error(format, 'not enough arguments')"
    assert err(c, "'x'", "[a]") == "E = domain_error(format, 'too many arguments')"
    assert err(c, "'~37r'", "[1]") == "E = domain_error(format, 'radix not in 2..36')"
    assert err(c, "'~y'", "[]") == "E = domain_error(format, 'unknown directive ~y')"
    # Fehler unterwegs: keine Teilausgabe
    assert capture_io(fn -> run(c, "catch(format('abc~a', [1]), _, true)") end) == ""
  end

  test "print/1 und ~p fragen portray/1", c do
    run(c, "assertz((portray(X) :- atom(X), write(X), write(X)))")

    assert capture_io(fn -> run(c, "print(f(ab, [cd], 1)), format('|~p', [g(x)])") end) ==
             "f(abab,[cdcd],1)|g(xx)"

    # Ausnahme in portray geht weiter, die Ausgabe landet wieder auf user_output
    run(c, "asserta((portray(boom(_)) :- throw(peng)))")
    assert run(c, "catch(print(boom(1)), E, true)") == ["E = peng"]
    assert capture_io(fn -> run(c, "write(danach)") end) == "danach"
  end
end
