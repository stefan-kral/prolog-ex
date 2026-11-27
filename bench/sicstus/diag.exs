# diag.exs – wo die Zeit der SICStus-Benchmarks in PrologEx hingeht: je
# Programm Laufzeit mit und ohne JIT, Anteil der Aufrufe, die durch den
# Interpreter laufen, und die meistgerufenen Prädikate dort mit ihrem
# JIT-Status (jit_listing: übersetzt, nur für Rufer, oder der Grund, warum
# nicht).
#
#   BENCH_DIR=~/bench mix run bench/sicstus/diag.exs [programm …]
#
# Umgebung: BENCH_DIR (Pflicht), DIV (Iterationen aus main.pl geteilt
# durch DIV, Vorgabe 20), TOP (Prädikate je Programm, Vorgabe 8).
#
# Gezählt werden Aufrufe von PrologEx.call_pred/4 (Tracing): jeder Aufruf
# über den Interpreter, auch der eingebauter Prädikate; Aufrufe innerhalb
# übersetzten Codes laufen daran vorbei. Mit JIT aus sind es alle Aufrufe
# – das Verhältnis ist der Anteil, den der Interpreter noch ausführt.
# Aufrufzahlen sind nicht Zeit, zeigen aber, wo sie liegt.

defmodule Diag do
  def bench_dir do
    d = System.get_env("BENCH_DIR") || raise "BENCH_DIR: Ordner der entpackten bench.zip"
    Path.expand(d)
  end

  def progs(dir) do
    Regex.scan(~r/^\(:-\[([a-z_]+)\],bench\((\d+)\)\)/m, File.read!(Path.join(dir, "main.pl")))
    |> Enum.map(fn [_, n, c] -> {n, String.to_integer(c)} end)
  end

  def q(db, text) do
    [{:term, g, _}] = PrologEx.Parser.read_terms(text <> " .")
    PrologEx.put_db(db)
    r = PrologEx.query(db, g) |> Enum.take(1)
    {r, PrologEx.current_db()}
  end

  def load(name, jit?) do
    PrologEx.Flags.set("jit", {:atom, to_string(jit?)})

    {[_], db} =
      q(%{}, "set_prolog_flag(double_quotes, codes), consult('harness.pl'), consult('#{name}.pl')")

    PrologEx.Flags.set("jit", {:atom, "true"})
    db
  end

  # dobench/1 aus harness.pl: K-mal data(D), benchmark(D, _); ms
  def time(db, k) do
    {t, _} = :timer.tc(fn -> q(db, "dobench(#{k})") end)
    div(t, 1000)
  end

  def count_calls(db, k) do
    tab = :ets.new(:calls, [:public, :set])
    me = self()

    tracer =
      spawn(fn ->
        loop = fn loop ->
          receive do
            {:trace, _, :call, {PrologEx, :call_pred, 4}, key} ->
              :ets.update_counter(tab, key, 1, {key, 0})
              loop.(loop)

            {:done, from} ->
              send(from, :ok)

            _ ->
              loop.(loop)
          end
        end

        loop.(loop)
      end)

    :erlang.trace(me, true, [:call, :arity, {:tracer, tracer}])

    :erlang.trace_pattern(
      {PrologEx, :call_pred, 4},
      [
        {[{:"$3", :"$1", :"$4"}, :_, :_, :_], [{:is_list, :"$4"}],
         [{:message, {{:"$1", {:length, :"$4"}}}}]},
        {[{:atom, :"$1"}, :_, :_, :_], [], [{:message, {{:"$1", 0}}}]}
      ],
      [:local]
    )

    q(db, "dobench(#{k})")
    :erlang.trace(me, false, [:call])
    :erlang.trace_pattern({PrologEx, :call_pred, 4}, false, [:local])
    send(tracer, {:done, self()})
    receive do: (:ok -> :ok)
    rows = :ets.tab2list(tab)
    :ets.delete(tab)
    Map.new(rows)
  end

  # Zähler des übersetzten Codes je Prädikat (PrologEx.call_pred/4):
  # Treffer, Fehlschläge (abgewiesen 1, aufgegeben 8; negativ: kalt, so
  # viele Aufrufe bis zum nächsten Versuch), wie oft kalt geworden
  def jit_stats(db) do
    for {{"user", n, a}, {:pred, _, _, j, _}} <- db,
        is_tuple(j),
        elem(j, 0) in [:jit, :jit_nd],
        stats = elem(j, 5),
        into: %{},
        do: {{n, a}, Enum.map(1..3, &:atomics.get(stats, &1))}
  end

  # jit_listing als %{{name, arity} => "status  detail"}
  def jit_status(db) do
    PrologEx.JitListing.listing(db, :all, "user")
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^% (\S+)\/(\d+)\s+(.*)$/, line) do
        [_, n, a, rest] -> [{{n, String.to_integer(a)}, String.replace(rest, ~r/\s{2,}/, "  ")}]
        _ -> []
      end
    end)
    |> Map.new()
  end
