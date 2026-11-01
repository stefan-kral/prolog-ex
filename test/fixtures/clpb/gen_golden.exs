# Erzeugt test/fixtures/clpb/golden.txt: zufällige clpb-Anfragen mit den
# Antworten der Prolog-Fassung (Scryer, b7066b4) als Referenz.
#   mix run test/fixtures/clpb/gen_golden.exs
defmodule Gen do
  @vars ~w(X Y Z W V)
  @atoms ~w(a b)

  def leaf(r) do
    case :rand.uniform(12) do
      n when n <= 8 -> Enum.at(@vars, rem(n + r, 5))
      9 -> "0"
      10 -> "1"
      _ -> Enum.at(@atoms, rem(r, 2))
    end
  end

  def f(0, r), do: leaf(r)

  def f(d, r) do
    case :rand.uniform(11) do
      1 -> "~ " <> paren(f(d - 1, r + 1))
      2 -> "(#{f(d - 1, r)} * #{f(d - 1, r + 2)})"
      3 -> "(#{f(d - 1, r)} + #{f(d - 1, r + 3)})"
      4 -> "(#{f(d - 1, r)} \# #{f(d - 1, r + 1)})"
      5 -> "(#{f(d - 1, r)} =:= #{f(d - 1, r + 4)})"
      6 -> "(#{f(d - 1, r)} =< #{f(d - 1, r + 1)})"
      7 -> "(#{f(d - 1, r)} =\\= #{f(d - 1, r + 2)})"
      8 -> "card([#{:rand.uniform(3) - 1}],[#{Enum.join(Enum.take_random(@vars, 3), ",")}])"
      9 -> "+[#{Enum.join(Enum.take_random(@vars, 2), ",")}]"
      10 -> "#{Enum.at(@vars, rem(r, 5))} ^ #{paren(f(d - 1, r + 1))}"
      _ -> leaf(r)
    end
  end

  defp paren(s), do: "(" <> s <> ")"

  def query do
    sats = for _ <- 1..:rand.uniform(3), do: "sat(#{f(:rand.uniform(3), :rand.uniform(5))})"

    extra =
      case :rand.uniform(10) do
        1 -> ["X = 1"]
        2 -> ["Y = 0"]
        3 -> ["taut(#{f(2, 1)}, T)"]
        4 -> ["labeling([X,Y,Z])"]
        5 -> ["sat_count(+[1,X,Y,Z,W], N)"]
        6 -> ["X = Y"]
        _ -> []
      end

    Enum.join(sats ++ extra, ", ")
  end
end

alias PrologEx.Reader
{:ok, r} = Reader.start_link()
Reader.put_current(r)
PrologEx.put_db(%{})
{db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, ":- use_module(library(clpb)).\n"))
PrologEx.put_db(db)
:rand.seed(:exsss, {2026, 11, 2})

lines =
  for _ <- 1..400 do
    q = Gen.query()
    [{:term, g, _}] = Reader.read_terms(r, q <> ".")

    ans =
      try do
        db
        |> PrologEx.query(g)
        |> Enum.take(4)
        |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
        |> case do
          [] -> "false"
          as -> Enum.join(as, " ; ")
        end
      rescue
        e in PrologEx.Error ->
          "error: " <> PrologEx.Writer.format(PrologEx.unmark(e.term), quoted: true)
      end

    q <> "\t" <> ans
  end

File.write!(Path.join(__DIR__, "golden.txt"), Enum.join(lines, "\n") <> "\n")
IO.puts("#{length(lines)} Anfragen")
