# Coroutining in Reinform: Permutation Sort, bei dem die Sortiertheit mit
# freeze/2 bzw. when/2 auf die Elemente wartet. Fast jede Bindung in der
# Suche weckt zwei Suspensionen – die Kosten des Weckens bestimmen die
# Laufzeit.
#
#   mix run bench/psort_bench.exs          (N = 13)
#   N=14 mix run bench/psort_bench.exs
#
# Jede Messung dreimal in einem frischen Prozess, das Minimum zählt.
{:ok, r} = PrologEx.Reader.start_link()
PrologEx.Reader.put_current(r)
n = String.to_integer(System.get_env("N", "13"))

PrologEx.put_db(%{})

for q <- ["use_module(library(lists))"] do
  [{:term, g, _}] = PrologEx.Reader.read_terms(r, q <> ".")
  [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
end

{db, []} =
  PrologEx.Consult.load(
    PrologEx.current_db(),
    PrologEx.Reader.read_terms(r, """
    psort_fz(Xs, Ys) :- length(Xs, N), length(Ys, N), sorted_fz(Ys), perm(Xs, Ys).
    sorted_fz([]).
    sorted_fz([_]).
    sorted_fz([X,Y|Zs]) :- freeze(X, freeze(Y, X =< Y)), sorted_fz([Y|Zs]).
    psort_wh(Xs, Ys) :- length(Xs, N), length(Ys, N), sorted_wh(Ys), perm(Xs, Ys).
    sorted_wh([]).
    sorted_wh([_]).
    sorted_wh([X,Y|Zs]) :- when((nonvar(X), nonvar(Y)), X =< Y), sorted_wh([Y|Zs]).
    perm([], []).
    perm(Xs, [Y|Ys]) :- select(Y, Xs, Xs1), perm(Xs1, Ys).
    % eine feste Durchmischung von 1..N
    mixed(N, L) :- numlist(1, N, Ns), mix(Ns, L).
    mix([], []).
    mix([X], [X]).
    mix([X,Y|Zs], [Y|L]) :- mix([X|Zs], L0), reverse(L0, L).
    """)
  )

time = fn q ->
  [{:term, g, _}] = PrologEx.Reader.read_terms(r, "\\+ \\+ (#{q}).")

  ts =
    for _ <- 1..3 do
      parent = self()

      spawn(fn ->
        PrologEx.Reader.put_current(r)
        i0 = PrologEx.inferences()
        {t, [_]} = :timer.tc(fn -> PrologEx.query(db, g) |> Enum.take(1) end)
        send(parent, {t, PrologEx.inferences() - i0})
      end)

      receive do
        t -> t
      end
    end

  {t, i} = Enum.min(ts)
  String.pad_leading("#{div(t, 1000)} ms", 9) <> String.pad_leading("#{i} Inferenzen", 22)
end

IO.puts("N = #{n}")
IO.puts("freeze(X, freeze(Y, X =< Y))        " <> time.("mixed(#{n}, L), psort_fz(L, _)"))
IO.puts("when((nonvar(X), nonvar(Y)), X =< Y)" <> time.("mixed(#{n}, L), psort_wh(L, _)"))
