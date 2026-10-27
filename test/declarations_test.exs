defmodule PrologEx.DeclarationsTest do
  # multifile/1, discontiguous/1, :- if/elif/else/endif, :- include/1 beim
  # Laden; dazu einige ISO-Fehlerfälle von assert und current_predicate
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  @moduletag :gprolog
  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.put_db(PrologEx.use_library(%{}, "lists", "user"))
    :ok
  end

  defp write(c, name, text) do
    path = Path.join(c.tmp_dir, name)
    File.write!(path, text)
    path
  end

  defp load(path) do
    capture_io(:stderr, fn -> PrologEx.Consult.load_file(path) end)
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(1)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "multifile: Klauseln aus mehreren Dateien werden angehängt", c do
    a = write(c, "a.pl", ":- multifile(farbe/1).\nfarbe(rot).\n")
    b = write(c, "b.pl", ":- multifile(farbe/1).\nfarbe(gruen).\nfarbe(blau).\n")
    load(a)
    load(b)
    assert ask(c, "findall(X, farbe(X), L)") == ["L = [rot, gruen, blau]"]

    assert ask(c, "findall(P, predicate_property(farbe(_), P), L)") ==
             ["L = [defined, compiled, static, multifile, number_of_clauses(3)]"]
  end

  test "ohne multifile ersetzt die zweite Datei die Definition", c do
    load(write(c, "a.pl", "zahl(1).\n"))
    load(write(c, "b.pl", "zahl(2).\n"))
    assert ask(c, "findall(X, zahl(X), L)") == ["L = [2]"]
  end

  test "deklariert, aber ohne Klauseln: scheitert statt existence_error", c do
    load(write(c, "a.pl", ":- multifile(m/0).\n:- discontiguous([d/1, e/2]).\n"))
    assert ask(c, "m") == []
    assert ask(c, "d(_)") == []
    assert ask(c, "predicate_property(e(_, _), discontiguous)") == ["true"]
    assert ask(c, "predicate_property(m, multifile)") == ["true"]
    assert ask(c, "predicate_property(d(_), multifile)") == []
  end

  test "discontiguous: verteilte Klauseln ohne Warnung", c do
    err = load(write(c, "a.pl", ":- discontiguous(p/1).\np(1).\nq.\np(2).\n"))

    assert err == ""
    assert ask(c, "findall(X, p(X), L)") == ["L = [1, 2]"]
  end

  test "if/elif/else/endif, auch verschachtelt; inaktive Direktiven laufen nicht", c do
    load(
      write(c, "a.pl", """
      :- if(fail).
        :- initialization(throw(nie)).
        a(1).
      :- elif(true).
        a(2).
        :- if(fail).
          a(3).
        :- else.
          a(4).
        :- endif.
      :- elif(true).
        a(5).
      :- else.
        a(6).
      :- endif.
      :- if(\\+ fail).
        a(7).
      :- if(true).
        a(8).
      :- endif.
      :- endif.
      """)
    )

    assert ask(c, "findall(X, a(X), L)") == ["L = [2, 4, 7, 8]"]
  end

  test "elif: nur der erste wahre Zweig; im inaktiven Rahmen keine Bedingung", c do
    out =
      capture_io(fn ->
        load(
          write(c, "a.pl", """
          :- if(true).
            b(1).
          :- elif(fail).
            b(2).
          :- elif(true).
            b(3).
          :- endif.
          :- if(fail).
            b(4).
          :- elif(fail).
            b(5).
          :- elif(true).
            b(6).
          :- endif.
          :- if(fail).
            :- if(true).
              b(7).
            :- elif((write(gesehen), fail)).
              b(8).
            :- else.
              b(9).
            :- endif.
          :- endif.
          """)
        )
      end)

    assert out == ""
    assert ask(c, "findall(X, b(X), L)") == ["L = [1, 6]"]
  end

  test "die Bedingung sieht das bisher Geladene; Fehler zählen als falsch", c do
    load(
      write(c, "a.pl", """
      version(3).
      :- if((version(V), V >= 2)).
        neu.
      :- else.
        alt.
      :- endif.
      :- if(gibtsnicht).
        x.
      :- else.
        y.
      :- endif.
      """)
    )

    assert ask(c, "neu, y") == ["true"]
    assert ask(c, "catch(alt, error(E, _), true)") == ["E = existence_error(procedure, alt/0)"]
  end

  test "Syntaxfehler im inaktiven Zweig: keine Meldung", c do
    err = load(write(c, "a.pl", ":- if(fail).\nx :- ) .\n:- endif.\nok.\n"))
    assert err == ""
    assert ask(c, "ok") == ["true"]
  end

  test "include: Terme an Ort und Stelle, relativ zur Datei, .pl ergänzt", c do
    File.mkdir_p!(Path.join(c.tmp_dir, "sub"))
    write(c, "sub/teil.pl", "w(2).\n:- include(tiefer).\n")
    write(c, "sub/tiefer.pl", "w(3).\n")
    load(write(c, "haupt.pl", "w(1).\n:- include('sub/teil').\nw(4).\n"))
    assert ask(c, "findall(X, w(X), L)") == ["L = [1, 2, 3, 4]"]
  end

  test "include einer fehlenden Datei meldet einen Fehler", c do
    assert load(write(c, "a.pl", ":- include(fehlt).\n")) =~ "include(fehlt)"
  end

  test "assert: Rumpf muss in ein Ziel umwandelbar sein; Klauseln als Kopf", c do
    assert ask(c, "catch(assertz((foo :- fail, 4)), error(E, _), true)") ==
             ["E = type_error(callable, (fail, 4))"]

    assert ask(c, "catch(asserta((foo :- X)), error(E, _), true)") == ["true"]

    assert ask(c, "catch(asserta(((a :- b) :- true)), error(E, _), true)") ==
             ["E = permission_error(modify, static_procedure, (:-)/2)"]

    assert ask(c, "catch(assertz(((:- b) :- true)), error(E, _), true)") ==
             ["E = permission_error(modify, static_procedure, (:-)/1)"]
  end

  test "current_predicate/1: negative Stelligkeit", c do
    assert ask(c, "catch(current_predicate(f/ -1), error(E, _), true)") ==
             ["E = type_error(predicate_indicator, f/ -1)"]
  end

  test "predicate_property/2: Fehler", c do
    assert ask(c, "catch(predicate_property(_, P), error(E, _), true)") ==
             ["E = instantiation_error"]

    assert ask(c, "catch(predicate_property(atom(_), foo), error(E, _), true)") ==
             ["E = domain_error(predicate_property, foo)"]
  end
end
