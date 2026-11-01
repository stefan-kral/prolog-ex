defmodule PrologEx.HeapsTest do
  # library(heaps): Vereinigung von SWI und SICStus, stabil, in Elixir
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @swi Path.expand("fixtures/heaps_swi.pl", __DIR__)

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
        :- use_module(library(heaps)).
        :- use_module(library(lists)).
        :- use_module('#{@swi}', []).
        % alle Schlüssel nach Priorität entnehmen
        keys(M, H, Ks) :- ( M:get_from_heap(H, K, _, H1) -> Ks = [K|Ks1], keys(M, H1, Ks1) ; Ks = [] ).
        values(H, Vs) :- ( get_from_heap(H, _, V, H1) -> Vs = [V|Vs1], values(H1, Vs1) ; Vs = [] ).
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

  test "aufbauen, entnehmen, umwandeln", c do
    assert ask(c, "empty_heap(H), heap_size(H, N)") == ["H = heap(0,0,t), N = 0"]

    assert ask(c, "list_to_heap([3-c,1-a,2-b], H), heap_to_list(H, L), heap_size(H, N)") |> hd() =~
             "L = [1-a,2-b,3-c], N = 3"

    assert ask(
             c,
             "list_to_heap([3-c,1-a,2-b], H), get_from_heap(H, K, V, H1), heap_to_list(H1, L)"
           )
           |> hd() =~
             "K = 1, L = [2-b,3-c], V = a"

    assert ask(c, "empty_heap(H), get_from_heap(H, _, _, _)") == []
    assert ask(c, "list_to_heap([2-b,1-a], H), min_of_heap(H, K, V)") |> hd() =~ "K = 1, V = a"
    assert ask(c, "empty_heap(H), min_of_heap(H, _, _)") == []

    assert ask(c, "list_to_heap([3-c,1-a,2-b], H), min_of_heap(H, K1, V1, K2, V2)") |> hd() =~
             "K1 = 1, K2 = 2, V1 = a, V2 = b"

    assert ask(c, "list_to_heap([1-a], H), min_of_heap(H, _, _, _, _)") == []
    # Schlüssel nach Standardordnung: Variable < Zahl < Atom < Struktur
    assert ask(c, "list_to_heap([f(x)-1, b-2, 3-3, 2.0-4], H), heap_to_list(H, L)") |> hd() =~
             "L = [2.0-4,3-3,b-2,f(x)-1]"

    # empty_heap/1 auch für einen leer gewordenen Heap
    assert ask(c, "list_to_heap([1-a], H), get_from_heap(H, _, _, H1), empty_heap(H1)")
           |> length() == 1

    assert ask(c, "list_to_heap([1-a], H), empty_heap(H)") == []
  end

  test "stabil: gleiche Schlüssel in Einfügereihenfolge", c do
    assert ask(c, "list_to_heap([1-a,0-x,1-b,1-c,0-y], H), heap_to_list(H, L)") |> hd() =~
             "L = [0-x,0-y,1-a,1-b,1-c]"

    assert ask(
             c,
             "empty_heap(E), add_to_heap(E, 5, a, H1), add_to_heap(H1, 5, b, H2), add_to_heap(H2, 1, z, H3), add_to_heap(H3, 5, c, H4), keys(heaps, H4, _), heap_to_list(H4, L)"
           )
           |> hd() =~
             "L = [1-z,5-a,5-b,5-c]"

    # auch beim Entnehmen
    [v] = ask(c, "list_to_heap([1-a,0-x,1-b,1-c,0-y,1-d], H), values(H, Vs)")
    assert v =~ "Vs = [x,y,a,b,c,d]"

    [v] =
      ask(
        c,
        "empty_heap(E), add_to_heap(E, 1, a, H1), add_to_heap(H1, 1, b, H2), add_to_heap(H2, 0, z, H3), add_to_heap(H3, 1, c, H4), get_from_heap(H4, _, _, H5), add_to_heap(H5, 1, d, H6), values(H6, Vs)"
      )

    assert v =~ "Vs = [a,b,c,d]"
    # nach merge_heaps: neue Paare nach allen alten
    [v] =
      ask(
        c,
        "list_to_heap([1-a], A), list_to_heap([1-b,1-c,1-e], B), merge_heaps(A, B, M), add_to_heap(M, 1, d, H), values(H, Vs)"
      )

    assert v =~ ~r/Vs = \[\w,\w,\w,\w,d\]/

    [a] =
      ask(
        c,
        "numlist(1, 200, Ns), findall(K-N, (member(N, Ns), K is N mod 3), Ps), list_to_heap(Ps, H), heap_to_list(H, L), msort(Ps, _), findall(K-N, (member(K, [0,1,2]), member(N, Ns), N mod 3 =:= K), L2), (L == L2 -> Ok = ja ; Ok = nein)"
      )

    assert a =~ "Ok = ja"
  end

  test "delete_from_heap/4: SICStus- und SWI-Richtung", c do
    q = "list_to_heap([3-c,1-a,2-b,2-bb], H), "

    assert ask(c, q <> "delete_from_heap(H, 2, V, H1), heap_to_list(H1, L)") |> hd() =~
             "L = [1-a,2-bb,3-c], V = b"

    assert ask(c, q <> "delete_from_heap(H, K, bb, H1), heap_to_list(H1, L)") |> hd() =~
             "K = 2, L = [1-a,2-b,3-c]"

    assert ask(c, q <> "delete_from_heap(H, 7, _, _)") == []
    assert ask(c, q <> "delete_from_heap(H, 2, c, _)") == []

    assert ask(c, q <> "delete_from_heap(H, 2, V, H1), heap_size(H1, N), is_heap(H1)") |> hd() =~
             "N = 3"
  end

  test "merge_heaps/3, singleton_heap/3 (SWI)", c do
    assert ask(
             c,
             "list_to_heap([3-c,1-a], A), list_to_heap([2-b,0-z], B), merge_heaps(A, B, H), heap_to_list(H, L), heap_size(H, N), is_heap(H)"
           )
           |> hd() =~
             "L = [0-z,1-a,2-b,3-c], N = 4"

    assert ask(c, "singleton_heap(H, 1, a), heap_to_list(H, L)") |> hd() =~ "L = [1-a]"
    assert ask(c, "list_to_heap([7-x], H), singleton_heap(H, K, V)") |> hd() =~ "K = 7, V = x"
    assert ask(c, "list_to_heap([7-x,8-y], H), singleton_heap(H, _, _)") == []
  end

  test "is_heap/1 und portray_heap/1", c do
    assert ask(c, "list_to_heap([3-c,1-a,2-b], H), is_heap(H)") |> length() == 1
    assert ask(c, "empty_heap(H), is_heap(H)") |> length() == 1
    assert ask(c, "is_heap(foo)") == []
    assert ask(c, "is_heap(_)") == []
    # Heap-Bedingung verletzt, falsche Größe, falscher Rang
    assert ask(c, "is_heap(heap(2,2,t(5,0,a,1,t(1,1,b,1,t,t),t)))") == []
    assert ask(c, "is_heap(heap(3,2,t(1,0,a,1,t(5,1,b,1,t,t),t)))") == []
    assert ask(c, "is_heap(heap(2,2,t(1,0,a,2,t(5,1,b,1,t,t),t)))") == []
    assert ask(c, "is_heap(heap(2,2,t(1,0,a,1,t,t(5,1,b,1,t,t))))") == []
    assert ask(c, "is_heap(heap(2,2,t(1,0,a,2,t,t(5,1,b,1,t,t))))") == []
    assert ask(c, "is_heap(heap(2,2,t(1,0,a,1,t(5,1,b,1,t,t),t)))") == ["true"]

    out =
      ExUnit.CaptureIO.capture_io(fn ->
        ask(c, "list_to_heap([2-'b c',1-a], H), portray_heap(H)")
      end)

    assert out == "heap{a->1, 'b c'->2}"

    assert ExUnit.CaptureIO.capture_io(fn -> ask(c, "empty_heap(H), portray_heap(H)") end) ==
             "heap{}"
  end

  test "Fehler", c do
    assert err(c, "get_from_heap(_, _, _, _)") == ["E = instantiation_error"]
    assert err(c, "add_to_heap(foo, 1, a, _)") == ["E = type_error(heap,foo)"]
    assert err(c, "heap_size(heap(a,0,t), _)") == ["E = type_error(heap,heap(a,0,t))"]
    assert err(c, "list_to_heap([1-a,x], _)") == ["E = type_error(pair,x)"]
    assert err(c, "list_to_heap([1-a|_], _)") == ["E = instantiation_error"]
    assert err(c, "list_to_heap(foo, _)") == ["E = type_error(list,foo)"]
  end

  # dieselbe Folge von Schlüsseln wie SWIs Pairing-Heap (die Werte gleicher
  # Schlüssel kommen dort in anderer Reihenfolge)
  test "dieselben Schlüssel wie SWI (zufällige Folgen)", c do
    :rand.seed(:exsss, {3, 1, 4})

    for _ <- 1..120 do
      init =
        "[" <>
          Enum.map_join(1..:rand.uniform(10), ",", fn i -> "#{:rand.uniform(8)}-i#{i}" end) <> "]"

      ops =
        for i <- 1..:rand.uniform(25) do
          k = :rand.uniform(8)

          case :rand.uniform(10) do
            n when n <= 5 ->
              "M:add_to_heap(A0, #{k}, v#{i}, A)"

            n when n <= 7 ->
              "(M:get_from_heap(A0, _, _, A) -> true ; A = A0)"

            8 ->
              "(M:delete_from_heap(A0, #{k}, _, A) -> true ; A = A0)"

            9 ->
              "(M:list_to_heap([#{k}-m#{i}, #{:rand.uniform(8)}-n#{i}], B), M:merge_heaps(A0, B, A))"

            10 ->
              "(M:min_of_heap(A0, K1, _, K2, _) -> M:add_to_heap(A0, K1-K2, p, A) ; A = A0)"
          end
        end

      run = fn m, x ->
        steps =
          ops
          |> Enum.with_index()
          |> Enum.map_join(", ", fn {o, j} ->
            o
            |> String.replace("M:", "#{m}:")
            |> String.replace(~r/\bA0\b/, "#{x}#{j}")
            |> String.replace(~r/\bA\b/, "#{x}#{j + 1}")
            |> String.replace(~r/\b(B|K1|K2)\b/, "\\1#{x}#{j}")
          end)

        "#{m}:list_to_heap(#{init}, #{x}0), #{steps}, keys(#{m}, #{x}#{length(ops)}, Ks#{x}), #{m}:heap_size(#{x}#{length(ops)}, N#{x})"
      end

      [a] =
        ask(
          c,
          "#{run.("heaps", "P")}, #{run.("heaps_swi", "Q")}, (KsP-NP == KsQ-NQ -> Gleich = ja ; Gleich = nein)"
        )

      assert a =~ "Gleich = ja", a
    end
  end

  test "nur nach use_module sichtbar", c do
    PrologEx.put_db(%{})
    assert err(c, "empty_heap(_)") == ["E = existence_error(procedure,empty_heap/1)"]
    assert ask(c, "use_module(library(heaps)), empty_heap(H)") == ["H = heap(0,0,t)"]
  end
end
