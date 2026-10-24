# Vergleich lists:memberd/2 (Elixir) mit library(memberd_pl) (Prolog, wie
# Neumerkels memberd/2 mit dif/2 in der Rekursion).
#
#   mix run bench/memberd_bench.exs          (N = 100000, M = 1000)
#   N=20000 M=1000 mix run bench/memberd_bench.exs
#
# Jede Messung dreimal in einem frischen Prozess, das Minimum zählt.
{:ok, r} = PrologEx.Reader.start_link()
PrologEx.Reader.put_current(r)
n = String.to_integer(System.get_env("N", "100000"))
m = String.to_integer(System.get_env("M", "1000"))

benches = [
  {"gefunden am Ende (N)", "numlist(1,#{n},L), memberd(#{n}, L)"},
  {"nicht gefunden (N)", "numlist(1,#{n},L), \\+ memberd(0, L)"},
  {"alle Antworten, ground X (N)", "numlist(1,#{n},L), findall(x, memberd(5, L), _)"},
  {"alle Antworten, X frei (M)", "numlist(1,#{m},L), findall(X, memberd(X, L), _)"},
  {"X frei, 10 Werte wiederholt (M)",
   "numlist(1,#{m},L0), findall(Y, (member(Z, L0), Y is Z mod 10), L), findall(X, memberd(X, L), _)"},
  {"Elemente f(_) (M)", "length(L, #{m}), maplist(=(f(_)), L), findall(X, memberd(f(1), L), _)"},
  {"Bezug: memberchk (N)", "numlist(1,#{n},L), memberchk(#{n}, L)"},
  {"Bezug: member, alle (N)", "numlist(1,#{n},L), findall(X, member(X, L), _)"}
]

time = fn db, q ->
  [{:term, g, _}] = PrologEx.Reader.read_terms(r, "\\+ \\+ (#{q}).")

  ts =
    for _ <- 1..3 do
      parent = self()

      spawn(fn ->
        PrologEx.Reader.put_current(r)
        {t, [_]} = :timer.tc(fn -> PrologEx.query(db, g) |> Enum.take(1) end)
        send(parent, t)
      end)

      receive do
        t -> t
      end
    end

  div(Enum.min(ts), 1000)
end

res =
  for lib <- ["lists", "memberd_pl"] do
    PrologEx.put_db(%{})

    # für memberd_pl aus lists alles außer memberd/2
    imports =
      if lib == "lists",
        do: ["use_module(library(lists))"],
        else: [
          "use_module(library(memberd_pl))",
          "use_module(library(lists), [numlist/3, member/2, memberchk/2, maplist/2])"
        ]

    for q <- imports do
      [{:term, g, _}] = PrologEx.Reader.read_terms(r, q <> ".")
      [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
    end

    db = PrologEx.current_db()
    ^lib = Map.fetch!(db, {:import, "user", "memberd", 2})
    {lib, for({name, q} <- benches, do: {name, time.(db, q)})}
  end

[{_, a}, {_, b}] = res
IO.puts("N = #{n}, M = #{m}               lists (Elixir)   memberd_pl (Prolog)   Faktor")

for {{name, ta}, {_, tb}} <- Enum.zip(a, b) do
  IO.puts(
    String.pad_trailing(name, 34) <>
      String.pad_leading("#{ta} ms", 12) <>
      String.pad_leading("#{tb} ms", 20) <>
      String.pad_leading(:erlang.float_to_binary(tb / max(ta, 1), decimals: 2), 10)
  )
end
