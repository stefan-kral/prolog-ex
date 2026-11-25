defmodule PrologEx.LfsrTest do
  # library(lfsr): Pseudozufallszahlen in 1..2^N−1 mit voller Periode
  use ExUnit.Case, async: true
  import Bitwise
  alias PrologEx.{Reader, TableCase}
  alias PrologEx.Builtins.Lfsr

  @program """
  :- use_module(library(lfsr)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(iso_ext)).
  alle(S, []) :- lfsr_done(S), !.
  alle(S0, [X|Xs]) :- lfsr_next(S0, X, S), alle(S, Xs).
  % jede Zahl in 1..2^N−1 genau einmal, die letzte ist der Seed
  voll(Seed, N, K) :-
      ( K == d -> lfsr_make(Seed, N, S) ; lfsr_make(Seed, N, K, S) ),
      alle(S, Xs), length(Xs, L), sort(Xs, Ys), length(Ys, L2), last(Xs, La),
      M is 2^N-1, L =:= M, L2 =:= M, La =:= Seed.
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, _} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  for {q, e} <- [
        {"lfsr_make(12345, 16, S)", ["S = st(12345,16,0,16)"]},
        {"lfsr_make(1, 6, S)", ["S = st(1,6,0,8)"]},
        {"lfsr_make(1, 4, 7, S)", ["S = st(1,4,0,7)"]},
        {"lfsr_make(1, 2, S), alle(S, L)", ["L = [2,3,1], S = st(1,2,0,2)"]},
        {"lfsr_make(1, 2, 1, S), alle(S, L)", ["L = [3,2,1], S = st(1,2,0,1)"]},
        {"lfsr_make(1, 1, S), alle(S, L)", ["L = [1], S = st(1,1,0,1)"]},
        {"lfsr_make(1, 4, S0), lfsr_next(S0, X, S1), lfsr_next(S1, Y, S2)", :succeeds},
        {"lfsr_done(st(1,4,15,4))", true},
        {"lfsr_done(st(1,4,14,4))", :fails},
        {"lfsr_next(st(1,4,15,4), _, _)", :fails},
        {"forall(between(1, 14, N), (voll(1, N, d), voll(1, N, 1)))", true},
        {"voll(77, 10, 1003), voll(5, 12, 1000003), voll(3, 8, 2)", true},
        {"lfsr_make(5, 168, S), lfsr_next(S, X, _), X > 0, X < 2^168", :succeeds},
        {"lfsr_make(1, 169, _)", {:error, "domain_error(lfsr_bits,169)"}},
        {"lfsr_make(1, 0, _)", {:error, "domain_error(lfsr_bits,0)"}},
        {"lfsr_make(0, 4, _)", {:error, "domain_error(lfsr_seed,0)"}},
        {"lfsr_make(16, 4, _)", {:error, "domain_error(lfsr_seed,16)"}},
        {"lfsr_make(1, 4, 3, _)", {:error, "domain_error(lfsr_step,3)"}},
        {"lfsr_make(1, 4, 0, _)", {:error, "domain_error(lfsr_step,0)"}},
        {"lfsr_make(_, 4, _)", {:error, "instantiation_error"}},
        {"lfsr_make(a, 4, _)", {:error, "type_error(integer,a)"}},
        {"lfsr_next(foo, _, _)", {:error, "type_error(lfsr,foo)"}},
        {"lfsr_next(st(1,169,0,1), _, _)", {:error, "type_error(lfsr,st(1,169,0,1))"}},
        {"lfsr_done(_)", {:error, "instantiation_error"}}
      ] do
    test "lfsr: #{q}", c do
      actual = TableCase.run(c.reader, c.db, unquote(q))
      assert TableCase.matches?(unquote(Macro.escape(e)), actual), inspect(actual)
    end
  end

  # notwendig für die volle Periode: x^(2^N−1) ≡ 1 modulo des Polynoms
  # (hinreichend erst mit den Primfaktoren von 2^N−1, nachgeprüft beim
  # Erstellen der Tabelle)
  test "jedes Polynom: x^(2^N−1) = 1" do
    for n <- 2..168 do
      p = Enum.reduce(Lfsr.taps(n), 1, &(&2 ||| 1 <<< &1))
      assert pow_x((1 <<< n) - 1, p, n) == 1, "N = #{n}"
    end
  end

  test "Periode genau 2^N−1 (N ≤ 18, ein Schritt)" do
    for n <- 1..18 do
      m = (1 <<< n) - 1
      assert period(Lfsr.steps(1, n, 1), n, 1) == m, "N = #{n}"
    end
  end

  test "Sprung über die Tabelle = K einzelne Schritte" do
    for n <- 1..168,
        k <- [3, n, Lfsr.default_step(n), 4 * n + 7] |> Enum.uniq() |> Enum.filter(&(&1 >= 3)) do
      s = rem(n * 7919 + k, (1 <<< n) - 1) + 1
      assert Lfsr.steps(s, n, k) == Lfsr.loop_steps(s, n, k), "N = #{n}, K = #{k}"
    end
  end

  defp period(s, n, i) do
    if s == 1, do: i, else: period(Lfsr.steps(s, n, 1), n, i + 1)
  end

  defp pow_x(e, p, n), do: pow_x(e, p, n, 2, 1)
  defp pow_x(0, _p, _n, _a, r), do: r

  defp pow_x(e, p, n, a, r) do
    r = if (e &&& 1) == 1, do: mulmod(r, a, p, n), else: r
    pow_x(e >>> 1, p, n, mulmod(a, a, p, n), r)
  end

  defp mulmod(a, b, p, n, r \\ 0)
  defp mulmod(_a, 0, _p, _n, r), do: r

  defp mulmod(a, b, p, n, r) do
    r = if (b &&& 1) == 1, do: bxor(r, a), else: r
    a = a <<< 1
    a = if (a >>> n &&& 1) == 1, do: bxor(a, p), else: a
    mulmod(a, b >>> 1, p, n, r)
  end
end
