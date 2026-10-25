Code.require_file("fixtures/writer_ref.ex", __DIR__)

defmodule PrologEx.WriterDeepTest do
  # Der Writer läuft entlang der Ränder in Schleifen (kein Stack, der mit der
  # Tiefe wächst). Vergleich mit dem früheren, rekursiven Writer
  # (fixtures/writer_ref.ex): zufällige Terme, alle Optionen, eigene
  # Operatoren – die Ausgabe muss Zeichen für Zeichen gleich sein.
  use ExUnit.Case, async: true
  import PrologEx, only: [a: 1, mk: 2]
  alias PrologEx.{Writer, WriterRef}

  # Standardtabelle plus Postfix-Operatoren, alphanumerische und solche,
  # die zugleich Präfix und Infix sind
  defp ops do
    PrologEx.Ops.default()
    |> Map.put("!!", %{postfix: {200, "xf"}})
    |> Map.put("++", %{postfix: {300, "yf"}, infix: {300, "xfx"}})
    |> Map.put("op_a", %{prefix: {700, "fx"}, infix: {650, "xfy"}})
    |> Map.put("lft", %{infix: {800, "yfx"}})
    |> Map.put("rgt", %{infix: {850, "xfy"}, postfix: {850, "yf"}})
  end

  @atoms ~w(a b foo [] {} - + * - mod is ! ; , | !! ++ op_a lft rgt :- \\+ dynamic) ++
           ["A b", "ä", "", ".", "/*", "'"]
  @funs ~w(f g - + * / ** ^ mod , ; -> :- \\+ = is {} !! ++ op_a lft rgt dynamic : $VAR) ++
          ["A b", "-", "-"]

  defp gen(0), do: leaf()

  defp gen(d) do
    case :rand.uniform(10) do
      n when n <= 2 ->
        leaf()

      n when n <= 8 ->
        f = Enum.random(@funs)
        arity = if f == "$VAR", do: 1, else: Enum.random([1, 2, 2, 2, 3])

        args =
          if f == "$VAR",
            do: [Enum.random([0, 3, 27, -1, a("x")])],
            else: for(_ <- 1..arity, do: gen(d - 1))

        mk(f, args)

      9 ->
        items = for _ <- 1..Enum.random(1..3), do: gen(d - 1)
        # {:glist, l}: markierte grundierte Liste (auch als Rest)
        tail = Enum.random([[], [], {:var, "T"}, gen(d - 1), {:glist, [a("g"), 1, a("h")]}])
        items ++ tail

      10 ->
        Enum.map(Enum.random([~c"ab", ~c"x", ~c"\"q"]), &a(<<&1>>))
    end
  end

  defp leaf do
    Enum.random([
      a(Enum.random(@atoms)),
      Enum.random([0, 1, -1, 42, -7, 1.5, -2.5e10]),
      {:var, Enum.random(["X", "_Y"])},
      {:var, 17},
      {:var, {:attv, 3}}
    ])
  end

  defp opts do
    for q <- [true, false],
        io <- [false, true],
        nv <- [true, false],
        st <- [false, true],
        sp <- [nil, :next_argument],
        md <- [0, 3],
        pr <- [1200, 999, 699],
        op <- [false, true] do
      [
        quoted: q,
        ignore_ops: io,
        numbervars: nv,
        strings: st,
        spacing: sp,
        max_depth: md,
        priority: pr,
        operand: op,
        variable_names: %{{:var, 17} => "Named"},
        ops: ops()
      ]
    end
  end

  test "zufällige Terme: gleiche Ausgabe wie der rekursive Writer" do
    :rand.seed(:exsss, {1, 2, 3})
    all = opts()

    for _ <- 1..4000 do
      t = gen(Enum.random(1..6))
      o = Enum.random(all)
      assert Writer.format(t, o) == WriterRef.format(t, o), inspect({t, o})
    end
  end

  # tiefe Terme jeder Sorte: gleiche Ausgabe, und das Ergebnis stimmt
  defp deep(:last_arg, n), do: Enum.reduce(1..n, a("z"), &mk("f", [&1, &2]))
  defp deep(:single, n), do: Enum.reduce(1..n, 0, fn _, t -> mk("s", [t]) end)
  defp deep(:xfy, n), do: Enum.reduce(1..n, a("z"), &mk(",", [a("g#{&1}"), &2]))
  defp deep(:yfx, n), do: Enum.reduce(1..n, 0, &mk("+", [&2, &1]))
  defp deep(:prefix, n), do: Enum.reduce(1..n, a("a"), fn _, t -> mk("-", [t]) end)
  defp deep(:curly, n), do: Enum.reduce(1..n, a("a"), fn _, t -> mk("{}", [t]) end)
  defp deep(:postfix, n), do: Enum.reduce(1..n, a("a"), fn _, t -> mk("++", [t]) end)

  defp deep(:lists, n), do: Enum.reduce(1..n, [], fn i, t -> [i, t] end)
  defp deep(:middle, n), do: Enum.reduce(1..n, a("z"), &mk("g", [&1, &2, mk("h", [&1])]))

  defp deep(:mixed, n) do
    Enum.reduce(1..n, a("z"), fn i, t ->
      case rem(i, 6) do
        0 -> mk("f", [t])
        1 -> mk("-", [mk("+", [t, i])])
        2 -> mk(";", [a("x"), t])
        3 -> mk("{}", [t])
        4 -> mk("g", [i, t, mk("h", [i])])
        5 -> [t | a("x")]
      end
    end)
  end

  @kinds [:last_arg, :single, :xfy, :yfx, :prefix, :curly, :postfix, :lists, :middle, :mixed]

  test "tiefe Terme: gleiche Ausgabe wie der rekursive Writer" do
    for k <- @kinds, o <- [[quoted: true], [ignore_ops: true], [max_depth: 50]] do
      t = deep(k, 5000)
      o = [{:ops, ops()} | o]
      assert Writer.format(t, o) == WriterRef.format(t, o), "#{k} #{inspect(o)}"
    end
  end

  test "Beispiele: tiefe Terme richtig geschrieben" do
    assert Writer.format(deep(:last_arg, 3)) == "f(3,f(2,f(1,z)))"
    assert Writer.format(deep(:yfx, 4)) == "0+1+2+3+4"
    assert Writer.format(deep(:xfy, 3)) == "g3,g2,g1,z"
    assert Writer.format(deep(:prefix, 3)) == "- - -a"
    assert Writer.format(deep(:last_arg, 2), ignore_ops: true) == "f(2,f(1,z))"
    assert Writer.format(mk("-", [mk("-", [1])])) == "- - (1)"
    assert Writer.format({:struct, "f", []}) == "f()"
    assert Writer.format(mk("g", [1, deep(:single, 2), a("b")])) == "g(1,s(s(0)),b)"

    n = 200_000
    assert Writer.format(deep(:last_arg, n), ignore_ops: true) |> byte_size() > 4 * n
  end

  # Der Stack des schreibenden Prozesses wächst nicht mit der Tiefe
  # (abgetastet, während er schreibt)
  test "konstanter Stack entlang der Ränder" do
    for k <- @kinds do
      small = max_stack(fn -> Writer.format(deep(k, 1000)) end)
      big = max_stack(fn -> Writer.format(deep(k, 100_000)) end)
      assert big < 2 * small + 1000, "#{k}: #{small} -> #{big}"
    end
  end

  # höchste Stackgröße (Wörter) während f läuft, abgetastet
  defp max_stack(f) do
    pid = spawn(fn -> receive(do: (:go -> f.())) end)
    ref = Process.monitor(pid)
    send(pid, :go)
    sample(pid, ref, 0)
  end

  defp sample(pid, ref, m) do
    receive do
      {:DOWN, ^ref, _, _, _} -> m
    after
      0 ->
        case Process.info(pid, :stack_size) do
          {:stack_size, s} -> sample(pid, ref, max(m, s))
          nil -> m
        end
    end
  end
end
