defmodule PrologEx.BuiltinsTest do
  use ExUnit.Case, async: true
  import PrologEx
  import ExUnit.CaptureIO

  @x v("X")
  @y v("Y")

  defp all(db, goal), do: db |> query(goal) |> Enum.map(&format_answer/1)

  setup_all do
    db =
      consult([
        fact(s("p", [1])),
        fact(s("p", [2])),
        fact(s("p", [3])),
        # Cut in der Bedingung ist lokal, Cut in Then wirkt aufs Prädikat
        rule(s("ite", [@x]), [s(";", [s("->", [s("p", [@x]), a("true")]), s("=", [@x, 0])])]),
        rule(s("ite_cut", [@x]), [
          s(";", [s("->", [a("true"), s(",", [s("p", [@x]), a("!")])]), a("fail")])
        ]),
        fact(s("ite_cut", [99])),
        rule(s("c", [@x]), [s("call", [s(",", [s("p", [@x]), a("!")])])]),
        fact(s("c", [99]))
      ])

    {:ok, db: db}
  end

  test "if-then-else nimmt nur die erste Lösung der Bedingung", %{db: db} do
    assert all(db, s("ite", [@x])) == ["X = 1"]
    assert all(db, s(";", [s("->", [a("fail"), a("true")]), s("=", [@x, 0])])) == ["X = 0"]
    assert all(db, s("->", [a("fail"), a("true")])) == []
  end

  test "Cut im Then-Zweig schneidet das Prädikat ab", %{db: db} do
    assert all(db, s("ite_cut", [@x])) == ["X = 1"]
  end

  test "call/1 ist undurchsichtig für Cut", %{db: db} do
    assert all(db, s("c", [@x])) == ["X = 1", "X = 99"]
  end

  test "call/N hängt Argumente an", %{db: db} do
    assert all(db, s("call", [a("p"), @x])) == ["X = 1", "X = 2", "X = 3"]
    assert all(db, s("call", [s("=", [@x]), 5])) == ["X = 5"]
  end

  test "Vergleich und Typprüfung", %{db: db} do
    assert all(db, s("==", [s("f", [@x]), s("f", [@x])])) == ["X = X"]
    assert all(db, s("==", [@x, @y])) == []
    assert all(db, s("\\==", [@x, @y])) == ["X = X, Y = Y"]
    assert all(db, s("\\=", [1, 2])) == ["true"]
    assert all(db, s("\\=", [@x, 2])) == []
    assert all(db, s("var", [@x])) == ["X = X"]
    assert all(db, s("atom", [a("a")])) == ["true"]
    assert all(db, s("atom", [list([])])) == ["true"]
    assert all(db, s("compound", [list([1])])) == ["true"]
    assert all(db, s("is_list", [list([1, 2])])) == ["true"]
    assert all(db, s("is_list", [list([1], @x)])) == []
  end

  test "Arithmetik", %{db: db} do
    assert all(db, s("is", [@x, s("/", [7, 2])])) == ["X = 3.5"]
    assert all(db, s("is", [@x, s("/", [8, 2])])) == ["X = 4"]
    assert all(db, s("is", [@x, s("**", [2, 100])])) == ["X = #{Integer.pow(2, 100)}"]
    assert all(db, s("is", [@x, s("-", [s("max", [3, 9])])])) == ["X = -9"]
  end

  test "write/nl", %{db: db} do
    out = capture_io(fn -> all(db, s(",", [s("write", [s("f", [list([1, 2])])]), a("nl")])) end)
    assert out == "f([1, 2])\n"
  end

  test "DCG-Übersetzung und phrase/2" do
    {h, b} = PrologEx.DCG.rule(a("ab"), s(",", [list([a("a")]), list([a("b")])]))
    db = consult([{h, b}])
    assert all(db, s("phrase", [a("ab"), list([a("a"), a("b")])])) == ["true"]
    assert all(db, s("phrase", [a("ab"), list([a("a")])])) == []
  end
end
