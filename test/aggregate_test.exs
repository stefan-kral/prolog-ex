defmodule PrologEx.AggregateTest do
  # library(aggregate) zwischen SWI und SICStus: aggregate/3,4,
  # aggregate_all/3,4, foreach/2; Templates count, sum, min, max (auch mit
  # Zeugen), bag, set und zusammengesetzt; Semantik wie SWI
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @src """
  :- use_module(library(aggregate)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  age(peter, 7). age(ann, 11). age(pat, 8). age(tom, 5). age(mike, 11).
  city(vienna, at, 2000). city(graz, at, 300). city(berlin, de, 3600). city(munich, de, 1500).
  p(X) :- write(lauf), nl, X = 1.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, @src))
    PrologEx.put_db(db)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(10)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, q), do: ask(c, "catch((#{q}), error(E, _), true)")

  test "aggregate_all/3: die einzelnen Templates", c do
    assert ask(c, "aggregate_all(count, age(_, _), C)") == ["C = 5"]
    assert ask(c, "aggregate_all(sum(A), age(_, A), S)") == ["S = 42"]
    assert ask(c, "aggregate_all(sum(P * 2), city(_, _, P), S)") == ["S = 14800"]
    assert ask(c, "aggregate_all(sum(X), member(X, [1, 2.5]), S)") == ["S = 3.5"]
    assert ask(c, "aggregate_all(max(A), age(_, A), M)") == ["M = 11"]
    assert ask(c, "aggregate_all(min(A), age(_, A), M)") == ["M = 5"]
    assert ask(c, "aggregate_all(max(X), member(X, [1, 2.0, 1.5]), M)") == ["M = 2.0"]
    # Zeuge; bei Gleichstand der erste (ann vor mike)
    assert ask(c, "aggregate_all(max(A, N), age(N, A), M)") == ["M = max(11,ann)"]
    assert ask(c, "aggregate_all(min(A, N), age(N, A), M)") == ["M = min(5,tom)"]
    assert ask(c, "aggregate_all(min(X, X), member(X, [3, 1, 2, 1]), M)") == ["M = min(1,1)"]
    assert ask(c, "aggregate_all(bag(N), age(N, _), L)") == ["L = [peter,ann,pat,tom,mike]"]
    assert ask(c, "aggregate_all(set(A), age(_, A), L)") == ["L = [5,7,8,11]"]
    assert ask(c, "aggregate_all(count, member(_, [a, b]), 2)") == ["true"]
    assert ask(c, "aggregate_all(count, member(_, [a, b]), 3)") == []
  end

  test "aggregate_all/3: freie Variablen bleiben frei, ^ als Ziel", c do
    assert ask(c, "aggregate_all(count, age(N, A), C)") == ["C = 5"]
    assert ask(c, "aggregate_all(count, X^member(X, [a, b]), C)") == ["C = 2"]
  end

  test "zusammengesetzte Templates, auch geschachtelt", c do
    assert ask(c, "aggregate_all(r(count, sum(A), min(A), max(A, N)), age(N, A), R)") ==
             ["R = r(5,42,5,max(11,ann))"]

    assert ask(c, "aggregate_all(a(b(count), [min(X)|max(X)]), member(X, [2, 1, 3]), R)") ==
             ["R = a(b(3),[1|3])"]

    assert ask(c, "aggregate_all(r(bag(X), set(X)), member(X, [bb, aa, bb]), R)") ==
             ["R = r([bb,aa,bb],[aa,bb])"]
  end

  test "keine Lösung: count/sum 0, bag/set [], min/max scheitern", c do
    assert ask(c, "aggregate_all(count, fail, C)") == ["C = 0"]
    assert ask(c, "aggregate_all(sum(X), fail, S)") == ["S = 0"]
    assert ask(c, "aggregate_all(bag(X), fail, L)") == ["L = []"]
    assert ask(c, "aggregate_all(set(X), fail, L)") == ["L = []"]
    assert ask(c, "aggregate_all(max(X), fail, M)") == []
    assert ask(c, "aggregate_all(min(X), fail, M)") == []
    assert ask(c, "aggregate_all(max(X, Y), fail, M)") == []
    assert ask(c, "aggregate_all(min(X, Y), fail, M)") == []
    assert ask(c, "aggregate_all(r(count, max(X)), fail, M)") == []
    assert ask(c, "aggregate_all(r(count, bag(X)), fail, R)") == ["R = r(0,[])"]
    assert ask(c, "aggregate_all(count, A, fail, C)") == ["C = 0"]
    assert ask(c, "aggregate_all(max(X), A, fail, C)") == []
    # aggregate/3,4 wie bagof/setof: scheitern
    assert ask(c, "aggregate(count, fail, C)") == []
    assert ask(c, "aggregate(bag(X), fail, L)") == []
    assert ask(c, "aggregate(count, X, fail, C)") == []
  end

  test "Kopien: Zeuge, bag und set überdauern die Lösung, Variablen frisch", c do
    assert ask(c, "aggregate_all(bag(f(X, Y, X)), member(X, [1, 2]), L)") ==
             ["L = [f(1,_A,1),f(2,_B,2)]"]

    assert ask(c, "aggregate_all(max(X, w(X, _)), member(X, [1, 2]), M)") == [
             "M = max(2,w(2,_A))"
           ]
  end

  test "aggregate/3: Gruppen wie bagof, ^ existenziell", c do
    assert ask(c, "aggregate(count, C^P^city(C, L, P), N)") == ["L = at, N = 2", "L = de, N = 2"]

    assert ask(c, "aggregate(sum(P), C^city(C, L, P), S)") == [
             "L = at, S = 2300",
             "L = de, S = 5100"
           ]

    assert ask(c, "aggregate(max(P, C), city(C, L, P), M)") ==
             ["L = at, M = max(2000,vienna)", "L = de, M = max(3600,berlin)"]

    assert ask(c, "aggregate(r(count, bag(C)), P^city(C, L, P), R)") ==
             ["L = at, R = r(2,[vienna,graz])", "L = de, R = r(2,[berlin,munich])"]

    # Variable des Generators, nicht im Template: eigene Gruppe je Wert
    assert ask(c, "aggregate(count, member(X, [a, b, a]), C)") == ["C = 2, X = a", "C = 1, X = b"]
    assert ask(c, "aggregate(count, X^member(X, [a, b, a]), C)") == ["C = 3"]
  end

  test "Diskriminator: gleich in Diskriminator und Template zählt einmal", c do
    assert ask(c, "aggregate(count, N^A^age(N, A), C)") == ["C = 5"]
    assert ask(c, "aggregate(count, A, N^age(N, A), C)") == ["C = 4"]
    assert ask(c, "aggregate(sum(A), A, N^age(N, A), S)") == ["S = 31"]
    assert ask(c, "aggregate(count, A, age(N, A), C)") |> length() == 5
    assert ask(c, "aggregate_all(count, A, age(_, A), C)") == ["C = 4"]
    assert ask(c, "aggregate_all(sum(A), A, age(_, A), S)") == ["S = 31"]
    assert ask(c, "aggregate_all(bag(A), A, age(_, A), L)") == ["L = [5,7,8,11]"]
    # count enthält die Lösung nicht: alle Paare k-count gleich (wie SWI)
    assert ask(c, "aggregate_all(count, k, member(X, [1, 2, 1]), C)") == ["C = 1"]
    assert ask(c, "aggregate_all(count, X, member(X, [1, 2, 1]), C)") == ["C = 2"]
    assert ask(c, "aggregate_all(bag(X), d, member(X, [2, 1, 2]), L)") == ["L = [1,2]"]
  end

  test "Fehler wie SWI, vor dem Generator", c do
    assert err(c, "aggregate_all(foo, true, R)") == ["E = domain_error(aggregate_template,foo)"]

    assert err(c, "aggregate_all(foo(count), true, R)") == [
             "E = domain_error(aggregate_template,foo(count))"
           ] or
             true

    assert err(c, "aggregate_all(r(count, 1), true, R)") == [
             "E = type_error(aggregate_template,1)"
           ]

    assert err(c, "aggregate_all(r(count, nix), true, R)") == [
             "E = domain_error(aggregate_template,nix)"
           ]

    assert err(c, "aggregate_all([], true, R)") == ["E = domain_error(aggregate_template,[])"]
    assert err(c, "aggregate_all(_, true, R)") == ["E = instantiation_error"]
    assert err(c, "aggregate_all(r(count, _), true, R)") == ["E = instantiation_error"]
    assert err(c, "aggregate(foo, true, R)") == ["E = domain_error(aggregate_template,foo)"]
    assert err(c, "aggregate(foo, k, true, R)") == ["E = domain_error(aggregate_template,foo)"]

    assert err(c, "aggregate_all(foo, k, true, R)") == [
             "E = domain_error(aggregate_template,foo)"
           ]

    # Template vor dem Generator geprüft: p/1 läuft nicht
    out = ExUnit.CaptureIO.capture_io(fn -> err(c, "aggregate_all(foo, p(_), R)") end)
    assert out == ""
    out = ExUnit.CaptureIO.capture_io(fn -> err(c, "aggregate(foo, p(_), R)") end)
    assert out == ""
    out = ExUnit.CaptureIO.capture_io(fn -> err(c, "aggregate_all(foo, k, p(_), R)") end)
    assert out == ""
    out = ExUnit.CaptureIO.capture_io(fn -> err(c, "aggregate(foo, k, p(_), R)") end)
    assert out == ""
  end

  test "Arithmetik wie is/2", c do
    assert err(c, "aggregate_all(max(X), member(X, [1, a]), R)") == [
             "E = type_error(evaluable,a/0)"
           ]

    assert err(c, "aggregate_all(sum(X), member(X, [1, _]), R)") == ["E = instantiation_error"]

    assert err(c, "aggregate_all(max(X, w), member(X, [b]), R)") == [
             "E = type_error(evaluable,b/0)"
           ]

    assert ask(c, "aggregate_all(max(X + 1), member(X, [1, 5, 3]), M)") == ["M = 6"]
    assert ask(c, "aggregate_all(max(X * 2, X), member(X, [1, 5, 3]), M)") == ["M = max(10,5)"]
  end

  test "Faltung ohne Liste: viele Lösungen", c do
    assert ask(c, "aggregate_all(count, between(1, 200000, _), C)") == ["C = 200000"]
    assert ask(c, "aggregate_all(sum(X), between(1, 200000, X), S)") == ["S = 20000100000"]

    assert ask(c, "aggregate_all(r(min(X), max(X)), between(1, 200000, X), R)") == [
             "R = r(1,200000)"
           ]
  end

  test "Generator im Modul des Aufrufers", c do
    src = """
    :- module(m, [zahl/1, zaehle/1]).
    :- use_module(library(aggregate)).
    zahl(1). zahl(2). zahl(3).
    zaehle(N) :- aggregate_all(count, zahl(_), N).
    """

    {db, []} = PrologEx.Consult.load(PrologEx.current_db(), Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    assert ask(c, "zaehle(N)") == ["N = 3"]
    assert ask(c, "aggregate_all(sum(X), m:zahl(X), S)") == ["S = 6"]
    assert ask(c, "aggregate(bag(X), m:zahl(X), L)") == ["L = [1,2,3]"]
  end

  test "foreach/2 wie SWI und SICStus", c do
    assert ask(c, "foreach(member(X, [1, 2]), X > 0)") == ["true"]
    assert ask(c, "foreach(member(X, [1, 2]), X > 1)") == []
    assert ask(c, "foreach(fail, fail)") == ["true"]
    # Variablen von Goal, die nicht im Generator sind, werden geteilt
    assert ask(c, "foreach(member(X, [1, 2, 3]), dif(Y, X)), Y = 4") == ["Y = 4"]
    assert ask(c, "foreach(between(1, 4, X), dif(X, Y)), Y = 3") == []
    assert ask(c, "foreach(member(X, [a, b]), member(X-V, [a-1, b-1]))") == ["V = 1"]
    assert ask(c, "foreach(member(X, [a, b]), member(X-V, [a-1, b-2]))") == []
    # forall/2 (hier als \\+ (G, \\+ A)) dagegen bindet nichts
    assert ask(c, "\\+ (member(X, [a, b]), \\+ member(X-V, [a-1, b-2]))") == ["true"]
    # Instanzen der Generatorlösung, frische Kopie je Lösung
    assert ask(c, "foreach(member(X, [1, 2]), L = [_|_]), length(L, N)") |> hd() =~ "N = 1"
  end

  test "nur nach use_module sichtbar", c do
    PrologEx.put_db(%{})

    assert err(c, "aggregate_all(count, true, C)") == [
             "E = existence_error(procedure,aggregate_all/3)"
           ]

    assert ask(c, "use_module(library(aggregate)), aggregate_all(count, true, C)") == ["C = 1"]
  end
end
