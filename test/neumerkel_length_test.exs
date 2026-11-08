defmodule PrologEx.NeumerkelLengthTest do
  # Neumerkels Vergleich zu length/2 und atom_length/2
  # (https://www.complang.tuwien.ac.at/ulrich/iso-prolog/length; Erwartung
  # nach der WG17-Resolution 2011). Nicht aufgenommen: #21, #22 und #30
  # (laufen endlos – erlaubt ist auch resource_error) und der zweite Teil
  # von #26 (dito).
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @rows [
    # a1–a5
    {"atom_length(A,N)", {:error, "instantiation_error"}},
    {"atom_length(a,a)", {:error, "type_error(integer,a)"}},
    {"atom_length(a,1.5)", {:error, "type_error(integer,1.5)"}},
    {"atom_length(a,-1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"atom_length(1,N)", {:error, "type_error(atom,1)"}},
    # 1–20
    {"length(L,N)", {:first, ["L = [], N = 0", "L = [_A], N = 1", "L = [_A,_B], N = 2"]}},
    {"length(L,0)", ["L = []"]},
    {"length([_|L],0)", :fails},
    {"length(2,0)", :fails},
    {"length([_|2],0)", :fails},
    {"length([_|2],N)", :fails},
    {"length([_|2],2)", :fails},
    {"length(L,-1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"length([],-1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"length(a,-1)", {:error, "domain_error(not_less_than_zero,-1)"}},
    {"length([],-0.5)", {:error, "type_error(integer,-0.5)"}},
    {"length(L,-0.5)", {:error, "type_error(integer,-0.5)"}},
    {"length([a],1.0)", {:error, "type_error(integer,1.0)"}},
    {"length(L,1.0)", {:error, "type_error(integer,1.0)"}},
    {"length(L,1.5)", {:error, "type_error(integer,1.5)"}},
    {"length(L,1.0e99)", {:error, "type_error(integer,1.0e99)"}},
    {"N is 2^52, length([], N)", :fails},
    {"length([],0+0)", {:error, "type_error(integer,0+0)"}},
    {"length([],-_)", {:error, "type_error(integer,-_"}},
    {"length([a],-_)", {:error, "type_error(integer,-_"}},
    # 23–25
    {"L = [_|_], length(L,L)", {:error, "type_error(integer,[_"}},
    {"L = [_], length(L,L)", {:error, "type_error(integer,[_"}},
    {"L = [1], length(L,L)", {:error, "type_error(integer,[1])"}},
    # 26–28: zyklische Listen (sto: ohne Occurs-Check)
    {"L = [a|L], ( true ; length(L,N) )", {:first, ["L = [a|L]"]}},
    {"L = [a|L], length(L,0)", :fails},
    {"L = [a|L], length(L,7)", :fails},
    # 29, 31
    {"freeze(L,L=[]), length(L,L)", :fails},
    {"freeze(L,L=[_|L]), N is 2^64, length(L,N)", :fails}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {:ok, reader: r, db: TableCase.db(r, ~w(lists freeze))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
