defmodule PrologEx.CharConversionTest do
  # char_conversion/2, current_char_conversion/2 und das Flag
  # char_conversion (ISO 8.14.5, 8.14.6, 7.11.2.5)
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  setup do
    PrologEx.put_db(%{})
    :ok
  end

  defp ask(q) do
    [{:term, g, _}] = PrologEx.Parser.read_terms(q <> " .")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp read(text) do
    for item <- PrologEx.Parser.read_terms(text) do
      case item do
        {:term, t, _} -> PrologEx.format(t, quoted: true, ignore_ops: true)
        {:error, _} -> :error
      end
    end
  end

  test "Fehler wie gprolog und SICStus" do
    assert ask("catch(char_conversion(_, a), error(E, _), true)") == ["E = instantiation_error"]
    assert ask("catch(char_conversion(a, _), error(E, _), true)") == ["E = instantiation_error"]

    assert ask("catch(char_conversion(ab, a), error(E, _), true)") ==
             ["E = type_error(character, ab)"]

    assert ask("catch(char_conversion(a, f(x)), error(E, _), true)") ==
             ["E = type_error(character, f(x))"]

    assert ask("catch(current_char_conversion(1, _), error(E, _), true)") ==
             ["E = type_error(character, 1)"]

    assert ask("catch(current_char_conversion(_, []), error(E, _), true)") ==
             ["E = type_error(character, [])"]
  end

  test "Tabelle: eintragen, ersetzen, mit In = Out entfernen; nur Paare In ≠ Out" do
    assert ask("findall(A-B, current_char_conversion(A, B), L)") == ["L = []"]
    assert ask("char_conversion('&', ','), char_conversion(ä, a)") == ["true"]
    assert ask("findall(A-B, current_char_conversion(A, B), L)") == ["L = [& -(','), 'ä'-a]"]
    assert ask("current_char_conversion(X, a)") == ["X = 'ä'"]
    assert ask("current_char_conversion(b, X)") == []
    assert ask("char_conversion(ä, ö), current_char_conversion(ä, X)") == ["X = 'ö'"]

    assert ask("char_conversion(ä, ä), findall(A, current_char_conversion(A, _), L)") == [
             "L = \"&\""
           ]
  end

  test "beim Lesen nur mit Flag on und nur außerhalb von Quotes, 0'c und Kommentaren" do
    ask("char_conversion('&', ',')")
    assert read("f(&).") == ["f(&)"]
    ask("set_prolog_flag(char_conversion, on)")
    assert read("f(a & b).") == ["f(a,b)"]

    assert read("x('a&b', \"&\", `&`, 0'& ).") == ["x('a&b','.'(&,[]),&,38)"]
    assert read("x & /* & */ y. % & \n") == ["','(x,y)"]
    assert read("x(0'&, (a & b)).") == ["x(38,','(a,b))"]
    assert read("x('a\\'&').") == ["x('a\\'&')"]
    assert read("a.% & \nb.") == ["a", "b"]
    ask("set_prolog_flag(char_conversion, off)")
    assert read("f(&).") == ["f(&)"]
  end

  test "Umsetzung kann Endepunkt und Kommentare erzeugen; Symbolfolgen bleiben ganz" do
    ask("char_conversion(!, '.'), char_conversion(#, '%'), set_prolog_flag(char_conversion, on)")
    assert read("a! b!") == ["a", "b"]
    assert read("a! #! b!\nc!") == ["a", "c"]
    # in =!! entsteht =.., kein Endepunkt
    assert read("x(a =!! b)!") == ["x(=..(a,b))"]
    # "/*" in einer Symbolfolge beginnt keinen Kommentar
    ask("char_conversion('&', b)")
    assert read("x(=/*&*/)!") == [:error]
  end

  test "Fehler nennen die Zeile im Original; danach geht es weiter" do
    ask("char_conversion('&', ','), set_prolog_flag(char_conversion, on)")

    assert [{:term, _, _}, {:error, msg}, {:term, {:atom, "ok"}, _}] =
             PrologEx.Parser.read_terms("a.\nf(& ).\nok.\n")

    assert msg =~ "Zeile 2"
  end

  test "beim Laden gilt eine Direktive ab dem nächsten Term" do
    path = Path.join(System.tmp_dir!(), "cc_#{System.unique_integer([:positive])}.pl")

    File.write!(path, """
    :- char_conversion('&', ',').
    :- set_prolog_flag(char_conversion, on).
    p((a & b)).
    """)

    capture_io(:stderr, fn -> PrologEx.Consult.load_file(path) end)
    File.rm(path)
    assert ask("p(X)") == ["X = (a, b)"]
  end
end
