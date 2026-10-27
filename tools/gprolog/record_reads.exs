# gprologs Lesart der Grenzfälle aufzeichnen (braucht gplc):
#   mix run tools/gprolog/record_reads.exs
# schreibt test/fixtures/reader/gprolog_reads.txt
Code.require_file("gprolog.ex", __DIR__)
PrologEx.Tools.Gprolog.ensure_loaded()
{:ok, r} = PrologEx.GprologReader.start_link()

cases =
  File.read!("conformance/reader_cases.txt")
  |> String.split("\n")
  |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  |> Enum.filter(&String.ends_with?(&1, "."))

pairs =
  for c <- cases do
    res =
      for item <- PrologEx.GprologReader.read_terms(r, c <> "\n") do
        case item do
          {:term, t, _} -> PrologEx.format(t, quoted: true, ignore_ops: true)
          {:error, _} -> :error
        end
      end

    {c, res}
  end

body =
  Enum.map_join(pairs, "", fn p ->
    inspect(p, limit: :infinity, printable_limit: :infinity) <> "\n"
  end)

File.write!(
  "test/fixtures/reader/gprolog_reads.txt",
  "# gprologs Lesart der einzeiligen Fälle aus conformance/reader_cases.txt\n# (aufgezeichnet mit tools/gprolog/record_reads.exs; je Zeile {Fall, Ergebnis})\n" <>
    body
)

IO.puts(length(pairs))
