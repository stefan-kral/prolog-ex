# ucd_check.exs UCD17 : char_type-Klassen und upper/lower gegen die Ausgabe
# von ucd.py, für jeden Codepunkt (Elixir, direkt auf PrologEx.Builtins.Charsio)
alias PrologEx.Builtins.Charsio
[file] = System.argv()
want = fn gc, ws ->
  %{"alphabetic" => String.starts_with?(gc, "L") or gc == "Nl",
    "lower" => gc == "Ll", "upper" => gc == "Lu",
    "numeric" => String.starts_with?(gc, "N"), "control" => gc == "Cc",
    "whitespace" => ws == "1"}
end
cps = fn s -> s |> String.split(".") |> Enum.map(&String.to_integer/1) end
res =
  file |> File.stream!() |> Stream.chunk_every(20000)
  |> Task.async_stream(fn ls ->
    Enum.reduce(ls, %{}, fn l, acc ->
      [c, gc, ws, up, lo] = String.split(l)
      c = String.to_integer(c)
      acc =
        Enum.reduce(want.(gc, ws), acc, fn {k, w}, acc ->
          if Charsio.type?(c, k) == w, do: acc, else: Map.update(acc, k, [{c, gc}], &[{c, gc} | &1])
        end)
      ch = <<c::utf8>>
      acc = if String.to_charlist(String.upcase(ch)) == cps.(up), do: acc, else: Map.update(acc, "upper(U)", [{c, gc}], &[{c, gc} | &1])
      if String.to_charlist(String.downcase(ch)) == cps.(lo), do: acc, else: Map.update(acc, "lower(L)", [{c, gc}], &[{c, gc} | &1])
    end)
  end, timeout: :infinity)
  |> Enum.reduce(%{}, fn {:ok, m}, acc -> Map.merge(acc, m, fn _, a, b -> a ++ b end) end)
for {k, v} <- Enum.sort(res) do
  v = Enum.sort(v)
  IO.puts("#{k}: #{length(v)} falsch, z. B. #{inspect(Enum.take(v, 6), base: :hex)}")
  IO.puts("   Kategorien: #{inspect(v |> Enum.frequencies_by(&elem(&1, 1)) |> Enum.sort_by(&(-elem(&1, 1))) |> Enum.take(8))}")
end
if res == %{}, do: IO.puts("alles gleich")
