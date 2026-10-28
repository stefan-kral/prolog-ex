defmodule PrologEx.GensymTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.put_db(PrologEx.use_library(%{}, "gensym"))
    :ok
  end

  # auf der Sitzungsdatenbank: die Zähler wirken über Anfragen hinweg
  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch((#{goal}), error(E, _), true)")

  test "Zähler je Basis, über Anfragen hinweg", c do
    assert ask(c, "gensym(a, X), gensym(a, Y), gensym(b, Z)") == ["X = a1, Y = a2, Z = b1"]
    assert ask(c, "gensym(a, X)") == ["X = a3"]
    assert ask(c, "gensym('ein Wort', X)") == ["X = 'ein Wort1'"]
    assert ask(c, "gensym([], X)") == ["X = '[]1'"]
    assert ask(c, "gensym(a, X), atom(X)") == ["X = a4"]
  end

  test "übersteht Backtracking, findall und Ausnahmen", c do
    assert ask(c, "(gensym(a, _), fail ; gensym(a, X))") == ["X = a2"]
    assert ask(c, "findall(X, (gensym(a, X) ; gensym(a, X)), L)") == ["L = [a3, a4]"]
    assert ask(c, "catch((gensym(a, _), throw(x)), x, true), gensym(a, X)") == ["X = a6"]
  end

  test "attributierte Variable: wird geweckt", c do
    assert ask(c, "freeze(X, Y = geweckt), gensym(a, X)") == ["X = a1, Y = geweckt"]
    assert ask(c, "dif(X, a2), gensym(a, X)") == []
    assert ask(c, "dif(X, a2), gensym(a, X)") == ["X = a3"]
  end

  test "reset_gensym/1 und /0", c do
    assert ask(
             c,
             "gensym(a, _), gensym(a, _), gensym(b, _), reset_gensym(a), gensym(a, X), gensym(b, Y)"
           ) ==
             ["X = a1, Y = b2"]

    assert ask(c, "reset_gensym(nie_benutzt)") == ["true"]
    assert ask(c, "reset_gensym, gensym(a, X), gensym(b, Y)") == ["X = a1, Y = b1"]
  end

  test "Fehler wie Scryer", c do
    assert err(c, "gensym(_, _)") == ["E = instantiation_error"]
    assert err(c, "gensym(1, _)") == ["E = type_error(atom, 1)"]
    assert err(c, "gensym(f(x), _)") == ["E = type_error(atom, f(x))"]
    assert err(c, "gensym(a, a1)") == ["E = uninstantiation_error(a1)"]
    # Unique wird zuerst geprüft (must_be(var, Unique) vor atom_si(Base))
    assert err(c, "gensym(_, x)") == ["E = uninstantiation_error(x)"]
    assert err(c, "reset_gensym(_)") == ["E = instantiation_error"]
    assert err(c, "reset_gensym(1)") == ["E = type_error(atom, 1)"]
    # ein Fehler zählt nicht hoch
    assert ask(c, "gensym(a, X)") == ["X = a1"]
  end

  test "current_gensym_base/1 (Erweiterung)", c do
    assert ask(c, "current_gensym_base(B)") == []
    assert ask(c, "current_gensym_base([])") == []

    assert ask(c, "gensym(z, _), gensym(b, _), gensym(b, _), gensym('ä', _), gensym([], _)") ==
             ["true"]

    # Standardordnung, wie sort/2 sie hat
    assert ask(c, "findall(B, current_gensym_base(B), L), msort(L, L)") ==
             ["L = [[], b, z, 'ä']"]

    assert ask(c, "current_gensym_base(b)") == ["true"]
    assert ask(c, "current_gensym_base([])") == ["true"]
    assert ask(c, "current_gensym_base(nie)") == []

    assert ask(c, "reset_gensym(b), findall(B, current_gensym_base(B), L)") == [
             "L = [[], z, 'ä']"
           ]

    # festgehalten beim Aufruf
    assert ask(c, "findall(B, (current_gensym_base(B), gensym(neu, _)), L)") ==
             ["L = [[], z, 'ä']"]

    assert err(c, "current_gensym_base(1)") == ["E = type_error(atom, 1)"]
    assert ask(c, "reset_gensym, current_gensym_base(_)") == []
  end

  test "ohne Import nicht sichtbar", c do
    PrologEx.put_db(%{})
    assert err(c, "gensym(a, _)") == ["E = existence_error(procedure, gensym/2)"]
  end
end
