defmodule PrologEx.LimitsTest do
  # call_with_inference_limit/3 (wie SWI und Scryer)
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :gprolog
  @moduletag timeout: 30_000

  # count(N) kostet 2N+1 Inferenzen (je Ebene count/1 und is/2, dazu count(0))
  @program """
  loop :- loop.
  count(0) :- !.
  count(N) :- N1 is N-1, count(N1).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = PrologEx.use_library(%{}, "lists", "user")
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
             ["L = [1, 2], R = !"]
  end

  test "Fehler", c do
    assert ask(c, "call_with_inference_limit(true, L, R)") == {:error, "instantiation_error"}

    assert ask(c, "call_with_inference_limit(true, -1, R)") ==
             {:error, "domain_error(not_less_than_zero, -1)"}

    assert ask(c, "call_with_inference_limit(true, a, R)") ==
             {:error, "type_error(integer, a)"}

    assert ask(c, "call_with_inference_limit(G, 10, R)") == {:error, "instantiation_error"}
  end
end
