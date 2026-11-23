defmodule PrologEx.ConcurrentChaosTest do
  # library(concurrent) mit erzwungenen Verzögerungen (PrologEx.Chaos): an
  # jeder markierten Stelle (vor dem Senden, vor dem Empfang, beim Beenden)
  # wartet ein Prozess zufällig, so kommen Nachrichten in Reihenfolgen an,
  # die sonst selten sind. Jede Anfrage muss dieselbe Antwort geben wie ohne
  # Verzögerungen, und danach ist der Aufrufer sauber (keine Nachrichten,
  # trap_exit wie vorher, keine :conc_*-Schlüssel, keine Arbeiter).
  use ExUnit.Case, async: false
  alias PrologEx.{Chaos, Reader, TableCase}

  @prog """
  sq(X, Y) :- Y is X * X.
  spin(_) :- between(1, inf, _), fail.
  even(X) :- 0 is X mod 2.
  cmp3(X, O) :- compare(O, X, 3).
  add(X, A0, A) :- A is A0 + X.
  boom(X) :- ( X =:= 7 -> throw(kaputt) ; true ).
  inner(X, Y) :- concurrent_maplist(sq, [X, X], Y).
  queens(N, Qs) :- length(Qs, N), Qs ins 1..N, safe(Qs).
  safe([]).
  safe([Q|Qs]) :- no_attack(Qs, Q, 1), safe(Qs).
  no_attack([], _, _).
  no_attack([Q1|Qs], Q, D) :- Q #\\= Q1, abs(Q - Q1) #\\= D, D1 is D + 1, no_attack(Qs, Q, D1).
  ph(N, Vs) :- N1 is N + 1, length(Vs, N1), Vs ins 1..N, all_different(Vs).
  lr([X|Ys]) :- X in 1..2, length(Ys, 9), Ys ins 1..9, all_different(Ys),
      no_nine(Ys, X).
  no_nine([], _).
  no_nine([Y|Ys], X) :- X #= 2 #==> Y #\\= 9, no_nine(Ys, X).
  % unter A = 1 links (Y = 1) eine lange Suche ohne Lösung, rechts (Y = 2)
  % schnell eine; A = 2 scheitert gleich: der freie Arbeiter bekommt den
  % Zweig Y = 2 abgegeben, findet die Lösung, der Geber sucht noch (Schnitt)
  c3([A,Y|Zs]) :- A in 1..2, Y in 1..2, length(Zs, 8), Zs ins 1..8, all_different(Zs),
      Zs = [Z1,Z2|_], A #= 2 #==> Z1 #= Z2, eight_off(Zs, Y).
  eight_off([], _).
  eight_off([Z|Zs], Y) :- Y #= 1 #==> Z #\\= 8, eight_off(Zs, Y).
  knap(Vs, Z) :- Vs = [A,B,C,D], Vs ins 0..6, 3*A + 4*B + 5*C + 7*D #=< 23,
      Z #= 4*A + 5*B + 7*C + 9*D.
  """

  # Anfragen mit eindeutiger Antwort (ohne Verzögerungen ermittelt)
  @queries [
    "numlist(1, 40, Ns), concurrent_maplist(sq, Ns, L)",
    "numlist(1, 40, Ns), concurrent_aggregate_all(sum(Y), member(X, Ns), sq(X, Y), S, [chunk(1), threads(3)])",
    "findall(X-Y, concurrent_and(member(X, [1, 2, 3]), member(Y, [a, b])), L)",
    "concurrent_findall(X, [member(X, [1, 2]), fail, X = z], Bags)",
    "first_solution(X, [fail, X = a, (sleep(0.2), X = b)], [on_fail(continue)])",
    "first_solution(X, [fail, throw(x), X = c], [on_fail(continue), on_error(continue)])",
    "concurrent_forall(between(1, 40, X), X > 0, [threads(3)])",
    "\\+ concurrent_forall(between(1, 40, X), X < 39, [threads(3)])",
    "concurrent(3, [X = 1, Y = 2, Z = 3, W = 4], [])",
    "concurrent_aggregate_all(count, between(1, 300, X), even(X), C)",
    "concurrent_aggregate_all(bag(Y), member(X, [3,1,2,5,4]), sq(X, Y), B)",
    "concurrent_aggregate_all(max(X), member(X, [3,1,9,5,4]), true, M)",
    "numlist(1, 30, Ns), concurrent_include(even, Ns, E)",
    "numlist(1, 9, Ns), concurrent_partition(cmp3, Ns, L, E, G)",
    "numlist(1, 50, Ns), concurrent_foldl(add, Ns, 0, S)",
    "numlist(1, 20, Ns), catch(concurrent_maplist(boom, Ns), E, true)",
    "concurrent_maplist(inner, [1, 2, 3, 4], L)",
    "queens(8, Qs), concurrent_labeling([], Qs, [serial(0), parts(8)])",
    "queens(6, Qs), concurrent_labelings([], Qs, L, [serial(0)])",
    "queens(7, Qs), concurrent_labelings([], Qs, L, [serial(0.001), parts(4)]), length(L, N)",
    "lr(L0), once(labeling([], L0)), lr(L), concurrent_labeling([], L, [serial(0.001), parts(2)]), L == L0",
    "c3(L), concurrent_labeling([], L, [serial(0), parts(2)]), L = [1, 2|_]",
    "knap(Vs, Z), concurrent_labeling([max(Z)], Vs, [serial(0)])",
    "knap(Vs, Z), concurrent_labeling([max(Z)], Vs, [serial(0.0005), parts(6)])",
    "ph(7, Vs), \\+ concurrent_labeling([], Vs, [serial(0)])"
  ]

  # Abbrüche: die Antwort hängt an der Zeit, nur der Zustand danach zählt
  @aborts [
    "ph(9, Vs), catch(call_with_time_limit(0.01, concurrent_labeling([], Vs, [serial(0), parts(16)])), E, true)",
    "ph(9, Vs), catch(call_with_time_limit(0.02, concurrent_labelings([], Vs, _, [serial(0)])), E, true)",
    "catch(call_with_time_limit(0.01, concurrent_forall(between(1, 8, X), spin(X), [threads(2)])), E, true)",
    "catch(call_with_time_limit(0.01, first_solution(X, [spin(X), spin(X)], [])), E, true)"
  ]

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    db = TableCase.db(r, ~w(clpz clpz_concurrent concurrent between lists time swi))
    {db, []} = PrologEx.Consult.load(db, Reader.read_terms(r, @prog))
    {:ok, reader: r, db: db, ops: Process.get(:prolog_ex_ops)}
  end

  setup do
    on_exit(fn -> Chaos.disable() end)
  end

  defp run(c, q) do
    Task.async(fn ->
      Reader.put_current(c.reader)
      Process.put(:prolog_ex_ops, c.ops)
      {_, ans} = TableCase.run(c.reader, c.db, q)
      {:messages, msgs} = Process.info(self(), :messages)
      {:trap_exit, trap} = Process.info(self(), :trap_exit)
      keys = for {k, _} <- Process.get(), conc_key?(k), do: k
      {ans, %{messages: msgs, trap_exit: trap, keys: keys}}
    end)
    |> Task.await(60_000)
  end

  defp conc_key?({k, _}) when is_atom(k), do: String.starts_with?(Atom.to_string(k), "conc_")
  defp conc_key?(_), do: false

  defp clean!(state, q) do
    assert state.messages == [], q
    assert state.trap_exit == false, q
    assert state.keys == [], q
  end

  defp gone! do
    left =
      Enum.find_value(1..100, fn _ ->
        ws =
          for p <- Process.list(),
              {:dictionary, d} <- [Process.info(p, :dictionary)],
              Keyword.get(d, :prolog_ex_conc_child) == true,
              do: p

        if ws == [], do: :ok, else: Process.sleep(10) && nil
      end)

    assert left == :ok, "Arbeiter übrig"
  end

  # CHAOS_Q=Text: nur die Anfragen, die Text enthalten; CHAOS_ONLY=t1,t2:
  # nur diese Stellen (zum Eingrenzen)
  defp baseline(c) do
    qs =
      case System.get_env("CHAOS_Q") do
        nil -> @queries
        f -> Enum.filter(@queries, &String.contains?(&1, f))
      end

    for q <- qs do
      {ans, state} = run(c, q)
      assert match?({:answers, [_ | _]}, ans), q
      clean!(state, q)
      {q, ans}
    end
  end

  defp chaos_rounds(c, base, seeds, opts) do
    for seed <- seeds do
      only =
        case System.get_env("CHAOS_ONLY") do
          nil -> []
          t -> [only: Enum.map(String.split(t, ","), &String.to_atom/1)]
        end

      Chaos.enable([seed: seed] ++ only ++ opts)

      for {q, expect} <- base do
        {ans, state} = run(c, q)
        assert ans == expect, "Seed #{seed}: #{q}"
        clean!(state, "Seed #{seed}: #{q}")
      end

      for q <- @aborts do
        {ans, state} = run(c, q)
        assert {:answers, [_]} = ans, "Seed #{seed}: #{q}"
        clean!(state, "Seed #{seed}: #{q}")
      end

      hits = Chaos.disable()
      gone!()
      hits
    end
    |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _, a, b -> a + b end))
  end

  test "die Stellen sind im Test-Build da" do
    assert Chaos.compiled?()
  end

  test "Antworten wie ohne Verzögerungen, danach sauber", c do
    base = baseline(c)
    hits = chaos_rounds(c, base, 1..3, p: 0.2, max_ms: 2)
    # jede Stelle wenigstens einmal verzögert – bis auf c_steal_cut: ein
    # abgegebener Teil findet eine Lösung, während sein Geber noch sucht;
    # in Versuchen mit Suchen unter einer Sekunde kam das nie vor (der Geber
    # gibt den tiefsten alten Knoten ab, kaum je der mit der Lösung)
    assert Chaos.tags() -- [:c_steal_cut | Map.keys(hits)] == [], inspect(hits)
  end

  @tag :slow
  @tag timeout: 900_000
  test "viele Runden, auch lange Verzögerungen", c do
    base = baseline(c)
    chaos_rounds(c, base, 1..15, p: 0.3, max_ms: 2)
    chaos_rounds(c, base, 16..20, p: 0.1, max_ms: 20)
    chaos_rounds(c, base, 21..25, p: 0.6, max_ms: 1)
  end
end
