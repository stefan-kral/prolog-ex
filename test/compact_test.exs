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
  % zwischen den beiden Vorkommen von X liegen andere n/4-Strukturen
  share3(0, X, X) :- !.
  share3(N, X, R) :-
      N1 is N - 1,
      share3(N1, n(N, X, u(n(-1, Y, Y, Y), n(-2, Y, Y, Y)), X), R).
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

  test "geteilte Teilterme mit Variablen: einmal abgelaufen, geteilt kopiert", c do
    # nicht ground (keine Markierung): die Kompaktierung erkennt geteilte
    # Teilterme an der physischen Identität; ohne das 2^40 Pfade
    assert both(c, "\\+ \\+ (share(40, g(_), R), functor(R, F, N), F == f, N == 2).") ==
             ["true"]

    # unten gebunden: die Kompaktierung setzt die Bindung ein und muss den
    # DAG dabei geteilt kopieren
    assert both(
             c,
             "\\+ \\+ (share(40, g(X), R), X = 1, R = f(A, _), A = f(B, _), B = f(_, _))."
           ) == ["true"]

    # Strukturen mit atomarem erstem Argument (wie BDD-Knoten mit ihrer ID)
    assert both(
             c,
             "\\+ \\+ (share(30, g(X), R0), R = n(7, R0, R0), X = 2, R = n(7, f(_, _), _))."
           ) == ["true"]
  end

  test "geteilte Teilterme mit Zahl als erstem Argument (wie BDD-Knoten)", c do
    # Zwischen den beiden Vorkommen von X liegen andere n/4-Strukturen; ohne
    # eigenen Schlüssel je erstem Argument fiele X aus dem Memo, und jede
    # Kompaktierung (hier durch die 300 000 Bindungen) liefe 2^21 Pfade ab.
    # Mit Zeitgrenze im eigenen Prozess, damit ein Rückfall nicht den
    # ganzen Testlauf mit Speicherüberlauf abbricht.
    [{:term, g, _}] =
      Reader.read_terms(
        c.reader,
        "share3(21, g(X), R), X = 1, length(L, 300000), seta(L), R = n(1, _, _, _)."
      )

    db = c.db
    reader = c.reader

    task =
      Task.async(fn ->
        Reader.put_current(reader)
        db |> PrologEx.query(g) |> Enum.take(1) |> length()
      end)

    assert {:ok, 1} = Task.yield(task, 10_000) || Task.shutdown(task, :brutal_kill)
  end

  test "attributierte Variablen in langen Listen bleiben erhalten", c do
    [answer] = both(c, "length(L, 5000), L = [X|_], freeze(X, true), last(L, Y), frozen(X, G).")
    assert answer =~ "G = freeze(X,user:true)"
    assert String.ends_with?(answer, ",_GJF,Y], freeze(X,true)")
  end
end
