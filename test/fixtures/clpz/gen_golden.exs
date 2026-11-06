# Erzeugt test/fixtures/clpz/golden.txt: zufällige clpz-Anfragen mit den
# Antworten der Prolog-Fassung (Triskas clpz.pl aus Scryer, b7066b4) als
# Referenz für jeden späteren Schritt nach Elixir.
#   mix run test/fixtures/clpz/gen_golden.exs
#
# Dieselben Anfragen (und mehr: SEED=n N=m) laufen auch in Scryer:
#   mix run test/fixtures/clpz/gen_golden.exs --queries > q.pl
#   cat test/fixtures/clpz/harness.pl q.pl > a.pl
#   scryer-prolog a.pl -g t -g halt   bzw.   mix prolog a.pl -g t -g halt
# und geben dann dieselben (normalisierten) Zeilen aus.
defmodule Gen do
  @vars ~w(X Y Z W)
  @rels ~w(#= #\\= #< #> #=< #>=)

  defp pick(l), do: Enum.random(l)
  defp int(a, b), do: Enum.random(a..b)

  def leaf, do: if(:rand.uniform() < 0.65, do: pick(@vars), else: "#{int(-3, 5)}")

  def expr(0), do: leaf()

  def expr(d) do
    a = fn -> expr(d - 1) end

    case int(0, 13) do
      0 -> "(#{a.()} + #{a.()})"
      1 -> "(#{a.()} - #{a.()})"
      2 -> "(#{a.()} * #{a.()})"
      3 -> "abs(#{a.()})"
      4 -> "min(#{a.()}, #{a.()})"
      5 -> "max(#{a.()}, #{a.()})"
      6 -> "(#{a.()} mod #{a.()})"
      7 -> "(#{a.()} rem #{a.()})"
      8 -> "(#{a.()} // #{a.()})"
      9 -> "(#{a.()} div #{a.()})"
      10 -> "(#{a.()} ^ #{int(0, 3)})"
      11 -> "(- #{a.()})"
      _ -> leaf()
    end
  end

  def dom do
    case int(0, 6) do
      0 -> "0..3"
      1 -> "-2..2"
      2 -> "1..3\\/6..7"
      3 -> "inf..2"
      4 -> "0..sup"
      5 -> "#{int(-2, 3)}"
      _ -> "#{int(-3, 0)}..#{int(1, 4)}"
    end
  end

  def vs(k \\ nil), do: "[" <> Enum.join(Enum.take_random(@vars, k || int(2, 4)), ",") <> "]"

  def rel, do: "#{expr(int(0, 2))} #{pick(@rels)} #{expr(int(0, 2))}"

  def reif(0), do: rel()

  def reif(d) do
    if :rand.uniform() < 0.4 do
      rel()
    else
      case int(0, 4) do
        0 -> "(#{reif(d - 1)} #<==> #{reif(d - 1)})"
        1 -> "(#{reif(d - 1)} #==> #{reif(d - 1)})"
        2 -> "(#{reif(d - 1)} #\\/ #{reif(d - 1)})"
        3 -> "(#{reif(d - 1)} #/\\ #{reif(d - 1)})"
        _ -> "#\\ (#{reif(d - 1)})"
      end
    end
  end

  def constraint do
    case int(0, 16) do
      k when k <= 4 ->
        rel()

      5 ->
        "#{pick(@vars)} in #{dom()}"

      6 ->
        "#{vs()} ins #{dom()}"

      7 ->
        "all_different(#{vs()})"

      8 ->
        "all_distinct(#{vs()})"

      9 ->
        "sum(#{vs()}, #{pick(@rels)}, #{expr(1)})"

      10 ->
        "element(#{pick(@vars)}, [#{Enum.map_join(1..3, ",", fn _ -> int(-2, 4) end)}], #{pick(@vars)})"

      11 ->
        [x, y] = Enum.take_random(@vars, 2)
        ts = Enum.map_join(1..int(1, 4), ",", fn _ -> "[#{int(0, 3)},#{int(0, 3)}]" end)
        "tuples_in([[#{x},#{y}]], [#{ts}])"

      12 ->
        "B #<==> (#{rel()})"

      13 ->
        reif(2)

      14 ->
        [x, y] = Enum.take_random(@vars, 2)
        "zcompare(O, #{x}, #{y})"

      15 ->
        "global_cardinality(#{vs(2)}, [0-C0,1-C1,2-C2])"

      _ ->
        "lex_chain([#{vs(2)},#{vs(2)}])"
    end
  end

  @all "[X,Y,Z,W]"
  @labelings [
    "label(#{@all})",
    "labeling([ff], #{@all})",
    "labeling([down], #{@all})",
    "labeling([max(X)], #{@all})",
    "labeling([min(X+Y)], #{@all})",
    "labeling([ffc,bisect], #{@all})"
  ]

  def query do
    cs = for _ <- 1..int(1, 4), do: constraint()

    extra =
      case int(0, 9) do
        k when k <= 3 -> ["#{@all} ins -3..3", pick(@labelings)]
        4 -> ["fd_dom(X, D)", "fd_size(Y, S)"]
        5 -> ["X = 1"]
        6 -> ["fd_inf(X, I), fd_sup(X, U)"]
        _ -> []
      end

    Enum.join(cs ++ extra, ", ")
  end
end

seed = String.to_integer(System.get_env("SEED", "2026"))
n = String.to_integer(System.get_env("N", "400"))
:rand.seed(:exsss, {seed, 11, 3})
queries = for _ <- 1..n, do: Gen.query()

if "--queries" in System.argv() do
  for {q, i} <- Enum.with_index(queries),
      do: IO.puts("q(#{i}, [X,Y,Z,W,B,O,D,S,I,U,C0,C1,C2], (#{q})).")
else
  alias PrologEx.Reader
  {:ok, r} = Reader.start_link()
  Reader.put_current(r)
  PrologEx.put_db(%{})

  {db, []} =
    PrologEx.Consult.load(%{}, Reader.read_terms(r, ":- use_module(library(clpz)).\n"))

  PrologEx.put_db(db)
  # Restziele in Scryers Form (Standard ist die lesbare)
  PrologEx.Flags.set("clpz_residuals", PrologEx.a("scryer"))

  lines =
    for q <- queries do
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

  File.write!(Path.expand("golden.txt", __DIR__), Enum.join(lines, "\n") <> "\n")
  IO.puts("#{length(lines)} Anfragen")
end
