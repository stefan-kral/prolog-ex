defmodule PrologEx.ConcurrentFilesTest do
  # library(concurrent): ein Element darf Dateien lesen, die es selbst
  # öffnet (open/3,4 mit read) – nichts Geteiltes: nicht schreiben, nicht
  # von Streams des Aufrufers oder user_input lesen. Was es offen lässt,
  # schließt library(concurrent) am Ende des Elements (Erfolg, Scheitern,
  # Ausnahme); ein beendeter Arbeiter nimmt seine Dateien mit.
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    dir = c.tmp_dir

    for i <- 1..5, do: File.write!(Path.join(dir, "d#{i}.pl"), "f(#{i}).\ng(#{i}, x).\n")
    File.write!(Path.join(dir, "t.txt"), "abc")
    :ok
  end

  @src ~S"""
  :- use_module(library(concurrent)).
  :- use_module(library(lists)).
  :- use_module(library(between)).
  :- use_module(library(time)).
  :- use_module(library(files)).
  :- use_module(library(pio)).
  :- use_module(library(dcgs)).
  terms(F, Ts) :- setup_call_cleanup(open(F, read, S), rd(S, Ts), close(S)).
  rd(S, Ts) :- read_term(S, T, []), ( T == end_of_file -> Ts = [] ; Ts = [T|Ts1], rd(S, Ts1) ).
  first(F, T) :- open(F, read, S), read(S, T).
  boom(F, _) :- open(F, read, _), throw(kaputt).
  nope(F) :- open(F, read, _), fail.
  wr(F) :- open(F, write, S), close(S).
  al(F, T) :- open(F, read, _, [alias(ein)]), read(ein, T), close(ein).
  chars(F, Cs) :- phrase_from_file(seq(Cs), F).
  fds(N) :- directory_files("/dev/fd", Es), length(Es, N).
  fd_open(F, N) :- open(F, read, _), fds(N).
  spin(F) :- open(F, read, _), between(1, inf, _), fail.
  """

  defp ask(c, q) do
    f = Path.join(c.tmp_dir, "prog.pl")
    File.write!(f, @src)
    PrologEx.put_db(%{})
    {:ok, _} = PrologEx.Consult.load_file(f)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp files(c), do: "[" <> Enum.map_join(1..5, ",", &"'#{c.tmp_dir}/d#{&1}.pl'") <> "]"

  test "eigene Dateien lesen: setup_call_cleanup, ohne close, Alias, phrase_from_file", c do
    assert ask(c, "concurrent_maplist(terms, #{files(c)}, L)") ==
             ["L = [[f(1),g(1,x)],[f(2),g(2,x)],[f(3),g(3,x)],[f(4),g(4,x)],[f(5),g(5,x)]]"]

    assert ask(c, "concurrent_maplist(first, #{files(c)}, L)") ==
             ["L = [f(1),f(2),f(3),f(4),f(5)]"]

    assert ask(c, "concurrent_maplist(al, #{files(c)}, L)") ==
             ["L = [f(1),f(2),f(3),f(4),f(5)]"]

    assert ask(c, "concurrent_maplist(chars, ['#{c.tmp_dir}/t.txt'], L)") ==
             [~S(L = ["abc"])]
  end

  test "Scheitern und Ausnahmen im Element", c do
    assert ask(c, "catch(concurrent_maplist(boom, #{files(c)}, _), E, true)") == ["E = kaputt"]
    assert ask(c, "\\+ concurrent_forall(member(F, #{files(c)}), nope(F))") == ["true"]
  end

  test "Geteiltes bleibt verboten: schreiben, Streams des Aufrufers, user_input", c do
    [a] = ask(c, "catch(concurrent_maplist(wr, ['#{c.tmp_dir}/neu.txt']), error(E, _), true)")
    assert a =~ "E = permission_error(perform,side_effect,open("
    refute File.exists?(Path.join(c.tmp_dir, "neu.txt"))

    [a] =
      ask(
        c,
        "open('#{c.tmp_dir}/t.txt', read, S), " <>
          "catch(concurrent_maplist(get_char(S), [_]), error(E, _), true), close(S)"
      )

    assert a =~ "E = permission_error(perform,side_effect,get_char("

    [a] = ask(c, "catch(concurrent_maplist(read, [_]), error(E, _), true)")
    assert a =~ "E = permission_error(perform,side_effect,read("
  end

  # gezählt über /dev/fd (Linux, macOS): ohne das Schließen je Element
  # wüchse die Zahl mit jedem Element (60 offene Dateien auf einem Arbeiter)
  @tag :unix
  test "offen gelassene Dateien: am Ende jedes Elements zu, beim Abbruch auch", c do
    if File.dir?("/dev/fd") do
      t = "'#{c.tmp_dir}/t.txt'"

      [a] =
        ask(
          c,
          "fds(B), numlist(1, 60, Is), " <>
            "concurrent_aggregate_all(max(N), member(_, Is), fd_open(#{t}, N), M, [threads(1)]), " <>
            "D is M - B"
        )

      [_, d] = Regex.run(~r/\bD = (-?\d+)/, a)
      assert String.to_integer(d) < 40, a

      # Verlierer von first_solution/3 (hart beendet): die Datei geht mit
      [a] =
        ask(
          c,
          "fds(B), first_solution(X, [spin(#{t}), (sleep(0.2), X = fertig)], []), " <>
            "sleep(0.1), fds(A), D is A - B"
        )

      assert a =~ "X = fertig"
      [_, d] = Regex.run(~r/\bD = (-?\d+)/, a)
      assert String.to_integer(d) <= 0, a
    end
  end
end
