defmodule PrologEx.HomesTest do
  # Eingebaute Prädikate außerhalb von ISO und SICStus: sichtbar erst nach
  # dem Import ihrer Heimat-Bibliothek (iso_ext, between, fastrw, swi);
  # mit dem Flag swi_compat wie früher ohne Import
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    PrologEx.Flags.reset()
    on_exit(fn -> PrologEx.Flags.reset() end)
    :ok
  end

  defp ask(c, q, src \\ "") do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(3)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  defp err(c, goal, src \\ ""), do: ask(c, "catch((#{goal}), error(E, _), true)", src)

  test "ohne Import: existence_error – auch für die Steuerkonstrukte der Maschine", c do
    for {g, pi} <- [
          {"between(1, 2, _)", "between/3"},
          {"forall(true, true)", "forall/2"},
          {"succ(1, _)", "succ/2"},
          {"atomic_list_concat([a], _)", "atomic_list_concat/2"},
          {"setup_call_cleanup(true, true, true)", "setup_call_cleanup/3"},
          {"call_nth(true, 1)", "call_nth/2"},
          {"countall(true, _)", "countall/2"},
          {"findnsols(1, X, true, _)", "findnsols/4"},
          {"call_with_inference_limit(true, 10, _)", "call_with_inference_limit/3"},
          {"call_with_depth_limit(true, 10, _)", "call_with_depth_limit/3"},
          {"(true *-> true ; true)", "(*->)/2"},
          {"not(fail)", "not/1"},
          {"plus(1, 2, _)", "plus/3"},
          {"time(true)", "time/1"},
          {"fast_write(user_output, x)", "fast_write/2"}
        ] do
      assert err(c, g) == ["E = existence_error(procedure,#{pi})"], g
    end
  end

  test "ISO und was SICStus eingebaut hat, bleibt ohne Import", c do
    for g <- [
          "length([a], 1)",
          "format(\"\")",
          "phrase([a], [a])",
          "freeze(_, true)",
          "dif(a, b)",
          "call_cleanup(true, true)",
          "if(true, true, true)",
          "findall(X, true, _, [])",
          "copy_term(f(_), _, _)",
          "numbervars(f(_), 0, _)"
        ] do
      assert ask(c, g) != [], g
    end
  end

  test "nach dem Import der Heimat-Bibliothek sichtbar", c do
    assert ask(c, "findall(X, between(1, 3, X), L)", ":- use_module(library(between)).\n") ==
             ["L = [1,2,3]"]

    assert ask(
             c,
             "forall(member(X, [1, 2]), X > 0), succ(1, S), setup_call_cleanup(true, Y = 1, true), " <>
               "call_nth(member(Z, [a, b]), 2), countall(member(_, [a, b]), N)",
             ":- use_module(library(iso_ext)).\n:- use_module(library(lists)).\n"
           ) == ["N = 2, S = 2, Y = 1, Z = b"]

    # nur importiert, was die Bibliothek exportiert
    assert err(c, "atomic_list_concat([a], _)", ":- use_module(library(iso_ext)).\n") ==
             ["E = existence_error(procedure,atomic_list_concat/2)"]

    # library(swi): alles, was früher ohne Import sichtbar war
    assert ask(
             c,
             "atomic_list_concat([a, b], A), between(1, 1, _), not(fail), (true *-> T = 1 ; T = 2)",
             ":- use_module(library(swi)).\n"
           ) == ["A = ab, T = 1"]

    # use_module/2 mit Auswahl
    assert ask(c, "between(1, 1, X)", ":- use_module(library(between), [between/3]).\n") ==
             ["X = 1"]
  end

  test "Flag swi_compat: Voreinstellung false; true wie früher", c do
    assert ask(c, "current_prolog_flag(swi_compat, F)") == ["F = false"]

    assert ask(c, "set_prolog_flag(swi_compat, true), between(1, 1, X), atom_number('3', N)") ==
             ["N = 3, X = 1"]

    PrologEx.Flags.reset()

    assert err(c, "set_prolog_flag(swi_compat, x)") == [
             "E = domain_error(flag_value,swi_compat+x)"
           ]
  end

  test "eigene Definitionen gleichen Namens sind erlaubt und gelten", c do
    src = """
    between(von, bis, mitte).
    forall(a, b).
    not(x).
    countall(eigen, 0).
    plus(eigen, eigen, eigen).
    """

    assert ask(
             c,
             "between(A, B, C), forall(D, E), not(x), countall(eigen, N), plus(P, P, P)",
             src
           ) ==
             ["A = von, B = bis, C = mitte, D = a, E = b, N = 0, P = eigen"]

    # und gehen auch dem Import vor (wie bei Bibliotheken üblich)
    assert ask(c, "between(A, _, _)", ":- use_module(library(between)).\n" <> src) ==
             ["A = von"]
  end

  test "time/1: library(time) Scryers, library(swi) SWIs", c do
    out =
      ExUnit.CaptureIO.capture_io(fn ->
        assert ask(c, "time(true)", ":- use_module(library(time)).\n") == ["true"]
      end)

    assert out =~ "% CPU time:"

    err =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert ask(c, "time(true)", ":- use_module(library(swi)).\n") == ["true"]
      end)

    assert err =~ "seconds"

    # im Bibliotheksmodul selbst gilt dessen eigenes time/1
    out =
      ExUnit.CaptureIO.capture_io(fn ->
        assert ask(c, "time:time(true)", ":- use_module(library(time)).\n") == ["true"]
      end)

    assert out =~ "% CPU time:"

    # ebenso delete_file/1 in library(files): Scryers (Zeichenliste), nicht SWIs
    assert err(c, "files:delete_file('/pex_gibts_nicht')") ==
             ["E = type_error(list,'/pex_gibts_nicht')"]
  end

  test "Bibliotheken des Systems sehen die Prädikate ohne Import", c do
    # library(pio) benutzt setup_call_cleanup/3, library(format) between/3 usw.
    f = Path.join(System.tmp_dir!(), "pex_homes_#{System.unique_integer([:positive])}.txt")
    File.write!(f, "abc")

    assert ask(
             c,
             "phrase_from_file((\"ab\", [_]), '#{f}')",
             ":- use_module(library(pio)).\n"
           ) == ["true"]
  after
    :ok
  end

  test "Heimaten", _c do
    assert PrologEx.Builtins.home("between", 3) == "between"
    assert PrologEx.Builtins.home("forall", 2) == "iso_ext"
    assert PrologEx.Builtins.home("fast_read", 1) == "fastrw"
    assert PrologEx.Builtins.home("atomic_list_concat", 3) == "swi"
    assert PrologEx.Builtins.home("length", 2) == nil
    assert PrologEx.Builtins.home("call_cleanup", 2) == nil
  end
end
