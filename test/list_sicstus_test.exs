defmodule PrologEx.ListSicstusTest do
  # Die übrigen Prädikate aus SICStus' library(lists) (PrologEx.Builtins.ListSicstus)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(lists)).
  plus3(X, Y, Z) :- Z is X + Y.
  same_key(K-_, K-_).
  dbl(X, Y) :- X > 1, Y is X * 2.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        # Zerlegen
        {"append([1,2], a, L1, b, L2)", ["L1 = [1,2|a], L2 = [1,2|b]"]},
        {"append(P, a, [1,2|a], b, L2)", ["L2 = [1,2|b], P = [1,2]"]},
        {"findall(P-S-N, append_length(P, S, [a,b,c], N), L)",
         ["L = [[]-[a,b,c]-0,[a]-[b,c]-1,[a,b]-[c]-2,[a,b,c]-[]-3]"]},
        {"append_length(P, S, [a,b,c], 2)", ["P = [a,b], S = [c]"]},
        {"findall(S-N, append_length(S, [a,b,c], N), L)", ["L = [[a,b,c]-0,[b,c]-1,[c]-2,[]-3]"]},
        {"append_length(S, [a,b,c], 1)", ["S = [b,c]"]},
        {"catch(append_length(_, [a], -1), error(E, _), true)",
         ["E = domain_error(not_less_than_zero,-1)"]},
        {"findall(P, prefix([a,b,c], P), L)", ["L = [[],[a],[a,b],[a,b,c]]"]},
        {"findall(P, proper_prefix([a,b,c], P), L)", ["L = [[],[a],[a,b]]"]},
        {"prefix_length([a,b,c], P, 2)", ["P = [a,b]"]},
        {"findall(P-N, proper_prefix_length([a,b], P, N), L)", ["L = [[]-0,[a]-1]"]},
        {"findall(S, suffix([a,b,c], S), L)", ["L = [[a,b,c],[b,c],[c],[]]"]},
        {"findall(S, proper_suffix([a,b,c], S), L)", ["L = [[b,c],[c],[]]"]},
        {"findall(S-N, suffix_length([a,b,c], S, N), L)", ["L = [[a,b,c]-3,[b,c]-2,[c]-1,[]-0]"]},
        {"suffix_length([a,b,c], S, 1)", ["S = [c]"]},
        {"suffix_length([a,b,c], [X,Y], N)", ["N = 2, X = b, Y = c"]},
        {"findall(S-N, proper_suffix_length([a,b], S, N), L)", ["L = [[b]-1,[]-0]"]},
        {"findall(B-P-A, sublist([a,b], P, B, _, A), L)",
         ["L = [0-[]-2,0-[a]-1,0-[a,b]-0,1-[]-1,1-[b]-0,2-[]-0]"]},
        {"sublist([a,b,c], [b,c], B)", ["B = 1"]},
        {"sublist([a,b,c], P, 1, 1)", ["P = [b]"]},
        {"findall(S, segment([a,b], S), L)", ["L = [[],[a],[a,b],[],[b],[]]"]},
        {"findall(S, proper_segment([a,b], S), L)", ["L = [[],[a],[],[b],[]]"]},
        {"findall(x, segment([a,b,c,b,c], [b,c]), L)", ["L = [x,x]"]},
        {"findall(S-C, subseq([1,2], S, C), L)", ["L = [[]-[1,2],[2]-[1],[1]-[2],[1,2]-[]]"]},
        {"findall(S, subseq0([a,b,c], S), L)",
         ["L = [[a,b,c],[b,c],[c],[],[b],[a,c],[a],[a,b]]"]},
        {"findall(S, subseq0([a,b,c,d], S), [F1,F2,F3,F4,F5|R]), append(_, [G1,G2], R)",
         :succeeds},
        {"findall(S, subseq1([a,b], S), L)", ["L = [[b],[],[a]]"]},
        {"findall(L, subseq(L, [1,2], [a]), Ls)", ["Ls = [[a,1,2],[1,a,2],[1,2,a]]"]},
        {"cons(h, [t], L), head(L, H), tail(L, T)", ["H = h, L = [h,t], T = [t]"]},
        {"last(F, X, [a,b,c])", ["F = [a,b], X = c"]},
        {"last([a,b], c, L)", ["L = [a,b,c]"]},
        # Löschen, Auswählen
        {"delete([a,b,a,c,a], a, 2, R)", ["R = [b,c,a]"]},
        {"delete([a,b,a], a, 0, R)", ["R = [a,b,a]"]},
        {"delete([a,X,a], a, 5, R)", ["R = []"]},
        {"catch(delete([a], a, -1, _), error(E, _), true)",
         ["E = domain_error(not_less_than_zero,-1)"]},
        {"catch(delete([a], a, x, _), error(E, _), true)", ["E = type_error(integer,x)"]},
        {"correspond(b, [a,b,c], [1,2,3], Y)", ["Y = 2"]},
        {"correspond(X, [a,b], [1,2], 2)", ["X = b"]},
        {"findall(P, perm([1,2,3], P), L)",
         ["L = [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]"]},
        {"findall(C-D, perm2(a, b, C, D), L)", ["L = [a-b,b-a]"]},
        {"rev([1,2,3], R)", ["R = [3,2,1]"]},
        {"rotate_list([a,b,c], R)", ["R = [b,c,a]"]},
        {"rotate_list(R, [a,b,c])", ["R = [c,a,b]"]},
        {"rotate_list(2, [a,b,c], R)", ["R = [c,a,b]"]},
        {"rotate_list(-1, [a,b,c], R)", ["R = [c,a,b]"]},
        {"rotate_list(0, [], R)", ["R = []"]},
        {"rotate_list(4, [a,b,c], _)", :fails},
        {"remove_dups([b,a,b,c,a], R)", ["R = [a,b,c]"]},
        {"max_member(@=<, M, [3,1,3.0,2])", ["M = 3"]},
        {"min_member(@=<, M, [3,1,2])", ["M = 1"]},
        {"max_member(@=<, _, [])", :fails},
        {"select_max(E, [1,3,2,3], R)", ["E = 3, R = [1,2,3]"]},
        {"select_min(E, [2,1,3,1], R)", ["E = 1, R = [2,3,1]"]},
        {"select_max(@>=, E, [1,3,2], R)", ["E = 1, R = [3,2]"]},
        {"select_max(_, [], _)", :fails},
        # Mit Prädikat
        {"scanlist(plus3, [1,2,3], 0, S)", ["S = 6"]},
        {"cumlist(plus3, [1,2,3,4], 0, Vs)", ["Vs = [1,3,6,10]"]},
        {"cumlist(plus3, [1,2], [10,20], 0, Vs)", {:error, "existence_error(procedure,plus3/4)"}},
        {"map_product(plus3, [1,2], [10,20,30], Zs)", ["Zs = [11,21,31,12,22,32]"]},
        {"some(==(b), [a,b,c])", :succeeds},
        {"findall(X, some(=(X), [a,b]), L)", ["L = [a,b]"]},
        {"findall(X, somechk(=(X), [a,b]), L)", ["L = [a]"]},
        {"some(=, [a,b], [c,b])", :succeeds},
        {"some(plus3, [1,2], [10,20], [11,30])", :succeeds},
        {"include(==, [a,b,c], [a,x,c], S)", ["S = [a,c]"]},
        {"exclude(==, [a,b,c], [a,x,c], S)", ["S = [b]"]},
        {"include(plus3, [1,2], [1,1], [2,0], S)", ["S = [1]"]},
        {"convlist(dbl, [1,2,3], L)", ["L = [4,6]"]},
        {"group(same_key, [a-1,a-2,b-3,c-4,c-5], G)", ["G = [[a-1,a-2],[b-3],[c-4,c-5]]"]},
        {"group(integer, [1,2,a,3], F, B)", ["B = [a,3], F = [1,2]"]},
        {"group(==, a, [a,a,b,a], F, B)", ["B = [b,a], F = [a,a]"]},
        {"increasing_prefix([1,2,2,1,5], P, S)", ["P = [1,2], S = [2,1,5]"]},
        {"increasing_prefix([1,2,3], P, S)", ["P = [1,2], S = [3]"]},
        {"increasing_prefix([3,2,1], P, S)", ["P = [], S = [3,2,1]"]},
        {"increasing_prefix([], P, S)", ["P = [], S = []"]},
        {"decreasing_prefix([3,2,2,5], P, S)", ["P = [3,2], S = [2,5]"]},
        {"increasing_prefix(<, [1,2,2,3], P, S)", ["P = [1], S = [2,2,3]"]},
        {"increasing_prefix(Q, [1,2], [3])", ["Q = [1,2,3]"]},
        # Gruppieren
        {"clumps([a,a,b,c,c,c], C)", ["C = [[a,a],[b],[c,c,c]]"]},
        {"clumped([a,a,b,c,c,c], C)", ["C = [a-2,b-1,c-3]"]},
        {"keyclumps([a-1,a-2,b-3], C)", ["C = [[a-1,a-2],[b-3]]"]},
        {"keyclumped([a-1,a-2,b-3], C)", ["C = [a-[1,2],b-[3]]"]}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  # Meta-Argumente im Modul des Aufrufers
  test "Prädikat aus dem Modul des Aufrufers", c do
    Reader.put_current(c.reader)

    {db, []} =
      PrologEx.Consult.load(
        c.db,
        Reader.read_terms(c.reader, """
        :- module(ls, [r/1]).
        :- use_module(library(lists)).
        add(X, A0, A) :- A is A0 + X.
        big(X) :- X > 2.
        r(R) :- cumlist(add, [1,2,3], 0, C), some(big, [1,3]), include(\\=, [a,b], [a,c], I),
                group(big, [3,4,1], G, _), R = C-I-G.
        """)
      )

    assert {_, {:answers, ["R = [1,3,6]-[b]-[3,4]"]}} = TableCase.run(c.reader, db, "ls:r(R)")
  end
end
