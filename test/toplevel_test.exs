defmodule PrologEx.ToplevelTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    PrologEx.Flags.reset()
    on_exit(fn -> PrologEx.Toplevel.reset_session() end)
    :ok
  end

  # Toplevel mit Eingabe; Seiten mit höchstens n Antworten (ohne Terminal)
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
    out = top("succ(1, X).\nm:(true *-> true ; true).\nfoo.\n")
    assert out =~ "% succ/2 liegt in library(iso_ext): :- use_module(library(iso_ext))."
    assert out =~ "% (*->)/2 liegt in library(swi)"
    refute out =~ "foo/0 liegt"
  end
end
