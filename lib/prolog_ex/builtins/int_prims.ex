defmodule PrologEx.Builtins.IntPrims do
  @moduledoc """
  Kern der Zahlentheorie in `library(arithmetic)`
  (`priv/library/arithmetic.pl`); die Rechnung in `PrologEx.NumberTheory`.
  Die Prädikate hier erwarten geprüfte Ganzzahlen (`'$int_arg'/4` vorher).
  """
  use PrologEx.Builtin
  import Bitwise
  alias PrologEx.{Error, NumberTheory, Store}

  # '$int_arg'(X, Min, Domain, PI): X Ganzzahl (sonst instantiation_error
  # bzw. type_error(integer, X)), und – wenn Min eine Zahl ist – X ≥ Min
  # (sonst domain_error(Domain, X)); Kontext PI
  defbuiltin "$int_arg", [x, min, dom, pi] do
    ctx_pi = resolve(pi)

    case deref(x) do
      {:var, _} ->
        raise_ctx(a("instantiation_error"), ctx_pi)

      n when is_integer(n) ->
        case deref(min) do
          m when is_integer(m) and n < m -> raise_ctx(mk("domain_error", [deref(dom), n]), ctx_pi)
          _ -> :ok
        end

      other ->
        raise_ctx(mk("type_error", [a("integer"), resolve(other)]), ctx_pi)
    end
  end

  defp raise_ctx(formal, pi), do: Error.throw!(mk("error", [formal, pi]))

  defbuiltin "$is_prime", [n] do
    NumberTheory.prime?(deref(n))
  end

  defbuiltin "$next_prime", [n, p] do
    {:unify, [{p, NumberTheory.next_prime(deref(n))}]}
  end

  defbuiltin "$prev_prime", [n, p] do
    case NumberTheory.prev_prime(deref(n)) do
      nil -> :fail
      q -> {:unify, [{p, q}]}
    end
  end

  defbuiltin "$primes_between", [l, h, ps] do
    lo = deref(l)
    hi = deref(h)
    # die Liste: etwa (H − L) / ln H Elemente zu je 2 Wörtern (Zelle)
    if hi - lo > 10_000,
      do: PrologEx.reserve!(div(2 * (hi - lo) * 10, 7 * NumberTheory.bit_length(hi)))

    {:unify, [{ps, list(NumberTheory.primes_between(lo, hi))}]}
  end

  defbuiltin "$factorial", [n, f] do
    k = deref(n)
    # log2(n!) < n·log2(n) Bits
    if k > 10_000, do: PrologEx.reserve!(div(k * NumberTheory.bit_length(k), 64))
    {:unify, [{f, NumberTheory.factorial(k)}]}
  end

  defbuiltin "$binomial", [n, k, b] do
    nn = deref(n)
    # höchstens n Bits
    if nn > 10_000, do: PrologEx.reserve!(div(nn, 64))
    {:unify, [{b, NumberTheory.binomial(nn, deref(k))}]}
  end

  defbuiltin "$isqrt", [n, r] do
    {:unify, [{r, NumberTheory.isqrt(deref(n))}]}
  end

  defbuiltin "$iroot", [n, k, r] do
    {:unify, [{r, NumberTheory.iroot(deref(n), deref(k))}]}
  end

  # expmod/4: Expo ≥ 0; Mod = 1: 0; Expo = 0: 1; Mod = 0: zero_divisor;
  # Mod < 0: Ergebnis mit dem Vorzeichen von Mod (wie mod)
  defbuiltin "$powm", [b, e, m, r] do
    bb = deref(b)
    ee = deref(e)

    v =
      case deref(m) do
        1 -> 0
        _ when ee == 0 -> 1
        0 -> Error.evaluation!("zero_divisor")
        mm when mm > 0 -> NumberTheory.powm(bb, ee, mm)
        mm -> Integer.mod(NumberTheory.powm(bb, ee, -mm), mm)
      end

    {:unify, [{r, v}]}
  end

  defbuiltin "$mod_inverse", [x, m, i] do
    case NumberTheory.mod_inverse(deref(x), deref(m)) do
      nil -> :fail
      v -> {:unify, [{i, v}]}
    end
  end

  defbuiltin "$jacobi", [x, n, j] do
    {:unify, [{j, NumberTheory.jacobi(deref(x), deref(n))}]}
  end

  defbuiltin "$trial_factor", [n, pes, rest] do
    {fs, r} = NumberTheory.trial_factor(deref(n))
    {:unify, [{pes, pes_term(fs)}, {rest, r}]}
  end

  defbuiltin "$perfect_power", [n, r, k] do
    case NumberTheory.perfect_power(deref(n)) do
      nil -> :fail
      {rr, kk} -> {:unify, [{r, rr}, {k, kk}]}
    end
  end

  # '$rho'(N, C, S0, R): S0 = start oder ein Zustand s(...);
  # R = found(D), more(S) oder fail
  defbuiltin "$rho", [n, c, s0, res] do
    nn = deref(n)
    budget = if nn < 1 <<< 128, do: 20_000, else: 2000

    st =
      case resolve(s0) do
        {:atom, "start"} -> nil
        {_, "s", args} -> List.to_tuple(args)
      end

    r =
      case NumberTheory.rho_step(nn, deref(c), st, budget) do
        {:found, d} -> mk("found", [d])
        {:more, st} -> mk("more", [mk("s", Tuple.to_list(st))])
        :fail -> a("fail")
      end

    {:unify, [{res, r}]}
  end

  # '$pm1'(N, A, I, R): R = found(D), more(A1, I1) oder none
  defbuiltin "$pm1", [n, x, i, res] do
    r =
      case NumberTheory.pm1_step(deref(n), deref(x), deref(i)) do
        {:found, d} -> mk("found", [d])
        {:more, a1, i1} -> mk("more", [a1, i1])
        :none -> a("none")
      end

    {:unify, [{res, r}]}
  end

  defbuiltin "$divisors", [pes, ds] do
    {:unify, [{ds, list(NumberTheory.divisors(pes_list(pes, subst())))}]}
  end

  defbuiltin "$totient", [pes, t] do
    {:unify, [{t, NumberTheory.totient(pes_list(pes, subst()))}]}
  end

  defp pes_term(fs), do: list(for({p, e} <- fs, do: mk("-", [p, e])))

  defp pes_list(t, s) do
    PrologEx.Builtins.Lists.items(t, s)
    |> Enum.map(fn pe ->
      {_, "-", [p, e]} = Store.walk(pe, s)
      {Store.walk(p, s), Store.walk(e, s)}
    end)
  end
end
