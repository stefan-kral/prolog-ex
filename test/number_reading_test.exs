defmodule PrologEx.NumberReadingTest do
  # Zahlen im Quelltext: Zifferngruppen (wie SWI) und Ganzzahlen beliebiger
  # Größe – direkt vom Reader (früher schrieb sie PrologEx.NumberSyntax für
  # gprolog um)
  use ExUnit.Case, async: true
  alias PrologEx.Reader

  defp ask(text) do
    [{:term, g, _}] = Reader.read_terms(nil, text)
    %{} |> PrologEx.query(g) |> Enum.map(&PrologEx.format_answer/1)
  end

  defp canon(text) do
    for {:term, t, _} <- Reader.read_terms(nil, text),
        do: PrologEx.format(t, quoted: true, ignore_ops: true)
  end

  test "Zifferngruppen und große Zahlen" do
    assert ask("X = 1_000_000.") == ["X = 1000000"]

    assert ask("X is 2 ** 100, X =:= 1_267_650_600_228_229_401_496_703_205_376.") == [
             "X = 1267650600228229401496703205376"
           ]

    assert ask("X = -99999999999999999999.") == ["X = -99999999999999999999"]
    assert ask("X is 10 - 99999999999999999999.") == ["X = -99999999999999999989"]

    assert ask("X = [12345678901234567890, f(99999999999999999999)].") ==
             ["X = [12345678901234567890, f(99999999999999999999)]"]

    assert ask("integer(1_152_921_504_606_846_976).") == ["true"]

    assert canon("x(0xFFFFFFFFFFFFFFFFFFFF, 2_000.25, 1_000_\n  000).") ==
             ["x(1208925819614629174706175,2000.25,1000000)"]
  end

  test "keine Zahlen: Namen, Quotes, Kommentare, 0'c" do
    assert canon("x(foo_1_000, '1_000', `1_000`, 0'_, \"1_0\"). % 1_000\n") ==
             ["x(foo_1_000,'1_000','1_000',95,'.'('1','.'('_','.'('0',[]))))"]
  end

  test "1_a ist die Zahl 1 vor der Variablen _a: Syntaxfehler" do
    assert [{:error, _}] = Reader.read_terms(nil, "x(1_a).")
  end

  test "Zeilennummern in Fehlermeldungen bleiben richtig" do
    [_, {:error, msg}] = Reader.read_terms(nil, "a(1_000_\n000).\nb(1_).\n")
    assert msg =~ "Zeile 3"
  end
end
