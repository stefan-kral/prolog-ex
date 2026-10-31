defmodule PrologEx.PairsTest do
  # library(pairs) wie SWI (Scryers Fassung plus transpose_pairs/2);
  # relational: jede Richtung
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(c.reader, """
        :- use_module(library(pairs)).
        :- use_module(library(lists)).
        doppelt(X, Y) :- Y is 2 * X.
        """)
      )

    PrologEx.put_db(db)
    PrologEx.Flags.set("double_quotes", {:atom, "codes"})
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "pairs_keys_values/3, pairs_keys/2, pairs_values/2 in jede Richtung", c do
    assert ask(c, "pairs_keys_values([a-1,b-2], K, V)") == ["K = [a,b], V = [1,2]"]
    assert ask(c, "pairs_keys_values(P, [a,b], [1,2])") == ["P = [a-1,b-2]"]
    assert ask(c, "pairs_keys_values(P, [a,b], V)") == ["P = [a-_A,b-_B], V = [_A,_B]"]
    assert ask(c, "pairs_keys_values([], K, V)") == ["K = [], V = []"]
    assert ask(c, "pairs_keys_values([a-1], [b], _)") == []
    assert ask(c, "pairs_keys([a-1,b-2], K)") == ["K = [a,b]"]
    assert ask(c, "pairs_values([a-1,b-2], V)") == ["V = [1,2]"]
    assert ask(c, "pairs_values(P, [1,2])") == ["P = [_A-1,_B-2]"]
    # keine Paare: scheitert
    assert ask(c, "pairs_keys([a], K)") == []
  end

  test "group_pairs_by_key/2: benachbarte gleiche Schlüssel (==)", c do
    assert ask(c, "group_pairs_by_key([a-1,a-2,b-3,a-4], G)") == ["G = [a-[1,2],b-[3],a-[4]]"]

    assert ask(c, "keysort([b-1,a-2,b-3], S), group_pairs_by_key(S, G)") ==
             ["G = [a-[2],b-[1,3]], S = [a-2,b-1,b-3]"]

    assert ask(c, "group_pairs_by_key([], G)") == ["G = []"]
    # == , nicht Unifikation: X und Y bleiben getrennt
    assert ask(c, "group_pairs_by_key([X-1,Y-2], G), length(G, N)") |> hd() =~ "N = 2"
  end

  test "transpose_pairs/2 (SWI): getauscht und nach dem neuen Schlüssel sortiert", c do
    assert ask(c, "transpose_pairs([a-2,b-1,c-2], T)") == ["T = [1-b,2-a,2-c]"]
    assert ask(c, "transpose_pairs([], T)") == ["T = []"]
    # keysort ist stabil: bei gleichem neuem Schlüssel bleibt die Reihenfolge
    assert ask(c, "transpose_pairs([b-1,a-1], T)") == ["T = [1-b,1-a]"]
  end

  test "map_list_to_pairs/3: Prädikat im Modul des Aufrufers", c do
    assert ask(c, "map_list_to_pairs(doppelt, [1,2,3], P)") == ["P = [2-1,4-2,6-3]"]

    assert ask(
             c,
             "map_list_to_pairs(length, [[a,b],[c],[]], P), keysort(P, S), pairs_values(S, V)"
           ) ==
             ["P = [2-[a,b],1-[c],0-[]], S = [0-[],1-[c],2-[a,b]], V = [[],[c],[a,b]]"]
  end

  test "nur nach use_module sichtbar; library(aggregate) nutzt sie", c do
    PrologEx.put_db(%{})

    assert ask(c, "catch(pairs_keys([a-1], K), error(E, _), true)") ==
             ["E = existence_error(procedure,pairs_keys/2)"]

    q =
      "use_module(library(aggregate)), use_module(library(lists)), " <>
        "aggregate_all(bag(X), x, member(X, [b,a,b]), L)"

    assert ask(c, q) == ["L = [a,b]"]
  end
end
