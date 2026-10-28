defmodule PrologEx.SetupCallCleanupTest do
  # setup_call_cleanup/3 wie SWI und der WG17-Vorschlag (N215); die
  # Beispiele aus Logtalks Konformitätstests bestehen alle (conformance/)
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @program """
  :- dynamic(v/1).
  det(1).
  ndet(aa).
  ndet(bb).
  ndet(_) :- 1 =:= 0.
  log(X) :- assertz(v(X)).
  logs(L) :- findall(X, retract(v(X)), L).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = Enum.reduce(["lists", "iso_ext", "swi"], %{}, &PrologEx.use_library(&2, &1, "user"))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp ask(c, q, n \\ 5) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      c.db
      |> PrologEx.query(g)
      |> Enum.take(n)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    rescue
      e in PrologEx.Error -> {:error, Exception.message(e)}
    end
  end

  test "Cleanup mit den aktuellen Bindungen übersteht die Kompaktierung", c do
    # viele Bindungen in G: die Substitution wird kompaktiert, solange der
    # Rahmen noch liegt; C muss S und X danach noch sehen
    long = "length(_L, 20000), maplist(=(a), _L)"

    assert ask(c, "setup_call_cleanup(S = 1, (X = 2, #{long}), log(S-X)), logs(Z)") ==
             ["S = 1, X = 2, Z = [1-2]"]

    assert ask(c, "setup_call_cleanup(S = 1, (X = 2, #{long}, ndet(_)), log(S-X)), !, logs(Z)") ==
             ["S = 1, X = 2, Z = [1-2]"]

    # gescheitert: C mit den Bindungen nach S (X frei)
    assert ask(c, "\\+ setup_call_cleanup(S = 1, (X = 2, #{long}, fail), log(S-X)), logs([Z])") ==
             ["Z = 1-_A"]
  end

  test "deterministisch: Cleanup sofort, seine Bindungen bleiben", c do
    assert ask(c, "setup_call_cleanup(true, det(X), D = done)") == ["D = done, X = 1"]
    # Scheitern des Cleanups zählt nicht
    assert ask(c, "setup_call_cleanup(true, X = 1, X = 2)") == ["X = 1"]

    assert ask(c, "setup_call_cleanup(log(ss), log(gg), log(cc)), logs(L)") == [
             "L = [ss,gg,cc]"
           ]
  end

  test "Setup läuft wie once/1, ohne Cleanup bei Scheitern", c do
    assert ask(c, "findall(S, setup_call_cleanup((S = 1 ; S = 2), true, true), L)") ==
             ["L = [1]"]

    assert ask(c, "\\+ setup_call_cleanup(fail, true, log(c)), logs(L)") == ["L = []"]
  end

  test "G scheitert oder wirft: Cleanup mit den Bindungen nach dem Setup", c do
    assert ask(c, "\\+ setup_call_cleanup(A = 1, (B = 2, fail), log(A-B)), logs([X])") ==
             ["X = 1-_A"]

    assert ask(c, "catch(setup_call_cleanup(true, throw(oops), log(cc)), E, true), logs(L)") ==
             ["E = oops, L = [cc]"]

    # Ausnahme im Cleanup: die ursprüngliche gewinnt
    assert ask(c, "catch(setup_call_cleanup(true, throw(first), throw(second)), E, true)") ==
             ["E = first"]
  end

  test "Choice Points offen: Cleanup erst beim Cut, mit aktuellen Bindungen", c do
    assert ask(c, "setup_call_cleanup(true, ndet(X), D = done)", 1) == ["X = aa"]

    assert ask(c, "setup_call_cleanup(true, ndet(X), D = done), !") == ["D = done, X = aa"]

    # innen vor außen
    assert ask(
             c,
             "setup_call_cleanup(true, setup_call_cleanup(true, ndet(_), log(inner)), log(outer)), !, logs(L)"
           ) == ["L = [inner,outer]"]
  end

  test "... oder wenn G endgültig scheitert", c do
    assert ask(
             c,
             "(setup_call_cleanup(true, (ndet(X), log(X)), log(done)), fail ; logs(L))"
           ) == ["L = [aa,bb,done]"]
  end

  test "auch once/1, Wenn-dann-sonst, \\+, call_nth/2 und findall/3 schneiden ab", c do
    assert ask(c, "once(setup_call_cleanup(true, ndet(_), log(once))), logs(L)") ==
             ["L = [once]"]

    assert ask(c, "(setup_call_cleanup(true, ndet(_), log(ite)) -> true ; true), logs(L)") ==
             ["L = [ite]"]

    assert ask(c, "\\+ \\+ setup_call_cleanup(true, ndet(_), log(neg)), logs(L)") ==
             ["L = [neg]"]

    assert ask(c, "call_nth(setup_call_cleanup(true, ndet(_), log(nth)), 1), logs(L)") ==
             ["L = [nth]"]

    assert ask(c, "findall(X, setup_call_cleanup(true, ndet(X), log(fa)), Xs), logs(L)") ==
             ["L = [fa], Xs = [aa,bb]"]
  end

  test "findnsols/4: abgeschnittene Teilberechnung mit offenem Rahmen", c do
    assert ask(
             c,
             "findnsols(1, X, setup_call_cleanup(true, ndet(X), log(fn)), L), !, logs(Ls)"
           ) == ["L = [aa], Ls = [fn]"]
  end

  test "Abbruch durch call_with_inference_limit/3: Cleanup läuft", c do
    assert ask(
             c,
             "call_with_inference_limit(setup_call_cleanup(true, (repeat, fail), log(cc)), 1000, R), logs(L)"
           ) == ["L = [cc], R = inference_limit_exceeded"]
  end

  test "Ausnahme aus dem Cleanup nach deterministischem G geht weiter", c do
    assert ask(c, "catch(setup_call_cleanup(true, true, throw(c)), E, true)") == ["E = c"]
  end

  test "call_cleanup/2 (SWI) ist setup_call_cleanup(true, G, C)", c do
    assert ask(c, "call_cleanup(ndet(X), log(cc)), !, logs(L)") == ["L = [cc], X = aa"]
  end

  test "Fehler: alle drei müssen aufrufbar sein (C nach dem Setup)", c do
    assert ask(c, "catch(setup_call_cleanup(_, true, true), error(E, _), true)") ==
             ["E = instantiation_error"]

    assert ask(c, "catch(setup_call_cleanup(true, 1, true), error(E, _), true)") ==
             ["E = type_error(callable,1)"]

    assert ask(c, "catch(setup_call_cleanup(true, X = true, X), error(E, _), true)") ==
             ["E = instantiation_error"]

    # vom Setup gebunden: in Ordnung
    assert ask(c, "setup_call_cleanup(X = true, true, X)") == ["X = true"]
  end
end
