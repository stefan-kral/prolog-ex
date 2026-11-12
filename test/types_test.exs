defmodule PrologEx.TypesTest do
  # library(types) wie SICStus 4: must_be/4, illarg/3,4; Fehler als
  # error(ISO, SICStus) mit Ziel und Argumentnummer
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(types)).
  :- use_module(library(mutables)).
  e(G, E) :- catch((G, E = ok), error(E0, E1), E = E0/E1).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, expect} <- [
        # einfache Typen
        {"e(must_be(1, integer, foo(1), 1), E)", ["E = ok"]},
        {"e(must_be(a, integer, foo(a), 1), E)",
         ["E = type_error(integer,a)/type_error(foo(a),1,integer,a)"]},
        {"e(must_be(_, integer, foo, 1), E)",
         ["E = instantiation_error/instantiation_error(foo,1)"]},
        {"e(must_be(1.5, float, f, 2), E)", ["E = ok"]},
        {"e(must_be(1, float, f, 2), E)", ["E = type_error(float,1)/type_error(f,2,float,1)"]},
        {"e(must_be(f(x), callable, f, 1), E)", ["E = ok"]},
        {"e(must_be(3, callable, f, 1), E)",
         ["E = type_error(callable,3)/type_error(f,1,callable,3)"]},
        {"e(must_be(f(_), term, f, 1), E)", ["E = ok"]},
        {"e(must_be(_, term, f, 1), E)", ["E = ok"]},
        {"e(must_be(a, var, f(a), 1), E)",
         ["E = uninstantiation_error(a)/uninstantiation_error(f(a),1,a)"]},
        {"e(must_be(_, nonvar, f, 1), E)", ["E = instantiation_error/instantiation_error(f,1)"]},
        {"e(must_be(f(_), ground, f, 1), E)",
         ["E = instantiation_error/instantiation_error(f,1)"]},
        {"e(must_be(f(a), ground, f, 1), E)", ["E = ok"]},
        {"e(must_be(_, simple, f, 1), E)", ["E = ok"]},
        {"e(must_be(f(x), simple, f, 1), E)",
         ["E = type_error(simple,f(x))/type_error(f,1,simple,f(x))"]},
        {"e(must_be(false, boolean, f, 1), E)", ["E = ok"]},
        {"e(must_be(yes, boolean, f, 1), E)",
         ["E = type_error(boolean,yes)/type_error(f,1,boolean,yes)"]},
        {"e(must_be(a, character, f, 1), E)", ["E = ok"]},
        {"e(must_be(ab, character, f, 1), E)",
         ["E = type_error(character,ab)/type_error(f,1,character,ab)"]},
        {"e(must_be(97, character_code, f, 1), E)", ["E = ok"]},
        {"e(must_be(-1, character_code, f, 1), E)",
         ["E = representation_error(character_code)/representation_error(f,1,character_code)"]},
        {"e(must_be(a, character_code, f, 1), E)",
         ["E = type_error(integer,a)/type_error(f,1,integer,a)"]},
        {"e(must_be(x, db_reference, f, 1), E)",
         ["E = type_error(db_reference,x)/type_error(f,1,db_reference,x)"]},
        {"e((create_mutable(1, M), must_be(M, mutable, f, 1)), E)", :succeeds},
        {"e(must_be(m, mutable, f, 1), E)",
         ["E = type_error(mutable,m)/type_error(f,1,mutable,m)"]},
        {"e(must_be(<, order, f, 1), E)", ["E = ok"]},
        {"e(must_be(foo, order, f, 1), E)",
         ["E = domain_error(order,foo)/domain_error(f,1,order,foo)"]},
        {"e(must_be(1, order, f, 1), E)", ["E = type_error(atom,1)/type_error(f,1,atom,1)"]},
        {"e(must_be(b, oneof([a,b]), f, 1), E)", ["E = ok"]},
        {"e(must_be(c, oneof([a,b]), f, 1), E)",
         ["E = domain_error(oneof([a,b]),c)/domain_error(f,1,oneof([a,b]),c)"]},
        {"e(must_be(k-v, pair, f, 1), E)", ["E = ok"]},
        {"e(must_be(k+v, pair, f, 1), E)", ["E = type_error(pair,k+v)/type_error(f,1,pair,k+v)"]},
        # Bereiche
        {"e(must_be(2, integer(between(1,3)), f, 1), E)", ["E = ok"]},
        {"e(must_be(5, integer(between(1,3)), f(5), 1), E)",
         ["E = domain_error(between(1,3),5)/domain_error(f(5),1,between(1,3),5)"]},
        {"e(must_be(0, integer(>=(0)), f, 1), E)", ["E = ok"]},
        {"e(must_be(0, integer(>(0)), f, 1), E)",
         ["E = domain_error(>(0),0)/domain_error(f,1,>(0),0)"]},
        {"e(must_be(2.5, number(<(3)), f, 0), E)", ["E = ok"]},
        {"e(must_be(3, number(=\\=(3)), f, 0), E)",
         ["E = domain_error(=\\=(3),3)/domain_error(f,0,=\\=(3),3)"]},
        {"e(must_be(1.0, float(=:=(1)), f, 0), E)", ["E = ok"]},
        {"e(must_be(1, float(=:=(1)), f, 0), E)",
         ["E = type_error(float,1)/type_error(f,0,float,1)"]},
        {"e(must_be(a, integer(>(0)), f, 0), E)",
         ["E = type_error(integer,a)/type_error(f,0,integer,a)"]},
        # Listen
        {"e(must_be([1,2], list, f, 1), E)", ["E = ok"]},
        {"e(must_be([1|_], list, f, 1), E)",
         ["E = instantiation_error/instantiation_error(f,1)"]},
        {"e(must_be([1|a], proper_list, f, 1), E)",
         ["E = type_error(list,[1|a])/type_error(f,1,list,[1|a])"]},
        {"e(must_be([1,a], list(integer), f, 1), E)",
         ["E = type_error(integer,a)/type_error(f,1,integer,a)"]},
        {"e(must_be([1,_], proper_list(integer), f, 1), E)",
         ["E = instantiation_error/instantiation_error(f,1)"]},
        {"e(must_be([[a],[b,c]], list(list(atom)), f, 1), E)", ["E = ok"]},
        # Prädikatsangaben
        {"e(must_be(foo/2, pred_spec, f, 1), E)", ["E = ok"]},
        {"e(must_be(m:foo/0, pred_spec, f, 1), E)", ["E = ok"]},
        {"e(must_be(foo/_, pred_spec, f, 1), E)",
         ["E = instantiation_error/instantiation_error(f,1)"]},
        {"e(must_be(foo/(-1), pred_spec, f, 1), E)",
         ["E = type_error(pred_spec,foo/ -1)/type_error(f,1,pred_spec,foo/ -1)"]},
        {"e(must_be(foo, pred_spec, f, 1), E)",
         ["E = type_error(pred_spec,foo)/type_error(f,1,pred_spec,foo)"]},
        {"e(must_be((a/1, [b/2, m:(c/0, d/1)]), pred_spec_tree, f, 1), E)", ["E = ok"]},
        {"e(must_be([a/1, b], pred_spec_tree, f, 1), E)",
         ["E = type_error(pred_spec_tree,[a/1,b])/type_error(f,1,pred_spec_tree,[a/1,b])"]},
        {"e(must_be([a/1|_], pred_spec_tree, f, 1), E)",
         ["E = instantiation_error/instantiation_error(f,1)"]},
        # var_or
        {"e(must_be(_, var_or(integer), f, 1), E)", ["E = ok"]},
        {"e(must_be(a, var_or(integer), f, 1), E)",
         ["E = type_error(integer,a)/type_error(f,1,integer,a)"]},
        # unbekannter Typ
        {"e(must_be(x, nonsense, f, 1), E)",
         [
           "E = domain_error(typeterm,nonsense)/domain_error(must_be(x,nonsense,f,1),2,typeterm,nonsense)"
         ]},
        {"e(must_be([], list(nonsense), f, 1), E)",
         [
           "E = domain_error(typeterm,list(nonsense))/domain_error(must_be([],list(nonsense),f,1),2,typeterm,list(nonsense))"
         ]},
        # illarg/3,4
        {"e(illarg(var, foo(_), 1), E)",
         ["E = instantiation_error/instantiation_error(foo(_A),1)"]},
        {"e(illarg(type(integer), foo(a), 1), E)",
         ["E = type_error(integer,a)/type_error(foo(a),1,integer,a)"]},
        {"e(illarg(type(integer), foo(1), 1), E)", ["E = ok"]},
        {"e(illarg(domain(integer, positive), foo(-3), 1), E)",
         ["E = domain_error(positive,-3)/domain_error(foo(-3),1,positive,-3)"]},
        {"e(illarg(domain(integer, positive), foo(x), 1), E)",
         ["E = type_error(integer,x)/type_error(foo(x),1,integer,x)"]},
        {"e(illarg(force_type(atom), foo(1), 1), E)",
         ["E = type_error(atom,1)/type_error(foo(1),1,atom,1)"]},
        {"e(illarg(force_type(atom), foo(1), 1, 7), E)",
         ["E = type_error(atom,7)/type_error(foo(1),1,atom,7)"]},
        {"e(illarg(existence(file, 'x.pl', gone), open(x), 1), E)",
         ["E = existence_error(file,'x.pl')/existence_error(open(x),1,file,'x.pl',gone)"]},
        {"e(illarg(permission(open, source_sink, no), open(x), 1), E)",
         [
           "E = permission_error(open,source_sink,x)/permission_error(open(x),open,source_sink,x,no)"
         ]},
        {"e(illarg(representation(max_arity), f, 0), E)",
         ["E = representation_error(max_arity)/representation_error(f,0,max_arity)"]},
        {"e(illarg(evaluation(zero_divisor), f(0), 1), E)",
         ["E = evaluation_error(zero_divisor)/evaluation_error(f(0),1,zero_divisor,0)"]},
        {"e(illarg(context(if, cut), f, 0), E)",
         ["E = context_error(if,cut)/context_error(f,if,cut)"]},
        {"e(illarg(consistency(a, b, m), f, 0), E)",
         ["E = consistency_error(a,b,m)/consistency_error(f,a,b,m)"]},
        {"e(illarg(syntax(3, bad, [], []), f, 0), E)",
         ["E = syntax_error(bad)/syntax_error(f,3,bad,[],[])"]},
        {"e(illarg(resource(memory), f, 0), E)",
         ["E = resource_error(memory)/resource_error(f,memory)"]},
        {"e(illarg(system(boom), f, 0), E)", ["E = system_error/system_error(boom)"]},
        {"e(illarg(bogus, f, 0), E)",
         [
           "E = domain_error(illarg_error,bogus)/domain_error(illarg(bogus,f,0,_A),1,illarg_error,bogus)"
         ]}
      ] do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
