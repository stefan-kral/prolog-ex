# Laufzeit der Maschine: kleine klassische Programme, je beste von N Läufen.
#
#   mix run bench/suite.exs                    messen
#   mix run bench/suite.exs --save base.txt    messen und Ergebnis ablegen
#   mix run bench/suite.exs --compare base.txt messen und mit base.txt vergleichen
#   mix run bench/suite.exs --only nrev,tak    nur diese
#
# Zeit in ms (Minimum), dazu Inferenzen und LIPS (Inferenzen je Sekunde,
# gezählt wie SWI: jeder Prädikataufruf, auch eingebaute).

defmodule Suite do
  @program """
  :- use_module(library(between)).

  % naive reverse (30 Elemente: 496 Inferenzen)
  app([], L, L).
  app([H|T], L, [H|R]) :- app(T, L, R).
  nrev([], []).
  nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R).
  nrev_bench(0) :- !.
  nrev_bench(N) :- numlist(1, 30, L), nrev(L, _), N1 is N - 1, nrev_bench(N1).

  % deterministische Schleife
  loop(0) :- !.
  loop(N) :- N1 is N - 1, loop(N1).

  % Fakten, Backtracking über Klauseln
  p(1). p(2). p(3). p(4). p(5). p(6). p(7). p(8). p(9). p(10).

  % Damenproblem, alle Lösungen (Erzeugen und Prüfen mit select/3)
  queens(N, Qs) :- numlist(1, N, Ns), permq(Ns, [], Qs).
  permq([], Qs, Qs).
  permq(Ns, Placed, Qs) :-
      select(Q, Ns, Rest), safe(Placed, Q, 1),
      permq(Rest, [Q|Placed], Qs).
  safe([], _, _).
  safe([Q|Qs], Q0, D) :-
      Q0 =\\= Q + D, Q0 =\\= Q - D,
      D1 is D + 1, safe(Qs, Q0, D1).

  % Takeuchi: Arithmetik und tiefe Rekursion
  tak(X, Y, Z, A) :- X =< Y, !, Z = A.
  tak(X, Y, Z, A) :-
      X1 is X - 1, Y1 is Y - 1, Z1 is Z - 1,
      tak(X1, Y, Z, A1), tak(Y1, Z, X, A2), tak(Z1, X, Y, A3),
      tak(A1, A2, A3, A).

  % symbolisches Ableiten (Strukturen bauen und zerlegen)
  d(U+V, X, DU+DV) :- !, d(U, X, DU), d(V, X, DV).
  d(U-V, X, DU-DV) :- !, d(U, X, DU), d(V, X, DV).
  d(U*V, X, DU*V+U*DV) :- !, d(U, X, DU), d(V, X, DV).
  d(U^N, X, DU*N*U^N1) :- !, integer(N), N1 is N - 1, d(U, X, DU).
  d(X, X, 1) :- !.
  d(_, _, 0).
  deriv_bench(0) :- !.
  deriv_bench(N) :-
      d(((x+1)*(x^2+2)*(x^3+3))*((x+1)*(x^2+2)*(x^3+3)), x, _),
      N1 is N - 1, deriv_bench(N1).
  """

  @cases [
    {"nrev", "nrev_bench(400)"},
    {"loop", "loop(300000)"},
    {"between", "(between(1, 300000, _), fail ; true)"},
    {"member", "numlist(1, 300000, L), (member(_, L), fail ; true)"},
    {"facts", "(between(1, 30000, _), p(_), fail ; true)"},
    {"queens", "findall(Q, queens(8, Q), L), length(L, 92)"},
    {"tak", "tak(18, 12, 6, _)"},
    {"deriv", "deriv_bench(3000)"}
  ]

  def main(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [save: :string, compare: :string, only: :string, runs: :integer]
      )

    runs = Keyword.get(opts, :runs, 5)
    only = if o = opts[:only], do: String.split(o, ","), else: nil

    db = PrologEx.use_library(%{}, "lists", "user")
    {db, []} = PrologEx.Consult.load(db, PrologEx.Parser.read_terms(@program))
    PrologEx.put_db(db)

    base = if f = opts[:compare], do: load(f), else: %{}

    results =
      for {name, q} <- @cases, only == nil or name in only do
        [{:term, g, _}] = PrologEx.Parser.read_terms(q <> " .")
        # einmal zum Aufwärmen; Inferenzen zählen
        i0 = PrologEx.inferences()
        [_] = PrologEx.query(db, g) |> Enum.take(1)
        inf = PrologEx.inferences() - i0

        ms =
          for(
            _ <- 1..runs,
            do: elem(:timer.tc(fn -> PrologEx.query(db, g) |> Enum.take(1) end), 0)
          )
          |> Enum.min()
          |> Kernel./(1000)

        lips = if ms > 0, do: round(inf / ms * 1000), else: 0

        cmp =
          case base do
            %{^name => b} -> "  #{pct(b, ms)}"
            _ -> ""
          end

        :io.format("~-8s ~9.1f ms ~11w Inf. ~8.2f MLIPS~s~n", [name, ms, inf, lips / 1.0e6, cmp])
        {name, ms}
      end

    if f = opts[:save] do
      File.write!(f, Enum.map_join(results, "", fn {n, ms} -> "#{n} #{ms}\n" end))
    end
  end

  defp pct(b, ms), do: "(vorher #{Float.round(b, 1)} ms: #{Float.round(b / ms, 2)}x)"

  defp load(f) do
    for line <- File.read!(f) |> String.split("\n", trim: true), into: %{} do
      [n, ms] = String.split(line)
      {n, String.to_float(ms)}
    end
  end
end

Suite.main(System.argv())
