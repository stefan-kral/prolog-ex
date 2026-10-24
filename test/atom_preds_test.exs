defmodule PrologEx.AtomPredsTest do
  # atom_length, atom_concat, sub_atom, atom_chars, atom_codes, char_code
  # (Beispiele aus ISO 8.16) und atom_number
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :gprolog

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  defp goal(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    g
  end

  defp ask(c, text) do
    g = goal(c, text)

    %{}
    |> PrologEx.query(g)
    |> Enum.take(10)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, text), do: Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end))

  describe "atom_length/2 (ISO 8.16.1)" do
    test "Beispiele", c do
      assert ask(c, "atom_length('enchanted evening', N).") == ["N = 17"]
      assert ask(c, "atom_length('', N).") == ["N = 0"]
      assert ask(c, "atom_length([], N).") == ["N = 2"]
      assert ask(c, "atom_length(abc, 3).") == ["true"]
      assert ask(c, "atom_length(abc, 4).") == []
      # Zeichen, nicht Bytes
      assert ask(c, "atom_length('äöü€', N).") == ["N = 4"]
    end

    test "Fehler", c do
      assert err(c, "atom_length(X, 4).") =~ "instantiation_error"
      assert err(c, "atom_length(123, N).") =~ "type_error(atom, 123)"
      assert err(c, "atom_length(f(a), N).") =~ "type_error(atom, f(a))"
      assert err(c, "atom_length(atom, '4').") =~ "type_error(integer, '4')"
      assert err(c, "atom_length(atom, -1).") =~ "domain_error(not_less_than_zero, -1)"
    end
  end

  describe "atom_concat/3 (ISO 8.16.2)" do
    test "Beispiele", c do
      assert ask(c, "atom_concat(hello, ' world', S).") == ["S = 'hello world'"]
      assert ask(c, "atom_concat(T, ' world', 'small world').") == ["T = small"]
      assert ask(c, "atom_concat(hello, ' world', 'small world').") == []
      assert ask(c, "atom_concat(small, T, 'small world').") == ["T = ' world'"]
      assert ask(c, "atom_concat([], a, X).") == ["X = '[]a'"]
    end

    test "aufzählen", c do
      assert ask(c, "findall(X-Y, atom_concat(X, Y, hello), L).") ==
               [
                 "L = [''-hello, h-ello, he-llo, hel-lo, hell-o, hello-'']"
               ]

      assert ask(c, "atom_concat(X, Y, 'ä€').") ==
               ["X = '', Y = 'ä€'", "X = 'ä', Y = '€'", "X = 'ä€', Y = ''"]

      assert ask(c, "findall(X, atom_concat(X, Y, ''), L).") == ["L = ['']"]
    end

    test "Fehler", c do
      assert err(c, "atom_concat(A, iso, C).") =~ "instantiation_error"
      assert err(c, "atom_concat(iso, B, C).") =~ "instantiation_error"
      assert err(c, "atom_concat(f(a), x, C).") =~ "type_error(atom, f(a))"
      assert err(c, "atom_concat(x, 1, C).") =~ "type_error(atom, 1)"
      assert err(c, "atom_concat(A, B, 7).") =~ "type_error(atom, 7)"
    end
  end

  describe "sub_atom/5 (ISO 8.16.3)" do
    test "Beispiele", c do
      assert ask(c, "sub_atom(abracadabra, 0, 5, _, S).") == ["S = abrac"]
      assert ask(c, "sub_atom(abracadabra, _, 5, 0, S).") == ["S = dabra"]
      assert ask(c, "sub_atom(abracadabra, 3, L, 3, S).") == ["L = 5, S = acada"]

      assert ask(c, "sub_atom(abracadabra, B, 2, A, ab).") ==
               ["A = 9, B = 0", "A = 2, B = 7"]

      assert ask(c, "sub_atom('Banana', 3, 2, _, S).") == ["S = an"]

      assert ask(c, "findall(S, sub_atom(charity, _, 3, _, S), L).") ==
               ["L = [cha, har, ari, rit, ity]"]

      assert ask(c, "findall(B-L-S, sub_atom(ab, B, L, _, S), Xs).") ==
               [
                 "Xs = [0-0-'', 0-1-a, 0-2-ab, 1-0-'', 1-1-b, 2-0-'']"
               ]
    end

    test "gebundenes Sub: überlappend, mit Umlauten, leer", c do
      assert ask(c, "findall(B, sub_atom(aaaa, B, _, _, aa), L).") == ["L = [0, 1, 2]"]
      assert ask(c, "findall(B, sub_atom('äääa', B, _, _, 'ää'), L).") == ["L = [0, 1]"]
      assert ask(c, "sub_atom('xäyä', B, L, A, 'yä').") == ["A = 0, B = 2, L = 2"]
      assert ask(c, "findall(B, sub_atom(abc, B, L, A, ''), Xs).") == ["Xs = [0, 1, 2, 3]"]
      assert ask(c, "sub_atom(abc, B, 1, A, '').") == []
      assert ask(c, "sub_atom(abc, B, L, A, abcd).") == []
      assert ask(c, "sub_atom(abc, 1, L, A, bc).") == ["A = 0, L = 2"]
      assert ask(c, "sub_atom(abc, 1, L, A, ab).") == []
      assert ask(c, "sub_atom(abc, B, L, 0, bc).") == ["B = 1, L = 2"]
      assert ask(c, "sub_atom(abc, B, L, 1, bc).") == []
    end

    test "Kombinationen gebundener Zahlen", c do
      assert ask(c, "findall(B-L, sub_atom(abc, B, L, 1, _), Xs).") ==
               ["Xs = [0-2, 1-1, 2-0]"]

      assert ask(c, "findall(L, sub_atom(abc, 1, L, _, _), Xs).") == ["Xs = [0, 1, 2]"]
      assert ask(c, "sub_atom(abc, 1, 1, A, S).") == ["A = 1, S = b"]
      assert ask(c, "sub_atom(abc, 2, 2, A, S).") == []
      assert ask(c, "sub_atom(abc, 4, L, A, S).") == []
      assert ask(c, "sub_atom(abc, -1, L, A, S).") == []
      assert ask(c, "sub_atom(abc, B, L, 4, S).") == []
      assert ask(c, "sub_atom(abc, B, 1, 0, S).") == ["B = 2, S = c"]
    end

    test "Fehler", c do
      assert err(c, "sub_atom(W, 3, 2, S, T).") =~ "instantiation_error"
      assert err(c, "sub_atom(f(a), B, L, A, S).") =~ "type_error(atom, f(a))"
      assert err(c, "sub_atom(abc, a, L, A, S).") =~ "type_error(integer, a)"
      assert err(c, "sub_atom(abc, B, L, A, 1).") =~ "type_error(atom, 1)"
    end
  end

  describe "atom_chars/2, atom_codes/2 (ISO 8.16.4, 8.16.5)" do
    test "Beispiele", c do
      assert ask(c, "atom_chars('', L).") == ["L = []"]
      assert ask(c, "atom_chars([], L).") == ["L = \"[]\""]
      assert ask(c, "atom_chars('''', L).") == ["L = \"'\""]
      assert ask(c, "atom_chars(ant, L), L == [a, n, t].") |> length() == 1
      assert ask(c, "atom_chars(S, [s, o, p]).") == ["S = sop"]
      assert ask(c, "atom_chars('North', ['N'|X]).") == ["X = \"orth\""]
      assert ask(c, "atom_chars(soap, [s, o, p]).") == []
      assert ask(c, "atom_chars(X, ['[', ']']), X == [].") |> length() == 1
      assert ask(c, "atom_chars(X, ['ä', '€']).") == ["X = 'ä€'"]
      assert ask(c, "atom_codes('', L).") == ["L = []"]
      assert ask(c, "atom_codes(ant, L).") == ["L = [97, 110, 116]"]
      assert ask(c, "atom_codes(S, [0's, 0'o, 0'p]).") == ["S = sop"]
      assert ask(c, "atom_codes('North', [0'N|X]).") == ["X = [111, 114, 116, 104]"]
      assert ask(c, "atom_codes(soap, [0's, 0'o, 0'p]).") == []
      assert ask(c, "atom_codes('ä€', L).") == ["L = [228, 8364]"]
    end

    test "Fehler", c do
      assert err(c, "atom_chars(X, Y).") =~ "instantiation_error"
      assert err(c, "atom_chars(X, [a|_]).") =~ "instantiation_error"
      assert err(c, "atom_chars(X, [a, _]).") =~ "instantiation_error"
      assert err(c, "atom_chars(1, L).") =~ "type_error(atom, 1)"
      assert err(c, "atom_chars(X, a).") =~ "type_error(list, a)"
      assert err(c, "atom_chars(X, [a|b]).") =~ "type_error(list, [a|b])"
      assert err(c, "atom_chars(X, [ab]).") =~ "type_error(character, ab)"
      # Elemente werden auch bei gebundenem Atom geprüft (wie number_chars)
      assert err(c, "atom_chars(a, [f(x)|_]).") =~ "type_error(character, f(x))"
      assert err(c, "atom_codes(X, Y).") =~ "instantiation_error"
      assert err(c, "atom_codes(X, [-1]).") =~ "representation_error(character_code)"
    end
  end

  describe "char_code/2 (ISO 8.16.6)" do
    test "Beispiele", c do
      assert ask(c, "char_code(a, Code).") == ["Code = 97"]
      assert ask(c, "char_code(Char, 99).") == ["Char = c"]
      assert ask(c, "char_code(Char, 0'c).") == ["Char = c"]
      assert ask(c, "char_code(b, 84).") == []
      assert ask(c, "char_code('€', X).") == ["X = 8364"]
      assert ask(c, "char_code(X, 8364).") == ["X = '€'"]
    end

    test "Fehler", c do
      assert err(c, "char_code(ab, Code).") =~ "type_error(character, ab)"
      assert err(c, "char_code(C, D).") =~ "instantiation_error"
      assert err(c, "char_code(C, x).") =~ "type_error(integer, x)"
      assert err(c, "char_code(a, x).") =~ "type_error(integer, x)"
      assert err(c, "char_code(C, -2).") =~ "representation_error(character_code)"
      assert err(c, "char_code(1, C).") =~ "type_error(character, 1)"
    end
  end

  describe "atom_number/2" do
    test "beide Richtungen", c do
      assert ask(c, "atom_number('12', N).") == ["N = 12"]
      assert ask(c, "atom_number('-1.5', N).") == ["N = -1.5"]
      assert ask(c, "atom_number('0x1F', N).") == ["N = 31"]
      assert ask(c, "atom_number(A, 42).") == ["A = '42'"]
      assert ask(c, "atom_number(A, 2.5).") == ["A = '2.5'"]
      assert ask(c, "atom_number('12', 12).") == ["true"]
      # keine Zahl: scheitert (kein Syntaxfehler)
      assert ask(c, "atom_number(foo, N).") == []
      assert ask(c, "atom_number('12a', N).") == []
      assert ask(c, "atom_number('', N).") == []
    end

    test "Fehler", c do
      assert err(c, "atom_number(A, N).") =~ "instantiation_error"
      assert err(c, "atom_number(1, N).") =~ "type_error(atom, 1)"
      assert err(c, "atom_number(A, foo).") =~ "type_error(number, foo)"
    end
  end

  describe "letzte Lösung ohne Choice Point" do
    # {antwort, noch_choice_point?} je Lösung
    defp more(c, text), do: %{} |> PrologEx.solutions(goal(c, text)) |> Enum.map(&elem(&1, 1))

    test "atom_concat und sub_atom", c do
      assert more(c, "atom_concat(X, Y, abc).") == [true, true, true, false]
      assert more(c, "atom_concat(X, c, abc).") == [false]
      assert more(c, "sub_atom(abc, B, L, A, S).") |> List.last() == false
      assert more(c, "sub_atom(abcab, B, L, A, ab).") == [true, false]
      assert more(c, "sub_atom(abcab, B, L, A, ca).") == [false]
      assert more(c, "sub_atom(abc, B, 1, A, S).") == [true, true, false]
      assert more(c, "sub_atom(abc, B, L, A, '').") == [true, true, true, false]
    end
  end
end
