defmodule PrologEx.TablingTest do
  # library(tabling): :- table PI (wie Scryer); Fixpunkt je Komponente
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    Process.delete(:prolog_ex_tabling)
    :ok
  end

  @src ~S"""
  :- use_module(library(tabling)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(iso_ext)).
  :- use_module(library(swi)).

  e(n1, n2). e(n2, n3). e(n3, n1). e(n3, n4).

  :- table path/2.
  path(X, Y) :- path(X, Z), e(Z, Y).
  path(X, Y) :- e(X, Y).

  :- table rpath/2.
  rpath(X, Y) :- e(X, Y).
  rpath(X, Y) :- e(X, Z), rpath(Z, Y).

  :- table tc/2.
  tc(X, Y) :- tc(X, Z), tc(Z, Y).
  tc(X, Y) :- e(X, Y).

  :- table fib/2.
  fib(0, 0).
  fib(1, 1).
  fib(N, F) :- N > 1, N1 is N-1, N2 is N-2, fib(N1, F1), fib(N2, F2), F is F1+F2.

  % verschränkt
  :- table ev/1, od/1.
  ev(0).
  ev(N) :- od(M), M < 10, N is M+1.
  od(N) :- ev(M), M < 10, N is M+1.

  % q findet erst in einer späteren Runde den Weg zurück zu p (Führung abgeben)
  :- table p/1, q/1.
  p(X) :- q(X).
  p(a).
  q(X) :- q0(X).
  q(X) :- q(Y), Y == go, p(X).
  q0(go).

  % geschachtelte Komponenten
  :- table a1/1, b1/1, c1/1.
  a1(X) :- b1(X).
  a1(1).
  b1(X) :- c1(X).
  b1(X) :- a1(Y), X is Y + 10, X < 40.
  c1(X) :- c1(Y), X is Y * 2, X < 100.
  c1(3).

  % Ring x -> y -> z -> x: z hängt von x ab, also auch y (über z)
  :- table x/1, y/1, z/1.
  x(X) :- y(X).
  x(1).
  y(X) :- z(X).
  z(X) :- x(Y), Y < 5, X is Y+1.

  % m wird in späteren Runden nicht mehr gerufen, muss aber nachziehen
  :- table k/1, m/1.
  k(X) :- findall(Y, k(Y), L), length(L, N), N < 2, m(X).
  k(0).
  m(X) :- k(Y), X is Y + 10, X < 40.

  % Mengen: Duplikate und Varianten
  :- table d/1.
  d(a). d(b). d(a).
  :- table v/1.
  v(_). v(_). v(f(_)). v(f(_)).

  % links-rekursive Grammatik
  :- table expr//0.
  expr --> expr, "+", term.
  expr --> term.
  term --> "1".

  % Zähler: wie oft wird ausgewertet
  :- table cnt/1.
  cnt(X) :- nb_getval(n, N), N1 is N+1, nb_setval(n, N1), member(X, [1, 2]).
  :- table boom/1.
  boom(X) :- nb_getval(n, N), N1 is N+1, nb_setval(n, N1), ( N1 =:= 1 -> throw(boom) ; X = ok ).
  :- table rboom/1.
  rboom(X) :- rboom(Y), Y < 3, X is Y + 1.
  rboom(0).
  rboom(_) :- nb_getval(n, 1), throw(rb).

  set(T, G, S) :- findall(T, G, L), msort(L, S).
  """

  defp load(src) do
    f = Path.join(System.tmp_dir!(), "px_tbl_#{System.unique_integer([:positive])}.pl")
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

  test "Links-, Rechts- und doppelte Rekursion über Zyklen", c do
    assert ask(c, "set(Y, path(n1, Y), S)") == ["S = [n1,n2,n3,n4]"]
    assert ask(c, "set(X-Y, path(X, Y), S), length(S, N)") |> hd() =~ "N = 12"
    assert ask(c, "set(Y, rpath(n1, Y), S)") == ["S = [n1,n2,n3,n4]"]
    assert ask(c, "set(X, rpath(X, n4), S)") == ["S = [n1,n2,n3]"]
    assert ask(c, "set(X-Y, tc(X, Y), S), set(X-Y, path(X, Y), S)") |> length() == 1
  end

  test "fib, verschränkte und geschachtelte Komponenten", c do
    assert ask(c, "fib(200, F)") == ["F = 280571172992510140037611932413038677189525"]
    assert ask(c, "set(X, ev(X), S), set(X, od(X), T)") == ["S = [0,2,4,6,8,10], T = [1,3,5,7,9]"]
    assert ask(c, "set(X, p(X), S), set(X, q(X), T)") == ["S = [a,go], T = [a,go]"]

    assert ask(c, "set(X, a1(X), S), set(X, c1(X), T)") == [
             "S = [1,3,6,11,12,13,16,21,22,23,24,26,31,32,33,34,36,48,96], T = [3,6,12,24,48,96]"
           ]

    assert ask(c, "set(X, x(X), S), set(X, y(X), T)") == ["S = [1,2,3,4,5], T = [2,3,4,5]"]
    assert ask(c, "set(X, k(X), S), set(X, m(X), T)") == ["S = [0,10], T = [10,20]"]

    # dieselben Mengen, wenn zuerst die innere Komponente gerufen wird
    assert ask(c, "set(X, c1(X), T), set(X, b1(X), U), set(X, a1(X), S), length(S, 19)")
           |> length() == 1
  end

  test "Antworten als Menge (Varianten), deterministisch beim letzten", c do
    assert ask(c, "findall(X, d(X), L)") == [~S|L = "ab"|]
    assert ask(c, "findall(X, v(X), L), length(L, N)") |> hd() =~ "N = 2"
    assert ask(c, "fib(10, _), call_cleanup(fib(10, F), Det = true)") == ["Det = true, F = 55"]
  end

  test "links-rekursive Grammatik", c do
    assert ask(c, ~S|phrase(expr, "1+1+1")|) == ["true"]
    assert ask(c, ~S|phrase(expr, "1+")|) == []
    assert ask(c, ~S|findall(R, phrase(expr, "1+1", R), L)|) |> hd() =~ ~S|L = ["+1",[]]|
  end

  test "einmal ausgewertet; abolish_all_tables, neu laden", c do
    assert ask(
             c,
             "nb_setval(n, 0), findall(X, cnt(X), L), findall(X, cnt(X), L2), nb_getval(n, N)"
           ) ==
             ["L = [1,2], L2 = [1,2], N = 1"]

    assert ask(
             c,
             "nb_setval(n, 0), once(cnt(_)), abolish_all_tables, once(cnt(_)), nb_getval(n, N)"
           ) == [
             "N = 2"
           ]

    # neu laden mit anderen Fakten: keine alten Antworten
    src2 = String.replace(@src, "e(n3, n1). e(n3, n4).", "e(n3, n1).")
    assert ask(c, "set(Y, path(n1, Y), S)", src2) == ["S = [n1,n2,n3]"]
  end

  test "Ausnahmen verwerfen die unvollständigen Tabellen", c do
    assert ask(c, "nb_setval(n, 0), catch(boom(_), boom, true), boom(X), nb_getval(n, N)") ==
             ["N = 2, X = ok"]

    assert ask(
             c,
             "nb_setval(n, 1), catch(rboom(_), rb, true), nb_setval(n, 0), set(X, rboom(X), S)"
           ) ==
             ["S = [0,1,2,3]"]
  end

  test "Abbruch durch den Aufrufer: die Tabelle ist trotzdem vollständig", c do
    assert ask(c, "once(path(n1, _)), set(Y, path(n1, Y), S)") == ["S = [n1,n2,n3,n4]"]
  end

  test "start_tabling/2 wie Scryer", c do
    src =
      @src <>
        "my(X) :- start_tabling(my(X), my_worker(X)).\nmy_worker(X) :- my(Y), Y < 3, X is Y+1.\nmy_worker(0).\n"

    assert ask(c, "set(X, my(X), S)", src) == ["S = [0,1,2,3]"]
  end

  test "Fehler", c do
    {_db, msgs} = load(@src <> ":- table q.\n:- table _.\n")
    assert Enum.join(msgs) =~ "type_error(predicate_indicator,q)"
    assert Enum.join(msgs) =~ "instantiation_error"

    assert ask(c, "catch(table(foo/1), error(E, _), true)") ==
             ["E = context_error(nodirective,(table foo/1))"]

    assert ask(c, "freeze(X, true), catch(path(X, _), error(E, _), true)") |> hd() =~
             "E = representation_error(memo_attributed_variable)"
  end

  test "memo und table in einer Datei; der Hook endet mit der Datei", c do
    src = @src <> ":- use_module(library(memo)).\n:- memo mm/1.\nmm(X) :- path(n1, X).\n"
    assert ask(c, "set(X, mm(X), S)", src) == ["S = [n1,n2,n3,n4]"]
    refute Map.has_key?(PrologEx.current_db(), {"table_wrapper", "term_expansion", 2})
  end
end
