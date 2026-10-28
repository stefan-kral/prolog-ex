defmodule PrologEx.ScryerOsProcessTest do
  # library(os), library(process) aus Scryer Prolog
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)

    {db, []} =
      PrologEx.Consult.load(
        %{},
        Reader.read_terms(r, """
        :- use_module(library(os)).
        :- use_module(library(process)).
        :- use_module(library(charsio)).
        """)
      )

    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  defp ask(c, q, n \\ 5) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    c.db
    |> PrologEx.query(g)
    |> Enum.take(n)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    |> Enum.map(&String.replace(&1, ~r/'\$(stream|process)'\(\d+\)/, "<\\1>"))
  end

  defp err(c, goal), do: ask(c, "catch((#{goal}), error(E, _), true)")

  describe "library(os)" do
    test "getenv/2, setenv/2, unsetenv/1", c do
      System.put_env("PEX_TEST_VAR", "wert ä")
      assert ask(c, ~s|getenv("PEX_TEST_VAR", V)|) == [~s|V = "wert ä"|]
      assert ask(c, ~s|getenv("PEX_GIBTS_NICHT", _)|) == []

      assert ask(c, ~s|setenv("PEX_T2", "x"), getenv("PEX_T2", V)|) == [~s|V = "x"|]
      assert System.get_env("PEX_T2") == "x"
      assert ask(c, ~s|unsetenv("PEX_T2"), \\+ getenv("PEX_T2", _)|) == ["true"]
      assert System.get_env("PEX_T2") == nil
    end

    test "Namen und Werte: Fehler wie Scryer", c do
      assert ask(c, "getenv([], _)") == []
      assert err(c, "getenv(abc, _)") == ["E = type_error(list,abc)"]
      assert err(c, "getenv(_, _)") == ["E = instantiation_error"]
      assert err(c, "getenv([a, 1], _)") == ["E = type_error(character,1)"]
      assert err(c, ~s|getenv("A B", _)|) == [~s|E = domain_error(env_var,"A B")|]
      assert err(c, ~s|setenv("A", x)|) == ["E = type_error(list,x)"]
      assert err(c, ~s|setenv("A", _)|) == ["E = instantiation_error"]
      # "=" lässt Scryers Prüfung durch; so heißt keine Variable
      assert ask(c, ~s|getenv("A=B", _)|) == []
      assert err(c, ~s|setenv("A=B", "x")|) == [~s|E = domain_error(env_var,"A=B")|]
      assert err(c, ~s|unsetenv("A=B")|) == [~s|E = domain_error(env_var,"A=B")|]
    end

    test "shell/1,2: mit $SHELL", c do
      sh = Path.join(c.tmp_dir, "meinshell")
      mark = Path.join(c.tmp_dir, "benutzt")
      File.write!(sh, "#!/bin/sh\ntouch '#{mark}'\nexec /bin/sh \"$@\"\n")
      File.chmod!(sh, 0o755)
      old = System.get_env("SHELL")
      System.put_env("SHELL", sh)

      try do
        assert ask(c, ~s|shell("exit 2", S)|) == ["S = 2"]
        assert File.exists?(mark)
      after
        if old, do: System.put_env("SHELL", old), else: System.delete_env("SHELL")
      end
    end

    test "shell/1,2", c do
      f = Path.join(c.tmp_dir, "s.txt")
      assert ask(c, ~s|shell("exit 3", S)|) == ["S = 3"]
      assert ask(c, ~s|shell("exit 3", 3)|) == ["true"]
      assert ask(c, ~s|shell("exit 3")|) == []
      assert ask(c, ~s|shell("echo hi > '#{f}'")|) == ["true"]
      assert File.read!(f) == "hi\n"
      assert err(c, "shell(abc)") == ["E = type_error(list,abc)"]
      assert err(c, ~s|shell("true", x)|) == ["E = type_error(integer,x)"]
    end

    test "pid/1", c do
      assert ask(c, "pid(P)") == ["P = #{System.pid()}"]
      assert err(c, "pid(x)") == ["E = type_error(integer,x)"]
    end

    test "argv/1, raw_argv/1: Argumente nach -- beim Start" do
      out =
        capture_io(fn ->
          PrologEx.Toplevel.main([
            "-q",
            "-g",
            "use_module(library(os)), argv(A), raw_argv([_|R]), write(A-R), nl",
            "--",
            "-t",
            "hallo"
          ])
        end)

      assert out =~ ~s|[[-,t],[h,a,l,l,o]]-[[-,q],[-,g],|
      assert out =~ ~s|[-,-],[-,t],[h,a,l,l,o]]|

      # was hinter -- steht, sind keine Dateien zum Laden
      assert capture_io(:stderr, fn ->
               capture_io(fn -> PrologEx.Toplevel.main(["-q", "-g", "true", "--", "nix.pl"]) end)
             end) == ""
    after
      Application.delete_env(:prolog_ex, :argv)
    end
  end

  describe "library(process)" do
    test "Pipes: stdout, stdin, stderr; Status", c do
      assert ask(
               c,
               ~s|process_create("echo", ["hallo."], [stdout(pipe(S))]), read(S, T), close(S)|
             ) ==
               ["S = <stream>, T = hallo"]

      assert ask(c, """
             process_create("sh", ["-c", "cat; echo fehler. >&2; exit 4"],
                            [stdin(pipe(I)), stdout(pipe(O)), stderr(pipe(E)), process(P)]),
             write(I, 'abc.'), nl(I), close(I),
             read(O, X), read(E, Y), close(O), close(E),
             process_wait(P, St)
             """) == [
               "E = <stream>, I = <stream>, O = <stream>, P = <process>, St = exit(4), X = abc, Y = fehler"
             ]
    end

    test "Pipes sind ungepuffert", c do
      {us, [_]} =
        :timer.tc(fn ->
          ask(c, """
          process_create("cat", [], [stdin(pipe(I)), stdout(pipe(O)), process(P)]),
          write(I, 'abc.'), nl(I), read(O, X), close(I), close(O), process_wait(P, _)
          """)
        end)

      assert us < 1_500_000
    end

    test "Dateien und null; cwd/1; Arbeitsverzeichnis für Pfade", c do
      inp = Path.join(c.tmp_dir, "in.txt")
      out = Path.join(c.tmp_dir, "out.txt")
      File.write!(inp, "eins\nzwei\n")

      assert ask(c, """
             process_create("cat", [], [stdin(file("#{inp}")), stdout(file("#{out}")),
                                       stderr(null), process(P)]),
             process_wait(P, S)
             """) == ["P = <process>, S = exit(0)"]

      assert File.read!(out) == "eins\nzwei\n"

      assert ask(c, """
             process_create("pwd", [], [cwd("#{c.tmp_dir}"), stdout(pipe(O)), process(P)]),
             get_line_to_chars(O, L, []), close(O), process_wait(P, _)
             """)
             |> hd() =~ ~s|L = "#{c.tmp_dir}\\n"|

      assert ask(
               c,
               ~s|process_create("cat", [], [stdin(null), stdout(pipe(O))]), get_char(O, C), close(O)|
             ) ==
               ["C = end_of_file, O = <stream>"]

      assert err(c, ~s|process_create("cat", [], [stdin(file("#{c.tmp_dir}/gibts"))])|) ==
               [~s|E = permission_error(open,source_sink,"#{c.tmp_dir}/gibts")|]

      assert err(c, ~s|process_create("true", [], [cwd("#{c.tmp_dir}/gibts")])|) ==
               ["E = permission_error(create,process,process_create/3)"]
    end

    test "env/1 und environment/1", c do
      System.put_env("PEX_ERBE", "geerbt")

      run = fn opts ->
        ask(c, """
        process_create("sh", ["-c", "echo \\"$PEX_ERBE/$FOO\\""], [#{opts}, stdout(pipe(O)), process(P)]),
        get_line_to_chars(O, L, []), close(O), process_wait(P, _)
        """)
        |> hd()
      end

      assert run.(~s|environment(["FOO"="bar"])|) =~ ~s|L = "geerbt/bar\\n"|
      assert run.(~s|env(["FOO"="bar"])|) =~ ~s|L = "/bar\\n"|
    end

    test "process_wait/3: timeout(0), release; process_kill/1; process_id/2", c do
      assert ask(c, """
             process_create("sleep", ["10"], [process(P)]), process_id(P, Pid),
             integer(Pid), process_kill(P), process_wait(P, _)
             """)
             |> length() == 1

      [a] =
        ask(c, """
        process_create("sleep", ["10"], [process(P)]),
        process_wait(P, S0, [timeout(0), release(false)]),
        process_kill(P), process_kill(P),
        process_wait(P, S1, [release(false)]), process_wait(P, S2),
        catch(process_wait(P, _), error(E, _), true)
        """)

      assert a =~ "S0 = timeout"
      assert a =~ "S1 = killed(9), S2 = killed(9)"
      assert a =~ "E = existence_error(process,<process>)"

      # beendet: process_release/1; danach existiert das Handle nicht mehr
      assert ask(c, """
             process_create("true", [], [process(P)]), process_release(P),
             catch(process_id(P, _), error(E, _), true)
             """) == ["E = existence_error(process,<process>), P = <process>"]

      # durch ein Signal von außen: wie die BEAM es meldet
      assert ask(
               c,
               ~s|process_create("sh", ["-c", "kill -9 $$"], [process(P)]), process_wait(P, S)|
             ) ==
               ["P = <process>, S = exit(137)"]
    end

    test "Fehler wie Scryer", c do
      assert err(c, ~s|process_create("gibts_nicht_xyz", [], [])|) ==
               ["E = permission_error(create,process,process_create/3)"]

      assert err(c, ~s|process_create(echo, [], [])|) == ["E = type_error(list,echo)"]
      assert err(c, ~s|process_create("echo", [a], [])|) == ["E = type_error(list,a)"]

      assert err(c, ~s|process_create("echo", [], [foo(1)])|) ==
               ["E = domain_error(process_create_option,foo)"]

      assert err(c, ~s|process_create("echo", [], [stdin(std), stdin(null)])|) ==
               ["E = domain_error(non_duplicate_options,stdin)"]

      assert err(c, ~s|process_create("echo", [], [stdin(bad)])|) ==
               ["E = domain_error(stdio_spec,bad)"]

      assert err(c, ~s|process_create("echo", [], [stdout(_)])|) == ["E = instantiation_error"]

      assert err(c, ~s|process_create("echo", [], [env([]), environment([])])|) ==
               ["E = domain_error(non_conflicting_options,[env([]),environment([])])"]

      assert err(c, ~s|process_create("echo", [], [env([a])])|) ==
               [~s|E = domain_error(process_create_option,env("a"))|]

      assert err(c, "process_wait(_, _)") == ["E = instantiation_error"]
      assert err(c, "process_wait(foo, _)") == ["E = type_error(process,foo)"]
      assert err(c, "process_kill(foo)") == ["E = type_error(process,foo)"]

      # wie Scryer: andere Zeitgrenzen als 0 und infinite scheitern
      assert err(
               c,
               ~s|process_create("true", [], [process(P)]), process_wait(P, _, [timeout(5)])|
             ) == []
    end
  end
end
