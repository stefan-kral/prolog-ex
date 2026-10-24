# dif/2: Kosten des Weckens.
#
#   mix run bench/dif_bench.exs          (K = 300, N = 100000)
#
# Jede Messung dreimal in einem frischen Prozess, das Minimum zählt.
{:ok, r} = PrologEx.Reader.start_link()
PrologEx.Reader.put_current(r)
k = String.to_integer(System.get_env("K", "300"))
n = String.to_integer(System.get_env("N", "100000"))

PrologEx.put_db(%{})

for q <- ["use_module(library(lists))", "use_module(library(apply))"] do
  [{:term, g, _}] = PrologEx.Reader.read_terms(r, q <> ".")
  [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
end

{db, []} =
  PrologEx.Consult.load(
    PrologEx.current_db(),
    PrologEx.Reader.read_terms(r, """
    alle_dif([]).
    alle_dif([X|Xs]) :- maplist(dif(X), Xs), alle_dif(Xs).
    viele_dif(_, 0) :- !.
    viele_dif(X, I) :- dif(X, I), I1 is I - 1, viele_dif(X, I1).
    """)
  )

benches = [
  {"alle_dif(K Var.), dann binden", "length(Vs, #{k}), alle_dif(Vs), numlist(1, #{k}, Vs)"},
  {"alle_dif(K Var.), Kette X=Y gebunden",
   "length(Vs, #{k}), alle_dif(Vs), Vs = [_|T], numlist(2, #{k}, T), Vs = [0|_]"},
  {"N dif an X, dann X = 0", "viele_dif(X, #{n}), X = 0"},
  {"N dif an X, dann X = f(Y)", "viele_dif(X, #{n}), X = f(_)"},
  {"memberd: alle Antworten (K)", "numlist(1, #{k}, L), findall(X, memberd(X, L), _)"}
]

time = fn q ->
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

IO.puts("K = #{k}, N = #{n}")

for {name, q} <- benches do
  IO.puts(String.pad_trailing(name, 40) <> String.pad_leading("#{time.(q)} ms", 10))
end
