defmodule PrologEx.NumberSyntaxTest do
  use ExUnit.Case, async: true
  alias PrologEx.{NumberSyntax, Reader}

  defp rw(text), do: text |> NumberSyntax.rewrite() |> elem(0)

  describe "rewrite/1" do
    test "Zifferngruppen" do
      assert rw("X = 1_000_000.") == "X = 1000000."
      assert rw("f(1_0, 2_000.25, 3_000e3)") == "f(10, 2000.25, 3000e3)"
      # Leerraum nach "_", Zeilenumbrüche wandern hinter die Zahl
      assert rw("X = 1_000_\n  000.") == "X = 1000000\n."
      assert rw("X = 1_ 000.") == "X = 1000."
    end

    test "kein Zahltoken: unverändert" do
      for t <- [
            "foo_1_000",
            "X_1_000",
            "'1_000'",
            "\"1_000\"",
            "`1_000`",
            "'it''s 1_0'",
            "'a\\'1_0'",
            "% 1_000\n",
            "/* 1_000 */",
            "0'_",
            "0'''",
            "0'\\n",
            "0x1F",
            "16'FF",
            "1_",
            "1_a",
            "1.5_0"
          ] do
        assert rw(t) == t, t
      end
    end

    test "große Ganzzahlen werden markiert" do
      assert NumberSyntax.rewrite("X = 1152921504606846975.") ==
               {"X = 1152921504606846975.", false}

      assert NumberSyntax.rewrite("X = 1152921504606846976.") ==
               {"X = '$bigint'('1152921504606846976').", true}

      assert NumberSyntax.rewrite("X = 1_152_921_504_606_846_976.") ==
               {"X = '$bigint'('1152921504606846976').", true}

      # Floats nie
      assert NumberSyntax.rewrite("X = 99999999999999999999.5.") ==
               {"X = 99999999999999999999.5.", false}
    end
  end

  describe "über den gprolog-Reader" do
    @describetag :gprolog

    setup do
      {:ok, r} = Reader.start_link()
      {:ok, reader: r}
    end

    defp ask(r, text) do
      [{:term, g, _}] = Reader.read_terms(r, text)
      %{} |> PrologEx.query(g) |> Enum.map(&PrologEx.format_answer/1)
    end

    test "Zifferngruppen und große Zahlen", %{reader: r} do
      assert ask(r, "X = 1_000_000.") == ["X = 1000000"]

      assert ask(r, "X is 2 ** 100, X =:= 1_267_650_600_228_229_401_496_703_205_376.") == [
               "X = 1267650600228229401496703205376"
             ]

      assert ask(r, "X = -99999999999999999999.") == ["X = -99999999999999999999"]
      assert ask(r, "X is 10 - 99999999999999999999.") == ["X = -99999999999999999989"]

      assert ask(r, "X = [12345678901234567890, f(99999999999999999999)].") ==
               ["X = [12345678901234567890, f(99999999999999999999)]"]

      assert ask(r, "integer(1_152_921_504_606_846_976).") == ["true"]
    end

    test "Zeilennummern in Fehlermeldungen bleiben richtig", %{reader: r} do
      [_, {:error, msg}] = Reader.read_terms(r, "a(1_000_\n000).\nb(1_).\n")
      assert msg =~ "Zeile 3"
    end
  end
end
