defmodule PrologEx.ClpzLoadTest do
  # Laden von library(clpz) ohne Warnungen. Nicht async: capture_io(:stderr)
  # fängt stderr global, auch Warnungen anderer, gleichzeitig laufender Tests
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp load_stderr(c, text) do
    me = self()

    err =
      capture_io(:stderr, fn ->
        out =
          capture_io(fn ->
            send(me, {:load, PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, text))})
          end)

        IO.write(:stderr, out)
      end)

    assert_received {:load, {db, msgs}}
    {db, msgs, err}
  end

  test "Laden von clpz: keine Warnungen zu nicht zusammenhängenden Klauseln", c do
    assert {_db, [], ""} = load_stderr(c, ":- use_module(library(clpz)).\n")
  end

  test "clpz und lists zusammen: keine Warnung, chain/2 aus clpz", c do
    # lists hat kein chain/2 mehr (clpz: chain(Relation, Zs))
    for text <- [
          ":- use_module(library(clpz)).\n:- use_module(library(lists)).\n",
          ":- use_module(library(lists)).\n:- use_module(library(clpz)).\n"
        ] do
      {db, [], ""} = load_stderr(c, text)

      assert {_, {:answers, ["X = 1, Y = 2"]}} =
               TableCase.run(c.reader, db, "chain(#<, [X,Y]), [X,Y] ins 1..2")
    end
  end
end