end

Application.put_env(:prolog_ex, :verbose_load, :silent)
dir = Diag.bench_dir()
File.cd!(dir)
div_ = String.to_integer(System.get_env("DIV", "20"))
top = String.to_integer(System.get_env("TOP", "8"))
only = System.argv()
progs = for {n, _} = p <- Diag.progs(dir), only == [] or n in only, do: p

# Rauschen der Harness-Prädikate ausblenden
harness = MapSet.new([{"repeat", 1}, {"dobench", 1}, {"benchmark", 2}, {"data", 1}, {"dummy", 2}])

for {name, count} <- progs do
  k = max(div(count, div_), 1)
  on = Diag.load(name, true)
  off = Diag.load(name, false)

  # aufwärmen (JIT übersetzt nach jit_threshold Aufrufen), dann messen
  # (die Datenbank nach jedem Lauf: übersetzt wird erst beim Aufruf)
  Diag.time(on, k)
  on = PrologEx.current_db()
  Diag.time(off, k)
  t_on = Diag.time(on, k)
  on = PrologEx.current_db()
  t_off = Diag.time(off, k)

  kc = max(div(k, 10), 1)
  c_on = Diag.count_calls(on, kc)
  on = PrologEx.current_db()
  c_off = Diag.count_calls(off, kc)
  sum = fn m -> m |> Map.values() |> Enum.sum() end
  n_on = sum.(c_on)
  n_off = sum.(c_off)
  st = Diag.jit_status(on)
  js = Diag.jit_stats(on)

  IO.puts(
    "\n== #{name}: #{k} Iter.  JIT an #{t_on} ms, aus #{t_off} ms (×#{Float.round(t_off / max(t_on, 1), 1)}); " <>
      "Interpreter-Aufrufe #{n_on} von #{n_off} (#{round(100 * n_on / max(n_off, 1))} %, #{kc} Iter.)"
  )

  c_on
  |> Enum.reject(fn {k, _} -> MapSet.member?(harness, k) end)
  |> Enum.sort_by(fn {_, n} -> -n end)
  |> Enum.take(top)
  |> Enum.each(fn {{n, a} = key, c} ->
    s = Map.get(st, key, "eingebaut/Bibliothek")

    s =
      case js do
        %{^key => [h, f, k]} when f < 0 -> s <> "  [Treffer #{h}, kalt (#{k}-mal)]"
        %{^key => [h, f, k]} -> s <> "  [Treffer #{h}, Fehlschl. #{f}, kalt geworden #{k}-mal]"
        _ -> s
      end

    IO.puts(
      :io_lib.format("  ~10w ~5.1f %  ~-28ts ~ts", [c, 100 * c / max(n_on, 1), "#{n}/#{a}", s])
    )
  end)
end
