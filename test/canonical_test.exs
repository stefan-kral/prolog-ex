defmodule PrologEx.CanonicalTest do
  use ExUnit.Case, async: true
  import PrologEx
  alias PrologEx.Canonical, as: C

  test "Atome, Zahlen, Variablen" do
    assert C.parse!("foo") == a("foo")
    assert C.parse!("'it''s'") == a("it's")
    assert C.parse!("'a\\nb'") == a("a\nb")
    assert C.parse!("'\\x41\\'") == a("A")
    assert C.parse!("größe") == a("größe")
    assert C.parse!("-1") == -1
    assert C.parse!("2.5") == 2.5
    assert C.parse!("1.0e+10") == 1.0e10
    assert C.parse!("_14") == v("_14")
    assert C.parse!("X") == v("X")
  end

  test "Sonderatome und Symbolatome" do
    assert C.parse!("[]") == []
    assert C.parse!("'[]'") == []
    assert C.parse!("{}") == a("{}")
    assert C.parse!("f(=, ===>, !, ;, '|')") == s("f", Enum.map(~w(= ===> ! ; |), &a/1))
    assert C.parse!("','(a, b)") == s(",", [a("a"), a("b")])
    assert C.parse!("\\+(c)") == s("\\+", [a("c")])
    assert C.parse!("-(1)") == s("-", [1])
  end

  test "Listen in beiden Schreibweisen, geschweifte Klammern" do
    assert C.parse!("'.'(a, '.'(b, []))") == list([a("a"), a("b")])
    assert C.parse!("[a, b | T]") == list([a("a"), a("b")], v("T"))
    assert C.parse!("{}(x)") == s("{}", [a("x")])
    assert C.parse!("{x}") == s("{}", [a("x")])
  end

  test "Punkt am Ende, Fehler bei Resten" do
    assert C.parse!("f(a).") == s("f", [a("a")])
    assert {:error, _} = C.parse("f(a) g")
    assert {:error, _} = C.parse("f(a")
    assert {:error, _} = C.parse("'offen")
  end

  test "Variablennamen übernehmen" do
    {:ok, {_, "term", [t, vs]}} = C.parse("term(f(_14, _15, _14), '.'(=('X', _14), [])).")
    assert C.rename_vars(t, vs) == {s("f", [v("X"), v("_15"), v("X")]), %{"_14" => "X"}}
  end
end
