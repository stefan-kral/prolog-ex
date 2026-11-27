defmodule PrologEx.JitFuzz do
  @moduledoc false
  # Zufällige kleine Programme für den Differenztest JIT ↔ Interpreter.
  # p0 … pk mit vorgegebenen Modi und Typen (Zahl, Liste von Zahlen,
  # beliebig): Eingaben werden im Kopf zerlegt, Ausgaben im Rumpf gebunden –
  # durch is, =, ( -> ; ), functor/arg, compare/3 und Aufrufe von sich
  # selbst (auf kleineren Teiltermen oder N-1 hinter N > 0) und der
  # früheren; dazwischen Vergleiche, Typtests, ==, @<, \+, Schnitt, fail.
  # Je Programm ein Anteil Rauschen (irgendeine Variable statt einer
  # passenden, gebundene Ausgaben beim Aufruf, Ausgaben ungebunden), damit
  # auch Abweisen, Aufgeben und Typkonflikte vorkommen. Anfragen meist nach
  # Modi und Typen, teils mit freien Eingaben, gebundenen oder teilweise
  # gebundenen Ausgaben, unter einer Inferenzgrenze (auch die muss an
  # derselben Stelle greifen).

  def gen(seed) do
    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 5})
    Process.put(:fz_wild, Enum.random([0.0, 0.0, 0.03, 0.1]))
    k = Enum.random(2..5)

    preds =
      for i <- 0..(k - 1) do
        sig =
          for _ <- 1..Enum.random(1..4) do
            {if(:rand.uniform() < 0.6, do: :in, else: :out),
             Enum.random([:int, :int, :list, :any])}
          end

        {"p#{i}", sig}
      end

    clauses =
      for {{n, sig}, i} <- Enum.with_index(preds), _ <- 1..Enum.random(1..4) do
        clause(n, sig, Enum.take(preds, i))
      end

    queries = for {n, sig} <- preds, _ <- 1..4, do: query(n, sig)
    {Enum.join(clauses, "\n") <> "\n", queries}
  end

  defp w(choices) do
    choices = Enum.filter(choices, fn {wt, _} -> wt > 0 end)
    total = choices |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    r = :rand.uniform() * total

    Enum.reduce_while(choices, r, fn {wt, f}, r ->
      if r < wt, do: {:halt, {:ok, f.()}}, else: {:cont, r - wt}
    end)
    |> case do
      {:ok, x} -> x
      _ -> elem(List.last(choices), 1).()
    end
  end

  defp wild?, do: :rand.uniform() < Process.get(:fz_wild)
  defp get(k), do: Process.get(k, [])
  defp add(k, v), do: Process.put(k, [v | get(k)])

  defp fresh do
    n = Process.get(:fz_n, 0)
    Process.put(:fz_n, n + 1)
    v = "V#{n}"
    add(:fz_all, v)
    v
  end

  # gebundene Variablen mit Typ
  defp known(v, t) do
    add(:fz_known, {v, t})
    v
  end

  defp small(v, t) do
    add(:fz_small, {v, t})
    known(v, t)
  end

  defp of(k, t), do: for({v, u} <- get(k), t == :any or u == t, do: v)

  # eine gebundene Variable vom Typ t (mit Rauschen: irgendeine), sonst ein
  # Wert vom Typ t
  defp kv(t) do
    cond do
      wild?() -> Enum.random([fresh() | get(:fz_all)])
      of(:fz_known, t) == [] -> lit(t)
      true -> Enum.random(of(:fz_known, t))
    end
  end

  defp int, do: Integer.to_string(Enum.random(0..3))
  defp atm, do: Enum.random(~w(a b []))
  defp ival, do: w([{3, fn -> kv(:int) end}, {1, &int/0}])

  defp lit(:int), do: int()
  defp lit(:list), do: Enum.random(["[]", "[#{int()}]", "[#{int()},#{int()}]"])
  defp lit(:any), do: w([{1, &int/0}, {1, &atm/0}, {1, fn -> "f(#{int()})" end}])

  defp head_in(:int) do
    w([{4, fn -> known(fresh(), :int) end}, {1, &int/0}, {0.3, fn -> kv(:int) end}])
  end

  defp head_in(:list) do
    w([
      {2, fn -> known(fresh(), :list) end},
      {1, fn -> "[]" end},
      {3,
       fn ->
         "[#{w([{3, fn -> small(fresh(), :int) end}, {1, &int/0}])}|#{small(fresh(), :list)}]"
       end}
    ])
  end

  defp head_in(:any) do
    w([
      {3, fn -> known(fresh(), :any) end},
      {1, &int/0},
      {1, &atm/0},
      {1, fn -> "[#{small(fresh(), :int)}|#{small(fresh(), :list)}]" end},
      {1, fn -> "#{Enum.random(~w(f s))}(#{small(fresh(), :any)})" end},
      {1,
       fn ->
         "g(#{small(fresh(), :any)}, #{w([{2, fn -> small(fresh(), :int) end}, {1, &int/0}])})"
       end}
    ])
  end

  defp out_var(t), do: fresh() |> tap(&add(:fz_out, {&1, t}))

  defp head_out(:int), do: w([{6, fn -> out_var(:int) end}, {1, &int/0}])

  defp head_out(:list),
    do:
      w([
        {5, fn -> out_var(:list) end},
        {1, fn -> "[]" end},
        {1, fn -> "[#{out_var(:int)}|#{out_var(:list)}]" end}
      ])

  defp head_out(:any),
    do: w([{5, fn -> out_var(:any) end}, {1, &atm/0}, {1, fn -> "f(#{out_var(:any)})" end}])

  defp expr(d \\ 0) do
    if d > 1 or :rand.uniform() < 0.4 do
      ival()
    else
      w([
        {2, fn -> "#{expr(d + 1)} + #{expr(d + 1)}" end},
        {1, fn -> "#{expr(d + 1)} - #{expr(d + 1)}" end},
        {1, fn -> "#{expr(d + 1)} * #{int()}" end}
      ])
    end
  end

  # ein Term vom Typ t aus gebundenen Variablen
  defp term(:int), do: w([{1, &ival/0}])

  defp term(:list) do
    w([
      {2, fn -> kv(:list) end},
      {1, fn -> "[]" end},
      {2, fn -> "[#{ival()}|#{kv(:list)}]" end}
    ])
  end

  defp term(:any) do
    w([
      {2, fn -> kv(:any) end},
      {1, &int/0},
      {1, &atm/0},
      {1, fn -> term(:list) end},
      {1, fn -> "f(#{kv(:any)})" end},
      {1, fn -> "g(#{kv(:any)}, #{ival()})" end}
    ])
  end

  defp simple do
    w([
      {3, fn -> "#{ival()} #{Enum.random(~w(< =< > >= =:= =\\=))} #{ival()}" end},
      {1,
       fn ->
         "#{Enum.random(~w(integer atom var nonvar atomic compound is_list number))}(#{kv(:any)})"
       end},
      {1, fn -> "#{kv(:any)} #{Enum.random(~w(== \\== @< @>=))} #{term(:any)}" end},
      {0.3, fn -> "#{kv(:any)} = #{term(:any)}" end}
    ])
  end

  # Argumente eines Aufrufs nach Modi und Typen des Gerufenen; self:
  # Rekursion auf kleineren Teiltermen (sonst N-1 hinter N > 0, [] für
  # Listen)
  defp call_args(sig, self) do
    {pre, args} =
      Enum.map_reduce(sig, [], fn
        {:in, t}, acc when self ->
          case of(:fz_small, t) do
            [] when t == :list ->
              {"", ["[]" | acc]}

            [] ->
              x = kv(:int)
              y = fresh()
              known(y, :int)
              {"#{x} > 0, #{y} is #{x} - 1, ", [y | acc]}

            s ->
              {"", [Enum.random(s) | acc]}
          end

        {:in, t}, acc ->
          {"", [term(t) | acc]}

        {:out, t}, acc ->
          if wild?(), do: {"", [kv(t) | acc]}, else: {"", [known(fresh(), t) | acc]}
      end)

    {Enum.join(pre), Enum.reverse(args)}
  end

  defp call(n, sig, self) do
    {pre, args} = call_args(sig, self)
    pre <> "#{n}(#{Enum.join(args, ", ")})"
  end

  defp bind(v, :int), do: "#{v} is #{expr()}"
  defp bind(v, t), do: "#{v} = #{term(t)}"

  defp goal(n, sig, callees) do
    w([
      {2,
       fn ->
         v = fresh()
         g = bind(v, :int)
         known(v, :int)
         g
       end},
      {3, &simple/0},
      {1, fn -> "!" end},
      {2.5, fn -> call(n, sig, true) end},
      {if(callees == [], do: 0, else: 4),
       fn ->
         {m, s} = Enum.random(callees)
         call(m, s, false)
       end},
      {1,
       fn ->
         t = Enum.random([:list, :any])
         v = fresh()
         g = bind(v, t)
         known(v, t)
         g
       end},
      {0.5, fn -> "\\+ #{simple()}" end},
      {0.5, fn -> "( #{simple()} -> #{simple()} ; #{simple()} )" end},
      {0.8,
       fn ->
         t = Enum.random([:int, :list, :any])
         v = fresh()
         g = "( #{simple()} -> #{bind(v, t)} ; #{bind(v, t)} )"
         known(v, t)
         g
       end},
      {0.4,
       fn ->
         x = kv(:any)
         [a, b] = [fresh(), fresh()]
         known(a, :any)
         known(b, :int)
         "functor(#{x}, #{a}, #{b})"
       end},
      {0.4,
       fn ->
         x = kv(:any)
         v = fresh()
         known(v, :any)
         "arg(#{Enum.random(1..2)}, #{x}, #{v})"
       end},
      {0.3,
       fn ->
         t = term(:any)
         x = kv(:any)
         v = fresh()
         known(v, :any)
         "compare(#{v}, #{x}, #{t})"
       end},
      {0.1, fn -> "fail" end}
    ])
  end

  defp clause(n, sig, callees) do
    for k <- [:fz_n, :fz_all, :fz_known, :fz_small, :fz_out], do: Process.delete(k)

    head =
      "#{n}(#{Enum.map_join(sig, ", ", fn
        {:in, t} -> head_in(t)
        {:out, t} -> head_out(t)
      end)})"

    m = Enum.random([0, 1, 1, 2, 2, 3, 4])
    body = if m == 0, do: [], else: for(_ <- 1..m, do: goal(n, sig, callees))

    # nicht gebundene Ausgaben am Ende binden
    binds =
      for {v, t} <- Enum.reverse(get(:fz_out)),
          v not in Enum.map(get(:fz_known), &elem(&1, 0)),
          not wild?() do
        g = bind(v, t)
        known(v, t)
        g
      end

    case body ++ binds do
      [] -> head <> "."
      gs -> head <> " :- " <> Enum.join(gs, ", ") <> "."
    end
  end

  defp glist,
    do:
      "[" <>
        Enum.map_join(1..Enum.random(0..4)//1, ",", fn _ -> gnum() end) <>
        "]"

  # eine Zahl für Anfragen, ab und zu ein Float (ganzzahlig übersetzter
  # Code weist ab oder gibt auf)
  defp gnum,
    do: if(:rand.uniform() < 0.08, do: "#{Enum.random(0..5)}.5", else: "#{Enum.random(0..5)}")

  defp gterm(:int), do: gnum()
  defp gterm(:list), do: glist()
  defp gterm(:any), do: gterm_any(0)

  defp gterm_any(d) do
    w([
      {3, fn -> gterm(:int) end},
      {1, &atm/0},
      {2, &glist/0},
      {if(d < 2, do: 1, else: 0), fn -> "#{Enum.random(~w(f s))}(#{gterm_any(d + 1)})" end},
      {if(d < 2, do: 1, else: 0), fn -> "g(#{gterm_any(d + 1)}, #{gterm_any(d + 1)})" end}
    ])
  end

  defp query(n, sig) do
    for k <- [:fz_n, :fz_all], do: Process.delete(k)

    args =
      Enum.map_join(sig, ", ", fn
        {:in, t} ->
          w([
            {8, fn -> gterm(t) end},
            {0.5, fn -> gterm(:any) end},
            {0.7, &fresh/0},
            {0.4, fn -> "[#{fresh()}|#{fresh()}]" end}
          ])

        {:out, t} ->
          w([
            {8, &fresh/0},
            {1, fn -> gterm(t) end},
            {0.7, fn -> "[#{fresh()}, #{fresh()}|#{fresh()}]" end}
          ])
      end)

    # die ersten Antworten (TableCase: 5), je höchstens 20000 Inferenzen; R
    # ohne ! / true (übersetzter Code hinterlässt keine Choice Points),
    # und die Inferenzen bis zur Antwort (I; gleich wie im Interpreter)
    "statistics(inferences, _I0), " <>
      "catch((call_with_inference_limit(#{n}(#{args}), 20000, _R), " <>
      "(_R == inference_limit_exceeded -> R = _R ; R = ok)), error(E, _), true), " <>
      "statistics(inferences, _I1), I is _I1 - _I0"
  end
end

defmodule PrologEx.JitFuzzTest do
  # Differenztest: dieselben zufälligen Programme mit JIT (übersetzt beim
  # ersten Aufruf) und ohne – Antworten, Fehler, Inferenzen und
  # Inferenzgrenzen gleich (bis auf den einen Unterschied, same/2).
  #   FUZZ_N=2000 FUZZ_SEED=7 mix test test/jit_fuzz_test.exs
  # (Vorgabe 60 Programme ab einem zufälligen Startwert; der Startwert
  # einer Abweichung steht in der Meldung)
  use ExUnit.Case, async: false
  alias PrologEx.{JitFuzz, Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup do
    PrologEx.Flags.set("jit_threshold", 1)
    PrologEx.Flags.set("jit", {:atom, "true"})
    on_exit(fn -> PrologEx.Flags.set("jit", {:atom, "true"}) end)
    :ok
  end

  # Antworten ohne I, und die I je Antwort
  defp split_i({out, {:answers, as}}) do
    {is, rest} =
      as
      |> Enum.map(fn s ->
        case Regex.run(~r/(?:^|, )I = (\d+)/, s) do
          [m, n] -> {String.to_integer(n), String.replace(s, m, "", global: false)}
          nil -> {nil, s}
        end
      end)
      |> Enum.unzip()

    {{out, {:answers, rest}}, is}
  end

  defp split_i(r), do: {r, []}

  # Antworten und Fehler gleich, die Inferenzen gleich (:eq) – oder
  # weniger (:fewer): ein deterministisch übersetztes Prädikat probiert
  # beim Zurücksetzen keine Klauseln, die sicher scheitern (der Interpreter
  # schon; README, Abschnitt JIT). Daraus auch: nur der Interpreter
  # erreicht die Inferenzgrenze (:limit). Sonst false.
  defp same(a, b) do
    {ra, ia} = split_i(a)
    {rb, ib} = split_i(b)

    cond do
      ra == rb and ia == ib -> :eq
      ra == rb -> Enum.all?(Enum.zip(ia, ib), fn {x, y} -> x <= y end) and :fewer
      inspect(rb) =~ "inference_limit_exceeded" -> :limit
      true -> false
    end
  end

  defp load(reader, src, jit?) do
    PrologEx.Flags.set("jit", {:atom, to_string(jit?)})
    # call_with_inference_limit/3 aus library(iso_ext)
    db0 = PrologEx.use_library(%{}, "iso_ext", "user")
    {db, msgs} = PrologEx.Consult.load(db0, Reader.read_terms(reader, src))
    assert Enum.all?(msgs, &String.starts_with?(&1, "Warnung: Singleton")), inspect({src, msgs})
    PrologEx.Flags.set("jit", {:atom, "true"})
    db
  end

  @tag timeout: :infinity
  test "JIT und Interpreter antworten gleich (Zufallsprogramme)", c do
    Reader.put_current(c.reader)
    n = String.to_integer(System.get_env("FUZZ_N", "60"))
    s0 = String.to_integer(System.get_env("FUZZ_SEED", "#{:rand.uniform(1_000_000)}"))
    verbose = System.get_env("FUZZ_VERBOSE") != nil

    stats =
      for seed <- s0..(s0 + n - 1), reduce: {0, 0, 0, 0} do
        {tot, jitted, hits, fails} ->
          {src, qs} = JitFuzz.gen(seed)
          jit = load(c.reader, src, true)
          int = load(c.reader, src, false)

          for q <- qs do
            run = fn db, what ->
              try do
                TableCase.run(c.reader, db, q)
              catch
                k, e ->
                  flunk("Startwert #{seed} (#{what}): #{inspect({k, e})}\n#{src}\n?- #{q}")
              end
            end

            a = run.(jit, "JIT")
            b = run.(int, "Interpreter")

            if verbose, do: IO.puts("?- #{q}\n   #{inspect(a)}")
            refute inspect(a) =~ "existence_error(procedure,call_with", inspect(a)

            r = same(a, b)

            assert r,
                   "Startwert #{seed}\n#{src}\n?- #{q}\nJIT:         #{inspect(a)}\nInterpreter: #{inspect(b)}"

            Process.put(r, Process.get(r, 0) + 1)
          end

          {out, _} = TableCase.run(c.reader, jit, "jit_listing")
          ps = Regex.scan(~r/^% p\d+\/\d+ +(\S+)/m, out)
          j = Enum.count(ps, fn [_, s] -> s in ["übersetzt", "nur", "analysiert"] end)

          # Treffer und Fehlschläge des übersetzten Codes (abgewiesen 1, aufgegeben 8)
          {h, f} =
            for {_, {:pred, _, _, {t, _, _, _, _, st}, _}} <- jit,
                t in [:jit, :jit_nd],
                reduce: {0, 0} do
              # (2 negativ: kalt, PrologEx.jit_cold?/1)
              {h, f} -> {h + :atomics.get(st, 1), f + max(:atomics.get(st, 2), 0)}
            end

          if verbose,
            do: IO.puts("#{seed}: #{j}/#{length(ps)} Treffer #{h} Fehlschl. #{f}\n#{out}")

          {tot + length(ps), jitted + j, hits + h, fails + f}
      end

    # der übersetzte Code läuft tatsächlich
    if n >= 20, do: assert(elem(stats, 2) > 0)

    IO.puts(
      "\nJIT-Fuzz ab #{s0}: #{n} Programme, #{elem(stats, 1)} von #{elem(stats, 0)} Prädikaten übersetzt, " <>
        "Treffer #{elem(stats, 2)}, Fehlschläge #{elem(stats, 3)}; Anfragen gleich #{Process.get(:eq, 0)}, " <>
        "weniger Inferenzen #{Process.get(:fewer, 0)}, nur der Interpreter an der Grenze #{Process.get(:limit, 0)}"
    )
  end
end
