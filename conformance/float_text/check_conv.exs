# check_conv.exs OUT DATA... : Text als exakte Zahl N*10^E; ganzzahlig:
# float(Int) (Rational.int_to_float), sonst Rational.to_float(N/10^k); Bits gegen f64
alias PrologEx.Rational, as: Rat
[out | files] = System.argv()
re = ~r/^(\d*)(?:\.(\d*))?(?:[eE]([-+]?\d+))?$/
conv = fn f ->
  try do
    {:ok, f.()}
  rescue
    ArithmeticError -> :inf
    e in PrologEx.Error -> if Exception.message(e) =~ "overflow", do: :inf, else: {:err, Exception.message(e)}
  end
end
check = fn line ->
  <<_::binary-size(14), h::binary-size(16), " ", s::binary>> = String.trim_trailing(line)
  [_ | parts] = Regex.run(re, s)
  [i, f, e] = parts ++ List.duplicate("", 3 - length(parts))
  n = String.to_integer(if(i <> f == "", do: "0", else: i <> f))
  e = if(e == "", do: 0, else: String.to_integer(e)) - byte_size(f)
  digits = byte_size(Integer.to_string(n))
  cond do
    n == 0 or e + digits > 400 or e + digits < -400 or abs(e) > 1200 -> nil
    true ->
      want = if h == "7FF0000000000000", do: :inf, else: (<<x::float>> = Base.decode16!(h); {:ok, x})
      {what, got} =
        if e >= 0 do
          int = n * Integer.pow(10, e)
          {:int, conv.(fn -> Rat.int_to_float(int) end)}
        else
          {:rat, conv.(fn -> Rat.to_float({:rat, n, Integer.pow(10, -e)}) end)}
        end
      ok = case {got, want} do
        {{:ok, a}, {:ok, b}} -> <<a::float>> == <<b::float>>
        {a, b} -> a == b
      end
      if ok, do: nil, else: "#{h} #{s} #{what} #{inspect(got)} #{inspect(want)}"
  end
end
{:ok, dev} = File.open(out, [:write])
{n, bad} =
  files
  |> Stream.flat_map(&File.stream!/1)
  |> Stream.chunk_every(5000)
  |> Task.async_stream(fn ls -> {length(ls), for(l <- ls, r = check.(l), do: r)} end, max_concurrency: System.schedulers_online(), ordered: false, timeout: :infinity)
  |> Enum.reduce({0, 0}, fn {:ok, {k, rs}}, {n, b} ->
    for r <- rs, do: IO.puts(dev, r)
    {n + k, b + length(rs)}
  end)
IO.puts("#{n} Zeilen, #{bad} falsch")
