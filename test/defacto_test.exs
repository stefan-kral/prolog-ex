defmodule PrologEx.DefactoTest do
  # De-facto-Standardprädikate (SWI, SICStus), Erwartungen nach Logtalks
  # Konformitätstests: plus/3, numbervars/3, atomic_list_concat/2,3
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Stream.reset()
    PrologEx.put_db(%{})
    {:ok, f: Path.join(c.tmp_dir, "x.txt")}
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch(#{goal}, error(E, _), true)")

  test "plus/3", c do
    assert ask(c, "plus(1, 2, N)") == ["N = 3"]
    assert ask(c, "plus(1, N, 3)") == ["N = 2"]
    assert ask(c, "plus(N, 2, 3)") == ["N = 1"]
    assert ask(c, "plus(1, 2, 4)") == []
    assert ask(c, "plus(-5, 2, N)") == ["N = -3"]
    assert ask(c, "plus(100000000000000000000, 1, N)") == ["N = 100000000000000000001"]
    assert err(c, "plus(_, _, 1)") == ["E = instantiation_error"]
    assert err(c, "plus(1, _, _)") == ["E = instantiation_error"]
    assert err(c, "plus(a, 1, _)") == ["E = type_error(integer, a)"]
    assert err(c, "plus(_, 1, a)") == ["E = type_error(integer, a)"]
    assert err(c, "plus(1.0, 1, _)") == ["E = type_error(integer, 1.0)"]
  end

  test "numbervars/3", c do
    assert ask(c, "numbervars(t, 0, N)") == ["N = 0"]
    assert ask(c, "numbervars(t, 0, 1)") == []

    assert ask(
             c,
             "T = a(X, 1, b(Y, c(X)), W), numbervars(T, 3, N), T == a('$VAR'(3), 1, b('$VAR'(4), c('$VAR'(3))), '$VAR'(5))"
           )
           |> hd() =~ "N = 6"

    assert ask(c, "numbervars(f(X, Y), -7, N), X == '$VAR'(-7)") |> hd() =~ "N = -5"
    assert err(c, "numbervars(_, _, _)") == ["E = instantiation_error"]
    assert err(c, "numbervars(_, a, _)") == ["E = type_error(integer, a)"]
    assert err(c, "numbervars(_, 1, a)") == ["E = type_error(integer, a)"]
  end

  test "atomic_list_concat/2", c do
    assert ask(c, "atomic_list_concat([], R)") == ["R = ''"]

    assert ask(c, "atomic_list_concat([a, 1, b, '', +, 2.0, [], c, -3.5], R)") ==
             ["R = 'a1b+2.0[]c-3.5'"]

    assert ask(c, "atomic_list_concat([a, b], ab)") == ["true"]
    assert ask(c, "atomic_list_concat([a, b], ba)") == []
    assert err(c, "atomic_list_concat([_, bar], foobar)") == ["E = instantiation_error"]
    assert err(c, "atomic_list_concat([foo|_], foobar)") == ["E = instantiation_error"]
    assert err(c, "atomic_list_concat([a(1), bar], R)") == ["E = type_error(atomic, a(1))"]
    assert err(c, "atomic_list_concat([foo, bar], a(1))") == ["E = type_error(atom, a(1))"]
  end

  test "atomic_list_concat/3, auch zerlegen", c do
    assert ask(c, "atomic_list_concat([a, 42, c], '_', A)") == ["A = a_42_c"]
    assert ask(c, "atomic_list_concat([], '-', A)") == ["A = ''"]
    assert ask(c, "atomic_list_concat(L, '-', 'a-b--c')") == ["L = [a, b, '', c]"]
    assert ask(c, "atomic_list_concat([a, X], '-', 'a-b')") == ["X = b"]
    assert ask(c, "atomic_list_concat(L, ', ', 'xx, yy')") == ["L = [xx, yy]"]
    assert err(c, "atomic_list_concat([_, bar], '_', _)") == ["E = instantiation_error"]
    assert err(c, "atomic_list_concat([foo, bar], _, _)") == ["E = instantiation_error"]
    assert err(c, "atomic_list_concat([foo, bar], a(1), _)") == ["E = type_error(atomic, a(1))"]
    assert err(c, "atomic_list_concat([foo, bar], '_', a(1))") == ["E = type_error(atom, a(1))"]
    # leerer Trenner: nicht zerlegen
    assert err(c, "atomic_list_concat(L, '', abc)") == ["E = instantiation_error"]
  end
end
