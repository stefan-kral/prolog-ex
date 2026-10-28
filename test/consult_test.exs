defmodule PrologEx.ConsultTest do
  # Integrationstests: Laden über den Reader
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.{Consult, Reader}

  setup do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  defp load(r, db \\ %{}, text), do: Consult.load(db, Reader.read_terms(r, text))

  defp ask(r, db, text) do
    [{:term, g, _}] = Reader.read_terms(r, text)
    db |> PrologEx.query(g) |> Enum.map(&PrologEx.format_answer/1)
  end

  test "Programm mit Operatoren laden und ausführen", %{reader: r} do
    {db, []} =
      load(r, """
      :- op(700, xfx, ===>).
      app([], L, L).
      app([H|T], L, [H|R]) :- app(T, L, R).
      regel(a ===> b).
      """)

    assert ask(r, db, "app(X, Y, [1,2]).") == [
             "X = [], Y = [1,2]",
             "X = [1], Y = [2]",
             "X = [1,2], Y = []"
           ]

    assert ask(r, db, "regel(X ===> Y).") == ["X = a, Y = b"]
  end

  test "Strings sind Zeichenlisten, DCG funktioniert", %{reader: r} do
    {db, []} =
      load(r, """
      ab --> "a", ab.
      ab --> [].
      """)

    assert ask(r, db, ~S|phrase(ab, "aaa").|) == ["true"]
    assert ask(r, db, ~S|phrase(ab, "aab").|) == []
  end

  test "DCG: Pushback (H, PB --> B)", %{reader: r} do
    {db, []} =
      load(r, """
      look(X), [X] --> [X].
      upto([], W), [W] --> [W], !.
      upto([C|Cs], W) --> [C], !, upto(Cs, W).
      upto([], _) --> [].
      zwei, "ab" --> "x".
      """)

    assert ask(r, db, ~S|phrase(look(X), "abc", R).|) == [~S|R = "abc", X = a|]
    assert ask(r, db, ~S|phrase(upto(Cs, ~), "ab~cd", R).|) == [~S|Cs = "ab", R = "~cd"|]
    assert ask(r, db, ~S|phrase(zwei, "xy", R).|) == [~S|R = "aby"|]
    # Pushback muss eine Liste sein
    assert {_, [msg]} = load(r, "p, x --> [].\n")
    assert msg =~ "type_error(list,x)"
  end

  test "DCG: M:Rumpf läuft im Modul M (wie SWI)", %{reader: r} do
    {db, []} =
      load(r, """
      m:x([x|S], S).
      xs --> m:x, m:(x, x).
      xy --> m:"x", m:{Y = 1}, [Y].
      """)

    assert ask(r, db, ~S|phrase(xs, "xxx").|) == ["true"]
    assert ask(r, db, ~S|phrase(m:x, "x").|) == ["true"]
    assert ask(r, db, ~S|phrase(xy, [x, 1]).|) == ["true"]
    assert ask(r, db, ~S|phrase(xs, "xx").|) == []
  end

  test "Reconsult ersetzt Prädikate, andere bleiben", %{reader: r} do
    {db, []} = load(r, "f(1).\nf(2).\ng(x).\n")
    {db, []} = load(r, db, "f(3).\n")
    assert ask(r, db, "f(X).") == ["X = 3"]
    assert ask(r, db, "g(X).") == ["X = x"]
  end

  test "Klauseln eines Prädikats über Direktiven hinweg bleiben zusammen", %{reader: r} do
    {db, []} = load(r, "h(1).\n:- h(1).\nh(2).\n")
    assert ask(r, db, "h(X).") == ["X = 1", "X = 2"]
  end

  test "Direktiven sehen bisher Geladenes, initialization läuft am Ende", %{reader: r} do
    out =
      capture_io(fn ->
        load(r, """
        :- initialization((spaet(X), write(init=X), nl)).
        a(1).
        :- a(X), write(direkt=X), nl.
        spaet(42).
        """)
      end)

    assert out == "direkt=1\ninit=42\n"
  end

  test "dynamic deklariert leere Prädikate", %{reader: r} do
    {db, []} = load(r, ":- dynamic(zaehler/1).\n")
    assert ask(r, db, "zaehler(X).") == []
  end

  test "Syntaxfehler werden gemeldet, Rest wird geladen", %{reader: r} do
    {db, [msg]} = load(r, "ok(1).\nkaputt(.\nok2(2).\n")
    assert msg =~ "Syntaxfehler: Zeile 2"
    assert ask(r, db, "ok2(X).") == ["X = 2"]
  end

  test "fehlgeschlagene Direktive ergibt Warnung", %{reader: r} do
    {_db, [msg]} = load(r, ":- fail.\n")
    assert msg =~ "Warnung"
  end

  test "listing zeigt den Quelltext", %{reader: r} do
    {db, []} = load(r, "app([], L, L).\napp([H|T], L, [H|R]) :- app(T, L, R).\n")
    out = capture_io(fn -> ask(r, db, "listing(app/3).") end)
    assert out == "app([],L,L).\napp([H|T],L,[H|R]) :-\n    app(T,L,R).\n"
  end

  test "Toplevel: Programm von stdin mit -g" do
    out =
      capture_io("p(1).\np(2).\n", fn ->
        assert PrologEx.Toplevel.main(["-", "-g", "p(X), X > 1, write(X), nl"]) == 0
      end)

    assert out == "2\n"
  end

  test "double_quotes: Direktive in der Datei und im Toplevel" do
    out =
      capture_io(
        "s1(\"ab\").\n:- set_prolog_flag(double_quotes, codes).\ns2(\"ab\").\n",
        fn -> PrologEx.Toplevel.main(["-", "-g", "s1(X), s2(Y), write(X-Y), nl"]) end
      )

    assert out == "[a,b]-[97,98]\n"

    input = "set_prolog_flag(double_quotes, atom).\nX = \"ab\".\nhalt.\n"
    out = capture_io(input, fn -> PrologEx.Toplevel.main(["-q"]) end)
    assert out =~ "X = ab."
  end

  test "Toplevel: ; setzt die Suche fort, Seiteneffekte nur einmal" do
    input = "[user].\np(1).\np(2).\nend_of_file.\np(X), write(seen(X)), nl.\n;\nhalt.\n"
    out = capture_io(input, fn -> assert PrologEx.Toplevel.main(["-q"]) == 0 end)
    assert out |> String.split("seen(1)") |> length() == 2
    assert out |> String.split("seen(2)") |> length() == 2
  end

  test "Toplevel: [user] und Anfragen mit ;" do
    input = "[user].\nf(a).\nf(b).\nend_of_file.\nf(X).\n;\nf(c).\nhalt.\n"
    out = capture_io(input, fn -> assert PrologEx.Toplevel.main(["-q"]) == 0 end)
    assert out =~ "X = a"
    assert out =~ "X = b."
    assert out =~ "false."
  end

  @tag :tmp_dir
  test "Dateinamen als Zeichen- oder Codeliste (wie Strings in SWI)", %{reader: r, tmp_dir: dir} do
    Reader.put_current(r)
    file = Path.join(dir, "h.pl")
    File.write!(file, "hallo(welt).\n")

    for q <- [
          "consult(\"#{file}\"), hallo(X).",
          "set_prolog_flag(double_quotes, codes), consult(\"#{file}\"), hallo(X).",
          "consult([\"#{file}\"]), hallo(X).",
          "consult(['#{file}']), hallo(X)."
        ] do
      PrologEx.put_db(%{})
      assert ask(r, %{}, q) |> hd() =~ "X = welt", q
    end

    PrologEx.Flags.reset()
    # Liste von Einzelzeichen ohne . oder /: Liste von Dateien
    PrologEx.put_db(%{})
    assert ask(r, %{}, "catch(consult([a, b]), E, true).") |> hd() =~ "'a.pl'"

    input = "[\"#{file}\"].\nhallo(X).\n"
    out = capture_io(input, fn -> PrologEx.Toplevel.main(["-q"]) end)
    assert out =~ "X = welt."
  end
end
