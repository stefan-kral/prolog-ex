defmodule PrologEx.AtomsTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  defp goal(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    g
  end

  defp ask(c, text),
    do:
      %{} |> PrologEx.query(goal(c, text)) |> Enum.take(3) |> Enum.map(&PrologEx.format_answer/1)

  defp err(c, text), do: Exception.message(assert_raise(PrologEx.Error, fn -> ask(c, text) end))

  describe "number_chars/2 (Beispiele aus ISO 8.16.7)" do
    test "lesen", c do
      assert ask(c, "number_chars(A, ['-', '2', '5']).") == ["A = -25"]
      assert ask(c, "number_chars(A, [' ', '3']).") == ["A = 3"]
      assert ask(c, "number_chars(A, ['0', x, f]).") == ["A = 15"]
      assert ask(c, "number_chars(A, ['0', '''', a]).") == ["A = 97"]
      assert ask(c, "number_chars(A, ['4', '.', '2']).") == ["A = 4.2"]
      assert ask(c, "number_chars(A, ['4', '2', '.', '0', e, '-', '1']).") == ["A = 4.2"]
      assert ask(c, "number_chars(X, ['3', '.', '3', 'E', '+', '0']).") == ["X = 3.3"]
    end

    test "schreiben", c do
      assert ask(c, "number_chars(33, L), L == ['3', '3'].") |> length() == 1
      assert ask(c, "number_chars(33.0, L), L == ['3', '3', '.', '0'].") |> length() == 1
      assert ask(c, "number_chars(-0.0, L), L == ['-', '0', '.', '0'].") |> length() == 1
      # teilweise Liste
      assert ask(c, "number_chars(12, [X|T]), X == '1', T == ['2'].") |> length() == 1
      # vollständige Liste wird gelesen, auch bei gebundenem N
      assert ask(c, "number_chars(1, ['0', '1']).") == ["true"]
      assert ask(c, "number_chars(2, ['0', '1']).") == []
    end

    test "Fehler", c do
      assert err(c, "number_chars(A, ['3', ' ']).") =~ "syntax_error(illegal_number)"
      assert err(c, "number_chars(A, L).") =~ "instantiation_error"
      assert err(c, "number_chars(A, ['1'|_]).") =~ "instantiation_error"
      assert err(c, "number_chars(A, [X]).") =~ "instantiation_error"
      assert err(c, "number_chars(a, L).") =~ "type_error(number, a)"
      assert err(c, "number_chars(A, 4).") =~ "type_error(list, 4)"
      assert err(c, "number_chars(A, ['4', 2]).") =~ "type_error(character, 2)"
      assert err(c, "number_chars(A, [ab]).") =~ "type_error(character, ab)"
      assert err(c, "number_chars(A, []).") =~ "syntax_error"
    end
  end

  describe "Zahlensyntax" do
    test "Leerraum und Kommentare davor, nichts danach", c do
      assert ask(c, "number_chars(A, \"/**/1\").") == ["A = 1"]
      assert ask(c, "number_chars(A, \"%x\\n12\").") == ["A = 12"]
      assert ask(c, "number_chars(A, \"\\n\\t 7\").") == ["A = 7"]
      assert err(c, "number_chars(A, \"/* 1\").") =~ "syntax_error"
      assert err(c, "number_chars(A, \"1 \").") =~ "syntax_error"
      # nach dem Minus Leerraum ja, Kommentar nein (ISO-Tests 21, 24)
      assert ask(c, "number_chars(A, \"- 1\").") == ["A = -1"]
      assert ask(c, "number_chars(A, \"-\\n 1\").") == ["A = -1"]
      assert err(c, "number_chars(A, \"-/**/1\").") =~ "syntax_error"
      assert err(c, "number_chars(A, \"+1\").") =~ "syntax_error"
    end

    test "Formen", c do
      assert ask(c, "number_chars(A, \"0b101\").") == ["A = 5"]
      assert ask(c, "number_chars(A, \"0o17\").") == ["A = 15"]
      assert ask(c, "number_chars(A, \"0xFF\").") == ["A = 255"]
      assert ask(c, "number_chars(A, \"1_000_000\").") == ["A = 1000000"]

      assert ask(c, "number_chars(A, \"123456789012345678901234567890\").") ==
               ["A = 123456789012345678901234567890"]

      assert ask(c, "number_chars(A, \"0'\\\\n\").") == ["A = 10"]
      assert ask(c, "number_chars(A, \"0'\\\\x41\\\\\").") == ["A = 65"]
      assert ask(c, "number_chars(A, \"0'''\").") == ["A = 39"]
      assert ask(c, "number_chars(A, \"0' \").") == ["A = 32"]
      assert ask(c, "number_chars(A, \"-0x10\").") == ["A = -16"]
      assert ask(c, "number_chars(A, \"1.5e3\").") == ["A = 1500.0"]

      for bad <- ~w(1e10 1. 1.e5 0x 0b2 0'' 1_ 1.0e 1.0e+ 0o8) do
        assert err(c, "number_chars(A, \"#{bad}\").") =~ "syntax_error", bad
      end
    end
  end

  describe "number_codes/2" do
    test "wie number_chars mit Codes", c do
      assert ask(c, "number_codes(A, [0'4, 0'2]).") == ["A = 42"]
      assert ask(c, "number_codes(-1.5, L).") == ["L = [45, 49, 46, 53]"]
      assert err(c, "number_codes(A, [0'1, -3]).") =~ "representation_error(character_code)"
      assert err(c, "number_codes(A, [0'1, a]).") =~ "type_error(integer, a)"
    end
  end

  test "Floats: dezimal für 1.0e-4 =< |f| < 1.0e15, sonst mit Exponent (wie SWI)" do
    cases = [
      {1500.0, "1500.0"},
      {12345.0, "12345.0"},
      {0.001, "0.001"},
      {0.0001, "0.0001"},
      {1.0e-5, "1.0e-5"},
      {1.0e14, "100000000000000.0"},
      {1.0e15, "1.0e15"},
      {1.0e20, "1.0e20"},
      {-2.5e-3, "-0.0025"},
      {-0.0, "-0.0"}
    ]

    for {f, s} <- cases, do: assert(PrologEx.format_float(f) == s, inspect(f))

    for f <- [1.0e3, 1.0e6, 1.5e7, 1.25e10, 9.999e14, 2.0e5, 3.0e-3],
        do: assert(String.to_float(PrologEx.format_float(f)) == f, inspect(f))
  end

  test "Hin und zurück für viele Zahlen", c do
    :rand.seed(:exsss, {9, 9, 9})

    nums =
      for _ <- 1..300 do
        case :rand.uniform(4) do
          1 -> :rand.uniform(1_000_000) - 500_000
          2 -> (:rand.uniform() - 0.5) * :math.pow(10, :rand.uniform(40) - 20)
          3 -> :rand.uniform(1_267_650_600_228_229_401_496_703_205_376) * Enum.random([1, -1])
          4 -> :rand.uniform(1000) / 8
        end
      end

    for n <- nums do
      t = if is_float(n), do: Float.to_string(n), else: Integer.to_string(n)
      assert ask(c, "number_chars(#{t}, L), number_chars(M, L), M == #{t}.") |> length() == 1, t
      assert ask(c, "number_codes(#{t}, L), number_codes(M, L), M == #{t}.") |> length() == 1, t
    end
  end
end
