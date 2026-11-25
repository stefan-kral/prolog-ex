defmodule PrologEx.ConcurrentSharedTest do
  # library(concurrent) gibt Datenbank und Operatoren über einen
  # persistent_term an die Arbeiter (ohne Kopie). Mehrere Aufrufer mit
  # verschiedenen Datenbanken zugleich: jeder Arbeiter muss die seines
  # Aufrufers bekommen (früher konnte zwischen put und get ein anderer
  # Aufrufer seinen Stand ablegen – die Arbeiter sahen fremde Prädikate,
  # existence_error mitten in clpz_concurrent)
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    dbs =
      for i <- 1..6 do
        db = TableCase.db(r, ~w(concurrent lists))

        {db, []} =
          PrologEx.Consult.load(
            db,
            Reader.read_terms(r, "p#{i}(X, Y) :- Y is X + #{i}.\nq(X, Y) :- p#{i}(X, Y).")
          )

        {i, db}
      end

    {:ok, reader: r, dbs: dbs, ops: Process.get(:prolog_ex_ops)}
  end

  @tag timeout: 300_000
  test "mehrere Aufrufer mit verschiedenen Datenbanken zugleich", c do
    bad =
      c.dbs
      |> Enum.map(fn {i, db} ->
        Task.async(fn ->
          Reader.put_current(c.reader)
          if c.ops, do: Process.put(:prolog_ex_ops, c.ops)

          for _ <- 1..60,
              {_, a} =
                TableCase.run(
                  c.reader,
                  db,
                  "catch(concurrent_maplist(q, [1,2,3], L), error(E, _), true)"
                ),
              a != {:answers, ["L = [#{1 + i},#{2 + i},#{3 + i}]"]},
              do: {i, a}
        end)
      end)
      |> Enum.flat_map(&Task.await(&1, 300_000))

    assert bad == []
  end
end
