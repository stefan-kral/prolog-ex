defmodule PrologEx.MemoTest do
  # library(memo): :- memo PI [as Optionen]
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.delete(:prolog_ex_memo)
    :ok
  end

  @src ~S"""
  :- use_module(library(memo)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(iso_ext)).
  :- use_module(library(swi)).

  :- memo fib/2.
  fib(0, 0).
  fib(1, 1).
  fib(N, F) :- N > 1, N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.

  % nichtdeterministisch, mit Duplikaten; Vergleich: dieselben Klauseln ohne Memo
  :- memo col/2.
  col(X, Y) :- member(Y, [X, b, X]).
  col(_, c).
  plain_col(X, Y) :- member(Y, [X, b, X]).
  plain_col(_, c).

  % Antworten mit Variablen
  :- memo pair/2.
  pair(X, f(X, _)).
  pair(_, g(_)).

  :- memo same/2.
  same(X, Y) :- X == Y.
  :- memo same23/3.
  same23(_, Y, Z) :- Y == Z.

  :- memo once_col/2 as first.
  once_col(X, Y) :- col(X, Y).

  :- memo loop/1.
  loop(X) :- loop(X).

  % unrein: terminiert über einen Zähler
  :- memo count_up/1 as reentrant.
  count_up(X) :- nb_getval(c, N), ( N >= 3 -> X = N ; N1 is N+1, nb_setval(c, N1), count_up(X) ).
  :- memo count_up2/1.
  count_up2(X) :- nb_getval(c, N), ( N >= 3 -> X = N ; N1 is N+1, nb_setval(c, N1), count_up2(X) ).

  % Seiteneffekte und Ausnahmen
  :- memo eff/1.
  eff(X) :- nb_getval(e, N), N1 is N+1, nb_setval(e, N1), ( X == boom -> throw(boom) ; true ).

  :- memo sq/2 as lru(3).
  sq(X, Y) :- Y is X*X.
  :- memo sqf/2 as fifo(3).
  sqf(X, Y) :- Y is X*X.

  % Grammatik
  :- memo digits//1.
  digits([D|Ds]) --> [D], { member(D, "0123456789") }, digits(Ds).
  digits([]) --> [].
  :- memo parsed//0 as [first, lru(10)].
  parsed --> digits(_).

  stats(PI, S) :- memo_statistics(PI, S).
  """

  # über eine Datei: die Operatoren (memo, as) gelten erst nach use_module
  defp load(src) do
    f = Path.join(System.tmp_dir!(), "px_memo_#{System.unique_integer([:positive])}.pl")
    File.write!(f, src)
    PrologEx.put_db(%{})

    try do
      err =
        ExUnit.CaptureIO.capture_io(:stderr, fn -> {:ok, _} = PrologEx.Consult.load_file(f) end)

      {PrologEx.current_db(), if(err == "", do: [], else: [err])}
    after
      File.rm(f)
    end
  end

  defp ask(c, q, src \\ @src) do
    {db, msgs} = load(src)
    assert msgs == [], inspect(msgs)
    run(c, db, q)
  end

  defp run(c, db, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(5)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "fib: jede Variante einmal", c do
    {us, res} = :timer.tc(fn -> ask(c, "fib(300, F), stats(fib/2, S)") end)
    [a] = res
    assert a =~ "F = 222232244629420445529739893461909967206666939096499764990979600"
    assert a =~ "S = [entries(301),hits(298),misses(301),evictions(0)]"
    assert us < 5_000_000
  end

  test "Bedeutung wie ohne Memo: Antworten, Reihenfolge, Duplikate", c do
    for x <- ["a", "_", "b"] do
      assert ask(
               c,
               "findall(Y, plain_col(#{x}, Y), L0), findall(Y, col(#{x}, Y), L1), " <>
                 "findall(Y, col(#{x}, Y), L2), L0 =@= L1, L1 =@= L2"
             )
             |> length() == 1,
             x
    end

    assert ask(c, "col(a, Y)") == ["Y = a", "Y = b", "Y = a", "Y = c"]
    # Treffer ohne Wahlpunkt beim letzten (einzigen) Element
    assert ask(c, "fib(10, _), call_cleanup(fib(10, F), Det = true)") == ["Det = true, F = 55"]
  end

  test "Varianten teilen sich einen Eintrag", c do
    assert ask(c, "col(X, _), col(Y, _), col(a, _), col(a, _), stats(col/2, S)") |> hd() =~
             "S = [entries(2),hits(2),misses(2),evictions(0)]"

    # p(X, X) und p(X, Y) sind verschiedene Varianten
    assert ask(c, "\\+ same(_, _), same(Z, Z), stats(same/2, S)") |> hd() =~
             "S = [entries(2),hits(0),misses(2),evictions(0)]"

    assert ask(c, "\\+ same23(A, B, A), same23(A, B, B)") |> length() == 1

    # erst gebunden, dann gerufen: eine andere Variante als col(_, _)
    assert ask(c, "X = a, col(X, _), col(a, _), stats(col/2, S)") |> hd() =~
             "S = [entries(1),hits(1),misses(1),evictions(0)]"
  end

  test "Antworten mit Variablen: bei jedem Abruf frisch", c do
    assert ask(c, "pair(1, A), pair(1, B), A = f(1, x), B = f(1, Y)") ==
             ["A = f(1,x), B = f(1,Y)"]

    assert ask(
             c,
             "findall(A, pair(Z, A), _), pair(Z, A2), A2 = f(W, V), W == Z, var(V), stats(pair/2, S)"
           )
           |> hd() =~ "S = [entries(1),hits(1),misses(1),evictions(0)]"
  end

  test "first: nur die erste Lösung", c do
    assert ask(c, "findall(Y, once_col(a, Y), L)") == [~S|L = "a"|]
    assert ask(c, "once_col(q, Y), once_col(q, Z)") == ["Y = q, Z = q"]
  end

  test "Selbstaufruf derselben Variante: Fehler, mit reentrant wie normales Prolog", c do
    assert ask(c, "catch(loop(_), error(E, _), true)") ==
             ["E = permission_error(reenter,memo,loop/1)"]

    # danach ist nichts als laufend vermerkt
    assert ask(c, "catch(loop(_), error(E, _), true), catch(loop(_), error(E2, _), true)") ==
             [
               "E = permission_error(reenter,memo,loop/1), E2 = permission_error(reenter,memo,loop/1)"
             ]

    assert ask(c, "nb_setval(c, 0), count_up(X), count_up(Y)") == ["X = 3, Y = 3"]

    assert ask(c, "nb_setval(c, 0), catch(count_up2(_), error(E, _), true)") ==
             ["E = permission_error(reenter,memo,count_up2/1)"]
  end

  test "Seiteneffekte einmal; eine Ausnahme hinterlässt nichts", c do
    assert ask(c, "nb_setval(e, 0), eff(a), eff(a), eff(b), nb_getval(e, N)") == ["N = 2"]

    assert ask(
             c,
             "nb_setval(e, 0), catch(eff(boom), boom, true), catch(eff(boom), boom, true), " <>
               "nb_getval(e, N), stats(eff/1, S)"
           ) == ["N = 2, S = [entries(0),hits(0),misses(2),evictions(0)]"]
  end

  test "lru und fifo", c do
    # lru(3): 1, 2, 3, Zugriff auf 1, dann 4 -> 2 fällt
    assert ask(
             c,
             "maplist(sq, [1, 2, 3], _), sq(1, _), sq(4, _), stats(sq/2, S0), " <>
               "sq(1, _), sq(3, _), sq(4, _), stats(sq/2, S1), sq(2, _), stats(sq/2, S2)"
           ) == [
             "S0 = [entries(3),hits(1),misses(4),evictions(1)], " <>
               "S1 = [entries(3),hits(4),misses(4),evictions(1)], " <>
               "S2 = [entries(3),hits(4),misses(5),evictions(2)]"
           ]

    # fifo(3): der Zugriff zählt nicht, 1 fällt
    assert ask(
             c,
             "maplist(sqf, [1, 2, 3], _), sqf(1, _), sqf(4, _), sqf(2, _), stats(sqf/2, S0), " <>
               "sqf(1, _), stats(sqf/2, S1)"
           ) == [
             "S0 = [entries(3),hits(2),misses(4),evictions(1)], " <>
               "S1 = [entries(3),hits(2),misses(5),evictions(2)]"
           ]
  end

  test "Grammatiken (Name//N)", c do
    assert ask(
             c,
             ~S|findall(Ds-R, phrase(digits(Ds), "12", R), L), findall(Ds-R, phrase(digits(Ds), "12", R), L2), L == L2, stats(digits//1, S)|
           ) == [
             ~S|L = ["12"-[],"1"-"2",[]-"12"], L2 = ["12"-[],"1"-"2",[]-"12"], S = [entries(3),hits(1),misses(3),evictions(0)]|
           ]

    assert ask(c, "phrase(parsed, \"1a\", R), phrase(parsed, \"1a\", R2), stats(parsed//0, S)")
           |> hd() =~ "S = [entries(1),hits(1),misses(1),evictions(0)]"
  end

  test "abolish_memo/0,1; neu laden beginnt leer", c do
    assert ask(
             c,
             "fib(5, _), once(col(a, _)), abolish_memo(fib/2), stats(fib/2, S), stats(col/2, T)"
           ) ==
             [
               "S = [entries(0),hits(0),misses(0),evictions(0)], " <>
                 "T = [entries(1),hits(0),misses(1),evictions(0)]"
             ]

    assert ask(c, "once(col(a, _)), abolish_memo, stats(col/2, T)") ==
             ["T = [entries(0),hits(0),misses(0),evictions(0)]"]

    # neu laden mit anderen Klauseln: kein alter Eintrag
    assert ask(c, "col(a, Y)") |> length() == 4
    src2 = String.replace(@src, "col(_, c).\n", "")
    assert ask(c, "findall(Y, col(a, Y), L)", src2) == [~S|L = "aba"|]
  end

  test "Fehler", c do
    bad = fn d ->
      {_db, msgs} = load(@src <> d)
      Enum.join(msgs, "\n")
    end

    assert bad.(":- memo q/1 as lru(0).\n") =~ "domain_error(positive_integer,0)"
    assert bad.(":- memo q/1 as foo.\n") =~ "domain_error(memo_option,foo)"
    assert bad.(":- memo q/1 as [lru(3), fifo(3)].\n") =~ "domain_error(memo_option,fifo(3))"
    assert bad.(":- memo q.\n") =~ "type_error(predicate_indicator,q)"
    assert bad.(":- memo _.\n") =~ "instantiation_error"

    assert ask(c, "catch(memo(foo/1), error(E, _), true)") ==
             ["E = context_error(nodirective,(memo foo/1))"]

    assert ask(c, "freeze(X, true), catch(col(X, _), error(E, _), true)") |> hd() =~
             "E = representation_error(memo_attributed_variable)"
  end

  test "der Hook lebt nur, solange eine Datei mit memo/1 geladen wird", c do
    ask(c, "true")
    db = PrologEx.current_db()
    refute Map.has_key?(db, {"table_wrapper", "term_expansion", 2})
    # danach geladene Klauseln eines gleichnamigen Prädikats bleiben unberührt
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(c.reader, "other(1).\nfib(x, y).\n"))
    assert run(c, db, "other(X)") == ["X = 1"]
  end

  test "zweimal geladen, während eine andere Datei mit Direktiven noch lädt", c do
    dir = Path.join(System.tmp_dir!(), "px_memo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      File.write!(
        Path.join(dir, "sub.pl"),
        ":- use_module(library(memo)).\n:- memo p/1.\np(1).\n"
      )

      File.write!(Path.join(dir, "main.pl"), """
      :- use_module(library(memo)).
      :- memo q/1.
      q(1).
      :- consult(sub).
      :- consult(sub).
      """)

      PrologEx.put_db(%{})

      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        {:ok, _} = PrologEx.Consult.load_file(Path.join(dir, "main.pl"))
      end)

      assert run(c, PrologEx.current_db(), "p(X), q(Y)") == ["X = 1, Y = 1"]
    after
      File.rm_rf!(dir)
    end
  end
end
