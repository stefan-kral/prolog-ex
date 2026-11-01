defmodule PrologEx.NeumerkelPhraseTest do
  # Beispiele und Fehlerfälle zu phrase/2,3 und call/1
  # (https://www.complang.tuwien.ac.at/ulrich/iso-prolog/phrase).
  # Bei type_error(callable, _) des übersetzten Rumpfs ist der Term
  # implementierungsabhängig; geprüft wird nur die Fehlerklasse.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @callable "type_error(callable,"
  @inst "instantiation_error"

  @rows [
    {"call(1)", {:error, "type_error(callable,1)"}},
    {"call((1,fail))", {:error, "type_error(callable,(1,fail))"}},
    {"call((fail,1))", {:error, "type_error(callable,(fail,1))"}},
    {"call((!;1))", {:error, "type_error(callable,(!;1))"}},
    {"call((!;\\+1))", true},
    {"call((!;call(1)))", true},
    {"call((\\+!;X=a))", ["X = a"]},
    {"functor(T,F,A)", {:error, @inst}},
    {"functor(T,1,2)", {:error, "type_error(atom,1)"}},
    {"functor([_],'.',2)", true},
    {"phrase(=,L)", ["L = []"]},
    {"phrase(1,L)", {:error, "type_error(callable,1)"}},
    {"phrase(K,L)", {:error, @inst}},
    {"K = [], phrase(K,L)", ["K = [], L = []"]},
    {"asserta((a-->b))", {:error, "permission_error(modify,static_procedure,(-->)/2)"}},
    {"clause((a-->b),B)", {:error, "permission_error(access,private_procedure,(-->)/2)"}},
    {"(X-->Y)", {:error, "existence_error(procedure,(-->)/2)"}},
    {"phrase(!,L)", ["L = []"]},
    {"phrase([a],L)", ["L = [a]"]},
    {"phrase([a|b],L)", {:error, "type_error(list,[a|b])"}},
    {"phrase([a|L],K)", {:error, @inst}},
    {"phrase([a|L],L)", {:error, @inst}},
    {"phrase([a|L],[a,b])", {:error, @inst}},
    {"phrase([a|L],[])", {:error, @inst}},
    {"phrase(([a],[]),[a])", true},
    {"phrase(([a],{1}),[])", {:error, @callable}},
    {"phrase((!,[a],{1}),[])", {:error, @callable}},
    {"phrase(({!,fail};[]),L)", :fails},
    {"phrase('|'([],[a]),[a])", true},
    {"phrase(({fail},1),L)", {:error, @callable}},
    {"phrase(([a];[]),L)", ["L = [a]", "L = []"]},
    {"phrase({fail,1},L)", {:error, @callable}},
    {"phrase({throw(h)},[a])", {:error, "h"}},
    {"phrase(({L=[]},[a|L]),[a])", {:error, @inst}},
    {"phrase([a|L],K), L=[b]", {:error, @inst}},
    {"phrase(([a|L],1),[])", {:error, @inst}},
    {"phrase((1,[a|L]),[])", {:error, @callable}},
    {"phrase((1,[a|b]),[])", {:error, @callable}},
    {"phrase((1,{2}),[])", {:error, @callable}},
    {"phrase(({2},1),[])", {:error, @callable}},
    {"phrase((1,(2,[_|_],3),4),[])", {:error, @callable}},
    {"phrase('|'(([x]->[y]),[z]),L)", ["L = [x,y]"]},
    {"phrase(;(([x]->[y]),[z]),L)", ["L = [x,y]"]},
    {"phrase(([a],phrase(2)),[])", :fails},
    {"phrase(\\+[a],[])", true},
    {"phrase(\\+1,L)", {:error, "type_error(callable,1)"}},
    # \+ übersetzt erst bei der Ausführung: [a] scheitert vorher
    {"phrase(([a],\\+1),[])", :fails},
    {"phrase(([a],\\+1;[]),[])", true},
    {"phrase(phrase(phrase,[]),L)", {:error, "existence_error(procedure,phrase/4)"}},
    {"phrase(call([]),[])", {:error, "existence_error(procedure,[]/2)"}},
    {"L=[],phrase([a|L],[b])", :fails},
    {"L=[],phrase([a|L],[a])", ["L = []"]},
    {"phrase([a],[b])", :fails},
    {"phrase(!,[_]) ; L=1", ["L = 1"]},
    {"phrase([], non_list)", :fails},
    {"phrase([], [a|non_list])", :fails},
    {"phrase([], L,non_list)", ["L = non_list"]},
    {"phrase([], L,[a|non_list])", ["L = [a|non_list]"]}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(dcgs lists))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
