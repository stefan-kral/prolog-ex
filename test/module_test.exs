defmodule PrologEx.ModuleTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.{Consult, Reader}

  @dir Path.expand("fixtures/modules", __DIR__)

  setup do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    PrologEx.put_db(%{})
    PrologEx.Flags.reset()
    {:ok, reader: r}
  end

  defp load(file), do: Consult.load_file(Path.join(@dir, file))

  defp goal(c, text) do
    [{:term, g, _}] = Reader.read_terms(c.reader, text)
    g
  end

  defp ask(c, text, opts \\ []) do
    PrologEx.current_db()
    |> PrologEx.query(goal(c, text), opts)
    |> Enum.take(20)
    |> Enum.map(&PrologEx.format_answer/1)
  end

  defp err(c, text) do
    e = assert_raise(PrologEx.Error, fn -> ask(c, text) end)
    Exception.message(e)
  end

  test "Exporte sind sichtbar, private Prädikate nicht", c do
    load("haupt.pl")
    assert ask(c, "flaeche(rechteck(2, 3), A).") == ["A = 6"]
    assert ask(c, "flaeche(quadrat(4), A).") == ["A = 16"]
    assert err(c, "mal(2, 3, X).") =~ "existence_error(procedure, mal/3)"
    # qualifiziert erreichbar
    assert ask(c, "geo:mal(2, 3, X).") == ["X = 6"]
    assert err(c, "geo:nix.") =~ "existence_error(procedure, geo:nix/0)"
  end

  test "Operatoren aus der Exportliste gelten im Rest der ladenden Datei", c do
    load("haupt.pl")
    assert ask(c, "pfeil_test(X), X = ===>(L, R).") |> hd() =~ "L = links, R = rechts"
    assert ask(c, "geo:pfeil(===>(A, B)).") == ["A = a, B = b"]
  end

  test "Rümpfe laufen im Definitionsmodul; Sichtbarkeit wie SICStus", c do
    load("haupt.pl")
    # geo:benutzt_user/1 ruft hilfe/1, das nur in user steht: unsichtbar
    assert err(c, "geo:benutzt_user(X).") =~ "existence_error(procedure, geo:hilfe/1)"
    assert ask(c, "geo:benutzt_user_q(X).") == ["X = user"]
    # in meta gibt es ein eigenes hilfe/1
    assert ask(c, "meta:hilfe(X).") == ["X = meta"]
    assert ask(c, "geo:benutzt_lists([1, 2, 3], X).") == ["X = 3"]
    # M:Kopf :- Rumpf in einer user-Datei: Rumpf läuft in user
    assert ask(c, "meta:von_haupt(X).") == ["X = user"]
    # kein Autoload, kein Rückgriff auf user: auto hat lists nicht
    # importiert und sieht last/2 nicht, obwohl user es importiert hat
    load("auto.pl")
    assert err(c, "letztes([1, 2], X).") =~ "existence_error(procedure, auto:last/2)"
    assert ask(c, "current_predicate(auto:last/2).") == []
    assert ask(c, "last([1, 2], X).") == ["X = 2"]
    # ohne Import auch in user nicht
    PrologEx.put_db(%{})
    assert err(c, "append([], [], X).") =~ "existence_error(procedure, append/3)"
  end

  test "dynamische Prädikate gehören ihrem Modul", c do
    load("haupt.pl")
    assert ask(c, "tick, tick, zaehle(N).") == ["N = 2"]
    assert ask(c, "geo:zaehler(N).") == ["N = 2"]
    assert err(c, "zaehler(N).") =~ "existence_error"
    assert ask(c, "assertz(geo:extra(1)), geo:extra(X).") == ["X = 1"]
    assert ask(c, "assertz(m2:(p(X) :- q(X))), assertz(m2:q(7)), m2:p(Y).") == ["Y = 7"]
    # (M:H :- B): Rumpf im Kontextmodul
    assert ask(c, "assertz(hier(5)), assertz((m3:r(X) :- hier(X))), m3:r(Y).") == ["Y = 5"]
    assert ask(c, "assertz((meta:r2(X) :- hilfe(X))), meta:r2(Y).") == ["Y = user"]
    assert ask(c, "assertz(meta:(r3(X) :- hilfe(X))), meta:r3(Y).") == ["Y = meta"]
    assert ask(c, "retract(geo:extra(1)), \\+ geo:extra(_).") == ["true"]
    assert ask(c, "retractall(geo:zaehler(_)), \\+ geo:zaehler(_).") == ["true"]

    assert err(c, "assertz(geo:mal(1, 1, 1)).") =~
             "permission_error(modify, static_procedure, geo:mal/3)"
  end

  test "meta_predicate: Argumente werden mit dem Kontextmodul qualifiziert", c do
    load("haupt.pl")

    out = capture_io(fn -> assert ask(c, "zweimal(write(x)).") == ["true"] end)
    assert out == "xx"

    # positiv/1 steht in user; alle/2 läuft in meta und findet es trotzdem
    assert ask(c, "alle(positiv, [1, 2, 3]).") == ["true"]
    assert ask(c, "alle(positiv, [1, -2]).") == []
    # schon qualifiziert: bleibt
    assert ask(c, "alle(geo:quadrat(2), [4]).") == ["true"]
    assert ask(c, "sammle(X, member(X, [a, b]), L).") == ["L = \"ab\""]
    # hilfe/1 im Ziel ist das aus user, nicht das private aus meta
    assert ask(c, "sammle(X, hilfe(X), L).") == ["L = [user]"]
    # Bibliotheks-Metaprädikate genauso
    assert ask(c, "geo:(maplist(quadrat, [1, 2], L)).") == ["L = [1, 4]"]
    assert ask(c, "maplist(positiv, [1, 2]), include(positiv, [-1, 3], I).") == ["I = [3]"]
  end

  test "use_module(library(...)), Import-Liste, Konflikte", c do
    assert ask(c, "use_module(library(lists)), append(X, [c], [a, c]).") == ["X = \"a\""]
    assert ask(c, "use_module(library(apply), [maplist/2]), maplist(integer, [1]).") == ["true"]

    assert err(c, "use_module(library(gibtsnicht)).") =~
             "existence_error(source_sink, library(gibtsnicht))"

    assert err(c, "use_module(library(lists), [nix/9]).") =~
             "permission_error(import, private_procedure, lists:nix/9)"

    load("haupt.pl")
    # zweites Modul mit quadrat/2: der erste Import bleibt (Warnung)
    out =
      capture_io(:stderr, fn ->
        assert ask(c, "use_module('#{@dir}/konflikt'), quadrat(3, Y).") == ["Y = 9"]
      end)

    assert out =~ "schon aus geo"
    # auch gegenüber einem Bibliotheksimport bleibt der erste
    out =
      capture_io(:stderr, fn ->
        assert ask(c, "use_module('#{@dir}/eigene_liste'), last([1], X).") == ["X = 1"]
      end)

    assert out =~ "schon aus lists"
  end

  test "eigene Definitionen gehen Bibliothek und Import vor", c do
    {db, []} =
      Consult.load(%{}, Reader.read_terms(c.reader, "append(_, _, eigen).\nlast(_, auch).\n"))

    PrologEx.put_db(db)
    assert ask(c, "append(a, b, X).") == ["X = eigen"]
    assert ask(c, "lists:append([a], [b], X).") == ["X = \"ab\""]
    assert ask(c, "last([1], X).") == ["X = auch"]
    # system-Prädikate sind geschützt, in jedem Modul
    {_db, [msg]} = Consult.load(%{}, Reader.read_terms(c.reader, "m:atom(x).\n"))
    assert msg =~ "permission_error"
  end

  test "clause/2, current_predicate/1, listing/1, current_module/1, strip_module/3", c do
    load("haupt.pl")
    assert [ans] = ask(c, "clause(geo:quadrat(A, B), Body).")
    assert ans =~ "Body = mal(A, A, B)"
    assert ask(c, "clause(quadrat(A, B), Body).") |> length() == 1

    assert err(c, "clause(lists:'$append'(_, _, _), _).") =~
             "permission_error(access, private_procedure, lists:'$append'/3)"

    assert ask(c, "current_predicate(geo:mal/3).") == ["true"]
    assert ask(c, "current_predicate(mal/3).") == []
    assert ask(c, "current_predicate(flaeche/N).") == ["N = 2"]
    assert ask(c, "current_predicate(M:tick/0).") == ["M = geo"]

    out = capture_io(fn -> ask(c, "listing(geo:quadrat/2).") end)
    assert out == "geo:quadrat(X, Y) :-\n    mal(X, X, Y).\n"

    mods = ask(c, "findall(M, current_module(M), L).") |> hd()
    for m <- ~w(user system lists apply geo meta), do: assert(mods =~ m)

    assert ask(c, "strip_module(a:b:foo(x), M, P).") == ["M = b, P = foo(x)"]
    assert ask(c, "strip_module(foo, M, P).") == ["M = user, P = foo"]
  end

  test "Kontextmodul bei query/3 und in Direktiven", c do
    load("haupt.pl")
    assert ask(c, "mal(2, 2, X).", module: "geo") == ["X = 4"]
    assert ask(c, "assertz(neu(1)).", module: "geo") == ["true"]
    assert ask(c, "geo:neu(X).") == ["X = 1"]
    assert err(c, "M:neu(X).") =~ "instantiation_error"
  end

  test "Laden: einmal (use_module) bzw. neu (consult); relative Pfade ab der Datei", c do
    load("haupt.pl")
    assert ask(c, "tick, zaehle(N).") == ["N = 1"]
    # use_module lädt nicht neu: Zähler bleibt
    assert ask(c, "use_module('#{@dir}/geo'), zaehle(N).") == ["N = 1"]
    # consult lädt neu
    assert ask(c, "consult('#{@dir}/geo'), zaehle(N).") == ["N = 0"]
    assert err(c, "consult(gibtsnicht).") =~ "existence_error(source_sink"
  end

  describe "predicate_property/2" do
    defp props(c, head) do
      [ans] = ask(c, "findall(P, predicate_property(#{head}, P), L).")
      ans
    end

    test "Implementierung, Herkunft, dynamic, meta_predicate", c do
      load("haupt.pl")
      assert props(c, "atom(_)") == "L = [built_in, static, defined]"

      assert props(c, "call(_)") ==
               "L = [built_in, static, defined, (meta_predicate call(0))]"

      assert props(c, "append(_, _, _)") ==
               "L = [defined, compiled, static, imported_from(lists)]"

      assert props(c, "maplist(_, _)") ==
               "L = [defined, compiled, static, imported_from(apply), (meta_predicate maplist(1, ?))]"

      assert props(c, "flaeche(_, _)") ==
               "L = [defined, compiled, static, imported_from(geo), number_of_clauses(2)]"

      assert props(c, "geo:flaeche(_, _)") ==
               "L = [defined, compiled, static, exported, number_of_clauses(2)]"

      assert props(c, "geo:mal(_, _, _)") ==
               "L = [defined, compiled, static, number_of_clauses(1)]"

      assert props(c, "geo:zaehler(_)") ==
               "L = [defined, interpreted, dynamic, number_of_clauses(1)]"

      assert props(c, "meta:zweimal(_)") ==
               "L = [defined, compiled, static, exported, (meta_predicate zweimal(0)), number_of_clauses(1)]"

      # unsichtbar oder unbekannt: scheitert
      assert props(c, "mal(_, _, _)") == "L = []"
      assert props(c, "gibtsnicht") == "L = []"

      assert_raise PrologEx.Error, ~r/type_error\(callable, 3\)/, fn ->
        ask(c, "predicate_property(3, P).")
      end
    end

    test "Aufzählen über Kopf und Modul", c do
      load("haupt.pl")

      [ans] =
        ask(
          c,
          "findall(N/A, (predicate_property(geo:H, exported), functor(H, N, A)), L), msort(L, S)."
        )

      assert ans =~ "S = [flaeche/2, quadrat/2, tick/0, zaehle/1]"

      assert ask(c, "findall(M-P, predicate_property(M:tick, P), L).") ==
               [
                 "L = [user-defined, user-compiled, user-static, user-imported_from(geo), user-number_of_clauses(1), geo-defined, geo-compiled, geo-static, geo-exported, geo-number_of_clauses(1)]"
               ]

      assert ask(c, "predicate_property(geo:H, dynamic).") |> length() == 1

      assert ask(c, "findall(M, predicate_property(M:flaeche(_, _), imported_from(geo)), L).") ==
               ["L = [user]"]
    end
  end

  test "library(lists) gibt maplist/N, include/3, exclude/3, partition/4 weiter", c do
    assert ask(c, "use_module(library(lists)), maplist(succ, [1, 2], L).") == ["L = [2, 3]"]
    assert ask(c, "include(integer, [a, 1], L).") == ["L = [1]"]
    assert ask(c, "exclude(integer, [a, 1], L).") == ["L = \"a\""]
    assert ask(c, "partition(integer, [a, 1], I, E).") == ["E = \"a\", I = [1]"]
    # foldl/4 gehört nur zu apply
    assert err(c, "foldl(plus, [1], 0, S).") =~ "existence_error"

    # lists und apply zusammen: kein Konflikt, keine Warnung
    assert capture_io(:stderr, fn ->
             assert ask(c, "use_module(library(apply)), maplist(succ, [1], L).") == ["L = [2]"]
           end) == ""

    assert ask(c, "predicate_property(maplist(_, _), imported_from(M)).") == ["M = apply"]
  end

  test "Re-Exporte: Import-Liste und qualifizierter Aufruf", c do
    assert ask(c, "use_module(library(lists), [include/3]), include(atom, [a, 1], L).") ==
             ["L = \"a\""]

    assert err(c, "maplist(atom, [a]).") =~ "existence_error"
    assert ask(c, "lists:maplist(atom, [a]).") == ["true"]
  end
end
