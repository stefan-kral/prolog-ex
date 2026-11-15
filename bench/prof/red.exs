# red.exs [--only a,b] [--save Datei] [--compare Datei] – je Fall die
# Reduktionen eines Laufs (deterministisch, auf rund 1 % genau) und die
# beste Zeit aus RUNS (7) Läufen; --compare zeigt die Änderung gegen einen
# gespeicherten Lauf. Reduktionen überschätzen Gewinne aus weniger
# Funktionsaufrufen (Enum → Rekursion), entscheidend ist die Zeit; die
# schwankt um ±10 %, also mehrmals abwechselnd messen.
#
#   MIX_ENV=prod mix run bench/prof/red.exs --save /tmp/vorher.txt
#   … ändern …
#   MIX_ENV=prod mix run bench/prof/red.exs --compare /tmp/vorher.txt
Code.require_file(Path.join(__DIR__, "common.exs"))

{opts, _, _} =
  OptionParser.parse(System.argv(), strict: [save: :string, compare: :string, only: :string])

only = if o = opts[:only], do: String.split(o, ","), else: nil
{db, cases} = Prof.setup()

base =
  if f = opts[:compare] do
    for l <- String.split(File.read!(f), "\n", trim: true), into: %{} do
      [n, r, t] = String.split(l)
      {n, {String.to_integer(r), String.to_float(t)}}
    end
  else
    %{}
  end

runs = String.to_integer(System.get_env("RUNS", "7"))

res =
  for {name, q} <- cases, only == nil or name in only do
    g = Prof.goal(q)
    [_] = Prof.run(db, g)
    :erlang.garbage_collect()
    {:reductions, r0} = Process.info(self(), :reductions)
    [_] = Prof.run(db, g)
    {:reductions, r1} = Process.info(self(), :reductions)
    r = r1 - r0

    t =
      for(_ <- 1..runs, do: elem(:timer.tc(fn -> Prof.run(db, g) end), 0))
      |> Enum.min()
      |> Kernel./(1000)

    cmp =
      case base do
        %{^name => {br, bt}} ->
          :io_lib.format("   Red. ~7.2f %  Zeit ~6.1f %", [100 * (r - br) / br, 100 * (t - bt) / bt])

        _ ->
          ""
      end

    :io.format("~-12s ~12w Red. ~9.1f ms~s~n", [name, r, t, cmp])
    {name, r, t}
  end

if f = opts[:save], do: File.write!(f, Enum.map_join(res, "", fn {n, r, t} -> "#{n} #{r} #{t}\n" end))
