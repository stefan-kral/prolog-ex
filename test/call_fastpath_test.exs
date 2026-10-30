defmodule PrologEx.CallFastpathTest do
  # call/1..8: Atom oder Struktur ohne Steuer-Funktor (',' ';' '->' '*->'
  # ':') geht ohne Rumpfumwandlung direkt los; alles andere wie bisher
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

  defp err(c, g), do: ask(c, "catch((#{g}), error(E, _), true)")

  test "Atom, Struktur, Zusatzargumente", c do
    src = "p. q(X, Y) :- Y is X + 1. r(A, B, C) :- C is A * B."
    assert ask(c, "call(p)", src) == ["true"]
    assert ask(c, "call(q, 1, Y)", src) == ["Y = 2"]
    assert ask(c, "call(q(1), Y)", src) == ["Y = 2"]
    assert ask(c, "call(r, 2, 3, Z)", src) == ["Z = 6"]
    assert ask(c, "G = q(4), call(G, Y)", src) == ["G = q(4), Y = 5"]
    assert ask(c, "call(member(X), [a,b])") == ["X = a", "X = b"]
    assert ask(c, "call(format, \"~w~n\", [x])") == ["true"]
    assert ask(c, "call(=(X), f(Y)), Y = 1") == ["X = f(1), Y = 1"]
  end

  test "Schnitt bleibt lokal", c do
    src = "t(X) :- member(X, [1,2,3]), call(!). u(X) :- call(member(X), [1,2]), call(!)."
    assert ask(c, "t(X)", src) == ["X = 1", "X = 2", "X = 3"]
    assert ask(c, "u(X)", src) == ["X = 1", "X = 2"]
    assert ask(c, "member(X, [1,2]), call(!)") == ["X = 1", "X = 2"]
  end

  test "Steuerkonstrukte und M:G wie bisher (mit Rumpfumwandlung)", c do
    assert ask(c, "X = !, call((member(Y, [1,2]), X))") == ["X = !, Y = 1"]
    assert ask(c, "call((fail ; true))") == ["true"]
    assert ask(c, "call((true -> X = a ; X = b))") == ["X = a"]
    assert ask(c, "call(',', X = 1, Y = 2)") == ["X = 1, Y = 2"]
    assert ask(c, "call(;, fail, X = 1)") == ["X = 1"]
    assert ask(c, "call(->, true, X = 1)") == ["X = 1"]
    assert ask(c, "call(','(X = 1), Y = 2)") == ["X = 1, Y = 2"]
    assert ask(c, "call(lists:append([1]), [2], L)") == ["L = [1,2]"]
    assert ask(c, "call(lists:member, X, [a])") == ["X = a"]
  end

  # Variable beim Aufruf ungebunden, später ! → wird call(G), der Schnitt
  # bleibt darin (ohne Umwandlung schnitte er die Disjunktion weg)
  test "Rumpfumwandlung auch bei call/N mit Steuer-Funktor", c do
    k = "(G = !, G, fail ; true)"
    assert ask(c, "findall(ja, call(;, (G = !, G, fail), true), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(;((G = !, G, fail)), true), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(',', #{k}, true), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(','(#{k}), true), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(->, true, #{k}), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(->(true), #{k}), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(*->, true, #{k}), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(lists:(#{k})), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(#{k}), L)") == ["L = [ja]"]
  end

  test "M:G mit Atom-Modul direkt; gebundene Variable innen", c do
    src = """
    :- module(m, []).
    nur_in_m(X, Y) :- Y is X * 10.
    """

    assert ask(c, "call(m:nur_in_m(2), Y)", src) == ["Y = 20"]
    assert ask(c, "call(m:nur_in_m, 3, Y)", src) == ["Y = 30"]
    assert ask(c, "M = m, call(M:nur_in_m, 1, Y)", src) == ["M = m, Y = 10"]
    assert ask(c, "call(m:nur_in_m(1, Y))", src) == ["Y = 10"]
    assert ask(c, "maplist(m:nur_in_m, [1,2], L)", src) == ["L = [10,20]"]
    # früher instantiation_error: das innere Ziel wurde nicht dereferenziert
    assert ask(c, "G = member(X), call(lists:G, [a])") == ["G = member(a), X = a"]
    assert ask(c, "G = member, call(lists:G, X, [a])") == ["G = member, X = a"]
    assert ask(c, "G = member(X, [ja]), call(lists:G)") == ["G = member(ja,[ja]), X = ja"]
    assert ask(c, "G = m:nur_in_m(4), call(G, Y)", src) == ["G = m:nur_in_m(4), Y = 40"]

    assert ask(c, "G = (;), findall(ja, call(lists:G, (H = !, H, fail), true), L)") ==
             ["G = (;), L = [ja]"]

    # Schnitt bleibt lokal, auch in M:G
    assert ask(c, "member(X, [1,2]), call(lists:!)") == ["X = 1", "X = 2"]
    # verschachtelt und Steuer-Funktor: allgemeiner Weg
    assert ask(c, "call(lists:lists:member, X, [a])") == ["X = a"]
    assert ask(c, "findall(ja, call(lists:(G = !, G, fail ; true)), L)") == ["L = [ja]"]
    assert ask(c, "findall(ja, call(lists:(;), (G = !, G, fail), true), L)") == ["L = [ja]"]
  end

  test "M:G Fehler wie bisher", c do
    assert err(c, "call(_:p)") == ["E = instantiation_error"]
    assert err(c, "call(_:p, 1)") == ["E = instantiation_error"]
    assert err(c, "call(1:p)") == ["E = type_error(module,1)"]
    assert err(c, "call(lists:_)") == ["E = instantiation_error"]
    assert err(c, "call(lists:_, 1)") == ["E = instantiation_error"]
    assert err(c, "call(lists:1)") == ["E = type_error(callable,lists:1)"]
    assert err(c, "call(lists:1, a)") == ["E = type_error(callable,1)"]

    assert err(c, "call(lists:gibts_nicht, 1)") ==
             ["E = existence_error(procedure,lists:gibts_nicht/1)"]
  end

  test "Fehler wie bisher", c do
    assert err(c, "call(_)") == ["E = instantiation_error"]
    assert err(c, "call(_, a)") == ["E = instantiation_error"]
    assert err(c, "call(1)") == ["E = type_error(callable,1)"]
    assert err(c, "call(1, a)") == ["E = type_error(callable,1)"]
    assert err(c, "call((a, 1))") == ["E = type_error(callable,(a,1))"]
    assert err(c, "call(',', a, 1)") == ["E = type_error(callable,(a,1))"]
    assert err(c, "call(gibts_nicht, 1)") == ["E = existence_error(procedure,gibts_nicht/1)"]
    assert err(c, "call(p(1), 2)") == ["E = existence_error(procedure,p/2)"]
  end

  test "Inferenzen wie bisher", c do
    d = fn g ->
      [a] =
        ask(
          c,
          "statistics(inferences, A), (#{g} -> true ; true), statistics(inferences, B), D is B - A",
          "p. q(_, _)."
        )

      Regex.run(~r/D = (\d+)/, a) |> List.last() |> String.to_integer()
    end

    base = d.("true")
    assert d.("call(p)") - base == 0
    assert d.("call(q, 1, 2)") - base == 0
    assert d.("call(q(1), 2)") - base == 0
    assert d.("call((p, p))") - base == 1
  end
end
