defmodule PrologEx.LoadWarningsTest do
  # Warnungen beim Laden: Singleton-Variablen, nicht zusammenhängende
  # Klauseln, style_check/1; Meldungen mit Zeile (und eingebundener Datei)
  # nicht async: fängt stderr ab (andere Tests schreiben dorthin, z. B. time/1)
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  setup do
    PrologEx.put_db(%{})
    :ok
  end

  # Meldungen beim Laden einer Datei (ohne Pfad davor)
  defp load(c, text, name \\ "a.pl") do
    path = Path.join(c.tmp_dir, name)
    File.write!(path, text)

    capture_io(:stderr, fn -> PrologEx.Consult.load_file(path) end)
    |> String.split("\n", trim: true)
    |> Enum.map(&String.replace_prefix(&1, path <> ": ", ""))
  end

  test "Singleton-Variablen in Klauseln und DCG-Regeln, mit Zeile", c do
    assert load(c, """
           p(X, Y) :- q(X).
           q(_, _Egal).
           r(X) --> [X, Z].
           s(X, X).
           t(X), [a] --> [].
           """) == [
             "Warnung (Zeile 1): Singleton-Variablen: [Y] in p/2",
             "Warnung (Zeile 3): Singleton-Variablen: [Z] in r/3",
             "Warnung (Zeile 5): Singleton-Variablen: [X] in t/3"
           ]
  end

  test "_Name mehrfach verwendet", c do
    assert load(c, "q(_A, f(_A, _B)).\n") ==
             ["Warnung (Zeile 1): mehrfach verwendete _-Variablen: [_A] in q/2"]
  end

  test "Reihenfolge des ersten Auftretens; Modul-Qualifikation; Fakten als Atom", c do
    assert load(c, "m:t(B, A) :- true.\n\nu :- X = 1.\n") == [
             "Warnung (Zeile 1): Singleton-Variablen: [B, A] in t/2",
             "Warnung (Zeile 3): Singleton-Variablen: [X] in u/0"
           ]
  end

  test "Direktiven und Terme in inaktiven Zweigen: keine Warnung", c do
    assert load(c, ":- X = 1.\n:- if(fail).\np(X).\n:- endif.\n") == []
  end

  test "nicht zusammenhängende Klauseln: einmal je Prädikat", c do
    assert load(c, """
           p(1).
           q.
           p(2).
           r.
           p(3).
           """) == [
             "Warnung (Zeile 3): Klauseln von p/1 nicht zusammenhängend (:- discontiguous(p/1) fehlt?)"
           ]
  end

  test "mit discontiguous/1, Direktiven dazwischen oder aus einer Expansion: keine Warnung", c do
    assert load(c, """
           :- discontiguous(p/1).
           p(1).
           q(1).
           p(2).
           q(2).
           :- dynamic(z/0).
           q(3).
           term_expansion(both(N), [a(N), b(N)]).
           both(1).
           both(2).
           """) == [
             "Warnung (Zeile 5): Klauseln von q/1 nicht zusammenhängend (:- discontiguous(q/1) fehlt?)"
           ]
  end

  test "eine Direktive zwischen Klauseln unterbricht nicht", c do
    assert load(c, "p(1).\n:- dynamic(z/0).\np(2).\n") == []
  end

  test "style_check/1 schaltet ab und wieder an (library(swi))", c do
    PrologEx.put_db(PrologEx.use_library(%{}, "swi"))

    assert load(c, """
           :- style_check(-singleton).
           p(X).
           :- style_check(-(discontiguous)).
           a. b. a.
           :- style_check(+singleton).
           q(Y).
           """) == ["Warnung (Zeile 6): Singleton-Variablen: [Y] in q/1"]

    PrologEx.put_db(%{})

    [{:term, g, _}] =
      PrologEx.Parser.read_terms(
        "(style_check(?(singleton)) -> A = an ; A = aus), " <>
          "(style_check(?(discontiguous)) -> B = an ; B = aus), " <>
          "catch(style_check(+foo), error(E, _), true) ."
      )

    assert PrologEx.query(PrologEx.use_library(%{}, "swi"), g)
           |> Enum.take(1)
           |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g))) == [
             "A = an, B = aus, E = domain_error(style_name,foo)"
           ]
  end

  test "Fehler in Direktiven nennen die Zeile; in eingebundenen Dateien auch die Datei", c do
    File.write!(Path.join(c.tmp_dir, "teil.pl"), "x.\nt(V).\n:- gibts_nicht.\n")

    assert load(c, "a.\n:- include(teil).\n:- auch_nicht.\n") == [
             "Warnung (teil.pl, Zeile 2): Singleton-Variablen: [V] in t/1",
             "Fehler (teil.pl, Zeile 3): in Direktive gibts_nicht: existence_error(procedure,gibts_nicht/0)",
             "Fehler (Zeile 3): in Direktive auch_nicht: existence_error(procedure,auch_nicht/0)"
           ]
  end
end
