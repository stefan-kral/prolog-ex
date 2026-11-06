defmodule PrologEx.ClpzCumulativeTest do
  # cumulative/2: Bei fester Dauer D zerlegt PrologEx „Aufgabe läuft zum
  # Zeitpunkt T“ in ein reifiziertes in/2 (Start in T-D+1..T) statt in
  # Triskas T #>= Start #/\ T #< End. Geprüft gegen die ursprüngliche
  # Zerlegung, hier im Programm nachgebaut (model_ref): dieselben Lösungen.
  # Mit einer variablen Dauer nimmt cumulative/2 den allgemeinen Weg.
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}

  @program """
  model_cum(H, Ds, L, Starts) :-
      length(Ds, N), length(Starts, N), Starts ins 0..H,
      maplist(mk_task, Starts, Ds, Tasks),
      cumulative(Tasks, [limit(L)]).
  mk_task(S, D, task(S, D, _, 1, _)).

  % die ursprüngliche Zerlegung, je Zeitpunkt
  model_ref(H, Ds, L, Starts) :-
      length(Ds, N), length(Starts, N), Starts ins 0..H,
      maplist(#=<(0), Ds),
      TEnd is H + 4, numlist(0, TEnd, Ts),
      maplist(slot(Starts, Ds, L), Ts).
  slot(Starts, Ds, L, T) :- maplist(running(T), Starts, Ds, Bs), sum(Bs, #=<, L).
  running(T, S, D, B) :- ((T #>= S) #/\\ (T #< S + D)) #<==> B.

  % Dauern aus einer Beschreibung: Zahl, oder Lo-Hi für eine Variable mit
  % dieser Domäne (in jedem Durchlauf frisch)
  mk_d(D, D) :- integer(D).
  mk_d(Lo-Hi, D) :- D in Lo..Hi.

  sols(M, H, Spec, L, Sorted) :-
      findall(Ds-S, (maplist(mk_d, Spec, Ds), call(M, H, Ds, L, S),
                     term_variables(Ds, DVs), append(DVs, S, Vs), label(Vs)), Ls),
      msort(Ls, Sorted).

  same(H, Ds, L, N) :-
      sols(model_cum, H, Ds, L, A),
      sols(model_ref, H, Ds, L, B),
      A == B, length(A, N).
  """

  # erst clpz laden (seine Operatoren), dann das Programm lesen
  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ["clpz", "lists"])
    PrologEx.put_db(db)
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.put(:prolog_ex_ops, c.ops)
    PrologEx.put_db(c.db)
    :ok
  end

  defp run(c, q), do: c.reader |> TableCase.run(c.db, q) |> elem(1)

  test "feste Dauern: dieselben Lösungen wie die ursprüngliche Zerlegung", c do
    for {h, ds, l} <- [{6, "[3,4,2,3]", 2}, {7, "[2,2,3]", 1}, {5, "[1,3,2,2]", 3}, {4, "[5]", 1}] do
      assert {:answers, [ans]} = run(c, "same(#{h}, #{ds}, #{l}, N)"), inspect({h, ds, l})
      assert ans =~ ~r/^N = [1-9]/, inspect({h, ds, l, ans})
    end
  end

  test "eine variable Dauer: der allgemeine Weg, dieselben Lösungen", c do
    assert {:answers, [ans]} = run(c, "same(6, [3,2-3,2], 1, N)")
    assert ans =~ ~r/N = [1-9]/
  end

  test "Optimum wie im Beispiel von Triska", c do
    assert {:answers, [ans]} =
             run(
               c,
               "Ts = [task(S1,3,E1,1,_),task(S2,4,E2,1,_),task(S3,2,E3,1,_),task(S4,3,E4,1,_)], " <>
                 "S = [S1,S2,S3,S4], S ins 0..100, cumulative(Ts, [limit(2)]), " <>
                 "E #= max(max(E1,E2),max(E3,E4)), once(labeling([min(E)], S))"
             )

    assert ans =~ "E = 6", ans
    assert ans =~ "S = [0,0,4,3]", ans
  end
end
