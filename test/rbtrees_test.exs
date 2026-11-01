defmodule PrologEx.RbtreesTest do
  # library(rbtrees): wie SWI (Bäume Term für Term gleich), in Elixir
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @swi Path.expand("fixtures/rbtrees_swi.pl", __DIR__)

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(c.reader, """
        :- use_module(library(rbtrees)).
        :- use_module(library(lists)).
        :- use_module('#{@swi}', []).
        doppelt(X, Y) :- Y is 2 * X.
        summe(_-V, S0, S) :- S is S0 + V.
        % Form eines Baums ohne die Variablen des leeren Knotens
        form(t(_,R), S) :- form_(R, S).
        form_(black('',_,_,''), nil) :- !.
        form_(black(L,K,V,R), b(SL,K,V,SR)) :- form_(L, SL), form_(R, SR).
        form_(red(L,K,V,R), r(SL,K,V,SR)) :- form_(L, SL), form_(R, SR).
        """)
      )

    PrologEx.put_db(db)
    PrologEx.Flags.set("double_quotes", {:atom, "codes"})
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(10)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, q), do: ask(c, "catch((#{q}), error(E, _), true)")

  test "anlegen, einfügen, nachschlagen", c do
    assert ask(c, "rb_new(T), rb_empty(T), rb_size(T, N), rb_visit(T, L)") |> hd() =~
             "L = [], N = 0"

    assert ask(
             c,
             "rb_new(T0), rb_insert(T0, b, 2, T1), rb_insert(T1, a, 1, T2), rb_insert(T2, c, 3, T), form(T, F)"
           )
           |> hd() =~
             "F = b(r(nil,a,1,nil),b,2,r(nil,c,3,nil))"

    q = "list_to_rbtree([c-3,a-1,b-2,d-4], T), "
    assert ask(c, q <> "rb_lookup(b, V, T)") |> hd() =~ "V = 2"
    assert ask(c, q <> "rb_lookup(x, V, T)") == []
    assert ask(c, q <> "rb_insert(T, b, neu, T1), rb_lookup(b, V, T1)") |> hd() =~ "V = neu"
    assert ask(c, q <> "rb_insert_new(T, b, neu, _)") == []
    assert ask(c, q <> "rb_insert_new(T, e, 5, T1), rb_keys(T1, K)") |> hd() =~ "K = [a,b,c,d,e]"
    assert ask(c, q <> "rb_update(T, b, neu, T1), rb_lookup(b, V, T1)") |> hd() =~ "V = neu"
    assert ask(c, q <> "rb_update(T, b, Alt, neu, _)") |> hd() =~ "Alt = 2"
    assert ask(c, q <> "rb_update(T, x, neu, _)") == []
    assert ask(c, q <> "rb_apply(T, c, doppelt, T1), rb_lookup(c, V, T1)") |> hd() =~ "V = 6"
    assert ask(c, q <> "rb_apply(T, x, doppelt, _)") == []
  end

  test "löschen, min, max, Nachbarn", c do
    q = "list_to_rbtree([c-3,a-1,b-2,d-4], T), "

    assert ask(c, q <> "rb_delete(T, b, T1), rb_visit(T1, L), is_rbtree(T1)") |> hd() =~
             "L = [a-1,c-3,d-4]"

    assert ask(c, q <> "rb_delete(T, b, V, _)") |> hd() =~ "V = 2"
    assert ask(c, q <> "rb_delete(T, x, _)") == []
    assert ask(c, q <> "rb_min(T, K, V)") |> hd() =~ "K = a, T = "
    assert ask(c, q <> "rb_max(T, K, V)") |> hd() =~ "K = d"
    assert ask(c, "rb_new(T), rb_min(T, _, _)") == []
    assert ask(c, "rb_new(T), rb_max(T, _, _)") == []

    assert ask(c, q <> "rb_del_min(T, K, V, T1), rb_keys(T1, Ks)") |> hd() =~
             "K = a, Ks = [b,c,d]"

    assert ask(c, q <> "rb_del_max(T, K, V, T1), rb_keys(T1, Ks)") |> hd() =~
             "K = d, Ks = [a,b,c]"

    assert ask(c, "rb_new(T), rb_del_min(T, _, _, _)") == []
    assert ask(c, q <> "rb_next(T, b, K, V)") |> hd() =~ "K = c"
    assert ask(c, q <> "rb_previous(T, b, K, V)") |> hd() =~ "K = a"
    assert ask(c, q <> "rb_next(T, d, K, V)") == []
    assert ask(c, q <> "rb_previous(T, a, K, V)") == []
    # wie SWI: der Schlüssel muss vorkommen
    assert ask(c, q <> "rb_next(T, bb, K, V)") == []
  end

  test "durchlaufen, abbilden, falten", c do
    q = "list_to_rbtree([c-3,a-1,b-2,d-4,e-5], T), "
    assert ask(c, q <> "rb_visit(T, L)") |> hd() =~ "L = [a-1,b-2,c-3,d-4,e-5]"
    assert ask(c, q <> "rb_keys(T, L)") |> hd() =~ "L = [a,b,c,d,e]"
    assert ask(c, q <> "rb_visit_range(T, b, d, L)") |> hd() =~ "L = [b-2,c-3,d-4]"
    assert ask(c, q <> "rb_size(T, N)") |> hd() =~ "N = 5"
    assert ask(c, q <> "findall(K-V, rb_in(K, V, T), L)") |> hd() =~ "L = [a-1,b-2,c-3,d-4,e-5]"
    assert ask(c, q <> "findall(K, rb_in(K, 3, T), L)") |> hd() =~ "L = [c]"

    assert ask(c, q <> "rb_map(T, doppelt, T1), rb_visit(T1, L)") |> hd() =~
             "L = [a-2,b-4,c-6,d-8,e-10]"

    assert ask(c, q <> "rb_map(T, integer)") |> length() == 1
    assert ask(c, q <> "rb_map(T, atom)") == []
    assert ask(c, q <> "rb_fold(summe, T, 0, S)") |> hd() =~ "S = 15"

    assert ask(c, q <> "rb_partial_map(T, [b,d], doppelt, T1), rb_visit(T1, L)") |> hd() =~
             "L = [a-1,b-4,c-3,d-8,e-5]"

    assert ask(c, q <> "rb_partial_map(T, [b,x], doppelt, _)") == []
    assert ask(c, q <> "rb_partial_map(T, [], doppelt, T1), T1 == T") |> length() == 1

    assert ask(c, q <> "rb_clone(T, T1, Ps), Ps = [_-X|_], X = neu, rb_lookup(a, V, T1)") |> hd() =~
             "V = neu"

    # Reihenfolge der Aufrufe von rb_map/2 wie SWI (Präordnung)
    assert ExUnit.CaptureIO.capture_io(fn -> ask(c, q <> "rb_map(T, write)") end) == "31245"
  end

  test "is_rbtree/1", c do
    assert ask(c, "rb_new(T), is_rbtree(T)") |> length() == 1
    assert ask(c, "list_to_rbtree([a-1,b-2,c-3], T), is_rbtree(T)") |> length() == 1
    assert ask(c, "is_rbtree(_)") == []
    assert ask(c, "is_rbtree(foo)") == []
    # rote Wurzel, ungeordnet, ungleiche Schwarzhöhe, rot unter rot
    assert ask(c, "N = black('',_,_,''), is_rbtree(t(N, red(N,a,1,N)))") == []
    assert ask(c, "N = black('',_,_,''), is_rbtree(t(N, black(black(N,b,1,N),a,1,N)))") == []
    assert ask(c, "N = black('',_,_,''), is_rbtree(t(N, black(black(N,a,1,N),b,1,N)))") == []

    assert ask(c, "N = black('',_,_,''), is_rbtree(t(N, black(red(red(N,a,1,N),b,1,N),c,1,N)))") ==
             []

    assert ask(
             c,
             "N = black('',_,_,''), is_rbtree(t(N, black(black(N,a,1,N),b,1,black(N,c,1,N))))"
           )
           |> length() == 1
  end

  test "Fehler", c do
    assert err(c, "rb_lookup(a, _, _)") == ["E = instantiation_error"]
    assert err(c, "rb_insert(foo, a, 1, _)") == ["E = type_error(rbtree,foo)"]

    assert err(c, "list_to_rbtree([a-1,a-2], _)") == [
             "E = domain_error(unique_key_pairs,[a-1,a-2])"
           ]

    assert err(c, "ord_list_to_rbtree([b-1,a-2], _)") == [
             "E = domain_error(key_ordered_pairs,[b-1,a-2])"
           ]

    assert err(c, "ord_list_to_rbtree([a-1,a-2], _)") == [
             "E = domain_error(key_ordered_pairs,[a-1,a-2])"
           ]

    assert err(c, "list_to_rbtree([a-1,x], _)") == ["E = type_error(pair,x)"]
    assert err(c, "list_to_rbtree([a-1|_], _)") == ["E = instantiation_error"]
    # gleiche Paare zählen einmal (sort/2)
    assert ask(c, "list_to_rbtree([a-1,a-1], T), rb_visit(T, L)") |> hd() =~ "L = [a-1]"
  end

  # Term für Term wie SWIs Fassung: zufällige Folgen von Operationen
  test "dieselben Bäume wie SWI (zufällige Folgen)", c do
    :rand.seed(:exsss, {5, 6, 7})

    for _ <- 1..120 do
      ops =
        for j <- 1..:rand.uniform(50) do
          k = :rand.uniform(40)

          case :rand.uniform(12) do
            x when x <= 5 ->
              "M:rb_insert(T, #{k}, v#{j}, T1)"

            6 ->
              "(M:rb_insert_new(T, #{k}, w#{j}, T1) -> true ; T1 = T)"

            x when x <= 8 ->
              "(M:rb_delete(T, #{k}, _, T1) -> true ; T1 = T)"

            9 ->
              "(M:rb_del_min(T, _, _, T1) -> true ; T1 = T)"

            10 ->
              "(M:rb_del_max(T, _, _, T1) -> true ; T1 = T)"

            11 ->
              "(M:rb_update(T, #{k}, u#{j}, T1) -> true ; T1 = T)"

            12 ->
              "(M:rb_next(T, #{k}, NK, _) -> M:rb_insert(T, NK-x, n, T1) ; M:rb_previous(T, #{k}, PK, _) -> M:rb_insert(T, PK-y, p, T1) ; T1 = T)"
          end
        end

      init =
        "[" <>
          Enum.map_join(
            Enum.uniq(for _ <- 1..:rand.uniform(20), do: :rand.uniform(40)),
            ",",
            &"#{&1}-i#{&1}"
          ) <> "]"

      prog = fn mod, x ->
        last = "#{x}#{length(ops)}"

        chain =
          ops
          |> Enum.with_index()
          |> Enum.map_join(", ", fn {o, j} ->
            o
            |> String.replace("M:", "#{mod}:")
            |> String.replace("T1", "#{x}#{j + 1}")
            |> String.replace(~r/\bT\b/, "#{x}#{j}")
            |> String.replace(~r/\b(NK|PK)\b/, "\\1#{x}#{j}")
          end)

        "#{mod}:list_to_rbtree(#{init}, #{x}0), #{chain}, form(#{last}, S#{x}), " <>
          "#{mod}:rb_size(#{last}, N#{x}), (#{mod}:is_rbtree(#{last}) -> I#{x} = ja ; I#{x} = nein), " <>
          "findall(K-V, #{mod}:rb_in(K, V, #{last}), In#{x}), #{mod}:rb_visit_range(#{last}, 10, 30, R#{x})"
      end

      [a] =
        ask(
          c,
          "#{prog.("rbtrees", "P")}, #{prog.("rbtrees_swi", "Q")}, (f(SP,NP,IP,InP,RP) == f(SQ,NQ,IQ,InQ,RQ) -> Gleich = ja ; Gleich = nein)"
        )

      assert a =~ "Gleich = ja", String.slice(a, 0, 2000)
    end
  end

  test "nur nach use_module sichtbar", c do
    PrologEx.put_db(%{})
    assert err(c, "rb_new(_)") == ["E = existence_error(procedure,rb_new/1)"]
    assert ask(c, "use_module(library(rbtrees)), rb_new(T), rb_empty(T)") |> length() == 1
  end
end
