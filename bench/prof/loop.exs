# loop.exs Fall – den Fall SECS Sekunden lang wiederholen (für perf.sh);
# READY=Datei wird angelegt, sobald die Schleife beginnt
Code.require_file(Path.join(__DIR__, "common.exs"))
[name] = System.argv()
{db, cases} = Prof.setup()

q =
  case List.keyfind(cases, name, 0) do
    {_, q} -> q
    nil -> raise "kein Fall #{name}"
  end

g = Prof.goal(q)
[_] = Prof.run(db, g)
secs = String.to_integer(System.get_env("SECS", "6"))
if r = System.get_env("READY"), do: File.write!(r, "")
t0 = System.monotonic_time(:millisecond)

n =
  Stream.repeatedly(fn -> Prof.run(db, g) end)
  |> Stream.take_while(fn _ -> System.monotonic_time(:millisecond) - t0 < secs * 1000 end)
  |> Enum.count()

IO.puts(:stderr, "#{name}: #{n} Läufe")
