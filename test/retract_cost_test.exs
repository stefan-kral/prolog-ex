defmodule PrologEx.RetractCostTest do
  # retract/1 über viele Fakten bleibt linear (bench/scaling: retract_each,
  # retract_call). Gezählt, deterministisch statt Zeit:
  #   - src_key/1: der Schlüssel eines Eintrags; vorher filterte jedes
  #     retract alle Klauseln (n retracts: ~n²/2 Aufrufe)
  #   - pred_from_entries/2: Neubau des Index; vorher nach jedem retract
  #     beim nächsten Aufruf (retract im Wechsel mit Aufrufen: n Neubauten)
  # Die Anfrage läuft im Testprozess (gezählt wird nur dort). async: false –
  # die Zählung gilt global
  use ExUnit.Case, async: false
  alias PrologEx.{Reader, TableCase}

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r, db: TableCase.db(r, ~w(lists between apply swi))}
  end

  defp count(c, q, fun) do
    Reader.put_current(c.reader)
    [{:term, g, _}] = Reader.read_terms(c.reader, q)

    {_, {:call_count, rows}} =
      :tprof.profile(
        fn -> assert [_] = c.db |> PrologEx.query(g) |> Enum.take(1) end,
        %{type: :call_count, pattern: {PrologEx, fun, :_}, report: :return}
      )

    Enum.sum(for {_m, _f, _a, l} <- rows, {_, n, _} <- l, do: n)
  end

  @n 2000

  defp fill,
    do:
      "dynamic(f/2), retractall(f(_, _)), forall(between(1, #{@n}, I), assertz(f(I, I))), f(1, _), "

  test "retract(f(I, _)) über alle Fakten: Schlüssel je Klausel einmal", c do
    n = count(c, fill() <> "forall(between(1, #{@n}, I), retract(f(I, _))).", :src_key)
    # einmal je Fakt für den Index (vorher ~2 Mio.); gezählt werden muss
    assert n >= @n and n < 4 * @n, "#{n}"
  end

  test "retract im Wechsel mit Aufrufen: kein Neubau des Index je Schritt", c do
    q =
      fill() <>
        "forall(between(1, #{@n}, I), (retract(f(I, _)), J is #{@n} + 1 - I, (f(J, _) -> true ; true)))."

    n = count(c, q, :pred_from_entries)
    # ein Aufbau am Anfang (vorher einer je Schritt)
    assert n >= 1 and n < 10, "#{n}"
  end

  # Warteschlange aus Fakten (vorn retract, hinten assertz), @n Runden:
  # nichts wird je retract zusammengelegt (vorher die ganze Liste je
  # Schritt). Gezählt: src_key/1 bei gebundenem erstem Argument (vorher
  # ~@n² für die Kandidaten), pred_entries/1 bei ungebundenem (vorher zwei
  # je Schritt)
  defp queue(first),
    do:
      "dynamic(g/2), retractall(g(_, _)), forall(between(1, #{@n}, I), assertz(g(q, I))), g(q, 1), " <>
        "forall(between(1, #{@n}, _), (once(retract(g(#{first}, X))), Y is X + #{@n}, assertz(g(q, Y))))."

  test "Warteschlange aus Fakten: retract ohne Zusammenlegen je Schritt", c do
    n = count(c, queue("q"), :src_key)
    assert n >= @n and n < 10 * @n, "src_key: #{n}"
    n = count(c, queue("_"), :pred_entries)
    assert n < 20, "pred_entries: #{n}"
  end
end
