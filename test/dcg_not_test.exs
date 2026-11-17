defmodule PrologEx.DcgNotTest do
  # (\+)//1 in DCGs. Der Entwurf für DCGs (WG17, 2022, 7.14.11) stellt es
  # frei; wenn vorhanden: phrase(\+ B, S0, S) gilt genau dann, wenn
  # \+ phrase(B, S0, _) gilt und S0 = S. Die Antworten sind dieselben wie
  # in SWI-Prolog (Scryer lehnt \+ in DCGs ab). Ein Prädikat (\+)/3 gibt es
  # wie in SWI und Scryer nicht: call(\+, [a]) als Rumpf ist ein
  # existence_error.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  look --> \\+ [x], [y].
  n1 --> \\+ ( !, [b] ), [a].
  n1 --> [z].
  n2 --> \\+ ( [a], !, {fail} ), [a].
  n2 --> [z].
  pk, [x] --> [].
  eq(X, [X|T], T).
  % lädt (SWI lehnt es schon beim Laden ab): der Fehler kommt erst, wenn
  % \\+ ausgeführt wird, wie \\+ phrase(3, S0, _)
  bad --> \\+ 3.
  twice(G) --> \\+ \\+ G, G.
  """

  @rows [
    # Vorausschau, verbraucht nichts
    {"phrase(look, [y], R)", ["R = []"]},
    {"phrase(look, [x], R)", :fails},
    {"phrase(\\+ [a], [b], R)", ["R = [b]"]},
    {"phrase(\\+ [a], [], R)", ["R = []"]},
    {"phrase(\\+ [a], [a], R)", :fails},
    {"phrase(\\+ [_], [a], R)", :fails},
    {"phrase(\\+ [], [a], R)", :fails},
    {"phrase((\\+ [b], [a]), [a,c], R)", ["R = [c]"]},
    # keine Bindungen nach außen
    {"phrase(\\+ \\+ [X], [a], R)", ["R = [a]"]},
    {"phrase(twice([a]), [a,b], R)", ["R = [b]"]},
    {"phrase(twice([a]), [b], R)", :fails},
    # ein Cut in \\+ bleibt dort
    {"phrase(n1, [z])", true},
    {"phrase(n2, [a|R])", ["R = []"]},
    {"phrase(n2, [z])", true},
    # Erzeugen: [a] gelingt mit offener Liste, also scheitert \\+
    {"phrase(\\+ [a], L, R)", :fails},
    {"L = [], phrase(\\+ [a], L, R)", ["L = [], R = []"]},
    # Pushback und call//N darin
    {"phrase(\\+ pk, [], R)", :fails},
    {"phrase(\\+ call(eq, a), [a], R)", :fails},
    {"phrase(\\+ call(eq, a), [b], R)", ["R = [b]"]},
    # Fehler erst bei der Ausführung
    {"phrase(\\+ _, [a], R)", {:error, "instantiation_error"}},
    {"phrase(\\+ 3, [a], R)", {:error, "type_error(callable,3)"}},
    {"phrase(bad, [a], R)", {:error, "type_error(callable,3)"}},
    # kein (\\+)/3
    {"call(\\+, [a], [b], R)", {:error, "existence_error(procedure,(\\+)/3)"}},
    {"phrase(call(\\+, [a]), [b], R)", {:error, "existence_error(procedure,(\\+)/3)"}}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ~w(dcgs lists))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
