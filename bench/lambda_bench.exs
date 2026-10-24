# Vergleich library(lambda) (Elixir) mit library(lambda_pl) (Prolog, wie
# Neumerkels lambda.pl) und einem normalen Hilfsprädikat als Bezug.
#
#   mix run bench/lambda_bench.exs          (N = 100000)
#   N=20000 mix run bench/lambda_bench.exs
#
# Jede Messung dreimal in einem frischen Prozess, das Minimum zählt.
{:ok, r} = PrologEx.Reader.start_link()
PrologEx.Reader.put_current(r)
n = String.to_integer(System.get_env("N", "100000"))

benches = [
  {"maplist  \\X^Y^(Y is X*2)", "numlist(1,#{n},L), maplist(\\X^Y^(Y is X*2), L, L2)"},
  {"maplist  N+\\X^Y^(Y is X+N)", "numlist(1,#{n},L), N = 7, maplist(N+\\X^Y^(Y is X+N), L, L2)"},
  {"foldl    \\X^A0^A^(A is A0+X)", "numlist(1,#{n},L), foldl(\\X^A0^A^(A is A0+X), L, 0, S)"},
  {"include  \\X^(X mod 3 =:= 0)", "numlist(1,#{n},L), include(\\X^(X mod 3 =:= 0), L, L2)"},
  {"maplist  großer Rumpf (Kopie)",
   "numlist(1,#{n},L), maplist(\\X^Y^(Z = f(X,X,X,X,X,X,X,X), arg(1,Z,Y)), L, L2)"},
  {"Bezug: maplist(double)", "numlist(1,#{n},L), maplist(double, L, L2)"},
  {"Bezug: foldl(plus3)", "numlist(1,#{n},L), foldl(plus3, L, 0, S)"}
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
  for lib <- ["lambda", "lambda_pl"] do
    PrologEx.put_db(%{})

    for q <- [
          "use_module(library(apply))",
          "use_module(library(lists))",
          "use_module(library(#{lib}))"
        ] do
      [{:term, g, _}] = PrologEx.Reader.read_terms(r, q <> ".")
      [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
    end

    {db, []} =
      PrologEx.Consult.load(
        PrologEx.current_db(),
        PrologEx.Reader.read_terms(r, "double(X, Y) :- Y is X*2. plus3(X, A0, A) :- A is A0+X.")
      )

    {lib, for({name, q} <- benches, do: {name, time.(db, q)})}
  end

[{_, a}, {_, b}] = res
IO.puts("n = #{n}                          lambda (Elixir)   lambda_pl (Prolog)   Faktor")

for {{name, ta}, {_, tb}} <- Enum.zip(a, b) do
  IO.puts(
    String.pad_trailing(name, 34) <>
      String.pad_leading("#{ta} ms", 12) <>
      String.pad_leading("#{tb} ms", 20) <>
      String.pad_leading(:erlang.float_to_binary(tb / max(ta, 1), decimals: 2), 10)
  )
end
