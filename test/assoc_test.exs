defmodule PrologEx.AssocTest do
  # library(assoc): AVL wie SWI/Scryer (Bäume Term für Term gleich), API
  # von SWI und SICStus; in Elixir
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @swi Path.expand("fixtures/assoc_swi.pl", __DIR__)

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
        :- use_module(library(assoc)).
        :- use_module(library(lists)).
        :- use_module('#{@swi}', []).
        doppelt(X, Y) :- Y is 2 * X.
        positiv(X) :- X > 0.
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

  test "aufbauen, nachschlagen, umwandeln", c do
    assert ask(c, "empty_assoc(A)") == ["A = t"]

    assert ask(c, "list_to_assoc([b-2,a-1,c-3], A), assoc_to_list(A, L)") ==
             ["A = t(b,2,-,t(a,1,-,t,t),t(c,3,-,t,t)), L = [a-1,b-2,c-3]"]

    assert ask(c, "list_to_assoc([b-2,a-1], A), assoc_to_keys(A, K), assoc_to_values(A, V)") ==
             ["A = t(b,2,<,t(a,1,-,t,t),t), K = [a,b], V = [1,2]"]

    assert ask(c, "ord_list_to_assoc([a-1,b-2,c-3], A)") ==
             ["A = t(b,2,-,t(a,1,-,t,t),t(c,3,-,t,t))"]

    assert ask(c, "list_to_assoc([a-1,b-2], A), get_assoc(b, A, V)") |> hd() =~ "V = 2"
    assert ask(c, "list_to_assoc([a-1,b-2], A), get_assoc(x, A, V)") == []
    # Schlüssel nach Standardordnung, == (nicht Unifikation)
    assert ask(c, "list_to_assoc([f(X)-1], A), get_assoc(f(Y), A, V)") == []
    assert ask(c, "list_to_assoc([f(X)-1], A), get_assoc(f(X), A, V)") |> hd() =~ "V = 1"
    assert ask(c, "list_to_assoc([1-a, 1.0-b], A), get_assoc(1.0, A, V)") |> hd() =~ "V = b"
    assert ask(c, "list_to_assoc([], A)") == ["A = t"]
    assert ask(c, "ord_list_to_assoc([], A)") == ["A = t"]
  end

  test "put, get/5, del, min, max, Nachbarn", c do
    assert ask(c, "list_to_assoc([a-1,c-3], A0), put_assoc(b, A0, 2, A), assoc_to_list(A, L)")
           |> hd() =~
             "L = [a-1,b-2,c-3]"

    assert ask(c, "list_to_assoc([a-1], A0), put_assoc(a, A0, neu, A), assoc_to_list(A, L)")
           |> hd() =~
             "L = [a-neu]"

    assert ask(
             c,
             "list_to_assoc([a-1,b-2], A0), get_assoc(a, A0, Alt, A, neu), assoc_to_list(A, L)"
           )
           |> hd() =~
             "Alt = 1"

    assert ask(c, "list_to_assoc([a-1], A0), get_assoc(x, A0, _, _, neu)") == []

    assert ask(c, "list_to_assoc([a-1,b-2,c-3], A0), del_assoc(b, A0, V, A), assoc_to_list(A, L)")
           |> hd() =~
             "L = [a-1,c-3]"

    assert ask(c, "list_to_assoc([a-1], A0), del_assoc(x, A0, V, A)") == []
    assert ask(c, "list_to_assoc([b-2,a-1,c-3], A), min_assoc(A, K, V)") |> hd() =~ "K = a, V = 1"
    assert ask(c, "list_to_assoc([b-2,a-1,c-3], A), max_assoc(A, K, V)") |> hd() =~ "K = c, V = 3"
    assert ask(c, "empty_assoc(A), min_assoc(A, K, V)") == []
    assert ask(c, "empty_assoc(A), max_assoc(A, K, V)") == []

    assert ask(
             c,
             "list_to_assoc([b-2,a-1,c-3], A0), del_min_assoc(A0, K, V, A), assoc_to_list(A, L)"
           )
           |> hd() =~
             "K = a, L = [b-2,c-3], V = 1"

    assert ask(
             c,
             "list_to_assoc([b-2,a-1,c-3], A0), del_max_assoc(A0, K, V, A), assoc_to_list(A, L)"
           )
           |> hd() =~
             "K = c, L = [a-1,b-2], V = 3"

    assert ask(c, "empty_assoc(A), del_min_assoc(A, _, _, _)") == []
    # SICStus: nächster und voriger Schlüssel (K muss nicht vorkommen)
    q = "list_to_assoc([10-a,20-b,30-c], A), "
    assert ask(c, q <> "get_next_assoc(10, A, K, V)") |> hd() =~ "K = 20, V = b"
    assert ask(c, q <> "get_next_assoc(15, A, K, V)") |> hd() =~ "K = 20, V = b"
    assert ask(c, q <> "get_next_assoc(5, A, K, V)") |> hd() =~ "K = 10, V = a"
    assert ask(c, q <> "get_next_assoc(30, A, K, V)") == []
    assert ask(c, q <> "get_prev_assoc(20, A, K, V)") |> hd() =~ "K = 10, V = a"
    assert ask(c, q <> "get_prev_assoc(35, A, K, V)") |> hd() =~ "K = 30, V = c"
    assert ask(c, q <> "get_prev_assoc(10, A, K, V)") == []
  end

  test "gen_assoc/3: ground nachschlagen, sonst aufzählen; map_assoc/2,3", c do
    q = "list_to_assoc([b-2,a-1,c-3], A), "
    assert ask(c, q <> "gen_assoc(b, A, V)") |> length() == 1

    assert ask(c, q <> "findall(K-V, gen_assoc(K, A, V), L)") |> hd() =~ "L = [a-1,b-2,c-3]"
    assert ask(c, q <> "findall(K, gen_assoc(K, A, 2), L)") |> hd() =~ "L = [b]"
    assert ask(c, q <> "map_assoc(positiv, A)") |> length() == 1
    assert ask(c, "list_to_assoc([a-1,b-0], A), map_assoc(positiv, A)") == []

    assert ask(c, q <> "map_assoc(doppelt, A, B), assoc_to_list(B, L)") |> hd() =~
             "L = [a-2,b-4,c-6]"
  end

  test "is_assoc/1 wie SWI", c do
    assert ask(c, "empty_assoc(A), is_assoc(A)") == ["A = t"]
    assert ask(c, "list_to_assoc([a-1,b-2,c-3], A), is_assoc(A)") |> length() == 1
    assert ask(c, "is_assoc(t(a,1,-,t,t))") == ["true"]
    # falsche Balance, falsche Ordnung, Variable als Schlüssel, kein Baum
    assert ask(c, "is_assoc(t(a,1,<,t,t))") == []
    assert ask(c, "is_assoc(t(b,1,>,t,t(a,2,-,t,t)))") == []
    assert ask(c, "is_assoc(t(_,1,-,t,t))") == []
    # doppelte Schlüssel links wie rechts
    assert ask(c, "is_assoc(t(a,1,>,t,t(a,2,-,t,t)))") == []
    assert ask(c, "is_assoc(t(a,1,<,t(a,2,-,t,t),t))") == []
    assert ask(c, "is_assoc(t(a,1,-,_,t))") == []
    assert ask(c, "is_assoc(foo)") == []
    assert ask(c, "is_assoc(_)") == []
  end

  test "Fehler", c do
    assert err(c, "get_assoc(a, foo, _)") == ["E = type_error(assoc,foo)"]
    assert err(c, "get_assoc(a, _, _)") == ["E = instantiation_error"]
    assert err(c, "put_assoc(a, t(a), 1, _)") == ["E = type_error(assoc,t(a))"]

    assert err(c, "list_to_assoc([a-1,a-2], _)") ==
             ["E = domain_error(unique_key_pairs,[a-1,a-2])"]

    assert err(c, "list_to_assoc([a-1,x], _)") == ["E = type_error(pair,x)"]
    assert err(c, "list_to_assoc([a-1|_], _)") == ["E = instantiation_error"]

    assert err(c, "ord_list_to_assoc([b-1,a-2], _)") ==
             ["E = domain_error(key_ordered_pairs,[b-1,a-2])"]

    assert err(c, "ord_list_to_assoc([a-1,a-2], _)") ==
             ["E = domain_error(key_ordered_pairs,[a-1,a-2])"]
  end

  test "portray_assoc/1 (SICStus)", c do
    out =
      ExUnit.CaptureIO.capture_io(fn ->
        ask(c, "list_to_assoc([b-'x y',a-1], A), portray_assoc(A)")
      end)

    assert out == "<a-1,b-'x y'>"
    out = ExUnit.CaptureIO.capture_io(fn -> ask(c, "empty_assoc(A), portray_assoc(A)") end)
    assert out == "<>"
  end

  # Term für Term wie SWIs Prolog-Fassung: zufällige Folgen
  test "dieselben Bäume wie SWI (zufällige Folgen von Operationen)", c do
    :rand.seed(:exsss, {4, 5, 6})

    for _ <- 1..150 do
      keys = Enum.uniq(for _ <- 1..:rand.uniform(12), do: :rand.uniform(30))
      init = "[" <> Enum.map_join(keys, ",", &"#{&1}-i#{&1}") <> "]"

      ops =
        for _ <- 1..:rand.uniform(30) do
          k = :rand.uniform(30)

          case :rand.uniform(10) do
            n when n <= 5 -> {"M:put_assoc(#{k}, A0, v#{k}, A)", :det}
            n when n <= 7 -> {"(M:del_assoc(#{k}, A0, _, A) -> true ; A = A0)", :det}
            8 -> {"(M:del_min_assoc(A0, _, _, A) -> true ; A = A0)", :det}
            9 -> {"(M:del_max_assoc(A0, _, _, A) -> true ; A = A0)", :det}
            10 -> {"(M:get_assoc(#{k}, A0, _, A, neu) -> true ; A = A0)", :det}
          end
        end

      run = fn m ->
        steps =
          ops
          |> Enum.with_index()
          |> Enum.map_join(", ", fn {{o, _}, j} ->
            o
            |> String.replace("M:", "#{m}:")
            |> String.replace(~r/\bA0\b/, "X#{j}")
            |> String.replace(~r/\bA\b/, "X#{j + 1}")
          end)

        "#{m}:list_to_assoc(#{init}, X0), #{steps}, R = X#{length(ops)}"
      end

      ours =
        run.("assoc") |> String.replace(~r/\bX(\d+)\b/, "_P\\1") |> String.replace("R =", "R1 =")

      theirs =
        run.("assoc_swi")
        |> String.replace(~r/\bX(\d+)\b/, "_Q\\1")
        |> String.replace("R =", "R2 =")

      [a] = ask(c, "#{ours}, #{theirs}, (R1 == R2 -> Gleich = ja ; Gleich = nein)")
      assert a =~ "Gleich = ja", a
    end
  end

  test "nur nach use_module sichtbar", c do
    PrologEx.put_db(%{})
    assert err(c, "empty_assoc(_)") == ["E = existence_error(procedure,empty_assoc/1)"]
    assert ask(c, "use_module(library(assoc)), empty_assoc(A)") == ["A = t"]
  end
end
