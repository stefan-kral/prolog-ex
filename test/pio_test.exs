defmodule PrologEx.PioTest do
  # library(pio): reine Eingabe wie SWI und Scryer
  use ExUnit.Case, async: false
  alias PrologEx.Reader

  @moduletag :tmp_dir

  @program """
  :- use_module(library(pio)).
  :- use_module(library(lists)).
  any([]) --> [].
  any([C|Cs]) --> [C], any(Cs).
  lines([L|Ls]) --> line(L), !, lines(Ls).
  lines([]) --> [].
  line([]) --> "\\n", !.
  line([C|Cs]) --> [C], line(Cs).
  count(N0, N) --> [_], !, { N1 is N0 + 1 }, count(N1, N).
  count(N, N) --> [].
  zahl --> [C], { char_type(C, digit(_)) }, !, zahl.
  zahl --> [].
  pruefe --> "a", ( "b" -> [] ; syntax_error(b_erwartet) ).
  offen([a|_], _).
  """

  setup_all do
    {:ok, r} = Reader.start_link()
    Reader.put_current(r)
    {db, []} = PrologEx.Consult.load(%{}, Reader.read_terms(r, @program))
    {:ok, reader: r, db: db}
  end

  setup c do
    Reader.put_current(c.reader)
    text = "hallo welt\nzweite zeile\n"
    small = Path.join(c.tmp_dir, "klein.txt")
    File.write!(small, text)
    # über mehrere Blöcke (4096 Zeichen), mit Umlauten (2 Bytes)
    big = Path.join(c.tmp_dir, "gross.txt")
    File.write!(big, Enum.map_join(0..1999, fn i -> "zeile #{i} äöü\n" end))
    {:ok, small: small, big: big}
  end

  defp ask(c, q, n \\ 5) do
    q = q |> String.replace("KLEIN", "'#{c.small}'") |> String.replace("GROSS", "'#{c.big}'")
    names = [{"'#{c.small}'", "KLEIN"}, {"'#{c.big}'", "GROSS"}, {c.small, "KLEIN"}]
    [{:term, g, _}] = Reader.read_terms(c.reader, q <> ".")

    try do
      c.db
      |> PrologEx.query(g)
      |> Enum.take(n)
      |> Enum.map(&PrologEx.format_answer(&1, PrologEx.query_var_names(g)))
      |> Enum.map(fn a -> Enum.reduce(names, a, fn {p, n}, a -> String.replace(a, p, n) end) end)
    rescue
      e in PrologEx.Error ->
        {:error, Exception.message(e) |> String.replace(c.small, "KLEIN")}
    end
  end

  test "phrase_from_file/2: Zeichen, Grammatik mit Strings", c do
    assert ask(c, "phrase_from_file(any(L), KLEIN)") == ["L = \"hallo welt\\nzweite zeile\\n\""]

    assert ask(c, "phrase_from_file(lines(Ls), KLEIN)") ==
             ["Ls = [\"hallo welt\",\"zweite zeile\"]"]

    assert ask(c, "phrase_from_file((\"hallo\", any(_)), KLEIN)") == ["true"]
    assert ask(c, "phrase_from_file(\"hallo\", KLEIN)") == []
    # mehrere Lösungen
    assert ask(c, "phrase_from_file((any(A), \" \", any(_)), KLEIN)") == [
             "A = \"hallo\"",
             "A = \"hallo welt\\nzweite\""
           ]
  end

  test "as(codes); ohne as/1 nach dem Flag double_quotes", c do
    assert ask(c, "phrase_from_file(any(L), KLEIN, [as(codes)]), L = [C|_]") ==
             [
               ~s(C = 104, L = [104,97,108,108,111,32,119,101,108,116,10,122,119,101,105,116,101,32,122,101,105,108,101,10])
             ]

    assert ask(c, """
           current_prolog_flag(double_quotes, F),
           set_prolog_flag(double_quotes, codes),
           phrase_from_file(any([C|_]), KLEIN),
           set_prolog_flag(double_quotes, F)
           """) == ["C = 104, F = chars"]

    assert ask(c, "phrase_from_file(any([C|_]), KLEIN, [as(chars), as(codes)])") == ["C = h"]
    # die übrigen Optionen gehen an open/4
    assert ask(c, "phrase_from_file(any([C|_]), KLEIN, [type(text), as(codes)])") ==
             ["C = 104"]
  end

  test "über Blockgrenzen; Rücksetzen liest nicht neu", c do
    assert ask(c, "phrase_from_file(count(0, N), GROSS)") == ["N = 28890"]

    assert ask(
             c,
             "phrase_from_file((any(A), \"zeile 1500 \", any(_)), GROSS), length(A, N)"
           )
           |> hd()
           |> String.ends_with?("N = 21390")

    assert ask(c, "phrase_from_file((any(_), \"zeile 1999 äöü\\n\"), GROSS)") == ["true"]
  end

  test "lazy_list_location//1, lazy_list_character_count//1", c do
    assert ask(
             c,
             "phrase_from_file((\"hallo welt\\nzw\", lazy_list_location(P), " <>
               "lazy_list_character_count(N), any(_)), KLEIN)"
           ) == ["N = 13, P = file(KLEIN,2,2,13)"]

    # am Anfang
    assert ask(c, "phrase_from_file((lazy_list_location(P), any(_)), KLEIN)") ==
             ["P = file(KLEIN,1,0,0)"]

    # weit hinten, über Blöcke hinweg
    assert ask(
             c,
             "phrase_from_file((any(_), \"zeile 1500 \", lazy_list_location(P), any(_)), GROSS)"
           ) == ["P = file(GROSS,1501,11,21401)"]

    # genau an einer Blockgrenze, deren Block schon einmal gelesen war
    # (im gescheiterten ersten Zweig)
    assert ask(
             c,
             "phrase_from_file(((any(_), \"§\" ; []), any(_A), {length(_A, 4096)}, " <>
               "lazy_list_character_count(N), any(_)), GROSS)",
             1
           ) == ["N = 4096"]

    # vollständig gelesen (der Rest ist [])
    assert ask(c, "phrase_from_file((any(_), lazy_list_character_count(N)), KLEIN)") ==
             ["N = end_of_file-0"]

    # keine faule Liste
    # keine faule Liste (wie SWI): fertige Liste, sonst Typfehler
    assert ask(c, "lazy_list_location(P, [a, b], _)") == ["P = end_of_file-2"]

    assert ask(c, "catch(lazy_list_location(_, [a|b], _), error(E, _), true)") ==
             ["E = type_error(lazy_list,[a|b])"]

    assert ask(c, "catch(lazy_list_character_count(_, [a|_], _), error(E, _), true)") ==
             ["E = type_error(lazy_list,[a|_A])"]
  end

  test "syntax_error//1", c do
    File.write!(c.small, "ac")

    assert ask(c, "catch(phrase_from_file(pruefe, KLEIN), error(E, P), true)") ==
             ["E = syntax_error(b_erwartet), P = file(KLEIN,1,1,1)"]
  end

  test "Stream wird geschlossen (auch bei Ausnahmen)", c do
    # erschöpft oder abgeschnitten
    assert ask(
             c,
             "once(phrase_from_file(any(_), KLEIN)), \\+ stream_property(_, file_name(KLEIN))"
           ) ==
             ["true"]

    assert ask(c, "\\+ phrase_from_file(\"x\", KLEIN), \\+ stream_property(_, file_name(KLEIN))") ==
             ["true"]

    assert ask(
             c,
             "catch(phrase_from_file((any(_), {throw(x)}), KLEIN), x, true), " <>
               "\\+ stream_property(_, file_name(KLEIN))"
           ) == ["true"]

    # mit offenen Choice Points bleibt er offen
    assert ask(
             c,
             "phrase_from_file(any(_), KLEIN), stream_property(S, file_name(KLEIN)), close(S)",
             1
           )
           |> hd() =~ "S = '$stream'("
  end

  test "phrase_from_stream/2, stream_to_lazy_list/2", c do
    assert ask(c, """
           open(KLEIN, read, S), get_char(S, C0),
           once(phrase_from_stream(("allo", any(_)), S)), close(S)
           """)
           |> length() == 1

    # nach close/1 zurücksetzen und Blöcke brauchen: Fehler
    assert ask(c, """
           open(KLEIN, read, S),
           catch((phrase_from_stream(any(_), S), close(S), fail), error(E, _), true)
           """)
           |> hd() =~ "E = existence_error(stream,"

    # die faule Liste beginnt an der aktuellen Position; eine zweite beim
    # nächsten ungelesenen Block
    assert ask(c, """
           open(GROSS, read, S), stream_to_lazy_list(S, L), L = [A, B|_],
           stream_to_lazy_list(S, L2), L2 = [X|_],
           lazy_list_character_count(N, L2, _), close(S)
           """)
           |> hd() =~ "N = 4096"

    assert ask(c, "open(KLEIN, read, S), stream_to_lazy_codes(S, [C|_]), close(S)") |> hd() =~
             "C = 104"

    assert ask(c, "open(KLEIN, read, S), stream_to_lazy_chars(S, [C|_]), close(S)") |> hd() =~
             "C = h"
  end

  test "Fehler", c do
    assert ask(c, "catch(phrase_from_file(any(_), 'gibts/nicht'), error(E, _), true)") ==
             ["E = existence_error(source_sink,'gibts/nicht')"]

    assert ask(c, "catch(phrase_from_file(any(_), KLEIN, [as(bytes)]), error(E, _), true)") ==
             ["E = domain_error(oneof([codes,chars]),bytes)"]

    assert ask(c, "catch(phrase_from_file(any(_), KLEIN, [as(_)]), error(E, _), true)") ==
             ["E = instantiation_error"]

    assert ask(c, "catch(phrase_from_file(any(_), KLEIN, [foo]), error(E, _), true)") ==
             ["E = domain_error(stream_option,foo)"]

    assert ask(c, "catch(phrase_from_file(any(_), _), error(E, _), true)") ==
             ["E = instantiation_error"]

    assert ask(c, """
           open(KLEIN, write, S),
           catch(stream_to_lazy_list(S, _), error(E, _), true), close(S)
           """)
           |> hd() =~ "E = permission_error(input,stream,"

    assert ask(c, """
           open(KLEIN, read, S, [type(binary)]),
           catch(stream_to_lazy_list(S, _), error(E, _), true), close(S)
           """)
           |> hd() =~ "E = permission_error(input,binary_stream,"

    assert ask(c, """
           open(KLEIN, read, S),
           catch(phrase_from_stream(any(_), S, [type(text)]), error(E, _), true), close(S)
           """)
           |> hd() =~ "E = domain_error(phrase_from_stream_option,type(text))"
  end

  test "phrase_to_file/2, phrase_to_stream/2 (Scryer)", c do
    out = Path.join(c.tmp_dir, "aus.txt")

    assert ask(c, "phrase_to_file((\"abc\", [d], \"\\n\"), '#{out}')") == ["true"]
    assert File.read!(out) == "abcd\n"

    assert ask(c, "phrase_to_file([0'x, 0'ä], '#{out}')") == ["true"]
    assert File.read!(out) == "xä"

    assert ask(c, "catch(phrase_to_file(offen, '#{out}'), error(E, _), true)") ==
             ["E = instantiation_error"]

    assert ask(c, """
           open('#{out}', write, S), phrase_to_stream("hi", S), close(S),
           phrase_from_file(any(L), '#{out}')
           """)
           |> hd() =~ "L = \"hi\""
  end
end
