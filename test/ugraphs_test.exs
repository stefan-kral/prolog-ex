defmodule PrologEx.UgraphsTest do
  # library(ugraphs) und library(wgraphs): Vereinigung von SWI/Scryer und
  # SICStus, in Elixir
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @swi Path.expand("fixtures/ugraphs_swi.pl", __DIR__)

  # Prüfprädikate in Prolog: alle einfachen Pfade (gewichtet), Cliquen
  # durch Aufzählen
  @checks """
  :- use_module(library(ugraphs)).
  :- use_module(library(wgraphs), []).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(iso_ext)).
  :- use_module('#{@swi}', []).

  % einfacher Pfad von A nach B mit mindestens einer Kante, Kosten C
  wpfad(G, A, B, C) :- wpfad(G, A, B, [A], C).
  wpfad(G, A, B, _, W) :- member(A-Ns, G), member(B-W, Ns).
  wpfad(G, A, B, Seen, C) :-
      member(A-Ns, G), member(N-W, Ns), \\+ memberchk(N, Seen), N \\== B,
      wpfad(G, N, B, [N|Seen], C0), C is C0 + W.
  kuerzest(G, A, B, C) :- findall(X, wpfad(G, A, B, X), Xs), Xs \\== [], min_list(Xs, C).
  laengst(G, A, B, C) :- findall(X, wpfad(G, A, B, X), Xs), Xs \\== [], max_list(Xs, C).

  clique(G, Vs) :- forall((member(A, Vs), member(B, Vs), A \\== B), (member(A-Ns, G), memberchk(B, Ns))).
  maximal(G, Vs) :- clique(G, Vs), \\+ (member(V-_, G), \\+ memberchk(V, Vs), clique(G, [V|Vs])).
  teilmenge([], []).
  teilmenge([X|Xs], [X|Ys]) :- teilmenge(Xs, Ys).
  teilmenge([_|Xs], Ys) :- teilmenge(Xs, Ys).
  alle_cliquen(G, Cs) :-
      vertices(G, Vs),
      findall(C, (teilmenge(Vs, C), C \\== [], maximal(G, C)), Cs0), msort(Cs0, Cs).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, @checks))
    PrologEx.put_db(db)
    PrologEx.Flags.set("double_quotes", {:atom, "codes"})
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  defp ask(c, q, n \\ 10) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(n)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, q), do: ask(c, "catch((#{q}), error(E, _), true)")

  test "Aufbauen und Ändern (Beispiele von SWI)", c do
    assert ask(c, "vertices_edges_to_ugraph([6,7,8],[1-3,2-4,4-5,1-5], L)") ==
             ["L = [1-[3,5],2-[4],3-[],4-[5],5-[],6-[],7-[],8-[]]"]

    assert ask(c, "vertices([1-[3,5],2-[4],3-[],4-[5],5-[]], L)") == ["L = [1,2,3,4,5]"]
    assert ask(c, "edges([1-[3,5],2-[4],3-[],4-[5],5-[]], L)") == ["L = [1-3,1-5,2-4,4-5]"]

    assert ask(c, "add_vertices([1-[3,5],2-[]], [0,1,2,9,9], NG)") == [
             "NG = [0-[],1-[3,5],2-[],9-[]]"
           ]

    assert ask(c, "del_vertices([1-[3,5],2-[4],3-[],4-[5],5-[],6-[],7-[2,6],8-[]], [2,1], NL)") ==
             ["NL = [3-[],4-[5],5-[],6-[],7-[6],8-[]]"]

    # SWI behält hier 1 (Fehler beim Überspringen); wie SICStus entfernt
    assert ask(c, "del_vertices([1-[1]], [1, 3.0], NL)") == ["NL = []"]

    assert ask(
             c,
             "add_edges([1-[3,5],2-[4],3-[],4-[5],5-[],6-[],7-[],8-[]], [1-6,2-3,3-2,5-7,3-2,4-5], NL)"
           ) ==
             ["NL = [1-[3,5,6],2-[3,4],3-[2],4-[5],5-[7],6-[],7-[],8-[]]"]

    assert ask(
             c,
             "del_edges([1-[3,5],2-[4],3-[],4-[5],5-[],6-[],7-[],8-[]], [1-6,2-3,3-2,5-7,3-2,4-5,1-3], NL)"
           ) ==
             ["NL = [1-[5],2-[4],3-[],4-[],5-[],6-[],7-[],8-[]]"]

    assert ask(c, "ugraph_union([1-[2],2-[3]],[2-[4],3-[1,2,4]],L)") == [
             "L = [1-[2],2-[3,4],3-[1,2,4]]"
           ]

    assert ask(c, "neighbours(4,[1-[3,5],2-[4],3-[],4-[1,2,7,5],5-[]], NL)") == ["NL = [1,2,7,5]"]
    assert ask(c, "neighbors(9,[1-[3,5]], NL)") == []
    # Knoten sind gleich, wenn ==: f(X) und f(Y) verschieden
    assert ask(c, "vertices_edges_to_ugraph([], [f(X)-f(Y), f(X)-f(X)], G)") ==
             ["G = [f(X)-[f(X),f(Y)],f(Y)-[]]"]
  end

  test "abgeleitete Graphen", c do
    assert ask(c, "transpose_ugraph([1-[3,5],2-[4],3-[],4-[5],5-[],6-[]], NL)") ==
             ["NL = [1-[],2-[],3-[1],4-[2],5-[1,4],6-[]]"]

    assert ask(c, "compose([1-[2],2-[3]],[2-[4],3-[1,2,4]],L)") == ["L = [1-[4],2-[1,2,4],3-[]]"]

    assert ask(c, "complement([1-[3,5],2-[4],3-[],4-[1,2,7,5],5-[],6-[],7-[],8-[]], NL)") ==
             [
               "NL = [1-[2,4,6,7,8],2-[1,3,5,6,7,8],3-[1,2,4,5,6,7,8],4-[3,6,8]," <>
                 "5-[1,2,3,4,6,7,8],6-[1,2,3,4,5,7,8],7-[1,2,3,4,5,6,8],8-[1,2,3,4,5,6,7]]"
             ]

    assert ask(c, "transitive_closure([1-[2,3],2-[4,5],4-[6]],L)") ==
             ["L = [1-[2,3,4,5,6],2-[4,5,6],4-[6]]"]

    # wie SWI: auf einem Zyklus erreicht ein Knoten sich selbst
    assert ask(c, "transitive_closure([1-[2],2-[1],3-[1]],L)") == [
             "L = [1-[1,2],2-[1,2],3-[1,2]]"
           ]

    assert ask(c, "symmetric_closure([1-[2],2-[3],3-[]], C)") == ["C = [1-[2],2-[1,3],3-[2]]"]

    assert ask(c, "transitive_reduction([1-[2,3,4],2-[3,4],3-[4],4-[]], R)") ==
             ["R = [1-[2],2-[3],3-[4],4-[]]"]

    assert ask(c, "reduce([1-[2],2-[1,3],3-[4],4-[3],5-[]], R)") ==
             ["R = [[1,2]-[[3,4]],[3,4]-[],[5]-[]]"]

    assert ask(c, "reduce([a-[b],b-[]], R)") == ["R = [[a]-[[b]],[b]-[]]"]
  end

  test "Ordnen, Erreichen, Pfade", c do
    assert ask(c, "top_sort([1-[2], 2-[3], 3-[]], L)") == ["L = [1,2,3]"]
    assert ask(c, "top_sort([a-[b,c], b-[d], c-[d], d-[]], L)") == ["L = [a,c,b,d]"]
    assert ask(c, "top_sort([1-[2], 2-[1]], L)") == []
    assert ask(c, "top_sort([1-[1]], L)") == []
    assert ask(c, "top_sort([1-[2]], L)") == []
    assert ask(c, "top_sort([1-[2], 2-[]], T, L)") |> hd() =~ ~r/L = \[1,2\|_\w+\]|L = \[1,2\|T\]/

    assert ask(c, "connect_ugraph([1-[2],2-[]], S, G)") == ["G = [0-[1,2],1-[2],2-[]], S = 0"]
    assert ask(c, "connect_ugraph([a-[]], S, G)") == ["G = [0-[a],a-[]], S = 0"]
    assert ask(c, "connect_ugraph([], S, G)") == ["G = [], S = 0"]
    assert err(c, "connect_ugraph([_-[]], S, G)") == ["E = instantiation_error"]

    assert ask(c, "reachable(1,[1-[3,5],2-[4],3-[],4-[5],5-[]],V)") == ["V = [1,3,5]"]
    assert ask(c, "reachable(9,[1-[3,5]],V)") == []
    # ein Nachbar, der kein Knoten ist: scheitert (wie SWI und SICStus)
    assert ask(c, "reachable(1,[1-[2]],V)") == []

    g = "[1-[2,3],2-[4],3-[2],4-[]]"
    assert ask(c, "max_path(1, 4, #{g}, P, C)") == ["C = 3, P = [1,3,2,4]"]
    assert ask(c, "max_path(1, 1, #{g}, P, C)") == ["C = 0, P = [1]"]
    # gleich lang: der zuerst gefundene, wie SICStus
    assert ask(c, "max_path(a, d, [a-[b,c],b-[d],c-[d],d-[]], P, C)") == ["C = 2, P = [a,c,d]"]
    assert ask(c, "max_path(4, 1, #{g}, P, C)") == []
    assert ask(c, "max_path(1, 2, [1-[2],2-[1]], P, C)") == []
    assert ask(c, "min_path(1, 4, #{g}, P, C)") == ["C = 2, P = [1,2,4]"]
    assert ask(c, "min_path(4, 1, #{g}, P, C)") == []
    assert ask(c, "min_path(1, 1, #{g}, P, C)") == ["C = 0, P = [1]"]

    assert ask(c, "min_path(1, 5, [1-[2,3],2-[4],3-[4],4-[5],5-[]], P, C)") == [
             "C = 3, P = [1,2,4,5]"
           ]

    assert ask(c, "min_paths(1, #{g}, T)") == ["T = [1-[2,3],2-[4],3-[],4-[]]"]
    assert ask(c, "min_paths(3, #{g}, T)") == ["T = [2-[4],3-[2],4-[]]"]
    assert ask(c, "path(1, #{g}, P)") == ["P = [1,2,4]", "P = [1,3,2,4]"]
    assert ask(c, "path(4, #{g}, P)") == ["P = [4]"]
    assert ask(c, "path(9, #{g}, P)") == []
    # kein Knoten zweimal, auch nicht über eine Schlinge
    assert ask(c, "path(1, [1-[1,2],2-[1]], P)") == ["P = [1,2]"]
    assert ask(c, "path(1, [1-[2],2-[2,3],3-[]], P)") == ["P = [1,2,3]"]
    assert ask(c, "path(1, [1-[2],2-[3],3-[2,4],4-[]], P)") == ["P = [1,2,3,4]"]
    # das letzte Ergebnis ohne Choice Point
    assert ask(c, "path(1, #{g}, P), P = [_,_,_,_], !, true") == ["P = [1,3,2,4]"]
  end

  test "Spannbaum, Cliquen", c do
    assert ask(c, "min_tree([1-[2,3],2-[1,3],3-[1,2,4],4-[3]], T, C)") ==
             ["C = 3, T = [1-[2,3],2-[1],3-[1,4],4-[3]]"]

    assert ask(c, "min_tree([1-[]], T, C)") == ["C = 0, T = [1-[]]"]
    assert ask(c, "min_tree([], T, C)") == []
    assert ask(c, "min_tree([1-[2],2-[1],3-[]], T, C)") == []

    assert ask(c, "max_cliques([1-[2,3],2-[1,3],3-[1,2,4],4-[3],5-[]], Cs)") ==
             ["Cs = [[1,2,3],[3,4],[5]]"]

    assert ask(c, "max_cliques([], Cs)") == ["Cs = []"]
  end

  test "random_ugraph/3", c do
    assert ask(c, "random_ugraph(0.0, 3, G)") == ["G = [1-[],2-[],3-[]]"]
    assert ask(c, "random_ugraph(1.0, 3, G)") == ["G = [1-[2,3],2-[1,3],3-[1,2]]"]
    assert ask(c, "random_ugraph(0.5, 0, G)") == ["G = []"]
    assert err(c, "random_ugraph(1, 3, G)") == ["E = type_error(float,1)"]
    assert err(c, "random_ugraph(1.5, 3, G)") == ["E = domain_error(between(0.0,1.0),1.5)"]
    assert err(c, "random_ugraph(_, 3, G)") == ["E = instantiation_error"]
    assert err(c, "random_ugraph(0.5, -1, G)") == ["E = domain_error(not_less_than_zero,-1)"]
    assert err(c, "random_ugraph(0.5, a, G)") == ["E = type_error(integer,a)"]

    # zufällig, aber ein gültiger Graph ohne Schlingen
    [a] =
      ask(
        c,
        "random_ugraph(0.5, 8, G), edges(G, E), vertices_edges_to_ugraph([1,2,3,4,5,6,7,8], E, G2), (G == G2, \\+ member(X-X, E) -> Ok = ja ; Ok = nein)"
      )

    assert a =~ "Ok = ja"
  end

  test "Fehler", c do
    assert err(c, "vertices_edges_to_ugraph(_, [], G)") == ["E = instantiation_error"]
    assert err(c, "vertices_edges_to_ugraph([], [a], G)") == ["E = type_error(pair,a)"]
    assert err(c, "edges(foo, E)") == ["E = type_error(list,foo)"]
    assert err(c, "edges([a-b], E)") == ["E = type_error(list,b)"]
    assert err(c, "transpose_ugraph([a], E)") == ["E = type_error(pair,a)"]
    assert err(c, "add_edges([], [a-b|_], E)") == ["E = instantiation_error"]
  end

  test "wgraphs", c do
    assert ask(c, "wgraphs:vertices_edges_to_wgraph([x], [a-(b-3),a-(b-1),b-(c-2)], G)") ==
             ["G = [a-[b-1],b-[c-2],c-[],x-[]]"]

    g = "[a-[b-1,c-5],b-[c-1],c-[]]"
    assert ask(c, "wgraphs:edges(#{g}, E)") == ["E = [a-(b-1),a-(c-5),b-(c-1)]"]
    assert ask(c, "wgraphs:vertices(#{g}, E)") == ["E = [a,b,c]"]
    assert ask(c, "wgraphs:neighbours(a, #{g}, E)") == ["E = [b-1,c-5]"]
    assert ask(c, "wgraphs:wgraph_to_ugraph(#{g}, U)") == ["U = [a-[b,c],b-[c],c-[]]"]
    assert ask(c, "wgraphs:ugraph_to_wgraph([a-[b],b-[]], W)") == ["W = [a-[b-1],b-[]]"]
    assert ask(c, "wgraphs:ugraph_to_wgraph([a-[c]], #{g}, W)") == ["W = [a-[c-5]]"]
    assert ask(c, "wgraphs:ugraph_to_wgraph([a-[x]], #{g}, W)") == []
    # doppelt: das kleinere Gewicht bleibt
    assert ask(c, "wgraphs:add_edges([a-[b-3]], [a-(b-1), c-(a-2)], G)") == [
             "G = [a-[b-1],b-[],c-[a-2]]"
           ]

    assert ask(c, "wgraphs:add_edges([a-[b-1]], [a-(b-3)], G)") == ["G = [a-[b-1],b-[]]"]
    assert ask(c, "wgraphs:del_edges(#{g}, [a-(b-_)], G)") == ["G = [a-[c-5],b-[c-1],c-[]]"]
    assert ask(c, "wgraphs:del_vertices(#{g}, [b], G)") == ["G = [a-[c-5],c-[]]"]
    assert ask(c, "wgraphs:add_vertices(#{g}, [d], G)") == ["G = [a-[b-1,c-5],b-[c-1],c-[],d-[]]"]
    assert ask(c, "wgraphs:transpose_wgraph(#{g}, T)") == ["T = [a-[],b-[a-1],c-[a-5,b-1]]"]
    assert ask(c, "wgraphs:symmetric_closure([a-[b-3],b-[a-1]], T)") == ["T = [a-[b-1],b-[a-1]]"]
    assert ask(c, "wgraphs:transitive_closure(#{g}, T)") == ["T = [a-[b-1,c-2],b-[c-1],c-[]]"]

    assert ask(c, "wgraphs:transitive_closure([a-[a-7,b-1],b-[a-2]], T)") ==
             ["T = [a-[a-7,b-1],b-[a-2]]"]

    assert ask(c, "wgraphs:top_sort(#{g}, L)") == ["L = [a,b,c]"]
    assert ask(c, "wgraphs:reachable(b, #{g}, L)") == ["L = [b,c]"]
    assert ask(c, "wgraphs:min_path(a, c, #{g}, P, C)") == ["C = 2, P = [a,b,c]"]
    assert ask(c, "wgraphs:max_path(a, c, #{g}, P, C)") == ["C = 5, P = [a,c]"]
    assert ask(c, "wgraphs:min_paths(a, #{g}, T)") == ["T = [a-[b-1],b-[c-1],c-[]]"]
    assert ask(c, "wgraphs:path(a, #{g}, P)") == ["P = [a,b,c]", "P = [a,c]"]

    assert ask(c, "wgraphs:reduce([a-[b-1],b-[a-2,c-3],c-[]], R)") == [
             "R = [[a,b]-[[c]-3],[c]-[]]"
           ]

    assert ask(c, "wgraphs:min_tree([a-[b-1,c-5],b-[a-1,c-1],c-[a-5,b-1]], T, C)") ==
             ["C = 2, T = [a-[b-1],b-[a-1,c-1],c-[b-1]]"]

    assert ask(c, "wgraphs:min_tree([a-[b-1],b-[a-1],c-[]], T, C)") == []
    # gleiche Gewichte: Reihenfolge wie SICStus (Kante vom größeren Knoten)
    assert ask(
             c,
             "wgraphs:min_tree([a-[d-1,e-1],b-[c-1,e-1],c-[b-1,d-1],d-[a-1,c-1],e-[a-1,b-1]], T, C)"
           ) ==
             ["C = 4, T = [a-[d-1,e-1],b-[c-1],c-[b-1,d-1],d-[a-1,c-1],e-[a-1]]"]

    assert ask(c, "wgraphs:min_tree([a-[b-1,c-1],b-[a-1,c-1],c-[a-1,b-1,d-5],d-[c-5]], T, C)") ==
             ["C = 7, T = [a-[b-1,c-1],b-[a-1],c-[a-1,d-5],d-[c-5]]"]

    # Gewicht 0: der Pfad bleibt (SICStus verliert ihn)
    assert ask(c, "wgraphs:max_path(a, b, [a-[b-0],b-[]], P, C)") == ["C = 0, P = [a,b]"]

    assert ask(c, "wgraphs:min_paths(a, [a-[b-2,c-5],b-[c-2],c-[]], T)") == [
             "T = [a-[b-2],b-[c-2],c-[]]"
           ]

    assert ask(c, "wgraphs:random_wgraph(1.0, 2, 1, G)") == ["G = [1-[2-1],2-[1-1]]"]

    assert err(c, "wgraphs:random_wgraph(1.0, 2, 0, G)") == [
             "E = domain_error(not_less_than_one,0)"
           ]

    assert err(c, "wgraphs:edges([a-[b]], E)") == ["E = type_error(pair,b)"]
    assert err(c, "wgraphs:edges([a-[b-x]], E)") == ["E = type_error(number,x)"]
  end

  # Zufällige Graphen: Knoten verschiedener Art (Zahlen, Floats, Atome,
  # Strukturen), mit Schlingen
  defp random_graph(n, p, opts \\ []) do
    vs =
      for i <- 1..n do
        case rem(i, 4) do
          0 -> "f(#{i})"
          1 -> "#{i}"
          2 -> "v#{i}"
          3 -> "#{i}.0"
        end
      end

    es =
      for {a, i} <- Enum.with_index(vs),
          {b, j} <- Enum.with_index(vs),
          Keyword.get(opts, :loops, true) or i != j,
          not Keyword.get(opts, :dag, false) or i < j,
          :rand.uniform() < p,
          do: {a, b, :rand.uniform(9)}

    {vs, es}
  end

  defp ug({vs, es}, name \\ "G"),
    do:
      "vertices_edges_to_ugraph([#{Enum.join(vs, ",")}], [#{Enum.map_join(es, ",", fn {a, b, _} -> "#{a}-#{b}" end)}], #{name})"

  defp wg({vs, es}, name),
    do:
      "wgraphs:vertices_edges_to_wgraph([#{Enum.join(vs, ",")}], [#{Enum.map_join(es, ",", fn {a, b, w} -> "#{a}-(#{b}-#{w})" end)}], #{name})"

  # gleiches Ergebnis wie SWIs Prolog-Fassung (auch gleich scheitern)
  test "dieselben Ergebnisse wie SWI (zufällige Graphen)", c do
    :rand.seed(:exsss, {7, 8, 9})

    for _ <- 1..40 do
      {vs, _} = g = random_graph(:rand.uniform(7), :rand.uniform() * 0.6)
      h = random_graph(:rand.uniform(7), :rand.uniform() * 0.6)
      v = Enum.random(vs)
      setup = "#{ug(g)}, #{ug(h, "H")}"

      for call <- [
            "M:transpose_ugraph(G, X)",
            "M:compose(G, H, X)",
            "M:complement(G, X)",
            "M:transitive_closure(G, X)",
            "M:top_sort(G, X)",
            "M:top_sort(G, t, X)",
            "M:ugraph_union(G, H, X)",
            "M:edges(G, X)",
            "M:vertices(G, X)",
            "M:reachable(#{v}, G, X)",
            "M:neighbours(#{v}, G, X)",
            "M:add_vertices(G, [#{v}, z], X)",
            "(M:edges(H, E), M:add_edges(G, E, X))",
            "(M:edges(H, E), M:del_edges(G, E, X))",
            "(M:edges(G, E), M:vertices(H, V), M:vertices_edges_to_ugraph(V, E, X))"
          ] do
        ours = call |> String.replace("M:", "ugraphs:") |> String.replace(~r/\b([XEV])\b/, "\\1o")

        theirs =
          call |> String.replace("M:", "ugraphs_swi:") |> String.replace(~r/\b([XEV])\b/, "\\1s")

        [a] =
          ask(
            c,
            "#{setup}, (#{ours} -> R1 = ja(Xo) ; R1 = nein), (#{theirs} -> R2 = ja(Xs) ; R2 = nein), (R1 == R2 -> Ok = ja ; Ok = nein)",
            1
          )

        assert a =~ "Ok = ja", "#{call} mit #{setup}: #{a}"
      end
    end
  end

  # Eigenschaften der SICStus-Prädikate auf zufälligen Graphen
  test "Pfade, Komponenten, Cliquen, Bäume: Eigenschaften", c do
    :rand.seed(:exsss, {1, 2, 3})

    for _ <- 1..25 do
      {vs, _} = g = random_graph(:rand.uniform(6), :rand.uniform() * 0.5)
      [a, b] = [Enum.random(vs), Enum.random(vs)]
      w = wg(g, "W")

      checks = [
        # kürzester Pfad: gleich lang wie der kürzeste einfache Pfad
        "#{w}, wgraphs:wgraph_to_ugraph(W, G), (#{a} == #{b} -> true ; (min_path(#{a}, #{b}, G, P, L) -> length(P, N), L =:= N - 1, wgraphs:ugraph_to_wgraph(G, W1), kuerzest(W1, #{a}, #{b}, L) ; \\+ wpfad(W, #{a}, #{b}, _)))",
        "#{w}, (#{a} == #{b} -> true ; wgraphs:min_path(#{a}, #{b}, W, _, C) -> kuerzest(W, #{a}, #{b}, C) ; \\+ wpfad(W, #{a}, #{b}, _))",
        # gewichteter Abschluss: kürzeste Wege, eigene Schlinge wie vorher
        "#{w}, wgraphs:transitive_closure(W, T), forall(member(X-Ns, T), forall(member(Y-C, Ns), (X == Y -> member(X-Ns0, W), memberchk(X-C, Ns0) ; kuerzest(W, X, Y, C)))), forall((member(X-_, W), member(Y-_, W), X \\== Y, wpfad(W, X, Y, _)), (member(X-Ns, T), memberchk(Y-_, Ns)))",
        # Komponenten: gleich, wenn gegenseitig erreichbar
        "#{w}, wgraphs:wgraph_to_ugraph(W, G), reduce(G, R), forall((member(X-_, G), member(Y-_, G)), ((member(K-_, R), memberchk(X, K), memberchk(Y, K)) -> (reachable(X, G, RX), memberchk(Y, RX), reachable(Y, G, RY), memberchk(X, RY)) ; \\+ (reachable(X, G, RX), memberchk(Y, RX), reachable(Y, G, RY), memberchk(X, RY))))",
        # maximale Cliquen: alle, durch Aufzählen
        "#{w}, wgraphs:wgraph_to_ugraph(W, G0), symmetric_closure(G0, G), max_cliques(G, Cs), alle_cliquen(G, Cs2), Cs == Cs2"
      ]

      dag = random_graph(:rand.uniform(6), 0.5, dag: true)
      {dvs, _} = dag
      [x, y] = [Enum.random(dvs), Enum.random(dvs)]

      checks =
        checks ++
          [
            # längster Pfad in einem DAG: der längste einfache Pfad
            "#{wg(dag, "W")}, (wgraphs:max_path(#{x}, #{y}, W, P, C) -> (#{x} == #{y} -> C == 0 ; laengst(W, #{x}, #{y}, C)) ; #{x} \\== #{y}, \\+ wpfad(W, #{x}, #{y}, _))",
            "#{wg(dag, "W")}, wgraphs:wgraph_to_ugraph(W, G), (max_path(#{x}, #{y}, G, P, C) -> length(P, N), C =:= N - 1, (#{x} == #{y} -> true ; wgraphs:ugraph_to_wgraph(G, W1), laengst(W1, #{x}, #{y}, C)) ; #{x} \\== #{y})",
            # transitive Reduktion eines DAG: gleicher Abschluss, keine
            # Kante überflüssig
            "#{ug(dag)}, transitive_reduction(G, R), transitive_closure(G, T), transitive_closure(R, T), forall((edges(R, Es), member(E, Es)), (del_edges(R, [E], R1), transitive_closure(R1, T1), T1 \\== T))",
            # Spannbaum: symmetrisch, n-1 Kanten, alles erreichbar
            "#{ug(g)}, symmetric_closure(G, S0), del_edges(S0, [], S), (min_tree(S, T, C) -> symmetric_closure(T, T), edges(T, E), length(E, N2), N2 =:= 2 * C, vertices(S, Vs), length(Vs, NV), C =:= NV - 1, Vs = [V0|_], reachable(V0, T, Vs) ; vertices(S, [V0|Vs1]), reachable(V0, S, R), R \\== [V0|Vs1] ; S == [])"
          ]

      for q <- checks do
        assert ask(c, q, 1) != [], q
      end
    end
  end

  test "nur nach use_module sichtbar", c do
    PrologEx.put_db(%{})
    assert err(c, "top_sort([], _)") == ["E = existence_error(procedure,top_sort/2)"]
    assert ask(c, "use_module(library(ugraphs)), top_sort([], L)") == ["L = []"]
    assert ask(c, "use_module(library(wgraphs), []), wgraphs:top_sort([], L)") == ["L = []"]
  end
end
