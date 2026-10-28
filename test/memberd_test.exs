defmodule PrologEx.MemberdTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r}
  end

  # Datenbank mit memberd/2 aus library(lists) (Elixir) oder
  # library(memberd_pl) (Prolog)
  defp db(c, lib) do
    PrologEx.put_db(%{})
    [{:term, g, _}] = Reader.read_terms(c.reader, "use_module(library(#{lib})).")
    [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
    PrologEx.current_db()
  end

  defp ask(c, db, text, n \\ 8) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(n)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  @cases [
    {"memberd(X, [a,b,c])", ["X = a", "X = b", "X = c"]},
    {"memberd(X, [a,b,a])", ["X = a", "X = b"]},
    {"memberd(a, [a,b,a])", ["true"]},
    {"memberd(b, [a,b,a])", ["true"]},
    {"memberd(d, [a,b,c])", []},
    {"memberd(X, [])", []},
    {"memberd(X, foo)", []},
    {"memberd(X, [a|foo])", ["X = a"]},
    {"memberd(f(Y), [f(1), g(2), f(Z)])", ["Y = 1", "Y = Z, dif(Z,1)"]},
    {"memberd(X, [Y, Z])", ["X = Y", "X = Z, dif(Z,Y)"]},
    {"memberd(X, [Y, Y])", ["X = Y"]},
    {"memberd(X, [Y, a]), Y = a", ["X = a, Y = a"]},
    {"memberd(X, L)", nil},
    {"memberd(a, [b|L])",
     [
       "L = [a|_A]",
       "L = [_A,a|_B], dif(_A,a)",
       "L = [_A,_B,a|_C], dif(_A,a), dif(_B,a)",
       "L = [_A,_B,_C,a|_D], dif(_A,a), dif(_B,a), dif(_C,a)"
     ]},
    {"L = [1,2,3,1,2,3], memberd(X,L), X > 1", nil},
    {"dif(X, a), memberd(X, [a,b])", ["X = b"]}
  ]

  test "lists:memberd/2 (Elixir) und memberd_pl (Prolog) antworten gleich", c do
    ex = db(c, "lists")
    pl = db(c, "memberd_pl")

    for {q, exp} <- @cases do
      got_ex = ask(c, ex, q, 4)
      got_pl = ask(c, pl, q, 4)
      assert got_ex == got_pl, "#{q}\n Elixir: #{inspect(got_ex)}\n Prolog: #{inspect(got_pl)}"
      if exp, do: assert(got_ex == exp, "#{q}: #{inspect(got_ex)}")
    end
  end

  test "ohne doppelte Antworten", c do
    ex = db(c, "lists")

    assert ask(c, ex, "memberd(X, [a,b,a,b,a])") |> Enum.map(&hd(String.split(&1, ","))) ==
             ["X = a", "X = b"]
  end

  test "lange Liste: keine Rekursionstiefe, gefunden ohne Choice Point", c do
    ex = db(c, "lists")
    assert ask(c, ex, "numlist(1, 200000, L), memberd(199999, L)", 3) |> length() == 1
    assert ask(c, ex, "numlist(1, 200000, L), memberd(0, L)") == []
  end
end
