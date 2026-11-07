defmodule PrologEx.PortrayUnicodeTest do
  # user:portray/1 als vordeklarierter Haken (dynamic, multifile) und
  # writeq ohne Hochkommas für Nicht-ASCII-Atome, die der Leser so liest
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  setup_all do
    {:ok, r} = Reader.start_link()
    {:ok, reader: r}
  end

  setup c do
    Reader.put_current(c.reader)
    :ok
  end

  @src """
  :- use_module(library(lists)).
  :- use_module(library(charsio)).
  :- use_module(library(swi)).
  q(T, A) :- with_output_to(chars(Cs), writeq(T)), atom_chars(A, Cs).
  back(T) :- q(T, A), atom_chars(A, Cs), append(Cs, " .", Cs1), read_from_chars(Cs1, T1), T1 == T.
  """

  defp ask(c, q, src \\ @src) do
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(c.reader, src))
    PrologEx.put_db(db)
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    db
    |> PrologEx.query(g)
    |> Enum.take(2)
    |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
  end

  test "portray/1: dynamic und multifile, ohne Klauseln scheitert es", c do
    assert ask(c, "predicate_property(portray(_), dynamic)") == ["true"]
    assert ask(c, "predicate_property(portray(_), multifile)") == ["true"]
    assert ask(c, "predicate_property(portray(_), number_of_clauses(N))") == ["N = 0"]
    assert ask(c, "portray(x)") == []
    assert ask(c, "clause(portray(_), _)") == []
    # andere unbekannte Prädikate bleiben ein Fehler
    assert ask(c, "catch(portrayx(x), error(E, _), true)") ==
             ["E = existence_error(procedure,portrayx/1)"]
  end

  test "portray/1: mit Klauseln (assertz oder Datei) wirkt es in print/1", c do
    assert ask(
             c,
             "assertz((portray(zz) :- write(zed))), " <>
               "predicate_property(portray(_), multifile), " <>
               "with_output_to(chars(Cs), print(f(zz, y))), atom_chars(A, Cs)"
           )
           |> hd() =~ "A = 'f(zed,y)'"

    src = @src <> ":- multifile(portray/1).\nportray(zz) :- write(zed).\n"

    assert ask(c, "with_output_to(chars(Cs), print([zz])), atom_chars(A, Cs)", src) |> hd() =~
             "A = '[zed]'"
  end

  test "writeq: Nicht-ASCII-Atome wie der Leser sie liest", c do
    for {t, out} <- [
          {"'αβγ'", "αβγ"},
          {"'Γβα'", "'Γβα'"},
          {"'αβγ'('Γβα')", "αβγ('Γβα')"},
          {"'中文'", "中文"},
          {"'äb'", "äb"},
          {"'ab中'", "ab中"},
          {"'x²'", "x²"},
          {"'ǅx'", "'ǅx'"},
          {"'a b'", "'a b'"},
          {"'αβ γ'", "'αβ γ'"},
          {"'Äb'", "'Äb'"},
          {"'α-β'", "'α-β'"},
          {"'α€'", "'α€'"},
          {"'²a'", "'²a'"},
          {"'€'", "'€'"}
        ] do
      assert ask(c, "q(#{t}, A), atom_chars(A, Cs), Cs == \"#{out}\"") != [], t
      assert ask(c, "back(#{t})") == ["true"], t
    end
  end

  test "writeq: Nicht-ASCII-Operatoren und -Operanden kleben nicht", c do
    src = @src <> ":- op(700, xfx, 'αβ').\n:- op(200, fy, 'γ').\n"
    assert ask(c, "q('αβ'(x, 'δ'), A)", src) == ["A = 'x αβ δ'"]
    assert ask(c, "q('γ'('δ'), A)", src) == ["A = 'γ δ'"]
    assert ask(c, "q(mod('δ', 'ε'), A)", src) == ["A = 'δ mod ε'"]
    assert ask(c, "back('αβ'(x, 'δ')), back('γ'('δ')), back(mod('δ', 'ε'))", src) == ["true"]
  end
end
