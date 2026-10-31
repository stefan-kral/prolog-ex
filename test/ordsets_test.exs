defmodule PrologEx.OrdsetsTest do
  # library(ordsets): SWI/Scryer und SICStus zusammen, in Elixir
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.put_db(PrologEx.use_library(%{}, "ordsets"))
    # Listen aus Einbuchstaben-Atomen als Listen zeigen, nicht als "abc"
    PrologEx.Flags.set("double_quotes", {:atom, "codes"})
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp yes(c, q), do: ask(c, q) != []
  defp err(c, q), do: ask(c, "catch((#{q}), error(E, _), true)")

  test "Beispiele: Vereinigung, Schnitt, Differenz, symmetrische Differenz", c do
    assert ask(c, "ord_union([a,c,e], [b,c,d], U)") == ["U = [a,b,c,d,e]"]
    assert ask(c, "ord_union([], [a], U)") == ["U = [a]"]
    assert ask(c, "ord_union([a], [], U)") == ["U = [a]"]
    assert ask(c, "ord_intersection([a,c,e], [b,c,d,e], I)") == ["I = [c,e]"]
    assert ask(c, "ord_intersect([a,c,e], [b,c,d,e], I)") == ["I = [c,e]"]
    assert ask(c, "ord_subtract([a,b,c,d], [b,d,x], D)") == ["D = [a,c]"]
    assert ask(c, "ord_symdiff([1,2], [2,3], X)") == ["X = [1,3]"]
    # Old, New: Vereinigung und New \\ Old
    assert ask(c, "ord_union([a,c], [b,c,d], U, N)") == ["N = [b,d], U = [a,b,c,d]"]
    # Schnitt und S2 \\ S1
    assert ask(c, "ord_intersection([a,c,e], [b,c,d,e], I, D)") == ["D = [b,d], I = [c,e]"]
    assert ask(c, "ord_union([[c,d],[a],[],[b,d]], U)") == ["U = [a,b,c,d]"]
    assert ask(c, "ord_union([], U)") == ["U = []"]
    assert ask(c, "ord_intersection([[a,b,c],[b,c,d],[b,c]], I)") == ["I = [b,c]"]
    assert ask(c, "ord_intersection([[a]], I)") == ["I = [a]"]
    # leere Liste von Mengen: scheitert (wie SWI)
    assert ask(c, "ord_intersection([], I)") == []
  end

  test "Tests: Teilmenge, disjunkt, schneiden, gleich, Ordnung", c do
    assert yes(c, "ord_subset([b,d], [a,b,c,d])")
    refute yes(c, "ord_subset([b,e], [a,b,c,d])")
    assert yes(c, "ord_subset([], [])")
    assert yes(c, "ord_disjoint([a,c], [b,d])")
    refute yes(c, "ord_disjoint([a,c], [c,d])")
    assert yes(c, "ord_intersect([a,c], [c,d])")
    refute yes(c, "ord_intersect([a,c], [b,d])")
    refute yes(c, "ord_intersect([], [])")
    assert yes(c, "ord_seteq([a,b], [a,b])")
    refute yes(c, "ord_seteq([a,b], [a])")
    assert ask(c, "ordset_order([a], [a,b], R)") == ["R = (<)"]
    assert ask(c, "ordset_order([a,b], [a,b], R)") == ["R = (=)"]
    assert ask(c, "ordset_order([a,b], [b], R)") == ["R = (>)"]
    assert ask(c, "ordset_order([a], [b], R)") == []
  end

  test "Elemente: memberchk, member, nonmember, add, del, selectchk", c do
    assert yes(c, "ord_memberchk(c, [a,c,e])")
    refute yes(c, "ord_memberchk(d, [a,c,e])")
    refute yes(c, "ord_memberchk(z, [a,c,e])")
    # sucht nur bis zum ersten größeren Element (wie SWI): in einer nicht
    # geordneten Liste wird a hinter b nicht gefunden
    refute yes(c, "ord_memberchk(a, [b,a])")
    assert yes(c, "ord_member(e, [a,c,e])")
    assert yes(c, "ord_nonmember(d, [a,c,e])")
    refute yes(c, "ord_nonmember(a, [a,c,e])")
    # eine freie Variable ist nur sie selbst
    refute yes(c, "ord_memberchk(_, [a,c,e])")
    assert yes(c, "X = Y, ord_memberchk(X, [Y])")
    assert ask(c, "ord_add_element([a,c], b, S)") == ["S = [a,b,c]"]
    assert ask(c, "ord_add_element([a,c], c, S)") == ["S = [a,c]"]
    assert ask(c, "ord_del_element([a,b,c], b, S)") == ["S = [a,c]"]
    assert ask(c, "ord_del_element([a,c], b, S)") == ["S = [a,c]"]
    # beide Richtungen
    assert ask(c, "ord_selectchk(b, [a,b,c], S)") == ["S = [a,c]"]
    assert ask(c, "ord_selectchk(x, [a,b,c], S)") == []
    assert ask(c, "ord_selectchk(b, S, [a,c])") == ["S = [a,b,c]"]
    assert ask(c, "ord_selectchk(a, S, [a,c])") == []
  end

  test "SICStus: disjunkte Vereinigung, Produkt; is_ordset, list_to_ord_set, ord_empty", c do
    assert ask(c, "ord_disjoint_union([a,c], [b,d], U)") == ["U = [a,b,c,d]"]
    assert ask(c, "ord_disjoint_union([a,c], [c,d], U)") == []
    assert ask(c, "ord_setproduct([a,b], [1,2], P)") == ["P = [a-1,a-2,b-1,b-2]"]
    assert ask(c, "ord_setproduct([], [1,2], P)") == ["P = []"]
    assert yes(c, "is_ordset([a,b,c])")
    assert yes(c, "is_ordset([])")
    refute yes(c, "is_ordset([b,a])")
    refute yes(c, "is_ordset([a,a])")
    refute yes(c, "is_ordset([a|_])")
    refute yes(c, "is_ordset(foo)")
    refute yes(c, "is_ordset(_)")
    assert ask(c, "list_to_ord_set([c,a,b,a], S)") == ["S = [a,b,c]"]
    assert ask(c, "ord_empty(S)") == ["S = []"]
    refute yes(c, "ord_empty([a])")
  end

  test "Standardordnung: gemischte Terme, Zahlen, Variablen", c do
    assert ask(c, "ord_union([1, a, f(x)], [1.0, b, g], U)") == ["U = [1.0,1,a,b,g,f(x)]"]
    assert ask(c, "ord_intersection([1], [1.0], I)") == ["I = []"]
    assert yes(c, "sort([X, Y], S), ord_union(S, [Y], U), U == S")
    assert yes(c, "sort([X, Y], S), ord_subtract(S, [X], D), D == [Y]")
    assert yes(c, "X = f(Y), ord_memberchk(f(Z), [X]) -> fail ; true")
  end

  test "Fehler: Teilliste und keine Liste (wie sort/2)", c do
    assert err(c, "ord_union([a|_], [b], U)") == ["E = instantiation_error"]
    assert err(c, "ord_union(foo, [b], U)") == ["E = type_error(list,foo)"]
    assert err(c, "ord_subtract([a], _, U)") == ["E = instantiation_error"]
    assert err(c, "ord_memberchk(a, foo)") == ["E = type_error(list,foo)"]
    assert err(c, "list_to_ord_set(_, S)") == ["E = instantiation_error"]
    assert err(c, "ord_union([[a], foo], U)") == ["E = type_error(list,foo)"]
    assert err(c, "ord_selectchk(a, _, _)") == ["E = instantiation_error"]
  end

  test "nur nach use_module sichtbar", c do
    PrologEx.put_db(%{})
    assert err(c, "ord_union([a], [b], U)") == ["E = existence_error(procedure,ord_union/3)"]
    assert ask(c, "use_module(library(ordsets)), ord_union([a], [b], U)") == ["U = [a,b]"]
  end

  # gegen eine Referenz in Elixir (Mengen kleiner Ganzzahlen)
  test "zufällige Mengen: wie die Referenz", c do
    :rand.seed(:exsss, {7, 8, 9})

    for _ <- 1..300 do
      a = Enum.uniq(for _ <- 1..:rand.uniform(8), do: :rand.uniform(12)) |> Enum.sort()
      b = Enum.uniq(for _ <- 1..:rand.uniform(8), do: :rand.uniform(12)) |> Enum.sort()
      a = if :rand.uniform(5) == 1, do: [], else: a
      ms = {MapSet.new(a), MapSet.new(b)}
      l = fn x -> "[" <> Enum.map_join(Enum.sort(x), ",", &Integer.to_string/1) <> "]" end
      {ma, mb} = ms
      q = fn p -> ask(c, "#{p}(#{l.(a)}, #{l.(b)}, R)") end
      assert q.("ord_union") == ["R = #{l.(MapSet.union(ma, mb))}"]
      assert q.("ord_intersection") == ["R = #{l.(MapSet.intersection(ma, mb))}"]
      assert q.("ord_subtract") == ["R = #{l.(MapSet.difference(ma, mb))}"]

      assert q.("ord_symdiff") ==
               ["R = #{l.(MapSet.union(MapSet.difference(ma, mb), MapSet.difference(mb, ma)))}"]

      assert yes(c, "ord_subset(#{l.(a)}, #{l.(b)})") == MapSet.subset?(ma, mb)
      assert yes(c, "ord_disjoint(#{l.(a)}, #{l.(b)})") == MapSet.disjoint?(ma, mb)
      assert yes(c, "ord_intersect(#{l.(a)}, #{l.(b)})") == not MapSet.disjoint?(ma, mb)
      e = :rand.uniform(12)
      assert yes(c, "ord_memberchk(#{e}, #{l.(b)})") == MapSet.member?(mb, e)
    end
  end
end
