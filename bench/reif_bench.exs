# Vergleich library(reif) (Elixir-Schnellwege) mit library(reif_pl) (reines
# Prolog, wie reif.pl).
#
#   mix run bench/reif_bench.exs          (N = 100000, M = 300)
#   N=20000 M=200 mix run bench/reif_bench.exs
#
# Jede Messung dreimal in einem frischen Prozess, das Minimum zählt.
{:ok, r} = PrologEx.Reader.start_link()
PrologEx.Reader.put_current(r)
n = String.to_integer(System.get_env("N", "100000"))
m = String.to_integer(System.get_env("M", "300"))

user = """
zaehle([], _, N, N).
zaehle([X|Xs], E, N0, N) :- if_(X = E, N1 is N0 + 1, N1 = N0), zaehle(Xs, E, N1, N).
gross(X, T) :- ( X > 5000 -> T = true ; T = false ).
mod10(L0, L) :- findall(Y, (member(Z, L0), Y is Z mod 10), L).
"""

benches = [
  {"tfilter(dif(5), L, Fs)  (N)", "numlist(1,#{n},L), tfilter(dif(5), L, _)"},
  {"tfilter(=(5), L, Fs)  (N)", "numlist(1,#{n},L), tfilter(=(5), L, _)"},
  {"tpartition(=(5), L, Ts, Fs)  (N)", "numlist(1,#{n},L), tpartition(=(5), L, _, _)"},
  {"memberd_t(N, L, T), am Ende  (N)", "numlist(1,#{n},L), memberd_t(#{n}, L, true)"},
  {"memberd_t(0, L, T), fehlt  (N)", "numlist(1,#{n},L), memberd_t(0, L, false)"},
  {"if_(X = E, ...) in Schleife  (N)", "numlist(1,#{n},L0), mod10(L0, L), zaehle(L, 3, 0, _)"},
  {"tfilter(gross, L, Fs), allgemein  (N)", "numlist(1,#{n},L), tfilter(gross, L, _)"},
  {"tfilter(dif(X), L, Fs), X frei, alle  (M)",
   "numlist(1,#{m},L), findall(Fs, tfilter(dif(_), L, Fs), _)"},
  {"memberd_t(X, L, T), X frei, alle  (M)",
   "numlist(1,#{m},L), findall(T, memberd_t(_, L, T), _)"},
  {"Bezug: exclude(==(5), L, Fs)  (N)", "numlist(1,#{n},L), exclude(==(5), L, _)"}
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
  for lib <- ["reif", "reif_pl"] do
    PrologEx.put_db(%{})

    for q <- ["use_module(library(lists))", "use_module(library(#{lib}))"] do
      [{:term, g, _}] = PrologEx.Reader.read_terms(r, q <> ".")
      [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
    end

    {db, []} = PrologEx.Consult.load(PrologEx.current_db(), PrologEx.Reader.read_terms(r, user))
    {lib, for({name, q} <- benches, do: {name, time.(db, q)})}
  end

[{_, a}, {_, b}] = res

IO.puts(
  "N = #{n}, M = #{m}" <> String.duplicate(" ", 22) <> "reif (Elixir)   reif_pl (Prolog)   Faktor"
)

for {{name, ta}, {_, tb}} <- Enum.zip(a, b) do
  IO.puts(
    String.pad_trailing(name, 42) <>
      String.pad_leading("#{ta} ms", 11) <>
      String.pad_leading("#{tb} ms", 19) <>
      String.pad_leading(:erlang.float_to_binary(tb / max(ta, 1), decimals: 1), 9)
  )
end
