defmodule PrologEx.CyclicTest do
  # zyklische Terme (rationale Bäume, ohne Occurs-Check): nichts hängt;
  # Unifikation, Vergleich, Kopie, findall, throw verstehen Zyklen
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    f = Path.join(System.tmp_dir!(), "px_cyc_#{System.unique_integer([:positive])}.pl")

    File.write!(f, """
    :- use_module(library(lists)).
    :- use_module(library(swi)).
    :- use_module(library(iso_ext)).
    same(X, X).
    cnt(0, _) :- !.
    cnt(N, A) :- N1 is N-1, cnt(N1, A).
    """)

    PrologEx.put_db(%{})
    {:ok, _} = PrologEx.Consult.load_file(f)
    File.rm(f)
    :ok
  end

  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text <> ".")

    # (in einem eigenen Prozess mit Zeitgrenze: der Zustand des
    # Interpreters liegt im Prozess)
    state = PrologEx.Toplevel.state_snapshot()

    task =
      Task.async(fn ->
        Enum.each(state, fn {k, v} -> Process.put(k, v) end)
        Reader.put_current(c.reader)

        PrologEx.current_db()
        |> PrologEx.query(g)
        |> Enum.take(2)
        |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
      end)

    case Task.yield(task, 20_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, r} -> r
      _ -> flunk("hängt: " <> text)
    end
  end

  defp yes(c, goal), do: assert(ask(c, goal) != [], goal)
  defp no(c, goal), do: assert(ask(c, goal) == [], goal)

  defp out(c, goal) do
    [ans] = ask(c, "with_output_to(atom(Out), (#{goal}))")
    ans |> String.split("Out = ") |> List.last()
  end

  test "Unifikation", c do
    yes(c, "A = f(A), B = f(B), A = B")
    yes(c, "A = f(A), B = f(f(B)), A = B")
    no(c, "A = f(A, 1), B = f(B, 2), A = B")
    yes(c, "L = [a,b|L], M = [a,b,a,b|M], L = M")
    no(c, "L = [a,b|L], M = [a,b,a|M], L = M")
    yes(c, "A = f(X, A), B = f(1, B), A = B, X == 1")
    yes(c, "A = g(A, Y), B = g(B, Z), A = B, Y == Z")
    yes(c, "A = f(A, B), B = g(A), C = f(C, D), D = g(C), A = C, A == C")
    # Kopf mit zweimal derselben Variablen
    yes(c, "A = f(A), B = f(f(B)), same(A, B)")
    no(c, "unify_with_occurs_check(A, f(A))")
  end

  test "Vergleich und Sortieren", c do
    yes(c, "A = f(A), B = f(B), A == B")
    yes(c, "A = f(A), B = f(f(B)), A == B")
    yes(c, "A = f(A, 1), B = f(B, 2), A \\== B, compare(O, A, B), O == (<)")
    yes(c, "L = [a,b|L], M = [a,b,a,b|M], L == M")
    yes(c, "L = [a,b|L], M = [a,b,a|M], compare(O, L, M), O \\== (=)")
    yes(c, "A = f(A), compare(O, A, f(x)), O == (>)")
    yes(c, "A = f(A), B = f(f(B)), sort([A, B, A], S), length(S, 1)")
    yes(c, "A = f(A), msort([A, b], [b, A])")
    # groß (über dem Schlüsselbudget): über compare/3
    yes(c, "A = f(A), msort([g(h(A)), g(h(b))], [g(h(b)), g(h(A))])")
    yes(c, "A = f(A), keysort([A-1, b-2], [b-2, A-1])")
  end

  test "Kopieren, findall, bagof, throw", c do
    yes(c, "A = f(A, X), copy_term(A, B), B = f(B1, Y), B1 == B, var(Y), Y \\== X")
    yes(c, "L = [a,b|L], copy_term(L, M), M == L")
    yes(c, "A = f(A, X), copy_term(A-X, B-Y), B = f(_, Y2), Y2 == Y")
    yes(c, "A = f(A), findall(A, true, [B]), B == A")
    yes(c, "L = [a|L], findall(X-L, member(X, [1,2]), [1-M, 2-N]), M == L, N == L")
    yes(c, "A = f(A), bagof(K, member(K, [A]), [B]), B == A")
    yes(c, "A = f(A), findnsols(1, A, (true;true), [B]), B == A, !")
    yes(c, "A = f(A), catch(throw(x(A)), x(B), true), B == A")
    yes(c, "A = f(A), catch(findall(_, throw(y(A)), _), y(B), true), B == A")
    yes(c, "L = [a|L], catch(length(L, _), error(type_error(list, M), _), true), M == L")
  end

  test "Variablen, ground, dif, numbervars", c do
    yes(c, "A = f(A, X, g(Y, A)), term_variables(A, Vs), Vs == [X, Y]")
    yes(c, "L = [X|L], term_variables(L, [V]), V == X")
    yes(c, "A = f(A), ground(A)")
    no(c, "A = f(A, _), ground(A)")
    yes(c, "A = f(A, X), numbervars(A, 0, E), E == 1, X == '$VAR'(0)")
    no(c, "A = f(A), B = f(f(B)), dif(A, B)")
    yes(c, "A = f(A, 1), B = f(B, 2), dif(A, B)")
    yes(c, "A = f(A, X), B = f(B, Y), dif(A, B), \\+ X = Y")
    yes(c, "A = f(A, X), B = f(B, Y), dif(A, B), X = 1, Y = 2")
    yes(c, "A = f(A), subsumes_term(f(_), A)")
    yes(c, "A = f(A), cyclic_term(A), \\+ acyclic_term(A), \\+ cyclic_term(f(_))")
  end

  test "Ausgabe wie SWI: @(Vorlage, Gleichungen)", c do
    assert out(c, "A = f(A), write(A)") == "'@(_S1,[_S1=f(_S1)])'"
    assert out(c, "L = [a,b|L], print(L)") == "'@(_S1,[_S1=[a,b|_S1]])'"

    assert out(c, "B = f(C), C = g(B), writeq(h(B, C, 'X'))") ==
             "'@(h(_S1,g(_S1),\\'X\\'),[_S1=f(g(_S1))])'"

    assert out(c, "A = f(A), format(\"~w\", [A])") == "'@(_S1,[_S1=f(_S1)])'"
  end

  test "Fehler statt Endlosschleife", c do
    yes(c, "A = f(A), catch(assertz(p(A)), error(representation_error(cyclic_term), _), true)")
    yes(c, "A = A + 1, catch(_ is A, error(type_error(acyclic_term, _), _), true)")
    yes(c, "A = A + 1, catch(cached_is(_, A), error(type_error(acyclic_term, _), _), true)")

    yes(
      c,
      "use_module(library(concurrent)), A = f(A),
            catch(concurrent_maplist(=(_), [A]), error(representation_error(cyclic_term), _), true)"
    )

    yes(c, "use_module(library(concurrent)), use_module(library(lambda)),
            catch(concurrent_maplist(\\X^(X = f(X)), [_]),
                  error(representation_error(cyclic_term), _), true)")
  end

  test "Kompaktierung mit lebendem Zyklus", c do
    yes(c, "L = [a,b|L], A = f(g(A), X, L), freeze(X, true), cnt(300000, A),
            A = f(g(B), Y, M), B == A, M == L, M = [a,b,a,b,a|_], Y == X")

    yes(c, "L = [1|T], T = [2|T], cnt(300000, L), L = [1,2,2,2|_]")
  end

  test "Toplevel zeigt Zyklen", c do
    assert ask(c, "X = f(Y), Y = g(X)") == ["X = f(g(X)), Y = g(X)"]
  end
end
