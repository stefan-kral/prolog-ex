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
    {"phrase([], L,[a|non_list])", ["L = [a|non_list]"]},
    # Rumpf, Teilziele und Listengerüste über gebundene Variablen
    # (phrase/2,3 löst nur die Steuerkonstrukte auf)
    {"X = [b], T = [c|U], U = [], G = ([a],X,T), phrase(G, L)",
     ["G = ([a],[b],[c]), L = [a,b,c], T = [c], U = [], X = [b]"]},
    {"Y = 1, X = (\\+ Y), phrase(X, [])", {:error, "type_error(callable,1)"}},
    {"Y = 1, X = ([a], Y), phrase(X, [])", {:error, @callable}},
    {"T = [b|V], phrase([a|T], L)", {:error, @inst}},
    {"X = [Y], Y = [], phrase(([a] -> X), L)", ["L = [a,[]], X = [[]], Y = []"]},
    {"M = lists, N = append([x]), phrase(M:N, [y], R)",
     ["M = lists, N = append([x]), R = [x,y]"]},
    {"G = {Z = 1}, phrase(G, [], R)", ["G = {1=1}, R = [], Z = 1"]},
    {"B = (A ; [c]), A = [b], phrase(([a], B), L)",
     ["A = [b], B = ([b];[c]), L = [a,b]", "A = [b], B = ([b];[c]), L = [a,c]"]},
    {"X = Y, phrase(X, L)", {:error, @inst}},
    # ! über Variablen: schneidet die Alternativen des ganzen Rumpfs ab
    {"A = !, B = (A, {fail}), C = (B ; []), phrase(C, [])", :fails},
    {"A = !, B = (A, {fail}), C = '|'(B, []), phrase(C, [])", :fails},
    {"A = !, B = (A, {fail}), C = (B, []), phrase((C ; []), [])", :fails},
    {"A = [a], B = {fail}, C = (A -> B), phrase((C ; [a]), L)", :fails},
    {"A = !, B = (A, {fail}), phrase((lists:B ; []), [])", :fails},
    {"A = !, B = (A, {fail}), phrase(\\+ B, [])", ["A = !, B = (!,{fail})"]},
    {"Y = 1, Z = f(W), W = 2, X = ([a], Z, Y), phrase(X, [])",
     {:error, "type_error(callable,1)"}},
    {"X = [a|T], T = [b|c], phrase(X, L)", {:error, "type_error(list,[a,b|c])"}},
    # der Fehlerterm ist aufgelöst (Bindungen im catch-Ziel sind danach weg)
    {"catch((W = 3, Z = g(W), phrase((Z, {1}), _)), error(type_error(_, (g(V,_,_),_,_)), _), true), V == 3",
     ["V = 3"]},
    {"catch((F = 1, T = [e(F)|c], phrase([a|T], _)), error(type_error(list, [_, e(V)|_]), _), true), V == 1",
     ["V = 1"]},
    {"A = [a], B = (!, {fail}), phrase((((A -> B) ; []) ; [a]), [a])", :fails}
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
