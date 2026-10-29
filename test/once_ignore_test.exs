defmodule PrologEx.OnceIgnoreTest do
  # once/1 und ignore/1 laufen direkt in der Maschine (statt als Klauseln
  # once(G) :- call(G), !. und ignore(G) :- (call(G) -> true ; true).) –
  # mit derselben Semantik
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    :ok
  end

  defp db(c, src) do
    libs = Enum.reduce(["lists", "swi"], %{}, &PrologEx.use_library(&2, &1))
    {db, []} = PrologEx.Consult.load(libs, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    db
  end

  defp goal(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")
    g
  end

  defp ask(c, q, src \\ "") do
    db = db(c, src)
    g = goal(c, q)

    db
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp more(c, q), do: db(c, "") |> PrologEx.solutions(goal(c, q)) |> Enum.map(&elem(&1, 1))
  defp err(c, g), do: ask(c, "catch((#{g}), error(E, _), true)")

  test "erste Lösung, deterministisch; Scheitern", c do
    assert ask(c, "once((member(X, [1, 2, 3]), X > 1))") == ["X = 2"]
    assert more(c, "once(member(_, [a, b]))") == [false]
    assert ask(c, "once(fail)") == []
    assert ask(c, "ignore(member(X, [1, 2]))") == ["X = 1"]
    assert more(c, "ignore(member(_, [a, b]))") == [false]
    assert ask(c, "ignore(fail)") == ["true"]
    # nur die Lösung, kein Weitersuchen davor
    assert ask(c, "findall(X, (member(X, [1, 2]), once(member(_, [a, b]))), L)") == ["L = [1,2]"]
  end

  test "Cut im Ziel bleibt lokal (call/1)", c do
    # beim Aufruf schon gebunden: der Rumpf ist ((!, fail) ; true), der Cut
    # schneidet das ; ab (ISO 7.6.2, wie vorher)
    assert ask(c, "X = !, once(((X, fail) ; true))") == []
    assert ask(c, "X = !, ignore(((X, fail) ; Y = da))") == ["X = !"]
    # beim Aufruf ungebunden: wird call(G), der Cut wirkt nur dort
    assert ask(c, "once(((G = !, G, fail) ; true))") == ["true"]
    assert ask(c, "ignore(((G = !, G, fail) ; Y = da))") == ["Y = da"]
    # once/ignore sind für den umgebenden Cut undurchsichtig
    assert ask(c, "findall(X, (member(X, [1, 2, 3]), once(!)), L)") == ["L = [1,2,3]"]
    assert ask(c, "findall(X, (member(X, [1, 2, 3]), ignore(!)), L)") == ["L = [1,2,3]"]
  end

  test "Fehler wie call/1", c do
    assert err(c, "once(_)") == ["E = instantiation_error"]
    assert err(c, "once(1)") == ["E = type_error(callable,1)"]
    assert err(c, "once((a, 1))") == ["E = type_error(callable,(a,1))"]
    assert err(c, "ignore(_)") == ["E = instantiation_error"]
    assert err(c, "ignore(1)") == ["E = type_error(callable,1)"]
    assert err(c, "once(gibts_nicht)") == ["E = existence_error(procedure,gibts_nicht/0)"]
  end

  test "Modulkontext: das Ziel läuft im Modul des Aufrufers", c do
    src = """
    :- module(m, [m_once/1]).
    :- use_module(library(swi)).
    nur_in_m(ja).
    m_once(X) :- once(nur_in_m(X)).
    """

    assert ask(c, "m_once(X)", src) == ["X = ja"]
    assert ask(c, "m:once(nur_in_m(X))", src) == ["X = ja"]
    assert ask(c, "m:ignore(nur_in_m(X))", src) == ["X = ja"]
    assert err(c, "once(nur_in_m(_))") |> hd() =~ "existence_error(procedure,nur_in_m/1)"
  end

  test "eigene Definition gilt; ignore/1 nur nach Import", c do
    src = """
    once(X) :- X = eigen.
    ignore(X) :- X = auch_eigen.
    """

    assert ask(c, "once(X), ignore(Y)", src) == ["X = eigen, Y = auch_eigen"]

    PrologEx.put_db(%{})
    [{:term, g, _}] = Reader.read_terms(c.reader, "catch(ignore(true), error(E, _), true).")

    assert %{}
           |> PrologEx.query(g)
           |> Enum.take(1)
           |> Enum.map(&PrologEx.format_answer(&1, ["E"])) ==
             ["E = existence_error(procedure,ignore/1)"]

    [{:term, g, _}] = Reader.read_terms(c.reader, "once(true).")
    assert %{} |> PrologEx.query(g) |> Enum.take(1) |> length() == 1
  end

  test "Inferenzen wie bisher (once, G; ignore, G, true)", c do
    d = fn g ->
      [a] =
        ask(
          c,
          "statistics(inferences, A), (#{g} -> true ; true), statistics(inferences, B), D is B - A",
          "p."
        )

      Regex.run(~r/D = (\d+)/, a) |> List.last() |> String.to_integer()
    end

    base = d.("true")
    assert d.("once(p)") - base == 1
    assert d.("ignore(p)") - base == 2
  end
end
