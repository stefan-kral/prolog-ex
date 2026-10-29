defmodule PrologEx.MetaBodyTest do
  # Ziele aus Daten werden wie bei call/1 zum Rumpf (ISO 7.6.2): beim
  # Aufruf ungebundene Variablen innen werden call(V) (Cut darin lokal),
  # gebundene werden eingesetzt; nicht aufrufbar → type_error(callable)
  # vor jeder Ausführung. Gilt für call/1 mit M:Rumpf, \+, findall/3 & Co.,
  # catch/3, forall/2, call_nth/2, Grenzen und time/1.
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    db = Enum.reduce(["iso_ext", "swi", "lists"], %{}, &PrologEx.use_library(&2, &1))
    PrologEx.put_db(db)
    {:ok, db: db}
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, g), do: ask(c, "catch((#{g}), error(E, _), true)")

  # Rumpf, in dem G beim Aufruf ungebunden ist und erst darin an ! gebunden wird
  @spaet "((G = !, G, fail) ; true)"
  # derselbe mit X schon beim Aufruf gebunden
  @frueh "((X, fail) ; true)"

  test "ungebunden beim Aufruf: call(G), Cut lokal", c do
    assert ask(c, "call(user:#{@spaet})") == ["true"]
    assert ask(c, "\\+ \\+ #{@spaet}") == ["true"]
    assert ask(c, "findall(x, #{@spaet}, L)") == [~s(L = "x")]
    assert ask(c, "forall(true, #{@spaet})") == ["true"]
    assert ask(c, "catch(#{@spaet}, _, true)") == ["true"]
    assert ask(c, "countall(#{@spaet}, N)") == ["N = 1"]
    assert ask(c, "findnsols(1, x, #{@spaet}, L)") |> hd() =~ ~s(L = "x")
    assert ask(c, "call_nth(#{@spaet}, 1)") == ["true"]
    assert ask(c, "call_with_inference_limit(#{@spaet}, 100, R)") |> hd() =~ "R = "
    assert ask(c, "call_with_depth_limit(#{@spaet}, 10, R)") |> hd() =~ "R = "
    capture_io(:stderr, fn -> assert ask(c, "time(#{@spaet})") == ["true"] end)
  end

  test "gebunden beim Aufruf: eingesetzt, Cut schneidet das ; ab (wie vorher)", c do
    assert ask(c, "X = !, call(user:#{@frueh})") == []
    assert ask(c, "X = !, \\+ #{@frueh}") == ["X = !"]
    assert ask(c, "X = !, findall(x, #{@frueh}, L)") == ["L = [], X = !"]
    assert ask(c, "X = !, catch(#{@frueh}, _, true)") == []
  end

  test "nicht aufrufbar: type_error vor jeder Ausführung", c do
    for g <- [
          "findall(x, (write(ja), 1), _)",
          "\\+ (write(ja), 1)",
          "call(user:(write(ja), 1))",
          "forall(true, (write(ja), 1))",
          "countall((write(ja), 1), _)"
        ] do
      out =
        capture_io(fn ->
          [e] = err(c, g)
          assert e =~ "type_error(callable,", g
        end)

      assert out == "", g
    end

    assert err(c, "findall(x, 1, _)") == ["E = type_error(callable,1)"]
    assert err(c, "\\+ 1") == ["E = type_error(callable,1)"]
    assert err(c, "call(user:1)") == ["E = type_error(callable,user:1)"]
    assert err(c, "findall(x, _, _)") == ["E = instantiation_error"]
    assert err(c, "\\+ _") == ["E = instantiation_error"]
    # catch/3 fängt den Fehler seines eigenen Ziels
    assert ask(c, "catch(1, error(E, _), true)") == ["E = type_error(callable,1)"]
    assert ask(c, "catch(_, error(E, _), true)") == ["E = instantiation_error"]
    capture_io(:stderr, fn -> assert err(c, "time(1)") == ["E = type_error(callable,1)"] end)
    assert err(c, "call_nth(1, 1)") == ["E = type_error(callable,1)"]
  end

  test "M:Rumpf: Module bleiben, offenes M wie bisher", c do
    {db, []} =
      PrologEx.Consult.load(c.db, Reader.read_terms(c.reader, ":- module(m, []).\nnur_m(ja).\n"))

    PrologEx.put_db(db)
    c = %{c | db: db}
    assert ask(c, "call(m:(nur_m(X), true))") == ["X = ja"]
    assert ask(c, "findall(X, m:(nur_m(X) ; X = b), L)") == ["L = [ja,b]"]
    assert err(c, "call(_:true)") == ["E = instantiation_error"]
  end
end
