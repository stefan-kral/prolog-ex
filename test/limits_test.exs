defmodule PrologEx.LimitsTest do
  # call_with_inference_limit/3 (wie SWI und Scryer), call_with_depth_limit/3
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag timeout: 30_000

  # count(N) kostet 2N+1 Inferenzen (je Ebene count/1 und is/2, dazu count(0))
  @program """
  loop :- loop.
  count(0) :- !.
  count(N) :- N1 is N-1, count(N1).
  p :- q.
  q.
  p2 :- X is 1+1, X > 0.
  lloop :- lloop, q.
  nat(0).
  nat(s(X)) :- nat(X).
  inc(X, Y) :- Y is X + 1.
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

  test "Ergebnis: ! (deterministisch), true (Choice Points), exceeded", c do
    assert ask(c, "call_with_inference_limit(true, 1, R)") == ["R = !"]
    assert ask(c, "call_with_inference_limit(count(10), 21, R)") == ["R = !"]

    assert ask(c, "call_with_inference_limit(count(10), 20, R)") == [
             "R = inference_limit_exceeded"
           ]

    assert ask(c, "call_with_inference_limit(true, 0, R)") == ["R = inference_limit_exceeded"]
    assert ask(c, "call_with_inference_limit(loop, 1000, R)") == ["R = inference_limit_exceeded"]

    assert ask(c, "call_with_inference_limit(member(X, [a, b, c]), 10, R)") ==
             ["R = true, X = a", "R = true, X = b", "R = !, X = c"]

    assert ask(c, "call_with_inference_limit(fail, 10, R)") == []

    # deterministisch heißt: kein Choice Point bleibt (auch nicht der Rahmen)
    assert ask(c, "call_with_inference_limit(call_with_inference_limit(true, 5, R1), 5, R)") ==
             ["R = !, R1 = !"]

    assert ask(
             c,
             "call_with_inference_limit(call_with_inference_limit(member(X, [1, 2]), 5, R1), 9, R)"
           ) == ["R = true, R1 = true, X = 1", "R = !, R1 = !, X = 2"]
  end

  test "die Grenze gilt je Lösung: Backtracking in G gibt ein frisches Kontingent", c do
    # Lösung X kostet 2X+2 (member beim ersten Mal, count(X)); zusammen 16
    assert ask(c, "call_with_inference_limit((member(X, [1, 2, 3]), count(X)), 8, R)") ==
             ["R = true, X = 1", "R = true, X = 2", "R = !, X = 3"]

    # die dritte Lösung allein braucht 7: abgebrochen, danach nichts mehr
    assert ask(c, "call_with_inference_limit((member(X, [1, 2, 3]), count(X)), 6, R)") ==
             ["R = true, X = 1", "R = true, X = 2", "R = inference_limit_exceeded"]
  end

  test "außerhalb von G gilt keine Grenze", c do
    assert ask(c, "call_with_inference_limit(true, 5, R), count(100)") == ["R = !"]

    # nach der letzten Lösung und nach dem Backtracking aus G heraus
    assert ask(c, "call_with_inference_limit(member(X, [1, 2]), 5, _), X > 1, count(100)") ==
             ["X = 2"]

    assert ask(c, "(call_with_inference_limit(fail, 5, _) ; count(100))") == ["true"]

    # Ausnahme aus G: die Grenze verschwindet mit dem Rahmen
    assert ask(c, "catch(call_with_inference_limit(throw(x), 10, _), E, true), count(100)") ==
             ["E = x"]

    # nach einer Überschreitung ebenso
    assert ask(c, "call_with_inference_limit(loop, 10, R), count(100)") ==
             ["R = inference_limit_exceeded"]
  end

  test "R wird unifiziert: passt es nicht, geht es mit der nächsten Lösung weiter", c do
    assert ask(c, "call_with_inference_limit(member(X, [1, 2]), 10, !)") == ["X = 2"]
    assert ask(c, "call_with_inference_limit(loop, 10, true)") == []
  end

  test "G kann die Überschreitung nicht verschlucken", c do
    assert ask(c, "call_with_inference_limit(catch(loop, _, true), 100, R)") ==
             ["R = inference_limit_exceeded"]

    assert ask(c, "call_with_inference_limit(catch(loop, _, loop), 100, R)") ==
             ["R = inference_limit_exceeded"]

    # die Ausnahme ist sichtbar wie in SWI
    assert ask(c, "call_with_inference_limit(catch(loop, E, true), 100, R)") ==
             ["R = inference_limit_exceeded"]
  end

  test "ein geworfenes inference_limit_exceeded ohne Überschreitung geht durch", c do
    assert ask(
             c,
             "catch(call_with_inference_limit(throw(inference_limit_exceeded), 100, R), E, true)"
           ) == ["E = inference_limit_exceeded"]
  end

  test "verschachtelt: die strengere Grenze gilt", c do
    # äußere strenger: die äußere meldet, die innere kommt nicht dazu
    assert ask(c, "call_with_inference_limit(call_with_inference_limit(loop, 1000, R1), 100, R)") ==
             ["R = inference_limit_exceeded"]

    # innere strenger: die innere meldet, außen geht es normal weiter
    assert ask(c, "call_with_inference_limit(call_with_inference_limit(loop, 100, R1), 1000, R)") ==
             ["R = !, R1 = inference_limit_exceeded"]

    # die innere darf die äußere nicht verlängern
    assert ask(
             c,
             "call_with_inference_limit((count(40), call_with_inference_limit(count(40), 1000, R1)), 100, R)"
           ) == ["R = inference_limit_exceeded"]
  end

  test "Unter-Maschinen (findall, \\+, forall) zählen mit", c do
    assert ask(c, "call_with_inference_limit(findall(X, loop, _), 100, R)") ==
             ["R = inference_limit_exceeded"]

    assert ask(c, "call_with_inference_limit(\\+ loop, 100, R)") ==
             ["R = inference_limit_exceeded"]

    assert ask(c, "call_with_inference_limit(forall(member(X, [1, 2]), loop), 100, R)") ==
             ["R = inference_limit_exceeded"]

    assert ask(c, "call_with_inference_limit(findall(X, member(X, [1, 2]), L), 100, R)") ==
             ["L = [1,2], R = !"]
  end

  test "Fehler", c do
    assert ask(c, "call_with_inference_limit(true, L, R)") == {:error, "instantiation_error"}

    assert ask(c, "call_with_inference_limit(true, -1, R)") ==
             {:error, "domain_error(not_less_than_zero, -1)"}

    assert ask(c, "call_with_inference_limit(true, a, R)") ==
             {:error, "type_error(integer, a)"}

    assert ask(c, "call_with_inference_limit(G, 10, R)") == {:error, "instantiation_error"}
  end

  # --- call_with_depth_limit/3 --------------------------------------------
  # Ebenen bilden nur Benutzerprädikate mit Klauseln; G ist Ebene 1

  test "Tiefe: Beispiele aus der Planung", c do
    assert ask(c, "call_with_depth_limit(true, 5, R)") == ["R = 1"]
    # Steuerkonstrukte sind durchsichtig
    assert ask(c, "call_with_depth_limit((q, q ; q), 5, R)") |> hd() == "R = 1"
    assert ask(c, "call_with_depth_limit((q -> \\+ q ; q), 5, R)") == []
    assert ask(c, "call_with_depth_limit(p, 5, R)") == ["R = 2"]
    assert ask(c, "call_with_depth_limit(call(p), 5, R)") == ["R = 2"]
    # count(N) steigt bis Ebene N+1 (count(0) ist ein Benutzeraufruf)
    assert ask(c, "call_with_depth_limit(count(3), 10, R)") == ["R = 4"]
    assert ask(c, "call_with_depth_limit(count(3), 4, R)") == ["R = 4"]
    assert ask(c, "call_with_depth_limit(count(3), 3, R)") == ["R = depth_limit_exceeded"]
    # eingebaute Prädikate an den Blättern kosten keine Ebene
    assert ask(c, "call_with_depth_limit(p2, 1, R)") == ["R = 1"]
  end

  test "Tiefe: Endlosschleifen werden erkannt, rechts- wie linksrekursiv", c do
    assert ask(c, "call_with_depth_limit(loop, 1000, R)") == ["R = depth_limit_exceeded"]
    assert ask(c, "call_with_depth_limit(lloop, 1000, R)") == ["R = depth_limit_exceeded"]
    assert ask(c, "call_with_depth_limit(fail, 3, R)") == []
  end

  test "Tiefe: zu tiefe Zweige scheitern (Iterative Deepening)", c do
    assert ask(c, "call_with_depth_limit(nat(X), 3, R)") ==
             ["R = 1, X = 0", "R = 2, X = s(0)", "R = 3, X = s(s(0))", "R = depth_limit_exceeded"]

    # R wird unifiziert: passt es nicht, geht es mit der nächsten Lösung weiter
    assert ask(c, "call_with_depth_limit(nat(X), 5, 3)") == ["X = s(s(0))"]

    # abgeschnittene Zweige in findall: findall gelingt, R ist die größte Ebene
    assert ask(c, "call_with_depth_limit(findall(X, nat(X), L), 4, R)") ==
             ["L = [0,s(0),s(s(0)),s(s(s(0)))], R = 4"]

    assert ask(c, "between(1, 5, D), call_with_depth_limit(nat(s(s(s(0)))), D, R), integer(R)") ==
             ["D = 4, R = 4", "D = 5, R = 4"]
  end

  test "Tiefe: Bibliotheken sind durchsichtig, zurückgerufene Ziele auf der Ebene des Aufrufs",
       c do
    assert ask(c, "call_with_depth_limit(maplist(inc, [1, 2, 3], L), 1, R)") ==
             ["L = [2,3,4], R = 1"]

    assert ask(c, "call_with_depth_limit(maplist(inc, [1, 2, 3], L), 0, R)") ==
             ["R = depth_limit_exceeded"]

    # Bibliothek in Prolog-Quelltext (rekursiv): ihre Klauseln zählen nicht
    assert ask(
             c,
             "use_module(library(memberd_pl), []), call_with_depth_limit(memberd_pl:memberd(X, [a, b, c]), 1, R)"
           ) == ["R = 1, X = a", "R = 1, X = b", "R = 1, X = c"]

    assert ask(c, "call_with_depth_limit(forall(member(X, [1, 2]), p), 2, R)") == ["R = 2"]
    # q liegt auf Ebene 2: abgeschnitten, forall scheitert, G also auch
    assert ask(c, "call_with_depth_limit(forall(member(X, [1, 2]), p), 1, R)") ==
             ["R = depth_limit_exceeded"]
  end

  test "Tiefe: außerhalb von G gilt keine Grenze", c do
    assert ask(c, "call_with_depth_limit(true, 1, _), count(10)") == ["true"]
    assert ask(c, "call_with_depth_limit(nat(X), 2, _), X == s(0), count(10)") == ["X = s(0)"]
    assert ask(c, "(call_with_depth_limit(count(5), 2, R), integer(R) ; count(10))") == ["true"]
    assert ask(c, "catch(call_with_depth_limit(throw(x), 3, _), E, true), count(10)") == ["E = x"]
  end

  test "Tiefe: verschachtelt gilt die strengere Grenze; deterministisch bleibt deterministisch",
       c do
    assert ask(c, "call_with_depth_limit(call_with_depth_limit(loop, 1000, R1), 10, R)") ==
             ["R = depth_limit_exceeded"]

    # der 11. Aufruf scheitert an der inneren Grenze, bevor er zählt
    assert ask(c, "call_with_depth_limit(call_with_depth_limit(loop, 10, R1), 1000, R)") ==
             ["R = 10, R1 = depth_limit_exceeded"]

    assert ask(c, "call_with_inference_limit(call_with_depth_limit(p, 3, R1), 10, R)") ==
             ["R = !, R1 = 2"]

    assert ask(c, "call_with_inference_limit(call_with_depth_limit(loop, 100000, R1), 1000, R)") ==
             ["R = inference_limit_exceeded"]
  end

  test "Tiefe: Endrekursion mit konstantem Speicher", c do
    assert ask(c, "call_with_depth_limit(count(200000), 1000000, R)") == ["R = 200001"]

    [{:term, g, _}] =
      Reader.read_terms(c.reader, "call_with_depth_limit(count(400000), 1000000, _).")

    db = c.db
    parent = self()

    pid =
      spawn(fn ->
        receive do
          :go ->
            [_] = db |> PrologEx.query(g) |> Enum.take(1)
            send(parent, :done)
        end
      end)

    ref = Process.monitor(pid)
    send(pid, :go)
    # ohne das Zusammenlegen der Marker wären es grob 30 MB
    assert peak(pid, ref, 0) < 10 * 1024 * 1024
  end

  defp peak(pid, ref, m) do
    receive do
      {:DOWN, ^ref, _, _, _} -> m
    after
      5 ->
        case Process.info(pid, :memory) do
          {:memory, x} -> peak(pid, ref, max(m, x))
          nil -> m
        end
    end
  end

  test "Tiefe: Fehler", c do
    assert ask(c, "call_with_depth_limit(true, L, R)") == {:error, "instantiation_error"}

    assert ask(c, "call_with_depth_limit(true, -1, R)") ==
             {:error, "domain_error(not_less_than_zero, -1)"}

    assert ask(c, "call_with_depth_limit(true, a, R)") == {:error, "type_error(integer, a)"}
  end
end
