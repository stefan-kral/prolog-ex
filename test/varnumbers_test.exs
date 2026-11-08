defmodule PrologEx.VarnumbersTest do
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    f = Path.join(System.tmp_dir!(), "px_vn_#{System.unique_integer([:positive])}.pl")
    File.write!(f, ":- use_module(library(varnumbers)).\n:- use_module(library(lists)).\n")
    PrologEx.put_db(%{})
    {:ok, _} = PrologEx.Consult.load_file(f)
    File.rm(f)
    :ok
  end

  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp yes(c, goal), do: assert(ask(c, goal) != [], goal)
  defp no(c, goal), do: assert(ask(c, goal) == [], goal)

  test "numbervars/1 und max_var_number/3", c do
    yes(c, "T = f(X, Y, X), numbervars(T), T == f('$VAR'(0), '$VAR'(1), '$VAR'(0))")
    yes(c, "max_var_number(f('$VAR'(3), '$VAR'(7), '$VAR'(a), g('$VAR'(5))), 0, 7)")
    yes(c, "max_var_number(f(_, '$VAR'(2)), 5, 5)")
    yes(c, "max_var_number(foo, -1, -1)")
    yes(c, "max_var_number('$VAR'(-3), -10, -3)")
  end

  test "varnumbers/2,3: Umkehrung, Variablen von T bleiben", c do
    yes(c, "T = f(X, Y, X, g(Z)), copy_term(T, T1), numbervars(T1, 0, _),
            varnumbers(T1, C), C = f(A, B, A2, g(D)), A == A2,
            term_variables(C, Vs), length(Vs, 3), A \\== B, B \\== D,
            \\+ (member(V, Vs), member(W, [X, Y, Z]), V == W)")
    yes(c, "varnumbers(f('$VAR'(0), '$VAR'(3), '$VAR'(3), W, '$VAR'(a)), 2, C),
            C = f(Z, A, B, W2, Q), Z == '$VAR'(0), A == B, var(A), W2 == W, Q == '$VAR'(a)")
    yes(c, "varnumbers(foo(bar), C), C == foo(bar)")
    yes(c, "varnumbers(f(X), C), C == f(X)")
    yes(c, "numbervars(T, 0, _), varnumbers(T, C), var(C)")
    yes(c, "T = p(X, Y), copy_term(T, T1), numbervars(T1, 10, _), varnumbers(T1, 10, C),
            C = p(A, B), var(A), var(B), A \\== B")
  end

  test "varnumbers_names/3", c do
    yes(c, "varnumbers_names(h('$VAR'('Foo'), '$VAR'(1), '$VAR'('Foo'), '$VAR'('Bar'), Q), C, B),
            C = h(F, O, F2, Ba, Q2), F == F2, Q2 == Q,
            B == [1 = O, 'Bar' = Ba, 'Foo' = F]")
    yes(c, "varnumbers_names(f(a), C, B), C == f(a), B == []")
  end

  test "Fehler", c do
    yes(c, "catch(varnumbers(f, x, _), error(type_error(integer, x), _), true)")
    yes(c, "catch(max_var_number(f, _, _), error(instantiation_error, _), true)")
    yes(c, "A = f(A), catch(varnumbers(A, _), error(domain_error(acyclic_term, _), _), true)")

    yes(
      c,
      "A = f(A), catch(varnumbers_names(A, _, _), error(domain_error(acyclic_term, _), _), true)"
    )

    no(c, "varnumbers(f('$VAR'(0)), f(a, b))")
  end
end
