defmodule PrologEx.TermHashTest do
  # library(terms): term_hash/2,4, term_size/2 (wie SWI); current_module/1
  # zeigt nur benutzte Bibliotheken
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.put_db(%{})
    :ok
  end

  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp yes(c, goal), do: assert(ask(c, goal) != [], goal)
  defp no(c, goal), do: assert(ask(c, goal) == [], goal)

  test "nur nach Import sichtbar", c do
    assert [_] = ask(c, "catch(term_hash(a, _), error(existence_error(_, _), _), true)")
    yes(c, "use_module(library(terms)), term_hash(a, H), integer(H)")
  end

  test "term_hash/2", c do
    yes(c, "use_module(library(terms))")
    # gleich für gleiche Terme, egal wie gebaut
    yes(c, "term_hash(f(a, [1,2], \"s\"), H), T =.. [f, a, [1,2], \"s\"], term_hash(T, H)")
    yes(c, "term_hash(f(X), H), var(H), var(X)")
    yes(c, "term_hash(1, H1), term_hash(1.0, H2), H1 \\== H2")
    yes(c, "term_hash(f(a), H1), term_hash(f(b), H2), H1 \\== H2")
    yes(c, "term_hash(foo, H), H >= 0, H < 134217728")
    # stabil über Sitzungen (phash2 der kanonischen Form)
    assert ask(c, "term_hash(foo(bar, 1), H)") == [
             "H = #{:erlang.phash2({"foo", 2, [{:atom, "bar"}, 1]})}"
           ]

    # zyklisch: gleiche rationale Bäume, gleicher Wert
    yes(c, "A = f(A), B = f(f(B)), term_hash(A, H1), term_hash(B, H2), H1 == H2")
    yes(c, "A = f(A, X), term_hash(A, H), var(H)")
  end

  test "term_hash/4", c do
    yes(c, "use_module(library(terms))")
    yes(c, "term_hash(f(a, X), 1, 100, H), integer(H), H < 100")
    yes(c, "term_hash(f(a, X), 2, 100, H), var(H)")
    yes(c, "term_hash(f(a, g(X)), 2, 1000, H), term_hash(f(a, g(Y)), 2, 1000, H)")
    yes(c, "term_hash(f(X), 0, 10, H), integer(H)")
    yes(c, "A = f(A, A), term_hash(A, 30, 1000, H), integer(H)")
    yes(c, "catch(term_hash(a, -1, 10, _), error(domain_error(not_less_than_zero, -1), _), true)")
    yes(c, "catch(term_hash(a, 1, 0, _), error(domain_error(hash_range, 0), _), true)")
    yes(c, "catch(term_hash(a, _, 10, _), error(instantiation_error, _), true)")
  end

  test "same_functor/2,3,4 (wie SICStus)", c do
    assert [_] = ask(c, "catch(same_functor(a, _), error(existence_error(_, _), _), true)")
    yes(c, "use_module(library(terms))")
    assert ask(c, "same_functor(f(a, b), T)") == ["T = f(_A,_B)"]
    assert ask(c, "same_functor(T, g(1))") == ["T = g(_A)"]
    assert ask(c, "same_functor([a], T)") == ["T = [_A|_B]"]
    assert ask(c, "same_functor(1, T)") == ["T = 1"]
    yes(c, "same_functor(f(a), f(b)), same_functor(a, a), same_functor(T, T, g, 1)")
    no(c, "same_functor(f(a), g(b))")
    no(c, "same_functor(f(a), f(a, b))")
    no(c, "same_functor(1, 1.0)")
    assert ask(c, "same_functor(f(a), T, N)") == ["N = 1, T = f(_A)"]
    assert ask(c, "same_functor(f(a), T, F, N)") == ["F = f, N = 1, T = f(_A)"]
    no(c, "same_functor(f(a), _, g, _)")
    no(c, "same_functor(f(a), _, _, 2)")
    no(c, "same_functor(f(a), _, _, a)")
    # beide offen: Name und Stelligkeit bauen beide (wie functor/3)
    assert ask(c, "same_functor(T1, T2, foo, 2)") == ["T1 = foo(_A,_B), T2 = foo(_C,_D)"]
    assert ask(c, "same_functor(T1, T2, 7, 0)") == ["T1 = 7, T2 = 7"]
    assert ask(c, "same_functor(T1, T2, '.', 2)") == ["T1 = [_A|_B], T2 = [_C|_D]"]
    # instantiation_error nur, wenn nichts den Funktor festlegt
    for g <- ["same_functor(_, _)", "same_functor(_, _, 2)", "same_functor(_, _, f, _)"] do
      assert ask(c, "catch(#{g}, error(E, _), true)") == ["E = instantiation_error"], g
    end

    assert ask(c, "catch(same_functor(_, _, foo, a), error(E, _), true)") ==
             ["E = type_error(integer,a)"]

    assert ask(c, "catch(same_functor(_, _, foo, -1), error(E, _), true)") ==
             ["E = domain_error(not_less_than_zero,-1)"]
  end

  test "term_size/2", c do
    yes(c, "use_module(library(terms))")
    yes(c, "term_size(a, 0), term_size(_, 0), term_size(1, 0)")
    yes(c, "term_size(f(a), 2), term_size([a,b], 6), term_size(f(g(a), b), 5)")
    # geteilt über eine Variable: einmal
    yes(c, "X = g(1,2), term_size(f(X, X), 6)")
    yes(c, "A = f(A), term_size(A, 2)")
    no(c, "term_size(f(a), 3)")
  end

  test "current_module/1: Bibliotheken erst, wenn benutzt", c do
    no(c, "current_module(assoc)")
    assert ask(c, "findall(M, current_module(M), L)") == ["L = [user,system]"]
    yes(c, "use_module(library(assoc)), current_module(assoc)")
    # lists gibt maplist/N aus apply weiter: auch apply gilt dann als geladen
    yes(c, "use_module(library(lists)), current_module(lists), current_module(apply)")

    assert ask(c, "findall(M, predicate_property(M:subsumes_term(_,_), built_in), L)") ==
             ["L = [user,system,apply,assoc,lists]"]
  end
end
