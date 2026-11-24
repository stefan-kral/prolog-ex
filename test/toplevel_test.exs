defmodule PrologEx.ToplevelTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    PrologEx.Flags.reset()
    on_exit(fn -> PrologEx.Toplevel.reset_session() end)
    :ok
  end

  # Toplevel mit Eingabe; Seiten mit höchstens n Antworten (ohne Terminal)
  # ohne vorher geladene Bibliotheken (für das Autoload)
  defp bare(input) do
    Process.put(:prolog_ex_force_chunk, true)
    input = "set_prolog_flag(answer_chunk, 1).\n" <> input

    capture_io(input, fn -> PrologEx.Toplevel.main(["-q"]) end)
    |> String.split("set_prolog_flag(answer_chunk, 1).")
    |> List.last()
  end

  defp top(input, n \\ 3) do
    Process.put(:prolog_ex_force_chunk, true)

    input =
      "use_module(library(lists)).\nuse_module(library(between)).\n" <>
        "set_prolog_flag(answer_chunk, #{n}).\n" <> input

    capture_io(input, fn -> PrologEx.Toplevel.main(["-q"]) end)
    |> String.split("set_prolog_flag(answer_chunk, #{n}).")
    |> List.last()
  end

  describe "Antworten seitenweise" do
    test "reine Anfrage: ohne Rückfrage bis die Seite voll ist" do
      out = top("between(1, 7, X).\n;\n\n")
      # (ohne Terminal kein Echo des getippten ";")
      assert out =~ "X = 1 ;\nX = 2 ;\nX = 3 X = 4 ;\nX = 5 ;\nX = 6 ."
      refute out =~ "X = 7"
    end

    # die erste Anfrage der Sitzung legt Zeitgrenzen-Map und
    # Inferenzzähler erst an – das ist kein Seiteneffekt
    test "schon die erste Anfrage der Sitzung: vorausgerechnet" do
      Process.put(:prolog_ex_force_chunk, true)
      PrologEx.Flags.set("answer_chunk", 3)
      out = capture_io("(X = 1 ; X = 2 ; X = 3).\n", fn -> PrologEx.Toplevel.main(["-q"]) end)
      assert out =~ "X = 1 ;\nX = 2 ;\nX = 3."
    end

    test "keine weitere Antwort: gleich mit Punkt" do
      assert top("member(X, [1, 2]).\n") =~ "X = 1 ;\nX = 2."
      assert top("member(X, [1, 2, 3]), X > 1.\n") =~ "X = 2 ;\nX = 3."
      # Choice Point da, aber keine weitere Lösung
      assert top("( X = 1 ; fail ).\n") =~ "X = 1."
    end

    test "mit Ausgabe: einzeln wie früher" do
      out = top("member(X, [a, b]), write(w(X)), nl.\n;\n")
      assert out =~ "w(a)\nX = a w(b)\nX = b."
    end

    test "Ausgabe ohne Zeilenende: Antwort auf neuer Zeile (wie SWI, Scryer)" do
      assert top("write(x).\n") =~ "x\ntrue."
      assert top("write(x), nl.\n") =~ "x\ntrue."
      refute top("write(x), nl.\n") =~ "x\n\ntrue."
      assert top("X = 1, write(z).\n") =~ "z\nX = 1."
      assert top("write(y), fail.\n") =~ "y\nfalse."
      assert top("member(X, [a, b]), write(X).\n;\n") =~ "a\nX = a b\nX = b."
    end

    test "Seiteneffekte beim Vorausrechnen werden verworfen" do
      out =
        top("""
        member(X, [1, 2]), ( X =:= 2 -> assertz(spur(X)), write(spur) ; true ).

        catch(spur(Y), _, fail).
        """)

      assert out =~ "X = 1 ."
      refute out =~ "spur\n"
      assert out =~ "false."

      # mit ; läuft es wirklich (einmal)
      out =
        top("""
        member(X, [1, 2]), ( X =:= 2 -> assertz(spur(X)), write(spur) ; true ).
        ;
        findall(Y, spur(Y), L).
        """)

      assert out =~ "spur"
      assert out =~ "L = [2]."
    end

    @tag :tmp_dir
    test "nach einem Seiteneffekt wird nicht vorausgerechnet (äußere Wirkungen)", c do
      f = Path.join(c.tmp_dir, "spur.txt")

      top("""
      member(X, [1, 2]), open('#{f}', append, S), write(S, X), close(S).

      """)

      assert File.read!(f) == "1"
    end

    @tag :tmp_dir
    test "Prozesse, Shell, Umgebung laufen nie probeweise voraus (library(os))", c do
      f = Path.join(c.tmp_dir, "lief.txt")

      out =
        top("""
        use_module(library(os)).
        member(C, ["true", "touch '#{f}'"]), shell(C).

        """)

      assert out =~ ~s|C = "true" |
      refute File.exists?(f)

      # auch nicht, wenn das Ziel alle Ausnahmen fängt
      top("""
      use_module(library(os)).
      member(C, ["true", "touch '#{f}'"]), catch(shell(C), _, true).

      """)

      refute File.exists?(f)

      # die Wirkung steht im Memo des Toplevels (wie Ausgaben und
      # Änderungen am Interpreter)
      before = PrologEx.Toplevel.state_snapshot()
      PrologEx.Effects.external!()
      refute PrologEx.Toplevel.state_snapshot() == before

      # mit ; läuft es
      top("""
      use_module(library(os)).
      member(C, ["true", "touch '#{f}'"]), shell(C).
      ;
      """)

      assert File.exists?(f)
    end

    test "dauert die nächste Antwort zu lange: Rückfrage" do
      out = top("( X = 1 ; between(0, inf, N), N < 0 ).\n\n")
      assert out =~ "X = 1 ."
    end

    test "answer_chunk 1: einzeln" do
      assert top("member(X, [p, q]).\n;\n", 1) =~ "X = p X = q."
    end

    test "ohne Terminal und ohne Zwang: einzeln (altes Protokoll)" do
      Process.delete(:prolog_ex_force_chunk)

      out =
        capture_io("use_module(library(lists)).\nmember(X, [p, q]).\n;\n", fn ->
          PrologEx.Toplevel.main(["-q"])
        end)

      assert out =~ "X = p X = q."
    end

    # am Terminal steht das Getippte samt Zeilenumbruch schon da: nach "."
    # kein zweiter Punkt in einer eigenen Zeile; nach bloßem Enter der Punkt
    # zurück in die Zeile der Antwort (eine Zeile hoch, hinter den Prompt)
    test "am Terminal: der Punkt nach dem Ende nur einmal, in der Zeile der Antwort" do
      Process.put(:prolog_ex_force_echo, true)

      try do
        out = top("between(1, 7, X).\n.\n")
        assert out =~ "X = 3 % 3 Antworten, abgebrochen\n"
        refute out =~ "X = 3 ."

        out = top("between(1, 7, X).\n\n")
        # "X = 3 " ist 6 Zeichen lang: der Punkt in Spalte 7
        assert out =~ "X = 3 \e[1A\e[7G.\n% 3 Antworten, abgebrochen\n"
      after
        Process.delete(:prolog_ex_force_echo)
      end
    end

    test "am Ende die Zahl der Antworten (Flag toplevel_answer_count)" do
      # auto: ab zwei Antworten
      assert top("member(X, [1, 2]).\n") =~ "X = 1 ;\nX = 2.\n% 2 Antworten, keine weiteren\n"
      refute top("member(X, [1]).\n") =~ "Antwort"
      refute top("fail.\n") =~ "Antwort"
      # abgebrochen (Enter nach der Rückfrage)
      assert top("between(1, 7, X).\n\n") =~ "X = 3 .\n% 3 Antworten, abgebrochen\n"
      # nach ";" keine weitere: false, dann nur die Zahl
      assert top("( X = 1 ; X = 2 ; fail ).\n;\n;\n", 1) =~ "X = 1 X = 2 false.\n% 2 Antworten\n"
      # Fehler nach einer Antwort
      out = top("member(X, [1, 0]), Y is 1/X.\n;\n", 1)
      assert out =~ "Fehler: evaluation_error(zero_divisor)\n% 1 Antwort, dann Fehler\n"
      # on: immer; off: nie
      out = top("set_prolog_flag(toplevel_answer_count, on).\nX = 1.\nfail.\n")
      assert out =~ "X = 1.\n% 1 Antwort, keine weiteren\n"
      assert out =~ "false.\n% 0 Antworten\n"

      refute top("set_prolog_flag(toplevel_answer_count, off).\nmember(X, [1, 2]).\n") =~
               "Antworten"
    end

    test "Flag answer_chunk" do
      out =
        top(
          "current_prolog_flag(answer_chunk, F).\ncatch(set_prolog_flag(answer_chunk, 0), error(E, _), true).\n"
        )

      assert out =~ "F = 3."
      assert out =~ "domain_error(flag_value"
    end
  end

  describe "Lesen" do
    test ":- G wie eine Direktive; op/3 gilt ab der nächsten Anfrage" do
      out = top(":- op(700, xfx, ===>).\nX = (a ===> b), X =.. L.\n")
      assert out =~ "L = [===>,a,b], X = (a===>b)."
    end

    test "double_quotes gilt ab der nächsten Anfrage; read/1 liest weiter von der Eingabe" do
      out =
        top("set_prolog_flag(double_quotes, atom).\nX = \"ab\".\nread(T).\nfoo(- 1, \"x\").\n")

      assert out =~ "X = ab."
      assert out =~ "T = foo(-1,x)."
    end

    test "Syntaxfehler mit Zeile und Spalte, danach geht es weiter" do
      err = capture_io(:stderr, fn -> send(self(), {:out, top("X = f(.\nX = ok.\n")}) end)
      assert_received {:out, out}
      assert err =~ "Syntaxfehler: Zeile 1, Spalte 7"
      assert out =~ "X = ok."
    end
  end

  describe "repl/1 (für iex)" do
    test "die Sitzung bleibt über Aufrufe hinweg" do
      out1 =
        capture_io("assertz(merk(42)).\nhalt.\n", fn ->
          assert PrologEx.Toplevel.repl(["-q"]) == :ok
        end)

      assert out1 =~ "true."

      out2 = capture_io("merk(X).\nhalt.\n", fn -> PrologEx.Toplevel.repl(["-q"]) end)
      assert out2 =~ "X = 42."

      PrologEx.Toplevel.reset_session()

      out3 =
        capture_io("catch(merk(X), error(E, _), true).\nhalt.\n", fn ->
          PrologEx.Toplevel.repl(["-q"])
        end)

      assert out3 =~ "existence_error"
    end

    test "in einem anderen Prozess (wie nach Ctrl-C) geht es weiter" do
      capture_io("assertz(merk(7)).\nhalt.\n", fn -> PrologEx.Toplevel.repl(["-q"]) end)

      task =
        Task.async(fn ->
          capture_io("merk(X).\nhalt.\n", fn -> PrologEx.Toplevel.repl(["-q"]) end)
        end)

      assert Task.await(task) =~ "X = 7."
    end
  end

  test "existence_error eines Builtins mit Heimat: Hinweis auf die Bibliothek" do
    out =
      top(
        "set_prolog_flag(toplevel_autoload, false).\nsucc(1, X).\nm:(true *-> true ; true).\nfoo.\n"
      )

    assert out =~
             "% succ/2 liegt in library(iso_ext): :- use_module(library(iso_ext)). (oder set_prolog_flag(swi_compat, true))"

    assert out =~ "% (*->)/2 liegt in library(swi)"
    refute out =~ "foo/0 liegt"
  end

  test "existence_error eines Bibliotheksprädikats: Hinweis, auch bei mehreren" do
    out =
      bare(
        "set_prolog_flag(toplevel_autoload, false).\nlast([1], X).\nadd_edges([], [a-b], G).\n"
      )

    assert out =~ "% last/2 liegt in library(lists): :- use_module(library(lists)).\n"
    assert out =~ "% add_edges/3 liegt in library(ugraphs) oder library(wgraphs)\n"
  end

  test "Syntaxfehler: Hinweis auf den Operator einer Bibliothek" do
    out = capture_io(:stderr, fn -> top("X #<==> B.\n") end)
    assert out =~ "% #<==> ist ein Operator aus library(clpz): :- use_module(library(clpz))."
  end

  # Toplevel: was eine Anfrage aufruft und eindeutig in einer Bibliothek
  # liegt, importiert er vorher selbst – nur diese Prädikate, mit Meldung;
  # auch in Meta-Argumenten (maplist(succ, ...) → succ/2)
  test "Autoload im Toplevel" do
    out = bare("last([1, 2], X).\n")
    assert out =~ "% last/2 aus library(lists) importiert\nX = 2.\n"

    out = bare("maplist(succ, [1, 2], L).\n")
    assert out =~ "% maplist/3 aus library(apply) importiert\n"
    assert out =~ "% succ/2 aus library(iso_ext) importiert\n"
    assert out =~ "L = [2,3]."

    # nur das Gebrauchte: reverse/2 bleibt unsichtbar
    out = bare("last([1], X).\nreverse([1], R).\n")
    assert out =~ "% last/2 aus library(lists) importiert"
    assert out =~ "% reverse/2 aus library(lists) importiert"

    # in findall/3, Konjunktionen, \\+ und phrase/2 (seq//1)
    out = bare("findall(X, (member(X, [1, 2]), \\+ last([3], X)), L).\nphrase(seq(S), [a]).\n")
    assert out =~ "% member/2, last/2 aus library(lists) importiert\nL = [1,2]."
    assert out =~ "% seq/3 aus library(dcgs) importiert"

    # mehrdeutig: kein Import, der Hinweis nennt beide
    out = bare("add_edges([], [a-b], G).\n")
    refute out =~ "importiert"
    assert out =~ "% add_edges/3 liegt in library(ugraphs) oder library(wgraphs)"

    # schon importiert: kein zweiter Import (trace/0 findet locate/4 nicht,
    # es ist eingebaut mit Heimat traces) – und der Import läuft am Tracer
    # vorbei, ohne die Meldung von verbose_load
    {out, trace_out} =
      with_io(:stderr, fn ->
        bare("use_module(library(traces)).\nleash(-all).\ntrace.\nlast([1], X).\nnotrace.\n")
      end)

    assert trace_out =~ "Call: (1) last("
    refute trace_out =~ "use_module("
    refute out =~ "trace/0 aus"
    refute out =~ "nichts Neues"
    refute out =~ "use_module(library(lists)"
    assert out =~ "% last/2 aus library(lists) importiert"

    # eigene Definitionen gehen vor
    out = bare("assertz(last(_, eigen)).\nlast([1], X).\n")
    refute out =~ "last/2 aus"
    assert out =~ "X = eigen."
  end

  # autoload/1,2 wie SWI – hier gleich geladen, wie use_module/1,2
  test "autoload/1,2 in einer Datei" do
    f = Path.join(System.tmp_dir!(), "px_autoload_#{System.unique_integer([:positive])}.pl")

    File.write!(f, """
    :- autoload(library(lists), [member/2]).
    :- autoload(library(apply)).
    t(L) :- findall(Y, (member(X, [1, 2]), maplist(=(X), [Y])), L).
    """)

    try do
      out = bare("set_prolog_flag(toplevel_autoload, false).\n['#{f}'].\nt(L).\nlast([1], X).\n")
      assert out =~ "L = [1,2]."
      # nur member/2 aus lists (die Datei lädt in user)
      assert out =~ "existence_error(procedure,last/2)"
    after
      File.rm(f)
    end
  end
end
