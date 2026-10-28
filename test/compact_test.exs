defmodule PrologEx.CompactTest do
  # Kompaktierung der Substitution bei langen Listen: der Listenrücken wird
  # iterativ abgelaufen (auch über gebundene Rest-Variablen), atomar
  # gebundene und freie Variablen kommen nicht ins Memo. Jede Anfrage läuft
  # einmal normal und einmal mit Kompaktierung bei jedem Schritt.
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @program """
  build(0, T, T) :- !.
  build(N, [N|T0], T) :- N1 is N - 1, build(N1, T0, T).
  seta([]).
  seta([a|T]) :- seta(T).
  share(0, X, X) :- !.
  share(N, X, R) :- N1 is N - 1, share(N1, f(X, X), R).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = Enum.reduce(["lists", "apply"], %{}, &PrologEx.use_library(&2, &1, "user"))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  defp both(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    names = PrologEx.query_var_names(g)

    [normal, eager] =
      for t <- [4096, 1] do
        c.db
        |> PrologEx.query(g, compact_threshold: t)
        |> Enum.take(3)
        |> Enum.map(&(PrologEx.format_answer(&1, names) |> normalize()))
      end

    assert normal == eager
    normal
  end

  # frische Variablen nach Reihenfolge des Auftretens benennen
  defp normalize(text) do
    {out, _} =
      Regex.split(~r/_[BG]?\d+/, text, include_captures: true)
      |> Enum.map_reduce(%{}, fn part, seen ->
        if part =~ ~r/^_[BG]?\d+$/ do
          n = Map.get(seen, part, map_size(seen))
          {"_F#{n}", Map.put_new(seen, part, n)}
        else
          {part, seen}
        end
      end)

    Enum.join(out)
  end

  test "lange Liste über verkettete Rest-Variablen", c do
    assert both(c, "build(5, L, T).") == ["L = [5,4,3,2,1|T]"]

    assert both(c, "build(3, L, T), T = [x|U], U = [].") == [
             "L = [3,2,1,x], T = \"x\", U = []"
           ]

    assert both(c, "build(20000, L, []), sum_list(L, S), length(L, N).") |> hd() =~
             "N = 20000, S = 200010000"
  end

  test "Elemente nach und nach gebunden, Rest offen", c do
    assert both(c, "length(L, 4), L = [_, _|R], seta(R).") == ["L = [_A,_B,a,a], R = \"aa\""]

    assert both(c, "length(L, 30000), seta(L), last(L, X), length(L, N), msort(L, [a|_]).")
           |> hd() =~ ", N = 30000, X = a"
  end

  test "geteilte Teilterme bleiben geteilt (kein exponentielles Aufblähen)", c do
    # R ist ein DAG mit 2^40 Pfaden; ohne Memo würde die Kompaktierung
    # (bei jedem Schritt) ihn ausrollen
    assert both(c, "\\+ \\+ (share(40, a, R), functor(R, F, N), F == f, N == 2).") == ["true"]
  end

  test "attributierte Variablen in langen Listen bleiben erhalten", c do
    [answer] = both(c, "length(L, 5000), L = [X|_], freeze(X, true), last(L, Y), frozen(X, G).")
    assert answer =~ "G = freeze(X,user:true)"
    assert String.ends_with?(answer, ",_GJF,Y], freeze(X,true)")
  end
end
