# Abdeckung der Prolog-Bibliotheken: welche Klauseln laufen in den Tests?
#
#   mix run bench/coverage/prolog.exs [--lib NAME]... [--pre LIB]... [--] TESTDATEIEN...
#
# Vorgabe: --lib concurrent --lib clpz_concurrent, Tests
# test/concurrent_test.exs test/clpz_concurrent_test.exs. --pre lädt eine
# Bibliothek vorher (ihre Operatoren braucht das Lesen), für
# clpz_concurrent automatisch clpz.
#
# Ablauf: jede Klausel von priv/library/NAME.pl bekommt als erstes Ziel
# '$coverage'(Id) (PrologEx.Coverage); die umgeschriebenen Dateien ersetzen
# vorübergehend die Originale, `mix test` läuft mit PROLOG_EX_COVERAGE,
# danach kommen die Originale zurück (auch bei Fehlern). Bericht: je
# Prädikat Klauseln getroffen / gesamt, die nie getroffenen mit Zeile.

{opts, files, _} = OptionParser.parse(System.argv(), strict: [lib: :keep, pre: :keep])
libs = Keyword.get_values(opts, :lib)
libs = if libs == [], do: ~w(concurrent clpz_concurrent), else: libs
pre = Keyword.get_values(opts, :pre)
pre = if "clpz_concurrent" in libs, do: Enum.uniq(["clpz" | pre]), else: pre
files = if files == [], do: ~w(test/concurrent_test.exs test/clpz_concurrent_test.exs), else: files

{:ok, r} = PrologEx.Reader.start_link()
PrologEx.Reader.put_current(r)

for l <- pre do
  {_, _} = PrologEx.Consult.load(%{}, PrologEx.Reader.read_terms(r, ":- use_module(library(#{l}))."))
end

lib_dir = Path.join(File.cwd!(), "priv/library")
tmp = Path.join(System.tmp_dir!(), "prolog_ex_coverage_#{System.unique_integer([:positive])}")
File.mkdir_p!(tmp)
hits_file = Path.join(tmp, "hits.txt")

# Variablen als V1, V2, ... (nicht _N: das gäbe Warnungen zu mehrfach
# verwendeten _-Variablen)
# einmal vorkommende als _ (sonst Singleton-Warnungen)
count = fn count, t, acc ->
  case PrologEx.unmark_top(t) do
    {:var, _} = v -> Map.update(acc, v, 1, &(&1 + 1))
    {:struct, _, as} -> Enum.reduce(as, acc, &count.(count, &1, &2))
    [h | tl] -> count.(count, tl, count.(count, h, acc))
    _ -> acc
  end
end

w = fn t ->
  t = PrologEx.unmark(t)
  occ = count.(count, t, %{})

  names =
    PrologEx.fresh_var_names([t])
    |> Enum.with_index(1)
    |> Enum.map(fn {{v, _}, i} -> {v, if(occ[v] == 1, do: "_", else: "V#{i}")} end)
    |> Map.new()

  PrologEx.Writer.format(t, quoted: true, variable_names: names)
end
cov = fn id -> {:struct, "$coverage", [id]} end

# {id, lib, zeile, name/stelligkeit}
{table, _} =
  Enum.flat_map_reduce(libs, 0, fn lib, n ->
    path = Path.join(lib_dir, lib <> ".pl")
    text = File.read!(path)
    File.cp!(path, Path.join(tmp, lib <> ".pl.orig"))

    {out, ids, n} =
      text
      |> PrologEx.Parser.read_terms(lines: true)
      # (ground Terme kommen markiert: oben aufheben)
      |> Enum.map(fn {:term, t, names, line} -> {:term, PrologEx.unmark_top(t), names, line} end)
      |> Enum.reduce({[], [], n}, fn
        {:term, {:struct, ":-", [_]} = d, _, _}, {out, ids, n} ->
          {[w.(d) | out], ids, n}

        {:term, {:struct, ":-", [h, b]}, _, line}, {out, ids, n} ->
          t = {:struct, ":-", [h, {:struct, ",", [cov.(n), b]}]}
          {[w.(t) | out], [{n, lib, line, h} | ids], n + 1}

        {:term, h, _, line}, {out, ids, n} ->
          t = {:struct, ":-", [h, cov.(n)]}
          {[w.(t) | out], [{n, lib, line, h} | ids], n + 1}

        other, _acc ->
          raise "#{lib}: nicht lesbar: #{inspect(other, limit: 5)}"
      end)

    File.write!(Path.join(tmp, lib <> ".pl"), Enum.map(Enum.reverse(out), &(&1 <> ".\n")))
    {Enum.reverse(ids), n}
  end)

pi = fn h ->
  case PrologEx.unmark_top(h) do
    {:struct, f, as} -> "#{f}/#{length(as)}"
    {:atom, f} -> "#{f}/0"
    other -> inspect(other)
  end
end

try do
  for lib <- libs, do: File.cp!(Path.join(tmp, lib <> ".pl"), Path.join(lib_dir, lib <> ".pl"))

  {_, code} =
    System.cmd("mix", ["test" | files],
      env: [{"PROLOG_EX_COVERAGE", hits_file}, {"MIX_ENV", "test"}],
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    )

  IO.puts("\n(mix test: Exit #{code})\n")
after
  for lib <- libs, do: File.cp!(Path.join(tmp, lib <> ".pl.orig"), Path.join(lib_dir, lib <> ".pl"))
end

hits =
  if File.exists?(hits_file) do
    for l <- File.read!(hits_file) |> String.split("\n", trim: true), into: %{} do
      [id, k] = String.split(l)
      {String.to_integer(id), String.to_integer(k)}
    end
  else
    %{}
  end

for lib <- libs do
  rows = for {id, ^lib, line, h} <- table, do: {id, line, pi.(h)}
  hit = Enum.count(rows, fn {id, _, _} -> Map.has_key?(hits, id) end)
  IO.puts("== #{lib}: #{hit}/#{length(rows)} Klauseln getroffen (#{div(hit * 100, max(length(rows), 1))} %)")
  src = File.read!(Path.join(lib_dir, lib <> ".pl")) |> String.split("\n") |> List.to_tuple()

  rows
  |> Enum.group_by(fn {_, _, p} -> p end)
  |> Enum.sort_by(fn {_, cs} -> elem(hd(cs), 1) end)
  |> Enum.each(fn {p, cs} ->
    miss = Enum.reject(cs, fn {id, _, _} -> Map.has_key?(hits, id) end)

    if miss != [] do
      IO.puts("  #{p}: #{length(cs) - length(miss)}/#{length(cs)}")

      for {_, line, _} <- miss,
          do: IO.puts("     Zeile #{line}: #{String.trim(elem(src, line - 1)) |> String.slice(0, 90)}")
    end
  end)
end
