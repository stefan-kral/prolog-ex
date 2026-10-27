defmodule PrologEx.BagofTest do
  # bagof/3, setof/3 (Beispiele aus ISO 8.10.2.4, 8.10.3.4; Gruppen nach
  # Zeugen sortiert wie SICStus/SWI), ^/2, =@=/2
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @program """
  age(peter, 7). age(ann, 11). age(pat, 8). age(tom, 5). age(mike, 11).
  pf(f(_, b), 1). pf(f(_, a), 2). pf(f(_, b), 3).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = Enum.reduce(["lists"], %{}, &PrologEx.use_library(&2, &1, "user"))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  # Antworten; " ;" wenn danach noch ein Choice Point bleibt
  defp ask(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)

    c.db
    |> PrologEx.solutions(g)
    |> Enum.take(6)
    |> Enum.map(fn {ans, more} ->
      a =
        Regex.replace(~r/_[BG]\d+/, PrologEx.format_answer(ans, PrologEx.query_var_names(g)), "_")

      if more, do: a <> " ;", else: a
    end)
  end

  defp err(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    e = assert_raise(PrologEx.Error, fn -> c.db |> PrologEx.query(g) |> Enum.take(1) end)
    Exception.message(e)
  end

  describe "bagof/3 (ISO 8.10.2.4)" do
    test "ohne freie Variablen", c do
      assert ask(c, "bagof(X, (X = 1 ; X = 2), S).") == ["S = [1, 2]"]
      assert ask(c, "bagof(X, (X = 1 ; X = 2), X).") == ["X = [1, 2]"]
      assert ask(c, "bagof(X, (X = Y ; X = Z), S).") == ["S = [Y, Z]"]
      assert ask(c, "bagof(X, fail, S).") == []
      assert ask(c, "bagof(X, Y^((X = 1, Y = 1) ; (X = 2, Y = 2)), S).") == ["S = [1, 2]"]
      assert ask(c, "bagof(X, Y^((X = 1 ; Y = 1) ; (X = 2, Y = 2)), S).") == ["S = [1, _A, 2]"]
    end

    test "freie Variablen: eine Lösung je Gruppe, nach Zeugen sortiert", c do
      assert ask(c, "bagof(1, (Y = 1 ; Y = 2), L).") == ["L = [1], Y = 1 ;", "L = [1], Y = 2"]
      assert ask(c, "bagof(f(X, Y), (X = a ; Y = b), L).") == ["L = [f(a, _A), f(_B, b)]"]

      assert ask(c, "bagof(X, (X = Y ; X = Z ; Y = 1), S).") ==
               ["S = [Y, Z] ;", "S = [_A], Y = 1"]

      # nach Zeuge sortiert (ISO nähme b zuerst)
      assert ask(c, "bagof(X, member(X-Y, [1-b, 2-a, 3-b]), L).") ==
               ["L = [2], Y = a ;", "L = [1, 3], Y = b"]

      # Zeugen, die Varianten sind, bilden eine Gruppe; ihre Variablen
      # werden unifiziert
      assert ask(c, "bagof(X, member(X-Y, [1-Z, 2-Z, 3-W]), L).") ==
               ["L = [1, 2], Y = Z ;", "L = [3], Y = W"]
    end

    test "Varianten, die nach dem Sortieren nicht benachbart sind", c do
      # sortiert: f(_1, b) < f(_2, a) < f(_3, b) (Variablen nach Alter);
      # f(_1, b) und f(_3, b) sind Varianten
      assert ask(c, "bagof(T, pf(W, T), L).") == [
               "L = [1, 3], W = f(_A, b) ;",
               "L = [2], W = f(_A, a)"
             ]
    end

    test "viele Gruppen: kein quadratischer Aufwand", c do
      {us, [_]} =
        :timer.tc(fn ->
          ask(c, "\\+ \\+ (bagof(X, (between(1, 20000, X), Y = X), _), fail ; true).")
        end)

      assert us < 5_000_000, "#{div(us, 1000)} ms"
    end

    test "existenziell: ^, geschachtelt, mit Modul", c do
      assert ask(c, "bagof(N, A^age(N, A), L).") == ["L = [peter, ann, pat, tom, mike]"]

      assert ask(c, "bagof(N, A^B^(age(N, A), B = A), L).") == [
               "L = [peter, ann, pat, tom, mike]"
             ]

      assert ask(c, "bagof(N, user:(A^age(N, A)), L).") == ["L = [peter, ann, pat, tom, mike]"]
    end

    test "Ergebnis ist eine Liste: Teilliste und Länge", c do
      assert ask(c, "bagof(X, member(X, [aa, bb]), [aa|T]).") == ["T = [bb]"]
      assert ask(c, "length(L, 2), bagof(X, member(X, [aa, bb, cc]), L).") == []
    end

    test "Fehler", c do
      assert err(c, "bagof(X, G, L).") =~ "instantiation_error"
      assert err(c, "bagof(X, Y^Z, L).") =~ "instantiation_error"
      assert err(c, "bagof(X, 1, L).") =~ "type_error(callable, 1)"
      assert err(c, "bagof(X, true, foo).") =~ "type_error(list, foo)"
      assert err(c, "bagof(X, true, [a|b]).") =~ "type_error(list, [a|b])"
    end
  end

  describe "setof/3 (ISO 8.10.3.4)" do
    test "sortiert ohne Duplikate", c do
      assert ask(c, "setof(X, (X = 1 ; X = 2), S).") == ["S = [1, 2]"]
      assert ask(c, "setof(X, (X = 2 ; X = 1), S).") == ["S = [1, 2]"]
      assert ask(c, "setof(X, (X = 2 ; X = 2), S).") == ["S = [2]"]
      assert ask(c, "setof(X, fail, S).") == []
      assert ask(c, "setof(1, (Y = 2 ; Y = 1), L).") == ["L = [1], Y = 1 ;", "L = [1], Y = 2"]
      assert ask(c, "setof(f(X, Y), X = Y, L).") == ["L = [f(_A, _A)]"]
      assert ask(c, "setof(X, Y^((X = 1 ; Y = 1) ; (X = 2, Y = 2)), S).") == ["S = [_A, 1, 2]"]
    end

    test "Beispiel age/2", c do
      assert ask(c, "setof(N, A^age(N, A), L).") == ["L = [ann, mike, pat, peter, tom]"]

      assert ask(c, "setof(N, age(N, A), L).") ==
               [
                 "A = 5, L = [tom] ;",
                 "A = 7, L = [peter] ;",
                 "A = 8, L = [pat] ;",
                 "A = 11, L = [ann, mike]"
               ]

      assert ask(c, "setof(A-N, age(N, A), L).") ==
               ["L = [5-tom, 7-peter, 8-pat, 11-ann, 11-mike]"]
    end

    test "geschachtelt", c do
      assert ask(c, "setof(K-Vs, setof(V, member(K-V, [b-1, a-2, b-3]), Vs), L).") ==
               ["L = [a-[2], b-[1, 3]]"]

      assert ask(c, "setof(X-Xs, Y^setof(Y, member(X-Y, [1-aa, 2-bb, 1-cc]), Xs), L).") ==
               ["L = [1-[aa, cc], 2-[bb]]"]
    end

    test "sortiert erst nach der Unifikation der Zeugen", c do
      # zwei Lösungen W = f(V1), T = V1 und W = f(V2), T = V2 mit frischen
      # Variablen: Varianten, eine Gruppe; die Unifikation der Zeugen macht
      # V1 = V2, sortiert bleibt also ein Element
      assert ask(c, "setof(T, Z^K^(member(K, [1, 2]), copy_term(f(Z)-Z, W-T)), L).") ==
               ["L = [_A], W = f(_A)"]

      assert ask(
               c,
               "bagof(T, Z^K^(member(K, [1, 2]), copy_term(f(Z)-Z, W-T)), L), L = [A, B], A == B."
             )
             |> length() == 1
    end
  end

  test "^/2 als Ziel und =@=/2", c do
    assert ask(c, "X^member(X, [aa]).") == ["X = aa"]
    assert ask(c, "f(X, Y) =@= f(A, B).") == ["true"]
    assert ask(c, "f(X, X) =@= f(A, B).") == []
    assert ask(c, "f(X, Y) =@= f(A, A).") == []
    # beide schon zugeordnet, aber zu verschiedenen Partnern
    assert ask(c, "f(X, Y, X) =@= f(A, B, B).") == []
    assert ask(c, "f(X, Y, X) =@= f(A, B, A).") == ["true"]
    assert ask(c, "f(X, b) \\=@= f(A, B).") == ["true"]
    assert ask(c, "f(aa, 1) =@= f(aa, 1.0).") == []
    assert ask(c, "[X|T] =@= [Y|U], X == Y.") == []
    assert ask(c, "X = (aa =@= bb).") == ["X = (aa=@=bb)"]
  end
end
