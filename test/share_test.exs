defmodule PrologEx.ShareTest do
  # Geteilte Teilterme (DAGs): Operationen, die Terme ablaufen, kopieren,
  # vergleichen oder unifizieren, bearbeiten jeden geteilten Teilterm nur
  # einmal (PrologEx.Share). Jede Anfrage baut eine Kette mit 2^40 Pfaden
  # (T(k+1) = f(T(k), T(k))) und läuft mit Zeitgrenze im eigenen Prozess –
  # ein Rückfall ins Exponentielle lässt nur den Test scheitern.
  use ExUnit.Case, async: true
  alias PrologEx.Reader

  @program """
  chain(0, T, T) :- !.
  chain(N, T0, T) :- N1 is N - 1, chain(N1, f(T0, T0), T).
  % B unten: g(_) (nicht ground) oder g(a) (ground)
  dag(B, T) :- chain(40, B, T).
  % eine Kopie (verschiedene Terme, gleiche Gestalt)
  dag2(B, T, T2) :- dag(B, T), copy_term(T, T2).
  % zweimal getrennt gebaut (gleich, aber nicht identisch)
  dag3(B, T, U) :- dag(B, T), dag(B, U).
  % dasselbe mit Listenzellen: L(k+1) = [L(k)|L(k)]
  lchain(0, L, L) :- !.
  lchain(N, L0, L) :- N1 is N - 1, lchain(N1, [L0|L0], L).
  % Listenzellen mit flachem Kopf im DAG: T(k+1) = f([1|T(k)], [1|T(k)])
  % (zwei Zellen) und T(k+1) = f(L, L) mit L = [g(1, 2)|T(k)] (eine geteilte)
  % wie lchain, der Kopf eine Struktur: M(k+1) = [h(M(k))|M(k)]
  mchain(0, L, L) :- !.
  mchain(N, L0, L) :- N1 is N - 1, mchain(N1, [h(L0)|L0], L).
  fchain(0, T, T) :- !.
  fchain(N, T0, T) :- N1 is N - 1, fchain(N1, f([1|T0], [1|T0]), T).
  gchain(0, T, T) :- !.
  gchain(N, T0, T) :- N1 is N - 1, L = [g(1, 2)|T0], gchain(N1, f(L, L), T).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    db =
      Enum.reduce(["lists", "apply", "swi"], %{}, &PrologEx.use_library(&2, &1, "user"))

    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  # die Anfrage (in \+ \+, ohne Antwort) gelingt innerhalb der Zeitgrenze
  defp quick(c, goal) do
    [{:term, g, _}] = Reader.read_terms(c.reader, "\\+ \\+ (" <> goal <> ").")
    db = c.db
    reader = c.reader

    task =
      Task.async(fn ->
        Reader.put_current(reader)
        db |> PrologEx.query(g) |> Enum.take(1) |> length()
      end)

    Task.yield(task, 10_000) || Task.shutdown(task, :brutal_kill)
  end

  for b <- ["g(_)", "g(a)"] do
    describe "DAG mit #{b} unten" do
      @b b

      test "term_variables, ground, acyclic_term, numbervars", c do
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), term_variables(T, Vs), length(Vs, N), N =< 1")
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), (ground(T) -> true ; true)")
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), acyclic_term(T)")
        assert {:ok, 1} = quick(c, "dag2(#{@b}, _, T2), numbervars(T2, 0, E), E =< 1")
      end

      test "copy_term/2,3, findall, bagof, setof, throw", c do
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), copy_term(T, C), C = f(_, _)")
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), copy_term(T, C, _), C = f(_, _)")
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), findall(T, true, [C]), C = f(_, _)")
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), bagof(T, true, [C]), C = f(_, _)")
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), setof(X, member(X, [T, T]), [_])")
        assert {:ok, 1} = quick(c, "dag(#{@b}, T), catch(throw(b(T)), b(C), true), C = f(_, _)")
      end

      test "==, compare, sort, msort zwischen Original und Kopie", c do
        assert {:ok, 1} = quick(c, "dag2(#{@b}, T, T2), (T == T2 -> true ; true)")
        assert {:ok, 1} = quick(c, "dag2(#{@b}, T, T2), compare(_, T, T2)")
        assert {:ok, 1} = quick(c, "dag2(#{@b}, T, T2), msort([T, T2, T], [_, _, _])")
        assert {:ok, 1} = quick(c, "dag2(#{@b}, T, T2), sort([T2, T], L), length(L, N), N >= 1")
      end

      test "getrennt gebaute gleiche DAGs: ==, compare, sort, =, subsumes_term, dif", c do
        assert {:ok, 1} = quick(c, "B = #{@b}, dag3(B, T, U), T == U")
        assert {:ok, 1} = quick(c, "B = #{@b}, dag3(B, T, U), compare(=, T, U)")
        assert {:ok, 1} = quick(c, "B = #{@b}, dag3(B, T, U), msort([U, T], [_, _])")
        assert {:ok, 1} = quick(c, "B = #{@b}, dag3(B, T, U), sort([U, T], [_])")
        assert {:ok, 1} = quick(c, "B = #{@b}, dag3(B, T, U), T = U")
        assert {:ok, 1} = quick(c, "B = #{@b}, dag3(B, T, U), unify_with_occurs_check(T, U)")
        assert {:ok, 1} = quick(c, "B = #{@b}, dag3(B, T, U), subsumes_term(T, U)")
        assert {:ok, 1} = quick(c, "B = #{@b}, dag3(B, T, U), dif(T, U) -> fail ; true")
        # Listenzellen
        assert {:ok, 1} = quick(c, "B = #{@b}, lchain(40, [B], L), lchain(40, [B], M), L == M")

        assert {:ok, 1} =
                 quick(c, "B = #{@b}, lchain(40, [B], L), findall(L-B, true, [M-B]), L == M")

        assert {:ok, 1} =
                 quick(c, "dag(g(a), T), findall(T, true, [U]), T == U, compare(=, T, U)")

        assert {:ok, 1} = quick(c, "B = #{@b}, mchain(40, [B], L), mchain(40, [B], M), L == M")

        # Listen, deren Folgezellen einen flachen Kopf haben (ohne eigenen
        # Memo-Eintrag; f(L, L) mit L als Variable ist selbst nicht im Memo)
        assert {:ok, 1} = quick(c, "B = #{@b}, fchain(40, B, T), fchain(40, B, U), T == U")
        assert {:ok, 1} = quick(c, "B = #{@b}, gchain(40, B, T), gchain(40, B, U), T == U")

        assert {:ok, 1} =
                 quick(c, "B = #{@b}, gchain(40, B, T), findall(T-B, true, [U-B]), T == U")
      end

      test "when(ground(_)), Fehlerterm mit DAG", c do
        assert {:ok, 1} = quick(c, "dag(g(X), T), X = #{@b}, when(ground(f(T, Z)), true), Z = 1")

        assert {:ok, 1} =
                 quick(
                   c,
                   "dag(g(X), T), X = #{@b}, catch(plus(T, 1, _), error(type_error(_, _), _), true)"
                 )
      end

      test "=, unify_with_occurs_check, subsumes_term, dif", c do
        assert {:ok, 1} = quick(c, "dag2(#{@b}, T, T2), T = T2")
        assert {:ok, 1} = quick(c, "dag2(#{@b}, T, T2), unify_with_occurs_check(T, T2)")
        assert {:ok, 1} = quick(c, "dag2(#{@b}, T, T2), (subsumes_term(T, T2) -> true ; true)")
        assert {:ok, 1} = quick(c, "dag2(#{@b}, T, T2), (dif(T, T2) -> true ; true)")
      end
    end
  end

  # Ergebnisse wie ohne Memo: auch große Terme mit vielen Strukturen
  # (über der Schwelle, ab der das Memo wirkt)
  defp answers(c, goal) do
    [{:term, g, _}] = Reader.read_terms(c.reader, goal <> ".")
    names = PrologEx.query_var_names(g)
    c.db |> PrologEx.query(g) |> Enum.take(3) |> Enum.map(&PrologEx.format_answer(&1, names))
  end

  test "Ergebnisse auf geteilten Termen wie auf ausgerollten", c do
    # f(f(g(X),g(X)), f(g(X),g(X))) geteilt und als Baum
    tree = "f(f(f(g(X),g(Y)),f(g(X),g(Y))),f(f(g(X),g(Y)),f(g(X),g(Y))))"

    assert answers(c, "chain(3, g(X), T), term_variables(T, Vs)") ==
             answers(
               c,
               "T = f(f(f(g(X),g(X)),f(g(X),g(X))),f(f(g(X),g(X)),f(g(X),g(X)))), term_variables(T, Vs)"
             )

    assert answers(c, "T = #{tree}, term_variables(T, Vs)") == ["T = #{tree}, Vs = [X,Y]"]

    # Kopie behält die Gleichheit der Variablen
    assert [a] = answers(c, "chain(6, g(X, Y), T), copy_term(T, C), C = f(A, B), A == B")
    assert a =~ "A = f("

    # zwei gleich gestaltete, aber verschiedene DAGs
    assert answers(c, "chain(8, g(1), T), chain(8, g(1), U), (T == U -> R = gleich ; R = nein)")
           |> hd() =~ "R = gleich"

    assert answers(c, "chain(8, g(1), T), chain(8, g(2), U), compare(O, T, U)") |> hd() =~
             "O = (<)"

    assert answers(c, "chain(8, g(X), T), chain(8, g(Y), U), T = U, X == Y") |> hd() =~ "X = Y"

    assert answers(c, "chain(8, g(1), T), chain(8, g(2), U), (T = U -> R = ja ; R = nein)")
           |> hd() =~ "R = nein"

    # Paar-Memo: derselbe linke Teilterm gegen verschiedene rechte
    for {op, r} <- [{"=", "nein"}, {"==", "nein"}, {"subsumes_term", "nein"}] do
      assert answers(
               c,
               "chain(8, g(1), T), chain(8, g(1), U1), chain(8, g(2), U2), (#{op}(h(T, T), h(U1, U2)) -> R = ja ; R = #{r})"
             )
             |> hd() =~ "R = #{r}"
    end

    assert answers(
             c,
             "chain(8, g(1), T), chain(8, g(1), U1), chain(8, g(2), U2), compare(O, h(T, T), h(U1, U2))"
           )
           |> hd() =~ "O = (<)"

    assert answers(
             c,
             "chain(8, g(1), T), chain(8, g(1), U1), chain(8, g(2), U2), (dif(h(T, T), h(U1, U2)) -> R = ja ; R = nein)"
           )
           |> hd() =~ "R = ja"

    # Occurs-Check findet die Variable auch tief im DAG
    assert answers(
             c,
             "chain(30, g(X), _T), (unify_with_occurs_check(X, _T) -> R = ja ; R = nein)"
           )
           |> hd() =~ "R = nein"

    # sort/msort: dieselbe Ordnung und dieselben Duplikate wie per compare/3
    assert answers(
             c,
             "chain(6, g(2), A), chain(6, g(1), B), chain(6, g(2), C), msort([A, B, C], L), L = [X, Y, Z], X == B, Y == A, Z == C"
           )
           |> length() == 1

    assert answers(
             c,
             "chain(6, g(2), A), chain(6, g(1), B), chain(6, g(2), C), sort([A, B, C], L), length(L, N)"
           )
           |> hd() =~ "N = 2"

    # subsumes_term: auch bei geteilten Teiltermen nur echte Instanzen
    assert answers(
             c,
             "chain(6, g(X), T), chain(6, g(a), U), (subsumes_term(T, U) -> R = ja ; R = nein)"
           )
           |> hd() =~ "R = ja"

    assert answers(
             c,
             "chain(6, g(a), T), chain(6, g(X), U), (subsumes_term(T, U) -> R = ja ; R = nein)"
           )
           |> hd() =~ "R = nein"
  end
end
