# check.exs OUT SHORTEST DATA... : liest jede Zeile (f16 f32 f64 Text) mit
# number_codes (Atoms.parse_number) und dem Leser (Parser.read_term),
# vergleicht die Bits mit f64; Schreiben: format_float liest sich zurück
# und hat die kürzesten Ziffern (shortest.txt aus Python).
alias PrologEx.Parser
alias PrologEx.Builtins.Atoms
[out, short | files] = System.argv()
ctx = Parser.context("")
tab = :ets.new(:shortest, [:set, :public, read_concurrency: true])
short |> File.stream!() |> Enum.each(fn l ->
  [h, d, e] = String.split(l)
  :ets.insert(tab, {h, {d, String.to_integer(e)}})
end)
sh = fn h -> case :ets.lookup(tab, h) do [{_, v}] -> v; _ -> nil end end
re = ~r/^(\d*)(?:\.(\d*))?(?:[eE]([-+]?\d+))?$/
norm = fn s ->
  # Wert = 0.DIGITS * 10^EXP wie in shortest.py
  {m, e} = case String.split(s, "e") do
    [m] -> {m, 0}
    [m, e] -> {m, String.to_integer(e)}
  end
  [i, f] = String.split(String.trim_leading(m, "-"), ".")
  all = i <> f
  ds = String.trim_leading(all, "0")
  lead = byte_size(all) - byte_size(ds)
  ds = String.trim_trailing(ds, "0")
  if ds == "", do: {"0", 0}, else: {ds, byte_size(i) + e - lead}
end
check = fn line ->
  <<_::binary-size(14), h::binary-size(16), " ", s::binary>> = String.trim_trailing(line)
  [_, i, f, e] = case Regex.run(re, s) do
    [a, b] -> [a, b, "", ""]
    [a, b, c] -> [a, b, c, ""]
    x -> x
  end
  t = (if i == "", do: "0", else: i) <> "." <> (if f == "", do: "0", else: f) <> (if e == "", do: "", else: "e" <> e)
  inf? = h == "7FF0000000000000"
  want = if inf?, do: :inf, else: (<<x::float>> = Base.decode16!(h); x)
  a = case Atoms.parse_number(t) do {:ok, x} -> x; :max_float -> :inf; o -> o end
  b = case Parser.read_term(t <> " .", 0, ctx) do
    {:term, x, _, _, _, _} -> x
    {:error, "Syntaxfehler" <> m, _, _} -> if String.ends_with?(m, "nicht darstellbar"), do: :inf, else: {:error, m}
    o -> o
  end
  same = fn x -> x == want and (is_atom(x) or <<x::float>> == <<want::float>>) end
  errs = []
  errs = if same.(a), do: errs, else: [{:number_codes, a} | errs]
  errs = if same.(b), do: errs, else: [{:read, b} | errs]
  errs =
    if inf? or not is_float(a) do
      errs
    else
      w = PrologEx.format_float(want)
      back = case Atoms.parse_number(w) do {:ok, x} -> x; o -> o end
      errs = if is_float(back) and <<back::float>> == <<want::float>>, do: errs, else: [{:roundtrip, w, back} | errs]
      if norm.(w) == sh.(h), do: errs, else: [{:shortest, w, sh.(h)} | errs]
    end
  if errs == [], do: nil, else: "#{h} #{s} #{t} #{inspect(errs)}"
end
{:ok, dev} = File.open(out, [:write])
n =
  files
  |> Stream.flat_map(&File.stream!/1)
  |> Stream.chunk_every(5000)
  |> Task.async_stream(fn ls -> {length(ls), for(l <- ls, r = check.(l), do: r)} end, max_concurrency: System.schedulers_online(), ordered: false, timeout: :infinity)
  |> Enum.reduce(0, fn {:ok, {k, rs}}, n ->
    for r <- rs, do: IO.puts(dev, r)
    n + k
  end)
IO.puts("#{n} Zeilen")
