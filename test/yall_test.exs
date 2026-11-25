defmodule PrologEx.YallTest do
  # library(yall) (Elixir) und library(yall_pl) (Prolog) wie SWI-Prologs
  # library(yall): dieselben Antworten und Fehler
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r}
  end

  defp db(c, lib) do
    PrologEx.put_db(%{})

    for l <- [lib, "apply", "lists"] do
      [{:term, g, _}] = Reader.read_terms(c.reader, "use_module(library(#{l})).")
      [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
    end

    PrologEx.current_db()
  end

  defp ask(c, db, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  @cases [
    {"maplist([X,Y]>>(Y is X*2), [1,2,3], L)", ["L = [2,4,6]"]},
    # Kopie: Bindungen bleiben im Lambda ...
    {"maplist([X]>>(Y = X), [1])", ["true"]},
    {"maplist([X]>>(X = f(_)), [A,B]), A == B", []},
    # ... außer für die Variablen von Free
    {"maplist({Y}/[X]>>(Y = X), [1,1])", ["Y = 1"]},
    {"maplist({Y}/[X]>>(Y = X), [1,2])", []},
    {"call({X}/(X = 1, Y = 2))", ["X = 1"]},
    {"call({}/[X]>>(X = 1), Z)", ["Z = 1"]},
    # übrige Argumente an den Rumpf
    {"call([X]>>atom_length(X), abc, N)", ["N = 3"]},
    {"call([X,Y]>>atom_length(X,Y), abc, N)", ["N = 3"]},
    {"call([]>>true)", ["true"]},
    {"maplist([L,S]>>foldl([X,A0,A]>>(A is A0+X), L, 0, S), [[1,2],[3]], Ss)", ["Ss = [3,3]"]},
    {"G = ([X]>>(X > 1)), call(G, 2), call(G, 3)", ["G = [X]>>(X>1)"]},
    {"member(X, [1,2,3]), call([Y]>>(Y > 1), X)", ["X = 2", "X = 3"]},
    # Fehler
    {"catch(call([X,Y]>>true, 1), error(E, _), true)",
     ["E = domain_error(lambda_parameters,[_A,_B])"]},
    {"catch(call([X]>>true), error(E, _), true)", ["E = domain_error(lambda_parameters,[_A])"]},
    {"catch(call(_>>true, 1), error(E, _), true)", ["E = instantiation_error"]},
    {"catch(call([X|_]>>true, 1), error(E, _), true)", ["E = instantiation_error"]},
    {"catch(call(foo>>true, 1), error(E, _), true)", ["E = type_error(list,foo)"]},
    {"catch(call(a/[X]>>true, 1), error(E, _), true)", ["E = type_error(lambda_free,a)"]},
    {"catch(call(_/foo), error(E, _), true)", ["E = instantiation_error"]},
    # is_lambda/1
    {"is_lambda([X]>>true)", ["true"]},
    {"is_lambda({X}/foo)", ["true"]},
    {"is_lambda({X}/[Y]>>foo)", ["true"]},
    {"is_lambda(foo)", []},
    {"is_lambda(_)", []},
    {"is_lambda([X|_]>>foo)", []},
    {"is_lambda(a/foo)", []}
  ]

  test "yall (Elixir) und yall_pl (Prolog): dieselben Antworten, wie SWI", c do
    ex = db(c, "yall")
    pl = db(c, "yall_pl")

    for {q, exp} <- @cases do
      got_ex = ask(c, ex, q)
      got_pl = ask(c, pl, q)
      assert got_ex == got_pl, "#{q}\n Elixir: #{inspect(got_ex)}\n Prolog: #{inspect(got_pl)}"
      assert got_ex == exp, "#{q}: #{inspect(got_ex)}"
    end
  end

  test "Rumpf im Modul des Aufrufers", c do
    for lib <- ~w(yall yall_pl) do
      d = db(c, lib)
      {d, []} = PrologEx.Consult.load(d, Reader.read_terms(c.reader, "dbl(X, Y) :- Y is 2 * X."))
      assert ask(c, d, "maplist([X,Y]>>dbl(X,Y), [1,2], L)") == ["L = [2,4]"], lib
      assert ask(c, d, "maplist([X]>>dbl(X), [1,2], L)") == ["L = [2,4]"], lib
    end
  end
end
