defmodule PrologEx.ExtrasTest do
  # Gefunden mit Treallas Tests (conformance/trealla): Edinburgh-E/A und
  # name/2, library(solution_sequences), Terme wie SWI, Schreib- und
  # Leseoptionen, zyklische Terme, tief verschachteltes catch/3
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    db = TableCase.db(r, ~w(lists swi terms solution_sequences charsio))
    {:ok, reader: r, db: db}
  end

  defp run(c, q) do
    assert {_, {:answers, [a]}} = TableCase.run(c.reader, c.db, q)
    a
  end

  defp out(c, q) do
    assert {out, {:answers, [_]}} = TableCase.run(c.reader, c.db, q)
    out
  end

  @tag :tmp_dir
  test "see/tell, seeing/telling, append/1, name/2", c do
    f = Path.join(c.tmp_dir, "e.txt")

    a =
      run(c, """
      tell('#{f}'), write(eins), write('.'), nl, telling(T), told,
      append('#{f}'), write(zwei), write('.'), nl, told,
      see('#{f}'), read(X), read(Y), seeing(F), seen, seeing(U),
      name(N, "12"), name(A, "ab"), name(12, Cs)
      """)

    assert a =~ "T = '#{f}'"
    assert a =~ "X = eins, Y = zwei"
    assert a =~ "F = '#{f}'"
    assert a =~ "U = user"
    assert a =~ "N = 12"
    assert a =~ "A = ab"
    assert a =~ "Cs = [49,50]"
  end

  test "see/1: fehlende Datei", c do
    assert {_, {:error, "existence_error(source_sink,'/nicht/da')"}} =
             TableCase.run(c.reader, c.db, "see('/nicht/da')")
  end

  test "limit/2, offset/2, distinct/1,2, order_by/2", c do
    assert run(c, "findall(X, limit(2, member(X, [a,b,c])), L)") =~ "L = [a,b]"
    assert run(c, "findall(X, offset(1, member(X, [a,b,c])), L)") =~ "L = [b,c]"
    assert run(c, "findall(X, distinct(member(X, [a,b,a,c,b])), L)") =~ "L = [a,b,c]"

    assert run(c, "findall(X-Y, distinct(X, member(X-Y, [a-1,b-2,a-3])), L)") =~
             "L = [a-1,b-2]"

    assert run(c, "findall(X-Y, order_by([desc(X)], member(X-Y, [a-1,b-2,a-3])), L)") =~
             "L = [b-2,a-1,a-3]"

    assert run(c, "findall(X-Y, order_by([asc(Y), desc(X)], member(X-Y, [a-1,b-1,c-0])), L)") =~
             "L = [c-0,b-1,a-1]"

    # der Zähler verschwindet mit dem Ziel, auch nach einem Cut
    assert run(c, "once(distinct(member(_, [a,b]))), findall(X, distinct(member(X, [a,a])), L)") =~
             "L = [a]"
  end

  test "unifiable/3, term_singletons/2, variant/2, atom_to_term/3", c do
    assert run(c, "unifiable(f(X,Y,Z), f(p,q,r), U)") =~ "U = [Z=r,Y=q,X=p]"
    assert TableCase.run(c.reader, c.db, "unifiable(f(a), f(b), _)") |> elem(1) == {:answers, []}
    assert run(c, "term_singletons(f(X,Y,X,Z), L)") =~ "L = [Y,Z]"
    assert run(c, "X = f(X), Y = f(Y), (variant(X, Y) -> R = ja ; R = nein)") =~ "R = ja"
    assert run(c, "(variant(f(A,B,A), f(C,D,D)) -> R = ja ; R = nein)") =~ "R = nein"

    assert run(c, "atom_to_term('foo(X, Y, X)', T, B)") =~
             "B = ['X'=_A,'Y'=_B], T = foo(_A,_B,_A)"
  end

  test "read_term_from_atom/3 ohne Schlusspunkt, auch nach 0'. und Kommentar", c do
    assert run(c, "term_to_atom(T, '0\\'.'), term_to_atom(U, 'x % c'), term_to_atom(V, '- .')") =~
             "T = 46, U = x, V = (-)"

    assert run(c, "read_term_from_atom('\\n', T, [])") =~ "T = end_of_file"
  end

  test "write_term/2: fullstop(true), nl(true)", c do
    assert out(
             c,
             "write_term(a = #, [fullstop(true)]), write_term(f(x), [fullstop(true), nl(true)])"
           ) ==
             "a= # .f(x).\n"
  end

  test "format/3 aus library(format) nimmt Senken", c do
    a =
      run(c, """
      use_module(library(format)), atom_chars('~a-~w', F1), atom_chars('~w', F2),
      format(atom(A), F1, [x, 1]),
      format(chars(Cs, [z]), F2, [ab]), format(codes(Co), F2, [1])
      """)

    assert a =~ "A = 'x-1'"
    assert a =~ "Co = [49]"
  end

  test "zyklische Terme: Occurs-Check, bagof/3 mit zyklischem Zeugen", c do
    assert run(c, "V = V-_, (unify_with_occurs_check(V, W) -> R = ja ; R = nein), W == V") =~
             "R = ja"

    assert run(
             c,
             "findall(W-L, bagof(N, (member(W-N, [K-1, J-2, K-3]), K = f(K), J = g(J)), L), Ps), length(Ps, Len)"
           ) =~ "Len = 2"
  end

  test "dif/2 mit einem zyklischen Wert", c do
    assert run(c, "dif([], A), L = A*L, (L = L*A -> R = ja ; R = nein)") =~ "R = ja"
  end

  test "100 000 verschachtelte catch/3 in linearer Zeit", c do
    {t, a} =
      :timer.tc(fn ->
        run(
          c,
          "assertz((d(0) :- !)), assertz((d(N) :- M is N - 1, catch(d(M), _, true))), d(100000)"
        )
      end)

    assert a == "true"
    assert t < 20_000_000
  end

  test "Schieben um sehr viele Stellen, statistics(cputime, T)", c do
    assert run(c, "X is 0 << (2^70), Y is -5 >> (2^70), Z is 5 >> (2^70)") =~
             "X = 0, Y = -1, Z = 0"

    assert run(c, "statistics(cputime, T), float(T)") =~ "T = "
  end
end
