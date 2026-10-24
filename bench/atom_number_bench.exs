# Vergleich atom_number/2 mit den Kombinationen
#   atom_chars(A, Cs), number_chars(N, Cs)    (Atom -> Zahl)
#   number_chars(N, Cs), atom_chars(A, Cs)    (Zahl -> Atom)
# und dasselbe mit _codes, je für kleine Ganzzahlen, Floats und große
# Ganzzahlen. Jeweils maplist über N Werte; abgezogen wird ein maplist mit
# id/2 (gleiche Liste), sodass nur die Umwandlung zählt.
#
#   mix run bench/atom_number_bench.exs        (N = 50000)
#   N=10000 mix run bench/atom_number_bench.exs
#
# Jede Messung dreimal in einem frischen Prozess, das Minimum zählt.

import PrologEx, only: [a: 1, v: 1, mk: 2, list: 1]

{:ok, r} = PrologEx.Reader.start_link()
PrologEx.Reader.put_current(r)
n = String.to_integer(System.get_env("N", "50000"))

program = """
id(X, X).
an(A, N) :- atom_number(A, N).
an_chars(A, N) :- atom_chars(A, Cs), number_chars(N, Cs).
an_codes(A, N) :- atom_codes(A, Cs), number_codes(N, Cs).
na(N, A) :- atom_number(A, N).
na_chars(N, A) :- number_chars(N, Cs), atom_chars(A, Cs).
na_codes(N, A) :- number_codes(N, Cs), atom_codes(A, Cs).
"""

db = Enum.reduce(["apply"], %{}, &PrologEx.use_library(&2, &1, "user"))
{db, []} = PrologEx.Consult.load(db, PrologEx.Reader.read_terms(r, program))

data = %{
  "Ganzzahlen" => Enum.to_list(1..n),
  "Floats" => Enum.map(1..n, &(&1 * 1.25)),
  "große Ganzzahlen" => Enum.map(1..n, &(&1 * 1_000_000_000_000_000_000_000))
}

# maplist(P, Eingabe, _) unter \+ \+ (keine Antwort aufbauen)
time = fn pred, input ->
  goal = mk("\\+", [mk("\\+", [mk("maplist", [a(pred), list(input), v("Out")])])])

  for _ <- 1..3 do
    parent = self()

    spawn(fn ->
      {t, [_]} = :timer.tc(fn -> PrologEx.query(db, goal) |> Enum.take(1) end)
      send(parent, t)
    end)

    receive do
      t -> t
    end
  end
  |> Enum.min()
end

fmt = fn us -> :erlang.float_to_binary(us / n, decimals: 2) end

IO.puts("N = #{n}; µs je Umwandlung (ohne maplist-Anteil)\n")

IO.puts(
  String.pad_trailing("", 20) <>
    String.pad_leading("atom_number", 13) <>
    String.pad_leading("chars", 10) <>
    String.pad_leading("codes", 10) <>
    String.pad_leading("chars/an", 11) <> String.pad_leading("codes/an", 11)
)

for kind <- ["Ganzzahlen", "Floats", "große Ganzzahlen"] do
  nums = data[kind]
  atoms = Enum.map(nums, &a(PrologEx.Builtins.Atoms.number_string(&1)))

  for {dir, input, preds} <- [
        {"Atom -> Zahl", atoms, ["an", "an_chars", "an_codes"]},
        {"Zahl -> Atom", nums, ["na", "na_chars", "na_codes"]}
      ] do
    base = time.("id", input)
    [t1, t2, t3] = for p <- preds, do: max(time.(p, input) - base, 1)

    IO.puts(
      String.pad_trailing("#{kind}, #{dir}", 36) <>
        String.pad_leading(fmt.(t1), 5) <>
        String.pad_leading(fmt.(t2), 10) <>
        String.pad_leading(fmt.(t3), 10) <>
        String.pad_leading(:erlang.float_to_binary(t2 / t1, decimals: 1) <> "×", 11) <>
        String.pad_leading(:erlang.float_to_binary(t3 / t1, decimals: 1) <> "×", 11)
    )
  end
end
