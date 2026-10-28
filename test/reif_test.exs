defmodule PrologEx.ReifTest do
  @moduledoc """
  library(reif) (Elixir-Schnellwege) gegen library(reif_pl) (reines Prolog):
  dieselben Antworten in derselben Reihenfolge, dieselben Fehler.
  """
  use ExUnit.Case, async: false
  alias PrologEx.{Consult, Reader}

  @user """
  ist_a(X, T) :- =(X, a, T).
  gross(X, T) :- ( X > 5 -> T = true ; T = false ).
  kaputt(_, kaputt).
  zaehle([], _, 0).
  zaehle([X|Xs], E, N) :- if_(X = E, (zaehle(Xs, E, N0), N is N0 + 1), zaehle(Xs, E, N)).
  schnitt(X, Y) :- if_(X = a, (!, Y = 1), Y = 2).
  schnitt(_, 3).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    dbs =
      for lib <- ["reif", "reif_pl"], into: %{} do
        PrologEx.put_db(PrologEx.use_library(%{}, "lists", "user"))
        [{:term, g, _}] = Reader.read_terms(r, "use_module(library(#{lib})).")
        [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
        {db, []} = Consult.load(PrologEx.current_db(), Reader.read_terms(r, @user))
        {lib, db}
      end

    {:ok, reader: r, dbs: dbs}
  end

  defp ask(c, db, q, n \\ 6) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      db
      |> PrologEx.query(g)
      |> Enum.take(n)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    rescue
      e in PrologEx.Error -> {:error, Exception.message(e)}
    end
  end

  defp same(c, q, n \\ 6) do
    ex = ask(c, c.dbs["reif"], q, n)
    pl = ask(c, c.dbs["reif_pl"], q, n)
    assert ex == pl, "#{q}\n reif:    #{inspect(ex)}\n reif_pl: #{inspect(pl)}"
    ex
  end

  test "=/3, dif/3", c do
    assert same(c, "=(a, a, T)") == ["T = true"]
    assert same(c, "=(a, b, T)") == ["T = false"]
    assert same(c, "=(X, a, T)") == ["T = true, X = a", "T = false, dif(X,a)"]
    assert same(c, "=(f(X, b), f(a, Y), T)") |> length() == 2
    assert same(c, "=(X, Y, true)") == ["X = Y"]
    assert same(c, "=(X, a, false)") == ["dif(X,a)"]
    assert same(c, "=(a, a, false)") == []
    assert same(c, "=(a, a, foo)") == []
    assert same(c, "dif(X, a, T)") == ["T = false, X = a", "T = true, dif(X,a)"]
    assert same(c, "dif(a, b, T)") == ["T = true"]
    same(c, "dif(X, Y, T), X = Y")
    same(c, "=(X, Y, T), X = a, Y = b")
  end

  test "if_/3", c do
    assert same(c, "if_(X = a, Y = 1, Y = 2)") == ["X = a, Y = 1", "Y = 2, dif(X,a)"]
    # wie reif: dif/3 über =/3, also zuerst der Fall X = a (Else)
    assert same(c, "if_(dif(X, a), Y = 1, Y = 2)") == ["X = a, Y = 2", "Y = 1, dif(X,a)"]
    assert same(c, "if_(a = a, Y = 1, Y = 2)") == ["Y = 1"]
    same(c, "if_((X = a, Y = b), T = 1, T = 0)")
    same(c, "if_((X = a ; Y = b), T = 1, T = 0)")
    same(c, "if_(((X = a ; X = b), dif(X, b)), T = 1, T = 0)")
    same(c, "if_(memberd_t(X, [a, b]), T = 1, T = 0)")
    same(c, "if_(ist_a(X), T = 1, T = 0)")
    same(c, "if_(gross(7), T = 1, T = 0)")
    same(c, "if_(gross(3), T = 1, T = 0)")
    same(c, "if_(cond_t(X = a, true), T = 1, T = 0)")
    # Fehler
    assert same(c, "if_(kaputt(x), true, true)") == {:error, "type_error(boolean,kaputt)"}
    assert same(c, "if_(_, true, true)") |> elem(0) == :error
    assert same(c, "if_(=(_), true, true)") == {:error, "instantiation_error"}
    assert same(c, "if_(foo, true, true)") |> elem(0) == :error
    # Cut in Then: lokal (call/1), wie in reif_pl
    assert same(c, "schnitt(a, Y)") == ["Y = 1", "Y = 3"]
    same(c, "schnitt(X, Y)")
    assert same(c, "zaehle([a, b, a, c, a], a, N)") == ["N = 3"]
    same(c, "zaehle([a, X, a], a, N)")
  end

  test "(',')/3, (;)/3, cond_t/3", c do
    same(c, "','(X = a, Y = b, T)")
    same(c, "';'(X = a, Y = b, T)")
    same(c, "cond_t(X = a, Y = 1, T)")
    same(c, "','(=(a), =(a), T)")
  end

  test "memberd_t/3, tmember/2, tmember_t/3", c do
    assert same(c, "memberd_t(a, [b, a, c], T)") == ["T = true"]
    assert same(c, "memberd_t(d, [b, a, c], T)") == ["T = false"]
    same(c, "memberd_t(X, [a, b, a], T)")
    same(c, "memberd_t(X, [Y, Z], T)")
    same(c, "memberd_t(a, [b|L], T)", 4)
    same(c, "memberd_t(X, L, T)", 4)
    same(c, "memberd_t(a, [b, a|foo], T)")
    same(c, "memberd_t(X, [a, b], false)")
    same(c, "memberd_t(X, [a, b], true)")
    same(c, "tmember(=(X), [a, b, X])")
    same(c, "tmember(ist_a, [b, Y, a])")
    same(c, "tmember_t(=(c), [a, b], T)")
    same(c, "tmember_t(dif(a), [a, X], T)")
  end

  test "tfilter/3, tpartition/4", c do
    assert same(c, "tfilter(dif(a), [a, b, a, c], Fs)") == ["Fs = \"bc\""]
    assert same(c, "tfilter(=(a), [a, b, a, c], Fs)") == ["Fs = \"aa\""]
    same(c, "tfilter(dif(a), [a, b, X, a, c], Fs)")
    same(c, "tfilter(=(X), [a, b, a], Fs)")
    same(c, "tfilter(dif(a), [b|L], Fs)", 4)
    same(c, "tfilter(dif(a), L, Fs)", 4)
    same(c, "tfilter(dif(a), [a, b], [b])")
    same(c, "tfilter(dif(a), [a, b], [a])")
    same(c, "tfilter(ist_a, [a, X, b], Fs)")
    same(c, "tfilter(gross, [3, 7, 9, 1], Fs)")
    assert same(c, "tpartition(=(a), [a, b, a], Ts, Fs)") == ["Fs = \"b\", Ts = \"aa\""]
    same(c, "tpartition(dif(a), [a, X, b], Ts, Fs)")
    same(c, "tpartition(=(X), [a, b], Ts, Fs)")
    same(c, "tpartition(=(a), [a|L], Ts, Fs)", 4)
    same(c, "tpartition(gross, [3, 7, 9, 1], Ts, Fs)")
  end

  # Zufällige Terme aus a, b, f(W), f(a), Variablen. In f(...) nur
  # Variablen, die nie allein vorkommen: X = f(X) ergäbe ohne occurs check
  # einen zyklischen Term (dessen Ausgabe hängt, in beiden Fassungen).
  defp term(vars) do
    case :rand.uniform(6) do
      1 -> "a"
      2 -> "b"
      3 -> "f(#{Enum.random(~w(W1 W2))})"
      4 -> "f(a)"
      _ -> Enum.random(vars)
    end
  end

  defp tlist(vars, n), do: "[" <> Enum.map_join(1..n, ", ", fn _ -> term(vars) end) <> "]"

  test "zufällige Terme: =/3, dif/3, memberd_t/3, tfilter/3, tpartition/4", c do
    :rand.seed(:exsss, {7, 8, 9})
    vars = ~w(X Y Z)

    for _ <- 1..60 do
      x = term(vars)
      y = term(vars)
      same(c, "=(#{x}, #{y}, T)")
      same(c, "dif(#{x}, #{y}, T)")
      same(c, "if_(#{x} = #{y}, R = ja, R = nein)")
      l = tlist(vars, :rand.uniform(4))
      same(c, "memberd_t(#{x}, #{l}, T)", 8)
      same(c, "tfilter(dif(#{x}), #{l}, Fs)", 8)
      same(c, "tfilter(=(#{x}), #{l}, Fs)", 8)
      same(c, "tpartition(=(#{x}), #{l}, Ts, Fs)", 8)
    end
  end

  test "eigenes =/3 im Modul geht vor (kein Schnellweg)", c do
    {db, []} =
      Consult.load(
        c.dbs["reif"],
        Reader.read_terms(c.reader, """
        :- module(eigen, [t/1]).
        :- use_module(library(reif), [if_/3]).
        =(_, _, true).
        t(R) :- if_(a = b, R = gleich, R = verschieden).
        """)
      )

    assert ask(c, db, "eigen:t(R)") == ["R = gleich"]
  end
end
