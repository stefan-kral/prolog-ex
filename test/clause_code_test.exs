defmodule PrologEx.ClauseCodeTest do
  # Köpfe und Rümpfe als BEAM-Code (PrologEx.ClauseCode): mit Schwelle 1
  # (gleich beim ersten Aufruf übersetzt) dieselben Antworten wie ohne
  # (Flag clause_jit beim Laden aus) – Lese- und Schreibmodus, geschachtelt
  # (dort übernimmt der Interpreter), mehrfache Variablen, ground Terme,
  # Occurs-Check, Wecken, Wächter, Arithmetik, assert, zu große Klauseln.
  # Dazu chat_parser (Programm-Batterie) ganz übersetzt. Übersetzt wird
  # hier gleich beim Aufruf (clause_jit = sync), sonst im Hintergrund.
  use ExUnit.Case, async: true
  alias PrologEx.{Reader, TableCase}

  @program """
  :- use_module(library(lists)).
  :- use_module(library(freeze)).
  app([], L, L).
  app([H|T], L, [H|R]) :- app(T, L, R).
  nrev([], []).
  nrev([H|T], R) :- nrev(T, RT), app(RT, [H], R).
  n([a, [b|T]], T, f(g(1, h(T)), [x, y])).
  eq(X, X).
  eq3(f(X, Y), g(Y, X), [X|Y]).
  d(X, X, 1).
  d(_, _, 0).
  gr(#(0,1,0)).
  gr(#(0,0,1,0)).
  gr(s([1,2,3], "ab", 1.5, -0.0, 7r3)).
  len([], 0).
  len([_|T], N) :- len(T, M), N is M + 1.
  b(X, Y) :- Y = f(X, [1,2], g(Z), Z, _), Z = k(X).
  b2(X, [X, a|_], q(1, X)).
  t(X, int) :- integer(X), !.
  t(X, atom) :- atom(X), !.
  t(_, other).
  cmp(X, Y, lt) :- X < Y, !.
  cmp(_, _, ge).
  c(a).
  c(b).
  dbl(X, f(X, X)).
  % (ruft ein dynamisches Prädikat: nicht für den JIT)
  r(X, Y) :- dy(X), Y = h(X, _, [X]).
  big(#{Enum.map_join(1..120, ",", &"X#{&1}")}, [#{Enum.map_join(1..120, ",", &"X#{&1}")}]).
  :- dynamic(dy/1).
  dy(1).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    terms = Reader.read_terms(r, @program)
    # ohne JIT: der nähme sonst etwa app/3 und nrev/2 vorweg
    PrologEx.Flags.set("jit", {:atom, "false"})
    PrologEx.Flags.set("clause_jit", {:atom, "false"})
    {off, _} = PrologEx.Consult.load(%{}, terms)
    PrologEx.Flags.set("clause_jit", {:atom, "sync"})
    PrologEx.Flags.set("clause_jit_threshold", 1)
    {on, _} = PrologEx.Consult.load(%{}, terms)
    PrologEx.Flags.set("clause_jit", {:atom, "true"})
    {bg, _} = PrologEx.Consult.load(%{}, terms)
    {:ok, reader: r, on: on, off: off, bg: bg}
  end

  for q <- [
        "app(X, Y, [1,2,3])",
        "app([1,2], [3], L)",
        "app([1|T], [2], [1,2])",
        "nrev([1,2,3,4,5], R)",
        "n(A, B, C)",
        "n([a, [b, c]], T, F)",
        "n([a, X], T, F)",
        "n([a, [X|Y]], T, f(G, [x|Z]))",
        "n(_, _, f(g(2, _), _))",
        "eq(f(X), f(Y))",
        "eq(f(X, b), f(a, Y))",
        "eq3(A, B, C)",
        "eq3(f(1, 2), B, C)",
        "eq3(A, g(1, 2), C)",
        "eq3(f(1, 2), g(2, 1), L)",
        "eq3(f(1, 2), g(1, 2), L)",
        "d(a, a, N)",
        "d(a, b, N)",
        "d(X, Y, N)",
        "gr(X)",
        "gr(#(0, X, 0))",
        "gr(#(A, B, C, D))",
        "gr(#(0, 0, 1, 0))",
        "gr(#(0, 0, 1))",
        "gr(s(L, S, F, Z, R))",
        "gr(s([1|T], _, 1.5, _, _))",
        "gr(s(_, _, 1, _, _))",
        "len([a, b, c], N)",
        "once(len(L, 2))",
        "b(1, Y)",
        "b(X, f(1, L, G, Z, W))",
        "b2(X, L, Q)",
        "b2(1, [Y, Z, c], Q)",
        "b2(X, [1, b], Q)",
        "t(1, T)",
        "t(a, T)",
        "t(f(x), T)",
        "t(X, T)",
        "cmp(1, 2, R)",
        "cmp(2, 1, R)",
        "catch(cmp(a, 1, R), error(E, _), true)",
        "c(X)",
        "freeze(X, (write(woke(X)), nl)), c(X)",
        "freeze(X, X == b), c(X)",
        "dif(X, a), c(X)",
        "freeze(X, (write(w(X)), nl)), app([X], [], [7])",
        "freeze(X, fail), app([1], [], [X])",
        "dbl(X, Y)",
        "r(X, Y)",
        "dbl(Z, f(a, W))",
        "dbl(1, f(1, 2))",
        "big(#{Enum.map_join(1..120, ",", &"#{&1}")}, L), length(L, N)",
        "dy(X), assertz(dy(2)), findall(Y, dy(Y), L)",
        "set_prolog_flag(occurs_check, true), (eq(X, f(X)) -> R = yes ; R = no)",
        "set_prolog_flag(occurs_check, true), (app([X], [], [f(X)]) -> R = yes ; R = no)",
        "set_prolog_flag(occurs_check, error), catch(dbl(X, f(X, f(X))), error(E, _), true)",
        "set_prolog_flag(occurs_check, error), catch(app([1], [], [X, f(X)]), error(E, _), true)"
      ] do
    test q, c do
      Reader.put_current(c.reader)
      on = TableCase.run(c.reader, c.on, unquote(q))
      off = TableCase.run(c.reader, c.off, unquote(q))
      PrologEx.Flags.set("occurs_check", {:atom, "false"})
      assert on == off, "mit: #{inspect(on)}\nohne: #{inspect(off)}"
    end
  end

  # die übersetzte Fassung eines Prädikats (aus dem Prozess-Dictionary:
  # die Datenbank der Anfrage ist danach wieder die alte)
  defp compiled(db, key) do
    {:cold, ref, _} = db[key] |> elem(1) |> hd() |> elem(7)
    {_, p} = Process.get({:"$clause_code", ref})
    p |> elem(1) |> hd() |> elem(7)
  end

  test "übersetzt wird an der Schwelle, auch für die nächste Anfrage", c do
    Reader.put_current(c.reader)
    on = c.on
    assert {:cold, ref, true} = on[{"user", "d", 3}] |> elem(1) |> hd() |> elem(7)
    assert Process.get({:"$clause_code", ref}) == nil
    TableCase.run(c.reader, on, "d(a, X, N)")
    assert {h, nil} = compiled(on, {"user", "d", 3})
    assert is_function(h, 4)
    # zu groß: Interpreter, ohne weiter zu zählen
    TableCase.run(c.reader, on, "big(#{Enum.map_join(1..120, ",", &"#{&1}")}, _)")
    assert compiled(on, {"user", "big", 121}) == nil
    # Fakten aus Konstanten: der Kopf bleibt beim Interpreter, der das
    # schon direkt macht (Rumpf haben sie keinen)
    TableCase.run(c.reader, on, "c(X)")
    assert compiled(on, {"user", "c", 1}) == {nil, nil}
    # Rumpf übersetzt
    TableCase.run(c.reader, on, "r(X, Y)")
    assert {_, b} = compiled(on, {"user", "r", 2})
    assert is_function(b, 5)
  end

  @tag :tmp_dir
  test "chat_parser mit Schwelle 1: dieselben Parsebäume", c do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.Flags.set("clause_jit", {:atom, "sync"})
    PrologEx.Flags.set("clause_jit_threshold", 1)
    dir = "test/programs"

    src =
      Enum.map_join(
        ~w(runner.pl chat80__parser.pl chat80__parser.checks.pl),
        "\n",
        &File.read!(Path.join(dir, &1))
      )

    file = Path.join(c.tmp_dir, "chat.pl")
    File.write!(file, src)
    PrologEx.put_db(%{})

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      {:ok, _} = PrologEx.Consult.load_file(file)
    end)

    db = PrologEx.current_db()
    assert {"", {:answers, ["Fs = []"]}} = TableCase.run(r, db, "failures(Fs)")
  end

  # wartet, bis das Übersetzen im Hintergrund fertig ist (höchstens n × 10 ms)
  defp ready(ref, n) do
    cond do
      :atomics.get(ref, 2) == 1 -> true
      n == 0 -> false
      true -> Process.sleep(10) && ready(ref, n - 1)
    end
  end

  test "im Hintergrund: erst interpretiert, dann übersetzt", c do
    Reader.put_current(c.reader)
    bg = c.bg
    key = {"user", "d", 3}
    assert {:cold, ref, false} = bg[key] |> elem(1) |> hd() |> elem(7)
    q = "d(a, X, N)"
    expected = TableCase.run(c.reader, c.off, q)
    # der erste Aufruf stößt das Übersetzen an und rechnet interpretiert
    assert TableCase.run(c.reader, bg, q) == expected
    assert Process.get({:"$clause_code", ref}) == nil

    assert ready(ref, 500)
    # der nächste nimmt den Code
    assert TableCase.run(c.reader, bg, q) == expected
    assert {h, nil} = compiled(bg, key)
    assert is_function(h, 4)
  end

  test "ohne Flag: kein Zähler", c do
    assert c.off[{"user", "app", 3}] |> elem(1) |> hd() |> elem(7) == nil
  end
end
