# calls.exs Fall [N] – wie oft welches Prolog-Prädikat aufgerufen wird
# (Tracing auf PrologEx.call_pred/4, nur Name und Modul, nicht die
# Argumente). Mit JIT laufen Aufrufe innerhalb übersetzter Prädikate an
# call_pred vorbei; für ein vollständiges Bild ohne JIT zählen:
#
#   PRELUDE=':- set_prolog_flag(jit, false).' EXTRA='x=go' mix run bench/prof/calls.exs x
#
# PRELUDE/EXTRA wie in common.exs; TOP (40) Zeilen. Das Modul in der Ausgabe
# ist das, aus dem gerufen wird (Kontextmodul), nicht das, in dem das
# Prädikat liegt: simplex:nth0 ist nth0/3 aus library(lists) (in Elixir),
# gerufen aus simplex. Gezählt wird jeder Aufruf über die Maschine, auch
# der von Builtins in Elixir
Code.require_file(Path.join(__DIR__, "common.exs"))

[name | _] = System.argv()
{db, cases} = Prof.setup()
{_, q} = List.keyfind(cases, name, 0) || raise("Fall #{name} unbekannt")
g = Prof.goal(q)

counter = :ets.new(:calls, [:public, :set])
me = self()

tracer =
  spawn(fn ->
    loop = fn loop ->
      receive do
        {:trace, _, :call, {PrologEx, :call_pred, 4}, key} ->
          :ets.update_counter(counter, key, 1, {key, 0})
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
  [{[:"$1", :"$2", :_, :_], [{:is_tuple, :"$1"}], [{:message, {{{:element, 2, :"$1"}, :"$2"}}}]}],
  [:local]
)

PrologEx.put_db(db)
Prof.run(db, g)
:erlang.trace(me, false, [:call])
send(tracer, {:done, self()})
receive do: (:ok -> :ok)

rows = :ets.tab2list(counter) |> Enum.sort_by(fn {_, n} -> -n end)
total = Enum.reduce(rows, 0, fn {_, n}, a -> a + n end)
IO.puts("Aufrufe gesamt: #{total} (Modul: aus dem gerufen wird)")

for {{f, m}, n} <- Enum.take(rows, String.to_integer(System.get_env("TOP", "40"))) do
  IO.puts(:io_lib.format("~10w ~5.1f %  ~ts:~ts", [n, 100 * n / total, m, f]))
end
