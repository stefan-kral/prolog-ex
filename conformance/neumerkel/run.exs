# Neumerkels Konformitätstabelle (ISO-Syntax, Lesen und Schreiben) in der
# Fassung von Scryer Prolog (tests-pl/iso-conformity-tests.pl, Nummern wie
# in der Tabelle):
#
#   git clone --depth 1 https://github.com/mthom/scryer-prolog /pfad/scryer
#   mix run conformance/neumerkel/run.exs /pfad/scryer
#
# Scryers Hilfsprädikate (read_from_chars/2, write_term_to_chars/3, ...)
# bildet prelude.pl über Dateien mit ISO-Builtins nach; bei
# test_syntax_error zählt nur die Fehlerart (die Bezeichnung in
# syntax_error/1 ist implementierungsabhängig).
[scryer] = System.argv()
src = File.read!(Path.join(scryer, "tests-pl/iso-conformity-tests.pl"))
i = :binary.match(src, "test_1 :-") |> elem(0)
j = :binary.match(src, "run_tests([Test|Tests])") |> elem(0)
body = binary_part(src, i, j - i)

work = Path.join(System.tmp_dir!(), "prolog_ex_neumerkel")
File.mkdir_p!(work)
tmp = Path.join(work, "io.txt")
file = Path.join(work, "tests.pl")

prelude =
  File.read!(Path.join(__DIR__, "prelude.pl")) <>
    "'$neumerkel_tmp'(#{PrologEx.format({:atom, tmp}, quoted: true)}).\n"

# wie im Original (Scryer): library(iso_ext) und library(files) importiert
File.write!(file, ":- set_prolog_flag(double_quotes, chars).\n:- use_module(library(iso_ext)).\n:- use_module(library(files)).\n" <> prelude <> "\n" <> body)

# Testtexte (für die Ausgabe): "test_N :- ..." bis zur nächsten Leerzeile
bodies =
  Regex.scan(~r/^(test_[\d_]+) :-(.*?)\n\n/ms, body <> "\n\n")
  |> Map.new(fn [_, name, b] -> {name, String.trim(b)} end)

PrologEx.put_db(%{})
{:ok, _} = Application.ensure_all_started(:ex_unit)
msgs = ExUnit.CaptureIO.capture_io(:stderr, fn -> PrologEx.Consult.load_file(file) end)
for m <- String.split(msgs, "\n"), m =~ "Fehler", do: IO.puts(m)

db = PrologEx.current_db()

tests =
  for({"user", "test_" <> n, 0} <- Map.keys(db), do: n)
  |> Enum.sort_by(fn n -> n |> String.split("_") |> Enum.map(&String.to_integer/1) end)

state = for k <- [:prolog_ex_ops, :prolog_ex_flags], do: {k, Process.get(k)}

run = fn n ->
  parent = self()

  pid =
    spawn(fn ->
      for {k, v} <- state, v != nil, do: Process.put(k, v)
      PrologEx.put_db(db)
      {:ok, io} = StringIO.open("")
      Process.group_leader(self(), io)

      r =
        try do
          case PrologEx.query(db, {:atom, "test_#{n}"}) |> Enum.take(1) do
            [_] -> :pass
            [] -> :fail
          end
        rescue
          e -> {:error, Exception.message(e) |> String.slice(0, 160)}
        end

      send(parent, {:r, r})
    end)

  receive do
    {:r, r} -> r
  after
    5000 ->
      Process.exit(pid, :kill)
      :timeout
  end
end

kind = fn b ->
  cond do
    b =~ "read_from_chars" or b =~ "test_syntax_error" -> :lesen
    b =~ "term_to_chars" or b =~ "writeq(" or b =~ "write_canonical(" -> :schreiben
    true -> :sonst
  end
end

results = for n <- tests, do: {n, kind.(Map.get(bodies, "test_#{n}", "")), run.(n)}

IO.puts("\nNicht bestanden:")

for {n, k, r} <- results, r != :pass do
  IO.puts(
    "##{n} [#{k}] #{inspect(r)}\n    " <>
      String.replace(Map.get(bodies, "test_#{n}", "?"), "\n", "\n    ")
  )
end

IO.puts("")

for k <- [:lesen, :schreiben, :sonst] do
  rs = for {_, ^k, r} <- results, do: r
  IO.puts("#{k}: #{Enum.count(rs, &(&1 == :pass))}/#{length(rs)}")
end

IO.puts("gesamt: #{Enum.count(results, &(elem(&1, 2) == :pass))}/#{length(results)}")
