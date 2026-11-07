defmodule PrologEx.ListFreqTest do
  # library(lists): list_frequencies/2, list_runs/2 (gleich heißt ==/2)
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  @src ":- use_module(library(lists)).\n"

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, g), do: ask(c, "catch(#{g}, error(E, _), true)")

  test "list_frequencies/2: Beispiel, Reihenfolge des ersten Vorkommens", c do
    assert ask(c, "list_frequencies([a,a,b,c,c,b,a,b], F)") == ["F = [a-3,b-3,c-2]"]
    assert ask(c, "list_frequencies([a,a,b,c,c,b,a,b], [a-3,b-3,c-2])") == ["true"]
    assert ask(c, "list_frequencies([c,a,c,b], F)") == ["F = [c-2,a-1,b-1]"]
    assert ask(c, "list_frequencies([], F)") == ["F = []"]
    assert ask(c, "list_frequencies([x], F)") == ["F = [x-1]"]
  end

  test "list_frequencies/2: gleich heißt ==/2", c do
    # Variablen: nur gleich mit sich selbst; 1 und 1.0 verschieden
    assert ask(c, "list_frequencies([X,Y,X,f(X),1,1.0,f(X),f(Y)], F)") ==
             ["F = [X-2,Y-1,f(X)-2,1-1,1.0-1,f(Y)-1]"]

    # keine Bindung: X und Y bleiben verschieden
    assert ask(c, "list_frequencies([X,Y], F), X \\== Y") |> hd() =~ "F = [X-1,Y-1]"
    # deterministisch
    assert ask(c, "call_cleanup(list_frequencies([a,b,a], _), Det = true)") == ["Det = true"]
  end

  test "list_runs/2: Beispiel und Grenzfälle", c do
    assert ask(c, "list_runs([a,a,b,c,c,b,a,b], R)") == ["R = [2-a,1-b,2-c,1-b,1-a,1-b]"]
    assert ask(c, "list_runs([a,a,b,c,c,b,a,b], [2-a,1-b,2-c,1-b,1-a,1-b])") == ["true"]
    assert ask(c, "list_runs([], R)") == ["R = []"]
    assert ask(c, "list_runs([a], R)") == ["R = [1-a]"]
    assert ask(c, "list_runs([a,a,a], R)") == ["R = [3-a]"]

    assert ask(c, "list_runs([X,X,Y,1,1.0,f(X),f(X)], R)") ==
             ["R = [2-X,1-Y,1-1,1-1.0,2-f(X)]"]

    assert ask(c, "call_cleanup(list_runs([a,b,a], _), Det = true)") == ["Det = true"]
  end

  test "Fehler: Liste muss fertig sein", c do
    for p <- ["list_frequencies", "list_runs"] do
      assert err(c, "#{p}(_, _)") == ["E = instantiation_error"], p
      assert err(c, "#{p}([a|_], _)") == ["E = instantiation_error"], p
      assert err(c, "#{p}(foo, _)") == ["E = type_error(list,foo)"], p
      assert err(c, "#{p}([a|b], _)") == ["E = type_error(list,[a|b])"], p
    end
  end

  test "groß: n log n", c do
    {us, res} =
      :timer.tc(fn ->
        ask(
          c,
          "numlist(1, 100000, L0), findall(X, (member(Y, L0), X is Y mod 100), L), " <>
            "list_frequencies(L, F), length(F, N)"
        )
      end)

    assert res |> hd() =~ "N = 100"
    assert us < 10_000_000
  end

  test "eigene Definitionen gehen vor", c do
    assert ask(c, "list_runs(a, R)", @src <> "list_runs(a, eigen).\n") == ["R = eigen"]
  end
end
