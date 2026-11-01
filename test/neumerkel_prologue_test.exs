defmodule PrologEx.NeumerkelPrologueTest do
  # Beispiele und Fehlerfälle aus dem Prologue-Entwurf
  # (https://www.complang.tuwien.ac.at/ulrich/iso-prolog/prologue).
  # Nicht aufgenommen: length(L, L) (läuft wie bei vielen Systemen endlos)
  # und die Zeilen mit dem Flag max_integer (unbeschränkte Ganzzahlen,
  # das Flag gibt es nicht).
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @rows [
    {"member(X, [1,2])", ["X = 1", "X = 2"]},
    {"member(1, L)", {:first, ["L = [1|_A]", "L = [_A,1|_B]", "L = [_A,_B,1|_C]"]}},
    {"member(X, [Y,Z|nonlist])", ["X = Y", "X = Z"]},
    {"member(X, nonlist)", :fails},
    {"append([a,b],[c,d], Xs)", ["Xs = [a,b,c,d]"]},
    {"append([a], nonlist, Xs)", ["Xs = [a|nonlist]"]},
    {"append([a], Ys, Zs)", ["Zs = [a|Ys]"]},
    {"append(Xs, Ys, [a,b,c])",
     [
       "Xs = [], Ys = [a,b,c]",
       "Xs = [a], Ys = [b,c]",
       "Xs = [a,b], Ys = [c]",
       "Xs = [a,b,c], Ys = []"
     ]},
    {"append(Xs, Ys, [a,b|Xs])",
     {:first,
      [
        "Xs = [], Ys = [a,b]",
        "Xs = [a], Ys = [b,a]",
        "Xs = [a,b], Ys = [a,b]",
        "Xs = [a,b,a], Ys = [b,a]"
      ]}},
    {"length([a,b,c], Length)", ["Length = 3"]},
    {"length(List, 5)", ["List = [_A,_B,_C,_D,_E]"]},
    {"length(List, Length)",
     {:first, ["Length = 0, List = []", "Length = 1, List = [_A]", "Length = 2, List = [_A,_B]"]}},
    {"length([a|List],Length)",
     {:first, ["Length = 1, List = []", "Length = 2, List = [_A]", "Length = 3, List = [_A,_B]"]}},
    {"length(L, -1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"length(L, a)", {:error, "type_error(integer,a)"}},
    {"length(L, 1+1)", {:error, "type_error(integer,1+1)"}},
    {"length([a|b], L)", :fails},
    {"between(1, 2, 0)", :fails},
    {"between(1, 2, I)", ["I = 1", "I = 2"]},
    {"between(2, 1, I)", :fails},
    {"between(I, I, 0)", {:error, "instantiation_error"}},
    {"between(1, I, 0)", {:error, "instantiation_error"}},
    {"between(I, -1, 0)", {:error, "instantiation_error"}},
    {"between(1, c, 0)", {:error, "type_error(integer,c)"}},
    {"between(1+1,2,I)", {:error, "type_error(integer,1+1)"}},
    {"select(X, [1,2], Xs)", ["X = 1, Xs = [2]", "X = 2, Xs = [1]"]},
    {"select(X, [Y|nonlist], Xs)", ["X = Y, Xs = nonlist"]},
    {"succ(X, S)", {:error, "instantiation_error"}},
    {"succ(X, X)", {:error, "instantiation_error"}},
    {"succ(0, S)", ["S = 1"]},
    {"succ(1, 1+1)", {:error, "type_error(integer,1+1)"}},
    {"succ(X, 0)", :fails},
    {"succ(-1, S)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"succ(a, S)", {:error, "type_error(integer,a)"}},
    {"succ(S, a)", {:error, "type_error(integer,a)"}},
    {"succ(S, -1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"maplist(>(3), [1, 2])", true},
    {"maplist(>(3), [1, 2, 3])", :fails},
    {"maplist(=(X), Xs)", {:first, ["Xs = []", "Xs = [X]", "Xs = [X,X]"]}},
    {"nth0(1, [a,b,c], E)", ["E = b"]},
    {"nth0(N, [a,b,c], E)", ["E = a, N = 0", "E = b, N = 1", "E = c, N = 2"]},
    {"nth0(0, [A,B|non_list], E)", ["A = E"]},
    {"nth0(2, Es, E)", ["Es = [_A,_B,E|_C]"]},
    {"nth0(N, Es, E)",
     {:first, ["Es = [E|_A], N = 0", "Es = [_A,E|_B], N = 1", "Es = [_A,_B,E|_C], N = 2"]}},
    {"nth0(non_integer, Es, E)", {:error, "type_error(integer,non_integer)"}},
    {"nth0(-1, Es, E)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"nth1(0, Es, E)", :fails},
    {"nth1(1, [a,b,c], E)", ["E = a"]},
    {"nth1(N, [a,b,c], E)", ["E = a, N = 1", "E = b, N = 2", "E = c, N = 3"]},
    {"nth0(1, [a,b,c], E, R)", ["E = b, R = [a,c]"]},
    {"nth1(2, [a,b,c], E, R)", ["E = b, R = [a,c]"]},
    {"nth0(N, [a,b,c], E, R)",
     ["E = a, N = 0, R = [b,c]", "E = b, N = 1, R = [a,c]", "E = c, N = 2, R = [a,b]"]},
    {"foldl(append, [[1,2],[3],[4,5]], [],Xs)", ["Xs = [4,5,3,1,2]"]}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(lists between apply iso_ext))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
