defmodule PrologEx.NeumerkelMiscTest do
  # Kleinere Seiten Neumerkels als Tabelle:
  #   * digit_separators (WG17 2025: Optionen 1, 3, 4 angenommen, 5–7
  #     abgelehnt, 2 offen – hier ein Fehler)
  #   * noname_operators: '[]' und '{}' sind keine Operatoren
  #   * syntax_extension: | als Infixoperator (1105, xfy, wie SWI/YAP; die
  #     mit ** markierten SWI-Erweiterungen sind Fehler)
  #   * error_k: uninstantiation_error bei open/3,4
  #   * draft-7.10.5: Schreiben (e1, e2, e3, h 1, h 2 iii/iv)
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  # Text lesen und kanonisch schreiben
  @rows [
    # digit separators
    {"read_term_from_atom('1_000', T, []), write_canonical(T)", {:out, "1000"}},
    {"read_term_from_atom('1_ 000', T, []), write_canonical(T)", {:out, "1000"}},
    {"read_term_from_atom('1_\\n  000', T, []), write_canonical(T)", {:out, "1000"}},
    {"read_term_from_atom('1_ /* comment */ 000', T, []), write_canonical(T)", {:out, "1000"}},
    {"read_term_from_atom('1_000_000', T, []), write_canonical(T)", {:out, "1000000"}},
    {"read_term_from_atom('0b1_0', T, []), write_canonical(T)", {:out, "2"}},
    {"read_term_from_atom('0o1_7', T, []), write_canonical(T)", {:out, "15"}},
    {"read_term_from_atom('0xf_f', T, []), write_canonical(T)", {:out, "255"}},
    {"read_term_from_atom('1__000', T, []), write_canonical(T)", {:error, "syntax_error"}},
    {"read_term_from_atom('1 000', T, []), write_canonical(T)", {:error, "syntax_error"}},
    # noname operators
    {"op(300, fx, '[]')", {:error, "permission_error(create,operator,[])"}},
    {"op(300, fx, '{}')", {:error, "permission_error(create,operator,{})"}},
    {"op(600, xfy, [])", {:error, "permission_error(create,operator,[])"}},
    # | (syntax extension)
    {"read_term_from_atom('(a|b)', T, []), write_canonical(T)", {:out, "'|'(a,b)"}},
    {"read_term_from_atom('f(a|b)', T, []), write_canonical(T)", {:error, "syntax_error"}},
    {"read_term_from_atom('f(a|b,c)', T, []), write_canonical(T)", {:error, "syntax_error"}},
    {"read_term_from_atom('f((a|b))', T, []), write_canonical(T)", {:out, "f('|'(a,b))"}},
    {"read_term_from_atom('f(|)', T, []), write_canonical(T)", {:error, "syntax_error"}},
    {"read_term_from_atom('f((|))', T, []), write_canonical(T)", {:error, "syntax_error"}},
    {"read_term_from_atom('\\'|\\'', T, []), write_canonical(T)", {:out, "'|'"}},
    {"read_term_from_atom('[|]', T, []), write_canonical(T)", {:error, "syntax_error"}},
    {"read_term_from_atom('[a|b|c]', T, []), write_canonical(T)", {:error, "syntax_error"}},
    {"read_term_from_atom('[a|b,c]', T, []), write_canonical(T)", {:error, "syntax_error"}},
    {"read_term_from_atom('(1;2|3;4)', T, []), write_canonical(T)", {:out, "'|'(;(1,2),;(3,4))"}},
    {"current_op(P, T, '|')", ["P = 1105, T = xfy"]},
    {"op(1100, fx, '|')", {:error, "permission_error(create,operator,'|')"}},
    # error_k
    {"open(t_error_k, write, foo)", {:error, "uninstantiation_error(foo)"}},
    # Schreiben (Entwurf 7.10.5)
    {"writeq('$VAR'(0))", {:out, "A"}},
    {"write_term('$VAR'(27), [numbervars(true)])", {:out, "B1"}},
    {"writeq('$VAR'(-1))", {:out, "'$VAR'(-1)"}},
    {"write_term(f(X), [variable_names(['x y'=X])])", {:out, "f(x y)"}},
    {"writeq([(a:-b),(c,d)])", {:out, "[(a:-b),(c,d)]"}},
    {"writeq('{}'(x))", {:out, "{x}"}},
    {"writeq({a,b})", {:out, "{a,b}"}},
    {"writeq('|'(a,b))", {:out, "a|b"}},
    {"writeq(- (1))", {:out, "- (1)"}},
    {"writeq(- (-1))", {:out, "- -1"}},
    {"writeq(- (a^2))", {:out, "- (a^2)"}},
    {"writeq(- (a+b))", {:out, "- (a+b)"}},
    {"writeq(- f(x))", {:out, "-f(x)"}},
    {"writeq(- (- a))", {:out, "- -a"}},
    {"writeq(\\+ (a^2))", {:out, "\\+a^2"}}
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    on_exit(fn -> File.rm("t_error_k") end)
    {:ok, reader: r, db: TableCase.db(r, ~w(swi))}
  end

  for {q, expect} <- @rows do
    test q, c do
      Reader.put_current(c.reader)
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(expect)), actual), inspect(actual)
    end
  end
end
