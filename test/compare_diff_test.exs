defmodule PrologEx.CompareDiffTest do
  # compare/3 und ==/2 gegen eine unabhängige Umsetzung der Standardordnung:
  # die Sortierschlüssel (Order.key/2), deren BEAM-Ordnung der
  # Standardordnung entspricht. Zufällige Termpaare mit gebundenen und
  # freien Variablen, markierten und gebauten Listen und Strukturen.
  use ExUnit.Case, async: true
  import PrologEx
  alias PrologEx.Order

  @vars for i <- 1..6, do: {:var, i}

  defp gen(0, _), do: leaf()

  defp gen(d, s) do
    case :rand.uniform(9) do
      n when n <= 3 -> leaf()
      4 -> mk(Enum.random(["f", "g", "."]), for(_ <- 1..:rand.uniform(3), do: gen(d - 1, s)))
      5 -> list(for(_ <- 1..:rand.uniform(4), do: gen(d - 1, s)))
      6 -> list(for(_ <- 1..:rand.uniform(4), do: gen(d - 1, s)), gen(d - 1, s))
      # unmarkiert gebaut, auch wenn ground
      7 -> {:struct, Enum.random(["f", "g"]), for(_ <- 1..:rand.uniform(3), do: gen(d - 1, s))}
      8 -> [gen(d - 1, s) | gen(d - 1, s)]
      9 -> {:struct, ".", [gen(d - 1, s), gen(d - 1, s)]}
    end
  end

  defp leaf do
    Enum.random([
      fn -> :rand.uniform(4) - 2 end,
      fn -> Enum.random([0.5, 1.0, -1.0, 2.0]) end,
      fn -> {:atom, Enum.random(["a", "b", "[]", "ab", "Z"])} end,
      fn -> [] end,
      fn -> Enum.random(@vars) end,
      fn -> {:var, "_G#{:rand.uniform(3)}"} end,
      fn -> {:var, {:c, :rand.uniform(3)}} end
    ]).()
  end

  # Variablen 1..3 binden (an Terme ohne diese Variablen: keine Zyklen)
  defp subst do
    for {:var, i} = v <- @vars, i <= 3, :rand.uniform(2) == 1, into: %{} do
      {v, gen_no_bound(2)}
    end
  end

  defp gen_no_bound(d) do
    t = gen(d, %{})
    if bound_var?(t), do: :rand.uniform(9), else: t
  end

  defp bound_var?({:var, i}) when is_integer(i) and i <= 3, do: true
  defp bound_var?({_, _, args}) when is_list(args), do: Enum.any?(args, &bound_var?/1)
  defp bound_var?({:glist, l}), do: bound_var?(l)
  defp bound_var?([h | t]), do: bound_var?(h) or bound_var?(t)
  defp bound_var?(_), do: false

  defp ref(a, b, s) do
    {ka, kb} = {Order.key(a, s), Order.key(b, s)}

    cond do
      ka < kb -> :lt
      ka > kb -> :gt
      true -> :eq
    end
  end

  defp flip(:lt), do: :gt
  defp flip(:gt), do: :lt
  defp flip(:eq), do: :eq

  test "compare/3 und ==/2 wie die Sortierschlüssel (20 000 Paare)" do
    :rand.seed(:exsss, {1, 2, 3})

    for _ <- 1..20_000 do
      s = subst()
      a = gen(4, s)
      b = if :rand.uniform(4) == 1, do: a, else: gen(4, s)
      r = Order.compare(a, b, s)
      assert r == ref(a, b, s), "compare(#{inspect(a)}, #{inspect(b)}, #{inspect(s)})"
      assert Order.compare(b, a, s) == flip(r)
      assert Order.equal?(a, b, s) == (r == :eq)
      assert Order.compare(a, a, s) == :eq
    end
  end

  test "ganze Zahlen gegen Floats und -0.0" do
    assert Order.compare(1, 1.0, %{}) == :gt
    assert Order.compare(1.0, 1, %{}) == :lt
    assert Order.compare(2, 1.5, %{}) == :gt
    assert Order.compare(1.5, 2, %{}) == :lt
    assert Order.compare(100, 1.0e10, %{}) == :gt
    assert Order.compare(-0.0, 0.0, %{}) == :eq
    assert Order.compare(s("f", [-0.0]), s("f", [0.0]), %{}) == :eq
    assert Order.compare(10 ** 30, 10 ** 30 + 1, %{}) == :lt
  end
end
