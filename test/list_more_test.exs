defmodule PrologEx.ListMoreTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = Enum.reduce(["lists", "apply", "lambda"], %{}, &PrologEx.use_library(&2, &1, "user"))

    {db, []} =
      PrologEx.Consult.load(
        db,
        Reader.read_terms(r, """
        cmp_num(X, R) :- compare(R, X, 3).
        bad_order(_, foo).
        unbound_order(_, _).
        """)
      )

    {:ok, reader: r, db: db}
  end

  # Liste der Antworten (höchstens n) als Text, "true" für leere Antwort;
  # {:error, text} bei einer Ausnahme
  defp run(c, text, n \\ 6) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")
    names = PrologEx.query_var_names(g)

    try do
      c.db
      |> PrologEx.query(g)
      |> Enum.take(n)
      |> Enum.map(fn ans ->
        if map_size(ans) == 0, do: "true", else: PrologEx.format_answer(ans, names)
      end)
    rescue
      e in PrologEx.Error -> {:error, Exception.message(e)}
    end
  end

  defp check(c, cases) do
    for {q, exp} <- cases do
      got = run(c, q)
      assert got == exp, "#{q}\n got: #{inspect(got)}\n exp: #{inspect(exp)}"
    end
  end

  test "one_longer/2", c do
    check(c, [
      {"one_longer([a,b,c], [x,y])", ["true"]},
      {"one_longer([a,b], [x,y])", []},
      {"one_longer([a], [])", ["true"]},
      {"one_longer([], X)", []},
      {"one_longer([a,b,c], S)", ["S = [_A, _B]"]},
      {"one_longer(L, [x,y])", ["L = [_A, _B, _C]"]},
      {"one_longer([a|T], [x,y,z])", ["T = [_A, _B, _C]"]},
      {"one_longer([a,b,c|T], [x])", []},
      {"one_longer(foo, [x])", []},
      {"one_longer([a|foo], S)", []},
      {"one_longer(L, S)",
       [
         "L = [_A], S = []",
         "L = [_A, _B], S = [_C]",
         "L = [_A, _B, _C], S = [_D, _E]",
         "L = [_A, _B, _C, _D], S = [_E, _F, _G]",
         "L = [_A, _B, _C, _D, _E], S = [_F, _G, _H, _I]",
         "L = [_A, _B, _C, _D, _E, _F], S = [_G, _H, _I, _J, _K]"
       ]}
    ])
  end

  test "shorter_list/2", c do
    check(c, [
      {"shorter_list([], [a])", ["true"]},
      {"shorter_list([], [])", []},
      {"shorter_list([x], [a,b])", ["true"]},
      {"shorter_list([x,y], [a,b])", []},
      # Long muss nur lang genug sein
      {"shorter_list([x], [a,b|foo])", ["true"]},
      {"shorter_list([x], [a|foo])", []},
      {"shorter_list([x], [a|T])", ["T = [_A|_B]"]},
      {"shorter_list([x,y], L)", ["L = [_A, _B, _C|_D]"]},
      {"shorter_list(S, [a,b,c])", ["S = []", "S = [_A]", "S = [_A, _B]"]}
    ])

    assert run(c, "shorter_list(S, L)", 3) == [
             "L = [_A|_B], S = []",
             "L = [_A, _B|_C], S = [_D]",
             "L = [_A, _B, _C|_D], S = [_E, _F]"
           ]
  end

  test "keys_and_values/3", c do
    check(c, [
      {"keys_and_values([a-1,b-2], K, V)", ["K = \"ab\", V = [1, 2]"]},
      {"keys_and_values(P, [a,b], [1,2])", ["P = [a-1, b-2]"]},
      {"keys_and_values(P, [a,b], V)", ["P = [a-_A, b-_B], V = [_A, _B]"]},
      {"keys_and_values(P, K, [1])", ["K = [_A], P = [_A-1]"]},
      {"keys_and_values([], K, V)", ["K = [], V = []"]},
      {"keys_and_values([a-1,b], K, V)", []},
      {"keys_and_values([a-1], [a,b], V)", []},
      {"keys_and_values([a-1|T], K, [1,2])", ["K = [a, _A], T = [_A-2]"]},
      {"keys_and_values(P, K, V)",
       [
         "K = [], P = [], V = []",
         "K = [_A], P = [_A-_B], V = [_B]",
         "K = [_A, _B], P = [_A-_C, _B-_D], V = [_C, _D]",
         "K = [_A, _B, _C], P = [_A-_D, _B-_E, _C-_F], V = [_D, _E, _F]",
         "K = [_A, _B, _C, _D], P = [_A-_E, _B-_F, _C-_G, _D-_H], V = [_E, _F, _G, _H]",
         "K = [_A, _B, _C, _D, _E], P = [_A-_F, _B-_G, _C-_H, _D-_I, _E-_J], V = [_F, _G, _H, _I, _J]"
       ]}
    ])
  end

  test "transpose/2", c do
    check(c, [
      {"transpose([[1,2,3],[4,5,6]], X)", ["X = [[1, 4], [2, 5], [3, 6]]"]},
      {"transpose(X, [[1,4],[2,5],[3,6]])", ["X = [[1, 2, 3], [4, 5, 6]]"]},
      {"transpose([[a]], X)", ["X = [\"a\"]"]},
      {"transpose([[a,b]], X)", ["X = [\"a\", \"b\"]"]},
      {"transpose([[A,B],[C,D]], X)", ["X = [[A, C], [B, D]]"]},
      {"transpose([[1,2],[3]], X)", []},
      {"transpose([], X)", []},
      {"transpose(X, [])", []},
      {"transpose([[]], X)", []},
      {"transpose([[],[]], X)", []},
      {"transpose([[1,2],[3,4]], [[1,3],[2,4]])", ["true"]},
      {"transpose([[1,2],[3,4]], [[1,2],[3,4]])", []},
      # Form von beiden Seiten
      {"transpose([[1,_],[_,4]], [[_,2],[3,_]])", ["true"]},
      {"transpose([[1,2],[3,4]], [_,_,_])", []},
      {"transpose([[1,2],[3,4]], [X|Y])", ["X = [1, 3], Y = [[2, 4]]"]}
    ])
  end

  test "transpose/2 ist deterministisch", c do
    assert run(c, "transpose([[1,2,3],[4,5,6]], X)", 2) |> length() == 1
    assert run(c, "transpose(X, [[1,4],[2,5]])", 2) |> length() == 1
  end

  test "partition/5", c do
    check(c, [
      {"partition(cmp_num, [1,5,3,2,4,3], L, E, G)", ["E = [3, 3], G = [5, 4], L = [1, 2]"]},
      {"partition(cmp_num, [], L, E, G)", ["E = [], G = [], L = []"]},
      {"partition(cmp_num, [1,5], [1], [], [5])", ["true"]},
      {"partition(cmp_num, [1,5], [], E, G)", []},
      {"partition(bad_order, [1], L, E, G)", {:error, "domain_error(order, foo)"}},
      {"partition(unbound_order, [1], L, E, G)", {:error, "instantiation_error"}},
      {"partition(\\X^R^compare(R,X,2), [3,1,2], L, E, G)", ["E = [2], G = [3], L = [1]"]}
    ])
  end

  test "chain/2", c do
    check(c, [
      {"chain([1,2,3], <)", ["true"]},
      {"chain([1,3,2], <)", []},
      {"chain([1,1,2], =<)", ["true"]},
      {"chain([1,1,2], <)", []},
      {"chain([], foo)", ["true"]},
      {"chain([a], foo)", ["true"]},
      {"chain([3,2,1], @>)", ["true"]},
      {"chain([a,B,c], @<)", []},
      {"chain([1,X], <)", {:error, "instantiation_error"}}
    ])
  end

  test "chain/2 und partition/5 rufen im Modul des Aufrufers", c do
    {db, []} =
      PrologEx.Consult.load(
        c.db,
        Reader.read_terms(c.reader, """
        :- module(mm, [t/1, p/2]).
        :- use_module(library(lists)).
        lt(A, B) :- A < B.
        cmp2(X, R) :- compare(R, X, 2).
        t(L) :- chain(L, lt).
        p(L, E-G) :- partition(cmp2, L, _, E, G).
        """)
      )

    c = %{c | db: db}

    check(c, [
      {"mm:t([1,2,3])", ["true"]},
      {"mm:t([2,1])", []},
      {"mm:p([3,2,1], X)", ["X = [2]-[3]"]}
    ])
  end
end
