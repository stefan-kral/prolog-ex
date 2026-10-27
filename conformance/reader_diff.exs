# Vergleicht PrologEx.Parser mit dem gprolog-Reader.
#   mix run conformance/reader_diff.exs datei...
#   mix run conformance/reader_diff.exs --list dateiliste
#   mix run conformance/reader_diff.exs --cases conformance/reader_cases.txt
# Fehler zählen nur als vorhanden/nicht vorhanden (Wiederaufsetzen ist
# implementierungsabhängig); Standardoperatoren, double_quotes=chars.
defmodule D do
  # Terme vergleichen; Fehler nur als Anzahl (Wiederaufsetzen nach
  # Zerlegungsfehlern ist implementierungsabhängig)
  def norm(items) do
    {errs, terms} = Enum.split_with(items, &match?({:error, _}, &1))
    Enum.map(terms, &n/1) ++ [{:errors, length(errs) > 0}]
  end

  def n({:error, _}), do: :error

  def n({:term, t, names}) do
    {t, _} = ren(PrologEx.unmark(t), %{})
    {:term, t, names |> Map.values() |> Enum.sort()}
  end

  def ren({:var, x}, m) do
    if Regex.match?(~r/^_\d+$/, x) do
      case m do
        %{^x => y} ->
          {{:var, y}, m}

        _ ->
          y = "_A#{map_size(m)}"
          {{:var, y}, Map.put(m, x, y)}
      end
    else
      {{:var, x}, m}
    end
  end

  def ren({:struct, f, as}, m) do
    {as, m} = Enum.map_reduce(as, m, &ren/2)
    {{:struct, f, as}, m}
  end

  def ren([h | t], m) do
    {h, m} = ren(h, m)
    {t, m} = ren(t, m)
    {[h | t], m}
  end

  def ren(x, m), do: {x, m}

  def cmp(label, text) do
    {:ok, r} = PrologEx.GprologReader.start_link()
    PrologEx.Ops.reset()
    g = PrologEx.Reader.read_terms(r, text)
    GenServer.stop(r)
    p = PrologEx.Parser.read_terms(text, ops: PrologEx.Ops.default(), double_quotes: "chars")
    {gn, pn} = {norm(g), norm(p)}

    if gn == pn do
      {:same, length(gn)}
    else
      IO.puts("=== #{label}: gprolog #{length(gn)} / parser #{length(pn)}")
      g = Enum.reject(g, &match?({:error, _}, &1))
      p = Enum.reject(p, &match?({:error, _}, &1))

      diffs =
        Enum.zip(Enum.zip(gn, pn), Enum.zip(g, p))
        |> Enum.reject(fn {{a, b}, _} -> a == b end)
        |> Enum.take(5)

      for {_, {x, y}} <- diffs do
        IO.puts("  gprolog: " <> show(x))
        IO.puts("  parser:  " <> show(y))
      end

      if length(gn) != length(pn), do: IO.puts("  (Anzahl verschieden)")
      :diff
    end
  end

  def show({:error, m}), do: "ERROR " <> m

  def show({:term, t, _}),
    do: PrologEx.format(t, quoted: true, ignore_ops: true) |> String.slice(0, 300)
end

case System.argv() do
  ["--cases", f] ->
    for line <- File.read!(f) |> String.split("\n"),
        String.trim(line) != "",
        not String.starts_with?(line, "#") do
      D.cmp(line, line <> "\n")
    end

  ["--list", lf] ->
    files = File.read!(lf) |> String.split("\n", trim: true)
    res = for f <- files, do: D.cmp(f, File.read!(f))

    IO.puts(
      "gleich: #{Enum.count(res, &match?({:same, _}, &1))}/#{length(res)}, Terme #{res |> Enum.map(fn
        {:same, n} -> n
        _ -> 0
      end) |> Enum.sum()}"
    )

  files ->
    res = for f <- files, do: D.cmp(f, File.read!(f))

    IO.puts(
      "gleich: #{Enum.count(res, &match?({:same, _}, &1))}/#{length(res)}, Terme #{res |> Enum.map(fn
        {:same, n} -> n
        _ -> 0
      end) |> Enum.sum()}"
    )
end
