defmodule PrologEx.CommalistTest do
  # library(commalist): Elemente eines beliebigen ','-Baums
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @inst "instantiation_error"

  @rows [
    # beliebig geschachtelt, von links nach rechts
    {"commalist_to_list((A,(B,C),D), L)", ["L = [A,B,C,D]"]},
    {"commalist_to_list((A,(B,C)), L)", ["L = [A,B,C]"]},
    {"commalist_to_list(((A,B),C), L)", ["L = [A,B,C]"]},
    {"commalist_to_list((((a,b),(c,d)),e), L)", ["L = [a,b,c,d,e]"]},
    {"commalist_to_list(a, L)", ["L = [a]"]},
    {"commalist_to_list(f((a,b)), L)", ["L = [f((a,b))]"]},
    {"commalist_to_list((a;b,c), L)", ["L = [(a;b,c)]"]},
    {"commalist_to_list((a,X), L)", ["L = [a,X]"]},
    {"A = (x,y), commalist_to_list((A,b), L)", ["A = (x,y), L = [x,y,b]"]},
    {"commalist_to_list((a,b), [a,b])", true},
    {"commalist_to_list((a,b), [a])", :fails},
    {"commalist_to_list((a,b), [X|T])", ["T = [b], X = a"]},
    {"commalist_to_list(C, [a,b])", {:error, @inst}},
    {"commalist_to_list(C, L)", {:error, @inst}},
    {"nonemptylist_to_commalist([a,b,c], C)", ["C = (a,b,c)"]},
    {"nonemptylist_to_commalist([a], C)", ["C = a"]},
    {"nonemptylist_to_commalist([a,(b,c)], C)", ["C = (a,b,c)"]},
    {"nonemptylist_to_commalist([X,Y], (a,b))", ["X = a, Y = b"]},
    {"nonemptylist_to_commalist([a,b], (a,c))", :fails},
    {"nonemptylist_to_commalist([], C)", {:error, "domain_error(non_empty_list,[])"}},
    {"nonemptylist_to_commalist(L, C)", {:error, @inst}},
    {"nonemptylist_to_commalist([a|L], C)", {:error, @inst}},
    {"nonemptylist_to_commalist([a|b], C)", {:error, "type_error(list,[a|b])"}},
    {"nonemptylist_to_commalist(foo, C)", {:error, "type_error(list,foo)"}},
    {"length(L, 2), nonemptylist_to_commalist(L, C)", ["C = (_A,_B), L = [_A,_B]"]},
    {"commalist_append((a,b), ((c,d),e), C)", ["C = (a,b,c,d,e)"]},
    {"commalist_append(a, b, C)", ["C = (a,b)"]},
    {"commalist_append(A, b, C)", {:error, @inst}},
    {"commalist_append(a, B, C)", {:error, @inst}},
    {"commalist_append(a, b, (a,c))", :fails},
    {"commalist_length(((a,b),c,(d,e)), N)", ["N = 5"]},
    {"commalist_length(a, N)", ["N = 1"]},
    {"commalist_length((a,b), 2)", true},
    {"commalist_length((a,b), 3)", :fails},
    {"commalist_length(C, 2)", {:error, @inst}},
    {"commalist_length((a,b), x)", {:error, "type_error(integer,x)"}},
    {"commalist_length((a,b), -1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"commalist_member(X, ((a,b),c))", ["X = a", "X = b", "X = c"]},
    {"commalist_member(b, (a,b,c))", true},
    {"commalist_member(X, a)", ["X = a"]},
    {"commalist_member(X, (a,Y))", ["X = a", "X = Y"]},
    {"commalist_member(X, C)", {:error, @inst}},
    {"commalist_memberchk(f(X), (a,f(1),f(2)))", ["X = 1"]},
    {"commalist_memberchk(z, (a,b))", :fails},
    {"commalist_memberchk(X, C)", {:error, @inst}}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(commalist lists))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end

  test "tief geschachtelt, links und rechts", c do
    Reader.put_current(c.reader)

    q =
      "numlist(1, 100000, Ns), foldl(links, Ns, 0, L), " <>
        "commalist_to_list(L, Ls), length(Ls, N), nonemptylist_to_commalist(Ls, R), " <>
        "commalist_length(R, M)"

    text =
      ":- use_module(library(commalist)).\n:- use_module(library(lists)).\n" <>
        ":- use_module(library(apply)).\nlinks(X, A0, (A0,X)).\n"

    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, text))
    {_, {:answers, [a]}} = TableCase.run(c.reader, db, q)
    assert a =~ "M = 100001, N = 100001"
  end
end
