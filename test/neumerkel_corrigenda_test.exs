defmodule PrologEx.NeumerkelCorrigendaTest do
  # Neumerkels Seiten zu den Korrigenda als Tabelle:
  #   * dtc2 (Cor.2): op/3 mit {} und |, subsumes_term/2, callable/1,
  #     ground/1, compare/3, sort/2, keysort/2, term_variables/2,
  #     retractall/1, call/N, Arithmetik (div, max/min, ^, asin, acos,
  #     atan2, tan, pi, xor), write_canonical/1 (C18)
  #   * WDCor3 (Cor.3, mit WDR3): Optionen (C14/C16), max_arity (C10),
  #     domain prolog_flag (C17), -1 ^ -2 (C19)
  #   * stc (Technical Corrigendum-Kandidaten): negative Zahlen, (:-B),
  #     double_quotes, current_predicate, abolish, close/2, max_float,
  #     max_arity, zyklisches keysort
  #   * built-in_predicates: ?=/2
  #   * evaluable_functors: Auswahl (e, lsb, popcount, gcd, copysign, ...)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @args65537 "length(L, 65537), maplist(=(a), L), atomic_list_concat(L, ',', A0), " <>
               "atomic_list_concat(['f(', A0, ').'], A)"

  @rows [
    # --- Operatoren (dtc2 C2) ---
    {"op(500, xfy, {})", {:error, "permission_error(create,operator,{})"}},
    {"op(500, xfy, [{}])", {:error, "permission_error(create,operator,{})"}},
    {"op(1000, xfy, '|')", {:error, "permission_error(create,operator,'|')"}},
    {"op(1000, xfy, ['|'])", {:error, "permission_error(create,operator,'|')"}},
    {"op(1150, fx, '|')", {:error, "permission_error(create,operator,'|')"}},
    {"op(1105, xfy, '|')", true},
    {"op(0, xfy, '|'), \\+ current_op(_, xfy, '|'), op(1105, xfy, '|')", true},
    # --- subsumes_term/2 (C3) ---
    {"subsumes_term(a, a)", true},
    {"subsumes_term(f(X,Y), f(Z,Z))", true},
    {"subsumes_term(f(Z,Z), f(X,Y))", :fails},
    {"subsumes_term(g(X), g(f(X)))", :fails},
    {"subsumes_term(X, f(X))", :fails},
    {"subsumes_term(X, Y), subsumes_term(Y, f(X))", true},
    # --- Typprüfung (C4–C6) ---
    {"callable(a)", true},
    {"callable(3)", :fails},
    {"callable(X)", :fails},
    {"callable((1,2))", true},
    {"ground(3)", true},
    {"ground(a(1, _))", :fails},
    {"acyclic_term(a(1, _))", true},
    {"X = f(X), \\+ acyclic_term(X), write(ok)", {:out, "ok", :succeeds}},
    # --- compare/3 (C7) ---
    {"compare(Order, 3, 5)", ["Order = (<)"]},
    {"compare(Order, d, d)", ["Order = (=)"]},
    {"compare(Order, Order, <)", ["Order = (<)"]},
    {"compare(<, <, <)", :fails},
    {"compare(1+2, 3, 3.0)", {:error, "type_error(atom,1+2)"}},
    {"compare(>=, 3, 3.0)", {:error, "domain_error(order,>=)"}},
    # --- sort/2 (C8) ---
    {"sort([1, 1], Sorted)", ["Sorted = [1]"]},
    {"sort([1+Y, z, a, V, 1, 2, V, 1, 7.0, 8.0, 1+Y, 1+2, 8.0, -a, -X, a], Sorted)",
     ["Sorted = [V,7.0,8.0,1,2,a,z,-X,-a,1+Y,1+2]"]},
    {"sort([X, 1], [1, 1])", ["X = 1"]},
    {"sort([1, 1], [1, 1])", :fails},
    {"sort([f(U),U,U,f(V),f(U),V],L)", ["L = [U,V,f(U),f(V)]"]},
    {"sort(_, L)", {:error, "instantiation_error"}},
    {"sort([a|_], L)", {:error, "instantiation_error"}},
    {"sort(a, L)", {:error, "type_error(list,a)"}},
    {"sort([a|b], L)", {:error, "type_error(list,[a|b])"}},
    {"sort([], a)", {:error, "type_error(list,a)"}},
    {"sort([], [a|b])", {:error, "type_error(list,[a|b])"}},
    # zyklische Liste: type_error(list, L) mit der Liste selbst
    {"\\+ \\+ (L = [a|L], catch(sort(L, _), error(type_error(list, E), _), true), E == L)", true},
    {"\\+ \\+ (L = [a|L], catch(msort(L, _), error(type_error(list, E), _), true), E == L)",
     true},
    # --- keysort/2 (C9) ---
    {"keysort([1-1, 1-1], Sorted)", ["Sorted = [1-1,1-1]"]},
    {"keysort([2-99, 1-a, 3-f(_), 1-z, 1-a, 2-44], Sorted)",
     ["Sorted = [1-a,1-z,1-a,2-99,2-44,3-f(_A)]"]},
    {"keysort([X-1,1-1],[2-1,1-1])", ["X = 2"]},
    {"\\+ \\+ (Pairs = [1-2|Pairs], " <>
       "catch(keysort(Pairs, _), error(type_error(list, E), _), true), E == Pairs)", true},
    {"keysort(_, S)", {:error, "instantiation_error"}},
    {"keysort(a, S)", {:error, "type_error(list,a)"}},
    {"keysort([], a)", {:error, "type_error(list,a)"}},
    {"keysort([_], S)", {:error, "instantiation_error"}},
    {"keysort([a], S)", {:error, "type_error(pair,a)"}},
    {"keysort([], [a])", {:error, "type_error(pair,a)"}},
    # --- term_variables/2 (C12) ---
    {"term_variables(t, Vars)", ["Vars = []"]},
    {"term_variables(A+B*C/B-D, Vars)", ["Vars = [A,B,C,D]"]},
    {"term_variables(t, [_, _|a])", {:error, "type_error(list,"}},
    {"S=B+T, T=A*B, term_variables(S, Vars)", ["S = B+A*B, T = A*B, Vars = [B,A]"]},
    {"T=A*B, S=B+T, term_variables(S, Vars)", ["S = B+A*B, T = A*B, Vars = [B,A]"]},
    {"term_variables(A+B+B, [B|Vars])", ["A = B, Vars = [B]"]},
    # --- retractall/1 (C13) ---
    {"retract((atom(_):-true))", {:error, "permission_error(modify,static_procedure,atom/1)"}},
    {"assertz(insect(ant)), assertz(insect(bee)), retractall(insect(bee)), " <>
       "findall(X, insect(X), L)", ["L = [ant]"]},
    {"retractall(mammal(_))", true},
    {"retractall(3)", {:error, "type_error(callable,3)"}},
    {"retractall(_)", {:error, "instantiation_error"}},
    {"retractall(retractall(_))",
     {:error, "permission_error(modify,static_procedure,retractall/1)"}},
    # --- call/N (C14) ---
    {"call(integer, 3)", true},
    {"call(functor(F,c), 0)", ["F = c"]},
    {"call(call(call(atom_concat, pro), log), Atom)", ["Atom = prolog"]},
    {"call(;, X = 1, Y = 2)", ["X = 1", "Y = 2"]},
    {"call(;, (true->fail), X=1)", :fails},
    {"call(_, a)", {:error, "instantiation_error"}},
    {"call(1, a)", {:error, "type_error(callable,1)"}},
    {"call(',', fail, 1)", {:error, "type_error(callable,(fail,1))"}},
    {"Y = (write(3), 3), call(Y)", {:error, "type_error(callable,(write(3),3))"}},
    {"catch(_, error(E, _), true)", ["E = instantiation_error"]},
    # über max_arity hinaus (Ziel mit 65537 Argumenten)
    {"functor(F, f, 65536), catch(call(F, a), error(representation_error(R), _), true), R == max_arity",
     :succeeds},
    # --- Arithmetik (C15–C17, Cor.3 C19) ---
    {"X is +(1)", ["X = 1"]},
    {"X is 7 div 2", ["X = 3"]},
    {"X is -7 div 2", ["X = -4"]},
    {"X is 7 div 0", {:error, "evaluation_error(zero_divisor)"}},
    {"current_op(P, fy, +)", ["P = 200"]},
    {"current_op(P, yfx, div)", ["P = 400"]},
    {"X is max(2, 3)", ["X = 3"]},
    {"X is max(2.0, 3)", ["X = 3"]},
    {"X is max(2, 3.0)", ["X = 3.0"]},
    {"X is min(2, 3)", ["X = 2"]},
    {"X is min(2, 3.0)", ["X = 2"]},
    {"X is min(2.0, 3)", ["X = 2.0"]},
    {"X is 0^0", ["X = 1"]},
    {"X is 3^1.0", ["X = 3.0"]},
    {"X is 3^3", ["X = 27"]},
    {"X is 3^27", ["X = 7625597484987"]},
    {"X is 3^3^3", ["X = 7625597484987"]},
    {"X is 2^(-1)", {:error, "type_error(float,2)"}},
    {"X is 1^(-1)", ["X = 1"]},
    {"X is -1^(-1)", ["X = -1"]},
    {"X is (-1)^(-2)", ["X = 1"]},
    {"X is -1 ^ -2", ["X = 1"]},
    # 0 hoch negativ: undefined (nicht zero_divisor)
    {"X is 0^(-1)", {:error, "evaluation_error(undefined)"}},
    {"X is 0 ** -1", {:error, "evaluation_error(undefined)"}},
    {"X is 0.0 ** -1", {:error, "evaluation_error(undefined)"}},
    {"X is 2^ -1.5", ["X = 0.3535533905932738"]},
    {"X is 2.0^(-1)", ["X = 0.5"]},
    {"X is -1.0 ** (1+0)", ["X = -1.0"]},
    {"X is asin(0.5)", ["X = 0.5235987755982989"]},
    {"X is 2*asin(1)", ["X = 3.141592653589793"]},
    {"X is asin(2)", {:error, "evaluation_error(undefined)"}},
    {"X is acos(-1)", ["X = 3.141592653589793"]},
    {"X is acos(1.5)", {:error, "evaluation_error(undefined)"}},
    {"X is atan2(1,0)", ["X = 1.5707963267948966"]},
    {"X is atan2(0,-1)", ["X = 3.141592653589793"]},
    {"X is atan2(0,0)", {:error, "evaluation_error(undefined)"}},
    {"X is tan(0.5)", ["X = 0.5463024898437905"]},
    {"X is pi", ["X = 3.141592653589793"]},
    {"X is xor(10, 12)", ["X = 6"]},
    {"X is xor(125, 255)", ["X = 130"]},
    {"X is xor(-10, 12)", ["X = -6"]},
    {"X is 7 / -3", ["X = -2.3333333333333335"]},
    {"X is foo + 1", {:error, "type_error(evaluable,foo/0)"}},
    # --- Schreiben (C18) ---
    {"write_canonical([1,2,3])", {:out, "'.'(1,'.'(2,'.'(3,[])))", true}},
    {"writeq('.')", {:out, "'.'", true}},
    {"writeq(f('.'))", {:out, "f('.')", true}},
    # --- Optionen (Cor.3 C14/C16) ---
    {"write_term(1,[quoted(non_boolean)])",
     {:error, "domain_error(write_option,quoted(non_boolean))"}},
    {"write_term(1,[quoted(B)])", {:error, "instantiation_error"}},
    {"B = true, write_term(1,[quoted(B)])", {:out, "1", ["B = true"]}},
    {"write_term(1, [foo])", {:error, "domain_error(write_option,foo)"}},
    {"write_term(1, foo)", {:error, "type_error(list,foo)"}},
    {"write_term(1, [_])", {:error, "instantiation_error"}},
    {"open(t_cor, write, S, [type(_)])", {:error, "instantiation_error"}},
    {"open(t_cor, write, S, [foo])", {:error, "domain_error(stream_option,foo)"}},
    {"open(t_cor, write, S, foo)", {:error, "type_error(list,foo)"}},
    {"open(t_cor, write, S, [_|_])", {:error, "instantiation_error"}},
    {"open(t_cor, write, S, [type(foo)])", {:error, "domain_error(stream_option,type(foo))"}},
    {"read_term_from_atom('foo.', T, [foo])", {:error, "domain_error(read_option,foo)"}},
    {"open(t_cor, write, S), catch(close(S, [foo]), E, (close(S), throw(E)))",
     {:error, "domain_error(close_option,foo)"}},
    # --- Flags (C10, C17) ---
    {"set_prolog_flag(date, 'July 1988')", {:error, "domain_error(prolog_flag,date)"}},
    {"current_prolog_flag(max_arity, A), X is A + 1, functor(T, foo, X)",
     {:error, "representation_error(max_arity)"}},
    {"set_prolog_flag(double_quotes, _)", {:error, "instantiation_error"}},
    {"set_prolog_flag(double_quotes, foo)",
     {:error, "domain_error(flag_value,double_quotes+foo)"}},
    {"set_prolog_flag(_, chars)", {:error, "instantiation_error"}},
    # --- bagof/findall ---
    {"bagof(X, G, L)", {:error, "instantiation_error"}},
    {"bagof(X, Y^G, L)", {:error, "instantiation_error"}},
    {"bagof(X, (X=2 ; X=1), S)", ["S = [2,1]"]},
    {"findall(X, fail, S)", ["S = []"]},
    # --- negative Zahlen (stc, Anm. 3) ---
    {"integer(- /**/ 1)", true},
    {"X = - 1, integer(X)", ["X = -1"]},
    {"X = - (1), \\+ integer(X)", ["X = - (1)"]},
    {"X = - -1, X = -(Y), integer(Y)", ["X = - -1, Y = -1"]},
    {"X = - 1^2, X = A^B, A == -1", ["A = -1, B = 2, X = -1^2"]},
    # --- Klauseln als Ziele (stc #56, #58) ---
    {"(:-B)", {:error, "existence_error(procedure,(:-)/1)"}},
    {"call((A:-B))", {:error, "existence_error(procedure,(:-)/2)"}},
    {"asserta(((a:-b):-true))", {:error, "permission_error(modify,static_procedure,(:-)/2)"}},
    {"asserta(((:-b):-true))", {:error, "permission_error(modify,static_procedure,(:-)/1)"}},
    # --- current_predicate/abolish (stc #67–#69) ---
    {"current_predicate(elk/Arity)", :fails},
    {"current_predicate(foo)", {:error, "type_error(predicate_indicator,foo)"}},
    {"current_predicate(elk/a)", {:error, "type_error(predicate_indicator,elk/a)"}},
    {"current_predicate(1/A)", {:error, "type_error(predicate_indicator,1/"}},
    {"abolish(foo/_)", {:error, "instantiation_error"}},
    {"abolish(foo)", {:error, "type_error(predicate_indicator,foo)"}},
    {"abolish(foo/a)", {:error, "type_error(integer,a)"}},
    {"abolish(foo/65537)", {:error, "representation_error(max_arity)"}},
    # --- nicht darstellbare Zahlen und Stelligkeiten (stc #73, #74) ---
    {"number_chars(N, ['1','.','0',e,'4','0','0'])", {:error, "representation_error(max_float)"}},
    {"number_codes(N, \"1.0e400\")", {:error, "representation_error(max_float)"}},
    {"atom_number('1.0e400', N)", :fails},
    {"read_term_from_atom('1.0e400', T, [])", {:error, "representation_error(max_float)"}},
    {"read_term_from_atom('-1.0e400', T, [])", {:error, "representation_error(max_float)"}},
    {@args65537 <> ", read_term_from_atom(A, T, [])",
     {:error, "representation_error(max_arity)"}},
    {"writeq(244124086793065425827.0)", {:out, "2.4412408679306543e20", true}},
    {"X is 244124086793065425827 - 244124086793065425827.0", ["X = 0.0"]},
    # --- Ziffertrenner im Bruchteil ---
    {"read_term_from_atom('1_000.000_1', T, []), write_canonical(T)", {:out, "1000.0001"}},
    {"read_term_from_atom('1.2_5', T, []), write_canonical(T)", {:out, "1.25"}},
    # --- ungültiges UTF-8 ist kein Zeichen (stc #76) ---
    {"open(t_u8, write, S, [type(binary)]), maplist(put_byte(S), [255]), close(S), open(t_u8, read, T), catch(get_char(T, C), error(E, _), true), close(T), E == representation_error(character)",
     :succeeds},
    {"open(t_u8, write, S, [type(binary)]), maplist(put_byte(S), [255]), close(S), open(t_u8, read, T), catch(peek_char(T, C), error(E, _), true), close(T), E == representation_error(character)",
     :succeeds},
    # get_code verbraucht das Byte, danach geht es weiter
    {"open(t_u8, write, S, [type(binary)]), maplist(put_byte(S), [255, 97]), close(S), open(t_u8, read, T), catch(get_code(T, C), error(E, _), true), get_char(T, D), close(T), E == representation_error(character), D == a",
     :succeeds},
    {"open(t_u8, write, S, [type(binary)]), maplist(put_byte(S), [195]), close(S), open(t_u8, read, T), catch(get_char(T, C), error(E, _), true), close(T), E == representation_error(character)",
     :succeeds},
    {"open(t_u8, write, S, [type(binary)]), maplist(put_byte(S), [195, 188]), close(S), open(t_u8, read, T), get_char(T, C), close(T), C == '\u00fc'",
     :succeeds},
    {"open(t_u8, write, S, [type(binary)]), maplist(put_byte(S), [97, 40, 39, 252, 39, 41, 46, 10]), close(S), open(t_u8, read, T), catch(read(T, X), error(E, _), true), close(T), E == representation_error(character)",
     :succeeds},
    {"open(t_u8, write, S, [type(binary)]), maplist(put_byte(S), [97, 40, 252, 41, 46, 10]), close(S), open(t_u8, read, T), catch(read(T, X), error(E, _), true), close(T), E == representation_error(character)",
     :succeeds},
    # --- ?=/2 (built-in_predicates) ---
    {"?=(a, a)", true},
    {"?=(a, b)", true},
    {"?=(X, Y)", :fails},
    {"?=(X, X)", true},
    {"?=(f(X), f(a))", :fails},
    {"?=(f(X,b), f(a,c))", true},
    # --- evaluable_functors (Auswahl) ---
    {"X is e", ["X = 2.718281828459045"]},
    {"X is lsb(8)", ["X = 3"]},
    {"X is popcount(7)", ["X = 3"]},
    {"X is gcd(12, 18)", ["X = 6"]},
    {"X is copysign(2, -0.0)", ["X = -2.0"]},
    {"X is log(2, 8)", ["X = 3.0"]},
    {"X is sinh(0)", ["X = 0.0"]},
    {"X is sign(-2.5)", ["X = -1.0"]},
    {"X is truncate(2.5)", ["X = 2"]},
    {"X is log2(8)", ["X = 3.0"]},
    {"X is trig", {:error, "type_error(evaluable,trig/0)"}}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    on_exit(fn -> Enum.each(["t_cor", "t_u8"], &File.rm/1) end)
    {:ok, reader: r, db: TableCase.db(r, ~w(lists iso_ext swi))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
