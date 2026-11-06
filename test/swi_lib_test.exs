defmodule PrologEx.SwiLibTest do
  # library(swi): Komfort aus SWI-Prolog (PrologEx.Builtins.Swi), sichtbar
  # erst nach use_module(library(swi))
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  @src ":- use_module(library(swi)).\ncmp(O, A-_, B-_) :- compare(O, A, B).\n"

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal), do: ask(c, "catch((#{goal}), error(E, _), true)")

  defp out(c, goal) do
    ExUnit.CaptureIO.capture_io(fn -> assert ask(c, goal) != [] end)
  end

  test "writeln/1,2, tab/1,2", c do
    assert out(c, "writeln(f('A', \"b\"))") == "f(A,[b])\n"
    assert out(c, "writeln(user_output, x)") == "x\n"
    assert out(c, "tab(1 + 2), write(x)") == "   x"
    assert out(c, "tab(user_output, 2), write(x)") == "  x"
    assert out(c, "tab(-1), write(x)") == "x"
    assert err(c, "tab(a)") == ["E = type_error(evaluable,a/0)"]
    assert err(c, "tab(1.5)") == ["E = type_error(integer,1.5)"]
  end

  test "with_output_to/2: Senken, once, Fehler, Ausgabe zurück", c do
    assert ask(c, "with_output_to(atom(A), (write(a), print(1)))") == ["A = a1"]
    assert ask(c, "with_output_to(chars(Cs), write(ab))") == ["Cs = \"ab\""]
    assert ask(c, "with_output_to(chars(Cs, T), write(ab))") == ["Cs = [a,b|T]"]
    assert ask(c, "with_output_to(codes(Cs), write(ab))") == ["Cs = [97,98]"]
    assert ask(c, "with_output_to(codes(Cs, []), write(ab))") == ["Cs = [97,98]"]
    # wie once/1
    assert ask(
             c,
             "with_output_to(atom(A), member(X, [1, 2]))",
             @src <> ":- use_module(library(lists)).\n"
           ) ==
             ["A = '', X = 1"]

    assert ask(c, "with_output_to(atom(_), fail)") == []
    assert ask(c, "with_output_to(atom(b), write(a))") == []
    assert ask(c, "catch(with_output_to(atom(_), throw(x)), x, true)") == ["true"]
    # danach geht die Ausgabe wieder an den alten Strom
    assert out(c, "(with_output_to(atom(_), fail) ; true), write(z)") == "z"
    assert out(c, "catch(with_output_to(atom(_), throw(x)), x, true), write(z)") == "z"
    assert err(c, "with_output_to(_, true)") == ["E = instantiation_error"]
    assert err(c, "with_output_to(foo(_), true)") == ["E = domain_error(output_sink,foo(_A))"]
    # geschachtelt
    assert ask(
             c,
             "with_output_to(atom(A), (write(x), with_output_to(atom(B), write(y)), write(B)))"
           ) ==
             ["A = xy, B = y"]
  end

  test "format/3 mit Senke (eingebaut, wie SWI)", c do
    assert ask(c, "format(atom(A), \"~w-~a\", [1, b])", "") == ["A = '1-b'"]
    assert ask(c, "format(chars(Cs), \"x~w\", [1])", "") == ["Cs = \"x1\""]
    assert ask(c, "format(codes(Cs, T), \"a\", [])", "") == ["Cs = [97|T]"]
  end

  test "select/4, selectchk/3,4", c do
    assert ask(c, "findall(Y, select(b, [a,b,c,b], x, Y), Ys)") ==
             ["Ys = [\"axcb\",\"abcx\"]"]

    assert ask(c, "select(X, [1,2], Y, [1,3])") == ["X = 2, Y = 3"]
    assert ask(c, "selectchk(b, [a,b,b], R)") == ["R = \"ab\""]
    assert ask(c, "selectchk(b, [a,b,b], x, R)") == ["R = \"axb\""]
    assert ask(c, "selectchk(z, [a], _)") == []
  end

  test "flatten/2 wie SWI", c do
    assert ask(c, "flatten([a,[b,[c,X]],[]], L)") == ["L = [a,b,c,X]"]
    assert ask(c, "flatten(a, L)") == ["L = \"a\""]
    assert ask(c, "flatten(X, L)") == ["L = [X]"]
    assert ask(c, "flatten([[[]]], L)") == ["L = []"]
    assert ask(c, "flatten([a|T], L)") == ["L = [a,T]"]
  end

  test "predsort/3: = entfernt, stabil", c do
    assert ask(c, "predsort(cmp, [b-1, a-2, b-3, c-4], P)") == ["P = [a-2,b-1,c-4]"]
    assert ask(c, "predsort(cmp, [], P)") == ["P = []"]
    assert ask(c, "predsort(cmp, [x-1], P)") == ["P = [x-1]"]
    assert ask(c, "predsort(cmp, [a-1, a-2], P)") == ["P = [a-1]"]

    assert ask(
             c,
             "numlist(1, 30, L), reverse(L, R), predsort(compare, R, S), S == L",
             @src <> ":- use_module(library(lists)).\n"
           ) != []
  end

  test "sort/4: Schlüssel, Richtung, Duplikate, stabil", c do
    assert ask(c, "sort(0, @>=, [1,3,2,3], S)") == ["S = [3,3,2,1]"]
    assert ask(c, "sort(0, @>, [1,3,2,3], S)") == ["S = [3,2,1]"]
    assert ask(c, "sort(0, @=<, [b,a,b], S)") == ["S = \"abb\""]
    assert ask(c, "sort(0, @<, [b,a,b], S)") == ["S = \"ab\""]
    assert ask(c, "sort(1, @<, [f(2,a),f(1,b),f(2,c)], S)") == ["S = [f(1,b),f(2,a)]"]
    assert ask(c, "sort(1, @=<, [f(2,a),f(1,b),f(2,c)], S)") == ["S = [f(1,b),f(2,a),f(2,c)]"]
    assert ask(c, "sort(1, @>=, [f(2,a),f(1,b),f(2,c)], S)") == ["S = [f(2,a),f(2,c),f(1,b)]"]
    assert ask(c, "sort(2, @>=, [f(2,a),f(1,b),f(2,c)], S)") == ["S = [f(2,c),f(1,b),f(2,a)]"]
    assert ask(c, "sort(1, @<, [[b|x],[a|y]], S)") == ["S = [[a|y],[b|x]]"]
    assert err(c, "sort(0, foo, [], _)") == ["E = domain_error(order,foo)"]
    assert err(c, "sort(-1, @<, [], _)") == ["E = domain_error(not_less_than_zero,-1)"]
    assert err(c, "sort(a, @<, [], _)") == ["E = type_error(integer,a)"]
    assert err(c, "sort(_, @<, [], _)") == ["E = instantiation_error"]
    assert err(c, "sort(0, _, [], _)") == ["E = instantiation_error"]
    assert err(c, "sort(0, @<, [a|_], _)") == ["E = instantiation_error"]
    assert err(c, "sort(0, @<, foo, _)") == ["E = type_error(list,foo)"]
    assert err(c, "sort(0, @<, [], foo)") == ["E = type_error(list,foo)"]
    assert err(c, "sort(3, @<, [f(1)], _)") == ["E = type_error(compound,f(1))"]
    assert err(c, "sort(1, @<, [_], _)") == ["E = instantiation_error"]
  end

  test "code_type/2 wie SWI", c do
    for {q, a} <- [
          {"code_type(0'a, alpha)", ["true"]},
          {"code_type(0'_, alpha)", ["true"]},
          {"code_type(0'1, alpha)", ["true"]},
          {"code_type(0'_, csymf)", ["true"]},
          {"code_type(0'1, csymf)", []},
          {"code_type(0'-, alnum)", []},
          {"code_type(0'7, digit(W))", ["W = 7"]},
          {"code_type(0'f, xdigit(W))", ["W = 15"]},
          {"code_type(0'F, xdigit(W))", ["W = 15"]},
          {"code_type(0'A, upper(L))", ["L = 97"]},
          {"code_type(0'a, lower(U))", ["U = 65"]},
          {"code_type(0'a, upper(_))", []},
          {"code_type(0'a, to_upper(U))", ["U = 65"]},
          {"code_type(0'1, to_lower(L))", ["L = 49"]},
          {"code_type(0'ß, to_upper(U))", ["U = 223"]},
          {"code_type(0' , white)", ["true"]},
          {"code_type(10, end_of_line)", ["true"]},
          {"code_type(10, space)", ["true"]},
          {"code_type(10, cntrl)", ["true"]},
          {"code_type(0'., period)", ["true"]},
          {"code_type(0'`, quote)", ["true"]},
          {"code_type(0'(, paren)", ["true"]},
          {"code_type(0'!, punct)", ["true"]},
          {"code_type(0'a, punct)", []},
          {"code_type(0' , graph)", []},
          {"code_type(0' , print)", ["true"]},
          {"code_type(200, ascii)", []},
          {"code_type(a, alpha)", ["true"]},
          {"code_type(0'x, code(C))", ["C = 120"]},
          {"findall(X, code_type(X, digit(_)), Ds)", ["Ds = [48,49,50,51,52,53,54,55,56,57]"]},
          {"findall(X, code_type(X, to_lower(0'a)), Xs)", ["Xs = [65,97]"]},
          {"findall(T, code_type(0'a, T), Ts)",
           [
             "Ts = [alnum,alpha,csym,csymf,ascii,lower,graph,print,lower(65),code(97),to_lower(97),to_upper(65),xdigit(10)]"
           ]}
        ] do
      assert ask(c, q) == a, q
    end

    assert err(c, "code_type(0'a, foo)") == ["E = domain_error(char_type,foo)"]
    assert err(c, "code_type(_, _)") == ["E = instantiation_error"]
    assert err(c, "code_type(f(x), alpha)") == ["E = type_error(character_code,f(x))"]
  end

  test "nb_setval/2, nb_getval/2, b_setval/2, b_getval/2, nb_current/2", c do
    # nb_setval kopiert, übersteht Backtracking
    assert ask(c, "(nb_setval(k, f(X)), fail ; nb_getval(k, V))") == ["V = f(_A)"]
    assert ask(c, "nb_setval(k, 1), nb_setval(k, 2), nb_getval(k, V)") == ["V = 2"]
    # b_setval wird zurückgenommen
    assert ask(c, "(b_setval(k, 1), fail ; true), \\+ nb_current(k, _)") == ["true"]
    assert ask(c, "b_setval(k, X), X = 5, b_getval(k, V)") == ["V = 5, X = 5"]
    assert ask(c, "nb_setval(k, 1), b_setval(k, 2), b_getval(k, V)") == ["V = 2"]

    assert ask(c, "nb_setval(a, 1), nb_setval(b, 2), findall(K-V, nb_current(K, V), L)") ==
             ["L = [a-1,b-2]"]

    assert ask(c, "nb_setval(a, 1), nb_current(a, V)") == ["V = 1"]
    assert ask(c, "nb_current(nix, _)") == []
    assert err(c, "nb_getval(nix, _)") == ["E = existence_error(variable,nix)"]
    assert err(c, "b_getval(nix, _)") == ["E = existence_error(variable,nix)"]
    assert err(c, "nb_setval(_, 1)") == ["E = instantiation_error"]
    assert err(c, "nb_setval(f(x), 1)") == ["E = type_error(atom,f(x))"]
    assert err(c, "nb_current(1, _)") == ["E = type_error(atom,1)"]
    # eigene Schlüssel neben bb_put/2
    assert ask(
             c,
             "nb_setval(k, 1), \\+ bb_get(k, _)",
             @src <> ":- use_module(library(iso_ext)).\n"
           ) ==
             ["true"]
  end

  test "term_variables/3, string/1, garbage_collect/0, get_time/1", c do
    assert ask(c, "term_variables(f(X, g(Y, X)), Vs, [z])") == ["Vs = [X,Y,z]"]
    assert ask(c, "term_variables(a, Vs, T)") == ["Vs = T"]
    assert ask(c, "string(\"abc\")") == []
    assert ask(c, "string(abc)") == []
    assert ask(c, "garbage_collect") == ["true"]
    assert ask(c, "get_time(T), float(T), T > 1.7e9") != []
  end

  test "nur nach use_module(library(swi)); eigene Definitionen gehen vor", c do
    for {g, pi} <- [
          {"writeln(x)", "writeln/1"},
          {"with_output_to(atom(_), true)", "with_output_to/2"},
          {"flatten([], _)", "flatten/2"},
          {"sort(0, @<, [], _)", "sort/4"},
          {"nb_setval(k, 1)", "nb_setval/2"},
          {"code_type(0'a, alpha)", "code_type/2"}
        ] do
      assert ask(c, "catch(#{g}, error(E, _), true)", "") ==
               ["E = existence_error(procedure,#{pi})"],
             g
    end

    assert ask(c, "flatten(a, L)", @src <> "flatten(X, eigen(X)).\n") == ["L = eigen(a)"]
  end

  test "Heimaten", _c do
    for pi <- [
          {"writeln", 1},
          {"tab", 2},
          {"with_output_to", 2},
          {"select", 4},
          {"selectchk", 3},
          {"flatten", 2},
          {"predsort", 3},
          {"sort", 4},
          {"code_type", 2},
          {"nb_getval", 2},
          {"b_setval", 2},
          {"term_variables", 3},
          {"get_time", 1}
        ] do
      assert PrologEx.Builtins.home(elem(pi, 0), elem(pi, 1)) == "swi", inspect(pi)
    end
  end
end
