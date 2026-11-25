defmodule PrologEx.FilesexTest do
  # library(filesex) (der lesende Teil) und die Dateinamen aus library(swi)
  # wie in SWI-Prolog
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    t = c.tmp_dir

    for d <- ~w(.hid a a/b c), do: File.mkdir_p!(Path.join(t, d))

    for f <- ~w(x.pl .hid/h.pl a/y.pl a/.dot.pl a/b/q.pl a/b/z.txt c/w.pl),
        do: File.write!(Path.join(t, f), "")

    File.ln_s!(t, Path.join(t, "a/loop"))
    PrologEx.put_db(%{})

    for l <- ~w(filesex swi lists) do
      [{:term, g, _}] = Reader.read_terms(c.reader, "use_module(library(#{l})).")
      [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
    end

    :ok
  end

  defp ask(c, q) do
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    PrologEx.current_db()
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
    |> Enum.map(&String.replace(&1, c.tmp_dir, "T"))
  end

  defp members(c, opts), do: ask(c, "findall(M, directory_member('#{c.tmp_dir}', M, #{opts}), L)")

  test "directory_member/3: Optionen wie SWI", c do
    assert members(c, "[]") == ["L = ['T/.hid','T/a','T/c','T/x.pl']"]

    # rekursiv, Tiefe zuerst; dem Link a/loop (zurück zur Wurzel) wird nicht
    # noch einmal gefolgt
    assert members(c, "[recursive(true)]") ==
             [
               "L = ['T/.hid','T/.hid/h.pl','T/a','T/a/.dot.pl','T/a/b','T/a/b/q.pl'," <>
                 "'T/a/b/z.txt','T/a/loop','T/a/y.pl','T/c','T/c/w.pl','T/x.pl']"
             ]

    assert members(c, "[recursive(true), extensions([pl])]") ==
             ["L = ['T/.hid/h.pl','T/a/.dot.pl','T/a/b/q.pl','T/a/y.pl','T/c/w.pl','T/x.pl']"]

    assert members(c, "[recursive(true), extensions(['.txt'])]") == ["L = ['T/a/b/z.txt']"]

    assert members(c, "[recursive(true), file_type(directory), hidden(false)]") ==
             ["L = ['T/a','T/a/b','T/a/loop','T/c']"]

    assert members(c, "[recursive(true), hidden(false), file_type(prolog)]") ==
             ["L = ['T/a/b/q.pl','T/a/y.pl','T/c/w.pl','T/x.pl']"]

    assert members(c, "[recursive(true), matches('*.txt')]") == ["L = ['T/a/b/z.txt']"]
    assert members(c, "[recursive(true), matches('[wx].pl')]") == ["L = ['T/c/w.pl','T/x.pl']"]

    assert members(c, "[recursive(true), exclude('*.pl'), file_type(regular)]") ==
             ["L = ['T/a/b/z.txt']"]

    assert members(c, "[recursive(true), exclude_directory(a)]") ==
             ["L = ['T/.hid','T/.hid/h.pl','T/c','T/c/w.pl','T/x.pl']"]

    # lazy: die erste Lösung, ohne den Rest
    assert ask(c, "directory_member('#{c.tmp_dir}', M, [recursive(true)])") ==
             ["M = 'T/.hid'", "M = 'T/.hid/h.pl'"]
  end

  test "directory_member/3: Fehler", c do
    nix = Path.join(c.tmp_dir, "gibtsnicht")

    assert ask(c, "catch(directory_member('#{nix}', M, []), error(E, _), true)") ==
             ["E = existence_error(directory,'T/gibtsnicht')"]

    assert ask(c, "findall(M, directory_member('#{nix}', M, [file_errors(fail)]), L)") ==
             ["L = []"]

    assert ask(
             c,
             "catch(directory_member('#{c.tmp_dir}', M, [file_type(foo)]), error(E, _), true)"
           ) ==
             ["E = domain_error(file_type,foo)"]

    assert ask(c, "catch(directory_member(_, M, []), error(E, _), true)") ==
             ["E = instantiation_error"]
  end

  test "directory_file_path/3, relative_file_name/3", c do
    assert ask(c, "directory_file_path(a, b, P)") == ["P = 'a/b'"]
    assert ask(c, "directory_file_path('a/', b, P)") == ["P = 'a/b'"]
    assert ask(c, "directory_file_path('.', b, P)") == ["P = b"]
    assert ask(c, "directory_file_path(a, '/b', P)") == ["P = '/b'"]
    assert ask(c, "directory_file_path(D, F, '/x/y/z.pl')") == ["D = '/x/y', F = 'z.pl'"]
    assert ask(c, "directory_file_path('/x/', F, '/x/y')") == ["F = y"]
    assert ask(c, "directory_file_path(D, 'z.pl', '/x/y/z.pl')") == ["D = '/x/y'"]
    assert ask(c, "directory_file_path(\"a\", b, P)") == ["P = 'a/b'"]

    assert ask(c, "relative_file_name('/h/j/nice', '/h/j/deep/dir/file', R)") ==
             ["R = '../../nice'"]

    assert ask(c, "relative_file_name(P, '/h/j/deep/dir/file', '../../nice')") ==
             ["P = '/h/j/nice'"]

    assert ask(c, "relative_file_name('/h/j/deep/dir/x', '/h/j/deep/dir/file', R)") ==
             ["R = x"]
  end

  test "Dateinamen: file_base_name/2, file_directory_name/2, file_name_extension/3", c do
    assert ask(c, "file_base_name('/a/b/', B), file_directory_name('/a/b/', D)") ==
             ["B = b, D = '/a'"]

    assert ask(
             c,
             "file_directory_name(b, D), file_directory_name('/b', D2), file_base_name(b, B)"
           ) ==
             ["B = b, D = '.', D2 = (/)"]

    assert ask(c, "file_name_extension(B, E, 'x/a.b.pl')") == ["B = 'x/a.b', E = pl"]
    assert ask(c, "file_name_extension(B, E, 'a.d/x')") == ["B = 'a.d/x', E = ''"]
    assert ask(c, "file_name_extension(B, E, '.bashrc')") == ["B = '', E = bashrc"]
    assert ask(c, "file_name_extension(foo, pl, N)") == ["N = 'foo.pl'"]
    assert ask(c, "file_name_extension(foo, '.pl', N)") == ["N = 'foo.pl'"]
    assert ask(c, "file_name_extension('foo.pl', pl, N)") == ["N = 'foo.pl'"]
    assert ask(c, "file_name_extension(B, pl, 'x.pl')") == ["B = x"]
    assert ask(c, "file_name_extension(B, pl, 'x.txt')") == []
    assert ask(c, "is_absolute_file_name('/a'), \\+ is_absolute_file_name(a)") == ["true"]
  end

  # nur Abfragen: in den Arbeitern von library(concurrent) erlaubt
  test "in Arbeitern von library(concurrent)", c do
    [{:term, g, _}] =
      Reader.read_terms(c.reader, "use_module(library(concurrent)), use_module(library(yall)).")

    [_] = PrologEx.query(PrologEx.current_db(), g) |> Enum.take(1)
    d = c.tmp_dir

    assert ask(
             c,
             "concurrent_maplist([D, L]>>findall(M, directory_member(D, M, [extensions([pl])]), L), " <>
               "['#{d}/a', '#{d}/c'], Ls)"
           ) == ["Ls = [['T/a/.dot.pl','T/a/y.pl'],['T/c/w.pl']]"]
  end
end
