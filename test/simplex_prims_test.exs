defmodule PrologEx.SimplexPrimsTest do
  # library(simplex): die Teile in Elixir (PrologEx.Builtins.SimplexPrims –
  # Pivot-Schleife, Zeilenaufbau, Elimination, find_row) gegen Triskas
  # Originale (simplex_ref/2 usw., simplex:ref_mode) auf zufälligen
  # linearen Programmen: das gelöste Tableau und alle Variablenwerte
  # Term für Term gleich, Scheitern ebenso
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @n 200

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  # ein zufälliges Programm wie conformance/simplex_fuzz/gen.py, dazu
  # Brüche und Floats als Koeffizienten
  defp problem(i) do
    nv = Enum.random(2..4)
    vs = for j <- 0..(nv - 1), do: "x(#{j})"

    coeff = fn ->
      case Enum.random(1..10) do
        1 -> "#{Enum.random(1..5)}r#{Enum.random(2..4)}"
        2 -> "0.5"
        _ -> "#{Enum.random(-5..6)}"
      end
    end

    cs =
      for _ <- 1..Enum.random(1..4) do
        terms = for v <- vs, :rand.uniform() < 0.8, do: "#{coeff.()}*#{v}"
        terms = if terms == [], do: ["1*#{hd(vs)}"], else: terms
        rel = Enum.random(["=<", "=<", ">=", ">=", "="])
        "constraint([#{Enum.join(terms, ", ")}] #{rel} #{Enum.random(0..20)})"
      end ++
        Enum.flat_map(vs, fn v ->
          ["constraint([#{v}] >= 0)", "constraint([#{v}] =< #{Enum.random(1..10)})"] ++
            if :rand.uniform() < 0.3, do: ["constraint(integral(#{v}))"], else: []
        end)

    obj = Enum.map_join(vs, ", ", fn v -> "#{Enum.random(-4..7)}*#{v}" end)
    opt = Enum.random(["maximize", "minimize"])

    {body, k} =
      Enum.reduce(cs, {"gen_state(S0)", 0}, fn c, {b, k} ->
        # die schließende Klammer von constraint(...) weg, die Zustände dazu
        open = binary_part(c, 0, byte_size(c) - 1)
        {b <> ", " <> open <> ", S#{k}, S#{k + 1})", k + 1}
      end)

    "p(#{i}, S-Vs) :- #{body}, #{opt}([#{obj}], S#{k}, S), " <>
      "findall(V, (member(X, [#{Enum.join(vs, ", ")}]), variable_value(S, X, V)), Vs)."
  end

  test "Elixir wie die Originale auf #{@n} zufälligen Programmen", c do
    :rand.seed(:exsss, {11, 22, 33})
    Reader.put_current(c.reader)

    src =
      [
        ":- use_module(library(simplex)).",
        ":- use_module(library(lists)).",
        "both(I, A, B) :- findall(R, p(I, R), A), assertz(simplex:ref_mode), " <>
          "findall(R, p(I, R), B), retract(simplex:ref_mode).",
        "diffs(Ds) :- findall(I-A-B, (between(0, #{@n - 1}, I), both(I, A, B), A \\== B), Ds).",
        "solved(N) :- findall(I, (between(0, #{@n - 1}, I), p(I, _)), L), length(L, N)."
        | for(i <- 0..(@n - 1), do: problem(i))
      ]
      |> Enum.join("\n")

    {db, msgs} =
      PrologEx.Consult.load(
        PrologEx.use_library(%{}, "between", "user"),
        Reader.read_terms(c.reader, src)
      )

    assert msgs == []

    assert inspect(elem(TableCase.run(c.reader, db, "diffs(Ds)"), 1)) =~ "Ds = []"
    # genug lösbare Fälle (nicht alle scheitern)
    assert inspect(elem(TableCase.run(c.reader, db, "solved(N)"), 1)) =~ ~r/N = (\d\d+)/
  end

  # Transport (Angebot = Nachfrage) und Zuordnung: der maximale Fluss in
  # Elixir gegen maximum_flow_ref/2 – derselbe Plan
  defp transport_problem(i) do
    m = Enum.random(1..6)
    n = Enum.random(1..6)
    sup = for _ <- 1..m, do: Enum.random(0..30)
    total = Enum.sum(sup)
    cuts = for(_ <- 1..(n - 1)//1, do: Enum.random(0..total)) |> Enum.sort()
    dem = Enum.zip_with([0 | cuts], cuts ++ [total], fn a, b -> b - a end)
    costs = for _ <- 1..m, do: for(_ <- 1..n, do: Enum.random(1..20))

    "t(#{i}, P) :- transportation(#{inspect(sup, charlists: :as_lists)}, " <>
      "#{inspect(dem, charlists: :as_lists)}, " <>
      "#{inspect(costs, charlists: :as_lists)}, P)."
  end

  defp assignment_problem(i) do
    n = Enum.random(1..7)
    costs = for _ <- 1..n, do: for(_ <- 1..n, do: Enum.random(1..30))
    "t(#{i}, P) :- assignment(#{inspect(costs, charlists: :as_lists)}, P)."
  end

  test "Transport und Zuordnung: Fluss in Elixir wie das Original", c do
    :rand.seed(:exsss, {44, 55, 66})
    Reader.put_current(c.reader)
    n = 150

    src =
      [
        ":- use_module(library(simplex)).",
        "both(I, A, B) :- findall(R, t(I, R), A), assertz(simplex:ref_mode), " <>
          "findall(R, t(I, R), B), retract(simplex:ref_mode).",
        "diffs(Ds) :- findall(I-A-B, (between(0, #{n - 1}, I), both(I, A, B), A \\== B), Ds).",
        "solved(N) :- findall(I, (between(0, #{n - 1}, I), t(I, _)), L), length(L, N)."
        | for(
            i <- 0..(n - 1),
            do: if(rem(i, 2) == 0, do: transport_problem(i), else: assignment_problem(i))
          )
      ]
      |> Enum.join("\n")

    {db, msgs} =
      PrologEx.Consult.load(
        PrologEx.use_library(%{}, "between", "user"),
        Reader.read_terms(c.reader, src)
      )

    assert msgs == []
    assert inspect(elem(TableCase.run(c.reader, db, "diffs(Ds)"), 1)) =~ "Ds = []"
    assert inspect(elem(TableCase.run(c.reader, db, "solved(N)"), 1)) =~ "N = #{n}"
  end

  test "Floats im Tableau: das Original rechnet weiter (fallback)", c do
    Reader.put_current(c.reader)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(c.reader, ":- use_module(library(simplex)).\n")
      )

    q =
      "simplex:'$simplex_simplex'(tableau(row(z, [-1.0, 0], 0), [x, s], [1, 1], " <>
        "[row(s, [1, 1], 4)]), R)"

    assert inspect(elem(TableCase.run(c.reader, db, q), 1)) =~ "R = fallback"
  end
end
