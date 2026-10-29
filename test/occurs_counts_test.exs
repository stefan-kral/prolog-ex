defmodule PrologEx.OccursCountsTest do
  # statistics/2: occurs_checks (tatsächliche Occurs-Checks) und
  # occurs_check_steps (besuchte Teilterme)
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    src = """
    :- use_module(library(lists)).
    kopf(f(X), X).
    """

    {db, []} =
      PrologEx.Consult.load(PrologEx.use_library(%{}, "lists"), Reader.read_terms(r, src))

    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(1)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  # {Checks, Schritte} während G (Vorbereitung P zählt nicht)
  defp delta(c, g, p \\ "true") do
    [a] =
      ask(c, """
      #{p}, statistics(occurs_checks, C0), statistics(occurs_check_steps, S0),
      (#{g} -> true ; true),
      statistics(occurs_checks, C1), statistics(occurs_check_steps, S1),
      DC is C1 - C0, DS is S1 - S0
      """)

    [_, dc] = Regex.run(~r/DC = (\d+)/, a)
    [_, ds] = Regex.run(~r/DS = (\d+)/, a)
    {String.to_integer(dc), String.to_integer(ds)}
  end

  test "was oben schon entschieden ist, zählt nicht", c do
    assert delta(c, "unify_with_occurs_check(X, 2)") == {0, 0}
    assert delta(c, "unify_with_occurs_check(X, abc)") == {0, 0}
    assert delta(c, "unify_with_occurs_check(X, Y)") == {0, 0}
    assert delta(c, "unify_with_occurs_check(X, X)") == {0, 0}
    # bekannt ground (markiert): kein Hineinschauen
    assert delta(c, "unify_with_occurs_check(X, G)", "copy_term(f([a, b, c]), G)") == {0, 0}
  end

  test "tatsächliche Checks und ihre Schritte", c do
    # f(Y): f(...) und Y
    assert delta(c, "unify_with_occurs_check(X, f(Y))") == {1, 2}
    # Liste mit n Elementen f(Y): 3n + 1 (Zelle, f(...), Y; am Ende [])
    assert delta(
             c,
             "unify_with_occurs_check(X, L)",
             "length(L0, 100), maplist(=(f(_)), L0), L = L0"
           ) ==
             {1, 301}

    # gefunden: Abbruch beim Fund (f(...), a, X)
    assert delta(c, "unify_with_occurs_check(X, f(a, X, b))") == {1, 3}
    # zwei Bindungen, zwei Checks
    assert delta(c, "unify_with_occurs_check(g(X, Y), g(f(Z), h(Z)))") == {2, 4}
  end

  test "Flag occurs_check: false zählt nicht, true und error zählen", c do
    assert delta(c, "X = f(Y)") == {0, 0}
    assert delta(c, "X = f(Y)", "set_prolog_flag(occurs_check, true)") == {1, 2}
    assert delta(c, "X = f(Y)", "set_prolog_flag(occurs_check, error)") == {1, 2}
    # gefunden und Fehler: der Check zählt, dazu bindet catch/3 den Ball an
    # den Fänger (wieder eine Variable an einen Term: ein zweiter Check)
    assert {2, _} = delta(c, "catch(X = f(X), _, true)", "set_prolog_flag(occurs_check, error)")
    # auch die Kopfunifikation kompilierter Klauseln
    assert delta(c, "kopf(A, B)", "set_prolog_flag(occurs_check, true)") |> elem(0) >= 1
  end

  test "bind_checked/4: Variable an sich selbst scheitert sofort, ohne Zählen" do
    v = {:var, :occ_self}
    before = PrologEx.occurs_counts()
    assert PrologEx.bind_checked(v, v, %{}, true) == :error
    assert PrologEx.occurs_counts() == before
  end

  test "Backtracking setzt nicht zurück", c do
    assert delta(c, "(member(T, [f(_), g(_, _)]), unify_with_occurs_check(_, T), fail ; true)") ==
             {2, 5}
  end

  test "statistics/0 zeigt beide", c do
    ask(c, "unify_with_occurs_check(_, f(_))")

    out = ExUnit.CaptureIO.capture_io(fn -> ask(c, "swi:statistics") end)
    assert out =~ ~r/% Occurs-Checks: +[\d ]+ \([\d ]+ Schritte\)/
  end
end
